"""Read-only T3 Code MCP observer. OAuth/HTTP transport is delegated to mcp-remote.
Only t3_project_list and t3_thread_list are callable. No transcripts, task control,
approval replies, token extraction, or database scraping.
"""
import hashlib
from datetime import datetime
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from urllib.parse import urlparse

from chan import emit

PROXY = 'mcp-remote@0.15.1'
ALLOWED = {'t3_project_list', 't3_thread_list'}
ACTIVE = {'queued', 'preparing', 'starting', 'running', 'waiting'}
MAPPING = dict.fromkeys(['queued', 'preparing', 'starting', 'running'], 'working')
MAPPING.update(waiting='waiting', completed='completed', failed='failed', interrupted='cancelled', cancelled='cancelled', rolled_back='cancelled')


def validate_url(raw):
    url = urlparse(raw)
    if url.username or url.password or url.query or url.fragment or not url.hostname:
        raise ValueError('Use the MCP URL without embedded credentials, query or fragment')
    if url.scheme != 'https' and not (url.scheme == 'http' and url.hostname in ('localhost', '127.0.0.1', '::1')):
        raise ValueError('Use HTTPS, or HTTP on localhost only')
    if url.path.rstrip('/') != '/mcp':
        raise ValueError('Copy the MCP URL ending in /mcp from T3 Connections')
    return raw.rstrip('/')


class Client:
    def __init__(self, command):
        self.process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=None, start_new_session=True)
        self.messages = queue.Queue(maxsize=256)
        self.counter = 0
        self.failure = None
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        try:
            while True:
                line = self.process.stdout.readline(2 * 1024 * 1024 + 1)
                if not line:
                    raise RuntimeError('T3 transport disconnected')
                if len(line) > 2 * 1024 * 1024:
                    raise RuntimeError('T3 response exceeded the local size limit')
                value = json.loads(line)
                # Ignore notifications; no content is written to disk or forwarded.
                if isinstance(value, dict) and 'id' in value:
                    self.messages.put_nowait(value)
        except Exception:
            self.failure = 'T3 transport stopped or returned an invalid response'
            try:
                self.messages.put_nowait(None)
            except queue.Full:
                pass

    def notify(self, method):
        self.process.stdin.write((json.dumps({'jsonrpc': '2.0', 'method': method}) + '\n').encode())
        self.process.stdin.flush()

    def request(self, method, params, timeout=20):
        if self.failure:
            raise RuntimeError(self.failure)
        self.counter += 1
        request = dict(jsonrpc='2.0', id=self.counter, method=method, params=params)
        self.process.stdin.write((json.dumps(request) + '\n').encode())
        self.process.stdin.flush()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                result = self.messages.get(timeout=max(.01, deadline - time.monotonic()))
            except queue.Empty:
                break
            if result is None:
                raise RuntimeError(self.failure)
            if result.get('id') != self.counter:
                continue
            if 'error' in result:
                raise RuntimeError('T3 refused the read-only request; check authorization and client version')
            return result.get('result', {})
        raise RuntimeError('T3 request timed out; no task outcome was inferred')

    def tool(self, name, arguments):
        if name not in ALLOWED:
            raise ValueError('This observer only permits read-only project/thread lists')
        result = self.request('tools/call', {'name': name, 'arguments': arguments})
        if result.get('isError'):
            raise RuntimeError('T3 could not list metadata; check project access')
        data = result.get('structuredContent')
        if not isinstance(data, dict):
            for block in result.get('content', []):
                if block.get('type') == 'text':
                    try:
                        data = json.loads(block['text'])
                    except (ValueError, KeyError):
                        continue
                    if isinstance(data, dict):
                        break
        if not isinstance(data, dict):
            raise RuntimeError('Unsupported T3 metadata response')
        return data

    def close(self):
        # npx can spawn a proxy child. Reap only this observer's process group.
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        if self.process.poll() is None:
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                pass
        try:
            os.killpg(self.process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.process.wait()
        for stream in (self.process.stdin, self.process.stdout):
            if stream:
                stream.close()
        self.reader.join(timeout=1)


class Observer:
    def __init__(self, endpoint, sender=emit, clock=time.time):
        self.endpoint = endpoint
        self.sender = sender
        self.clock = clock
        self.since = clock()
        self.known = {}
        self.last_sent = {}
        self.started = False

    def update(self, threads):
        if not isinstance(threads, list):
            raise RuntimeError('Unsupported T3 thread list')
        for row in threads[:100]:
            if not isinstance(row, dict) or not isinstance(row.get('threadId'), str):
                continue
            status = MAPPING.get(row.get('status'), 'idle' if row.get('status') == 'idle' else None)
            if status is None:
                continue  # Unknown/idle is not completed.
            ident = hashlib.sha256((self.endpoint + ':' + row['threadId']).encode()).hexdigest()
            marker = (row.get('latestRunId'), row.get('status'))
            old = self.known.get(ident)
            self.known[ident] = marker
            # Baseline existing terminal states silently; a new connection is not a mass completion.
            now = self.clock()
            try:
                updated = datetime.fromisoformat(row.get('updatedAt', '').replace('Z', '+00:00')).timestamp()
            except (ValueError, TypeError, AttributeError, OverflowError):
                updated = 0
            active = row.get('status') in ACTIVE
            changed = old is not None and old != marker
            # Also catch a newly created task that finishes entirely between polls.
            recent = old is None and row.get('latestRunId') and self.since <= updated <= now + 30
            if (active and (old != marker or now - self.last_sent.get(ident, 0) >= 60)) or (self.started and status != 'idle' and (changed or recent)) or (self.started and status == 'idle' and old and old[1] in ACTIVE):
                self.sender('t3', ident, status, 'T3 thread ' + ident[:6])
                self.last_sent[ident] = now
        self.started = True
        # One watched project, newest 100 threads. Never retain an unbounded history.
        if len(self.known) > 200:
            keep = list(self.known.items())[-100:]
            self.known = dict(keep)
            self.last_sent = {key: value for key, value in self.last_sent.items() if key in self.known}


def interactive():
    print('T3 Code → Settings → Connections → environment menu → Copy MCP URL.')
    print('This uses the pinned mcp-remote OAuth bridge from npm. Choose Read only at sign-in.')
    client = None
    try:
        endpoint = validate_url(input('MCP URL: ').strip())
        command = ['npx', '--yes', PROXY, endpoint, '--transport', 'http-only', '--auth-timeout', '300']
        if endpoint.startswith('http://'):
            command.append('--allow-http')
        client = Client(command)
        # OAuth may need a browser sign-in before this first request can finish.
        client.request('initialize', {'protocolVersion': '2025-03-26', 'capabilities': {},
                       'clientInfo': {'name': 'deepseek-chan-observer', 'version': '1.9.0'}}, timeout=300)
        client.notify('notifications/initialized')
        tools = client.request('tools/list', {}).get('tools', [])
        if not ALLOWED.issubset({tool.get('name') for tool in tools}):
            raise RuntimeError('This T3 version does not expose the required read-only list tools')
        data = client.tool('t3_project_list', {'limit': 100})
        projects = data.get('projects', [])
        if not projects:
            raise RuntimeError('No projects are available to this connection')
        for index, project in enumerate(projects):
            print(str(index + 1) + '. ' + str(project.get('title', project.get('id', 'Project'))))
        choice = int(input('Project number to watch: ')) - 1
        if not 0 <= choice < len(projects):
            raise ValueError('Invalid project number')
        project_id = projects[choice].get('id')
        if not isinstance(project_id, str):
            raise RuntimeError('Unsupported T3 project identity')
        observer = Observer(endpoint)
        print('Watching this project read-only every 5 seconds. Ctrl+C disconnects. No transcripts are read.')
        while True:
            data = client.tool('t3_thread_list', {'projectId': project_id, 'limit': 100, 'includeSubagents': False})
            observer.update(data.get('threads'))
            time.sleep(5)
    except (KeyboardInterrupt, EOFError):
        print('\nDisconnected. Running T3 tasks are unchanged.')
    except (RuntimeError, ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        return 1
    finally:
        if client:
            client.close()
    return 0
