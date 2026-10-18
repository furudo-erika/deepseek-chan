#!/usr/bin/env python3
"""DeepSeek-chan: local task snapshots, lifecycle adapters and a stdio MCP server.
Python 3.9+, standard library only. Never reads transcripts or sends network requests.
"""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unicodedata
import uuid

SOURCES = ('codex', 'claude', 'cursor', 'pi', 'omp', 'grok', 'dsh', 't3', 'other')
STATUSES = ('working', 'waiting', 'completed', 'failed', 'cancelled', 'idle')
MAX_INPUT = 1024 * 1024


def home():
    return Path(os.environ.get('DEEPSEEK_CHAN_HOME', str(Path.home() / '.deepseek-chan'))).expanduser()


def clean(value, limit):
    if not isinstance(value, str):
        raise ValueError('Expected text')
    value = ''.join(c for c in value if not unicodedata.category(c).startswith('C')).strip()
    if not value or len(value) > limit:
        raise ValueError('Text is empty or too long')
    return value


@contextmanager
def writer_lock():
    target = home() / '.writer.lock'
    if target.is_symlink():
        raise OSError('Lock must not be a symbolic link')
    fd = os.open(target, os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    with os.fdopen(fd, 'r+b') as lock:
        if os.name == 'nt':
            import msvcrt
            if os.fstat(lock.fileno()).st_size == 0:
                lock.write(b'\0'); lock.flush()
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
            try:
                yield
            finally:
                lock.seek(0); msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            yield


def emit(source, task_id, status, title='Current turn', *, turn_id=None, begin=False, settle=False):
    if source not in SOURCES or status not in STATUSES:
        raise ValueError('Unknown source or task state')
    task_id, title = clean(task_id, 128), clean(title, 80)
    directory = home() / 'tasks'
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(home(), 0o700)
    os.chmod(directory, 0o700)
    key = hashlib.sha256((source + ':' + task_id).encode()).hexdigest()
    # Serialize writers, including cleanup, so concurrent sessions cannot partially overwrite a snapshot.
    with writer_lock():
        prior = None
        destination = directory / (key + '.json')
        if turn_id is not None or settle:
            try:
                if destination.stat().st_size <= 8192:
                    prior = json.loads(destination.read_text(encoding='utf-8'))
            except (OSError, ValueError):
                pass
            if not isinstance(prior, dict):
                prior = None
            if turn_id is not None and not begin and prior and prior.get('turn_id') not in (None, turn_id):
                return None  # Delayed end of an older Grok turn cannot settle the new one.
            if settle and (not prior or prior.get('status') not in ('working', 'waiting')):
                return None  # Idle is not proof of success; preserve known failure/cancellation.
        event = dict(version=1, event_id=str(uuid.uuid4()), source=source, task_id=task_id,
                     title=title, status=status, updated_at=time.time())
        if turn_id is not None:
            event['turn_id'] = turn_id
        elif prior and prior.get('turn_id'):
            event['turn_id'] = prior['turn_id']
        temp_fd, name = tempfile.mkstemp(prefix='.pending-', dir=directory)
        try:
            with os.fdopen(temp_fd, 'w', encoding='utf-8') as output:
                json.dump(event, output, ensure_ascii=False, allow_nan=False)
                output.write('\n')
            os.replace(name, directory / (key + '.json'))
        finally:
            if os.path.exists(name):
                os.unlink(name)
        files = []
        for path in directory.glob('*.json'):
            info = path.lstat()
            if stat.S_ISREG(info.st_mode):
                files.append((info.st_mtime, path))
        for index, (modified, path) in enumerate(sorted(files, reverse=True)):
            if index >= 128 or time.time() - modified > 86400:
                path.unlink(missing_ok=True)
    return event


def hook(source, payload):
    """Only allowlisted metadata survives. Prompts, messages, paths and tool outputs are ignored."""
    if not isinstance(payload, dict):
        return
    status = None
    # Grok scans Claude/Cursor compatibility hooks too. Do not mislabel those events.
    if source in ('claude', 'cursor') and 'sessionId' in payload and 'hookEventName' in payload:
        return
    if source == 'grok':
        return grok_hook(payload)
    if source == 'codex':
        identity = payload.get('thread-id')
        if payload.get('type') == 'agent-turn-complete':
            status = 'completed'
    elif source == 'claude':
        identity = payload.get('session_id')
        event = payload.get('hook_event_name')
        status = {'UserPromptSubmit': 'working', 'PreToolUse': 'working', 'PostToolUse': 'working',
                  'Stop': 'completed', 'StopFailure': 'failed', 'SessionEnd': 'cancelled'}.get(event)
        if event == 'Notification' and payload.get('notification_type') in ('permission_prompt', 'elicitation_dialog'):
            status = 'waiting'
        if event == 'PreToolUse' and payload.get('tool_name') == 'AskUserQuestion':
            status = 'waiting'
    elif source == 'cursor':
        identity = payload.get('conversation_id')
        event = payload.get('hook_event_name')
        if event in ('beforeSubmitPrompt', 'preToolUse', 'postToolUse'):
            status = 'working'
        elif event == 'stop':
            status = {'completed': 'completed', 'error': 'failed', 'aborted': 'cancelled'}.get(payload.get('status'))
    else:
        return
    if status and isinstance(identity, str) and identity:
        opaque_id = hashlib.sha256(identity.encode()).hexdigest()
        emit(source, opaque_id, status)


def grok_hook(payload):
    identity = payload.get('sessionId')
    if not isinstance(identity, str) or not identity or payload.get('subagentType'):
        return
    event = payload.get('hookEventName')
    status = {'user_prompt_submit': 'working', 'pre_tool_use': 'working',
              'post_tool_use': 'working', 'post_tool_use_failure': 'working',
              'stop_failure': 'failed', 'stop_cancelled': 'cancelled'}.get(event)
    settling = False
    if event == 'notification':
        kind = payload.get('notificationType')
        if kind == 'permission_prompt':
            status = 'waiting'
        elif kind == 'idle_prompt':
            status, settling = 'idle', True
    if event == 'session_end':
        status, settling = 'idle', True
    # Stop is a vetoable gate, so never celebrate it as a confirmed completion.
    if status:
        prompt = payload.get('promptId')
        turn = hashlib.sha256(prompt.encode()).hexdigest() if isinstance(prompt, str) and prompt else None
        emit('grok', hashlib.sha256(identity.encode()).hexdigest(), status,
             turn_id=turn, begin=event == 'user_prompt_submit', settle=settling)


def hook_config(source):
    if os.name == 'nt':
        raise ValueError('Native hook installation is not yet supported on Windows. Use the report_task MCP connector or emit command.')
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), 'hook', source])
    if source in ('claude', 'grok'):
        hooks = {event: [{'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]}]
                 for event in ('UserPromptSubmit', 'PreToolUse', 'PostToolUse', 'Stop', 'StopFailure')}
        hooks['Notification'] = [{'matcher': 'permission_prompt|elicitation_dialog',
                                  'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]}]
        if source == 'grok':
            hooks.pop('Stop')
            hooks['StopCancelled'] = [{'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]}]
            hooks['SessionEnd'] = [{'hooks': [{'type': 'command', 'command': command, 'timeout': 1}]}]
            hooks['Notification'][0]['matcher'] = 'permission_prompt|idle_prompt'
        return {'hooks': hooks}
    if source == 'cursor':
        return {'version': 1, 'hooks': {event: [{'command': command}]
                for event in ('beforeSubmitPrompt', 'preToolUse', 'postToolUse', 'stop')}}
    raise ValueError('Use claude, cursor or grok for lifecycle hooks')


def install_hooks(source):
    target = Path.home() / {'claude': '.claude/settings.json', 'cursor': '.cursor/hooks.json', 'grok': '.grok/hooks/deepseek-chan.json'}[source]
    target.parent.mkdir(parents=True, exist_ok=True)
    original = target.read_text(encoding='utf-8') if target.exists() else None
    current = json.loads(original) if original else {}
    if not isinstance(current, dict) or not isinstance(current.get('hooks', {}), dict):
        raise ValueError('Existing config has an unexpected format; left unchanged')
    fragment = hook_config(source)
    if source == 'cursor' and current.get('version', 1) != 1:
        raise ValueError('Unsupported Cursor hook version; left unchanged')
    hooks = current.setdefault('hooks', {})
    for event, entries in fragment['hooks'].items():
        existing = hooks.setdefault(event, [])
        if not isinstance(existing, list):
            raise ValueError('Existing hook entry is not a list; left unchanged')
        for entry in entries:
            if entry not in existing:
                existing.append(entry)
    if source == 'cursor':
        current['version'] = 1
    updated = json.dumps(current, indent=2, ensure_ascii=False) + '\n'
    if original and json.loads(original) == current:
        print('Already connected. Restart the client if needed.')
        return
    if original is not None:
        backup = target.with_name(target.name + '.deepseek-chan-' + str(time.time_ns()) + '.bak')
        backup.write_text(original, encoding='utf-8')
        backup.chmod(0o600)
    fd, name = tempfile.mkstemp(prefix='.chan-config-', dir=target.parent)
    with os.fdopen(fd, 'w', encoding='utf-8') as output:
        output.write(updated)
    os.replace(name, target)
    print('Connected. Existing hooks preserved; restart the client. Config: ' + str(target))


TOOL = {
    'name': 'report_task',
    'description': 'Update the local DeepSeek-chan desktop pet for this task. Report working at start, waiting only when human input is needed, completed when this turn ends, failed on terminal failure, cancelled when stopped. Use a stable unique task_id per conversation. Titles must be short, non-sensitive labels; never include prompts, code, credentials or private paths. This displays a status, not an independent verification of success.',
    'inputSchema': {'type': 'object', 'properties': {
        'task_id': {'type': 'string', 'minLength': 1, 'maxLength': 128},
        'status': {'type': 'string', 'enum': list(STATUSES)},
        'title': {'type': 'string', 'minLength': 1, 'maxLength': 80}},
        'required': ['task_id', 'status', 'title'], 'additionalProperties': False},
    'annotations': {'readOnlyHint': False, 'destructiveHint': False, 'idempotentHint': True, 'openWorldHint': False}
}


def rpc(request, source):
    if not isinstance(request, dict) or request.get('jsonrpc') != '2.0':
        return {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32600, 'message': 'Invalid request'}}
    if 'id' not in request:
        return None
    base = {'jsonrpc': '2.0', 'id': request['id']}
    method, params = request.get('method'), request.get('params', {})
    if not isinstance(params, dict):
        return dict(base, error={'code': -32602, 'message': 'Invalid params'})
    if method == 'initialize':
        versions = ('2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25')
        version = params.get('protocolVersion')
        return dict(base, result={'protocolVersion': version if version in versions else '2025-03-26',
                    'capabilities': {'tools': {}}, 'serverInfo': {'name': 'deepseek-chan', 'version': '1.9.0'},
                    'instructions': 'Report task lifecycle using report_task. Share only a short, non-sensitive label. Refresh working during long jobs; stale status is shown after five minutes without an update.'})
    if method == 'ping':
        return dict(base, result={})
    if method == 'tools/list':
        return dict(base, result={'tools': [TOOL]})
    if method == 'tools/call':
        args = params.get('arguments', {})
        try:
            if params.get('name') != 'report_task' or not isinstance(args, dict) or set(args) != {'task_id', 'status', 'title'}:
                raise ValueError('Expected report_task with task_id, status and title')
            event = emit(source, args['task_id'], args['status'], args['title'])
            result = {'content': [{'type': 'text', 'text': 'Local pet status updated: ' + event['status']}], 'isError': False}
        except (ValueError, TypeError, OSError):
            result = {'content': [{'type': 'text', 'text': 'Task update rejected. Check fields and local inbox permissions.'}], 'isError': True}
        return dict(base, result=result)
    return dict(base, error={'code': -32601, 'message': 'Method not found'})


def mcp(source):
    while True:
        line = sys.stdin.buffer.readline(MAX_INPUT + 1)
        if not line:
            break
        if len(line) > MAX_INPUT:
            # End this malformed transport rather than interpret fragments as new requests.
            break
        try:
            response = rpc(json.loads(line), source)
        except (ValueError, TypeError):
            response = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'Parse error'}}
        if response is not None:
            print(json.dumps(response, ensure_ascii=False, allow_nan=False), flush=True)


def run_command(source, title, command):
    """Process lifetime fallback, not a parser of an interactive agent's individual turns."""
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        raise ValueError('A command is required after --')
    task_id = 'process-' + str(uuid.uuid4())
    def report(status):
        try:
            emit(source, task_id, status, title)
        except (OSError, ValueError):
            pass  # A pet connection must never stop the user's command.
    report('working')
    try:
        child = subprocess.Popen(command)  # inherited stdio; no shell and no output capture
    except OSError:
        report('failed')
        raise
    try:
        while True:
            try:
                code = child.wait(timeout=60)
                break
            except subprocess.TimeoutExpired:
                report('working')
    except KeyboardInterrupt:
        child.send_signal(signal.SIGINT)
        code = child.wait()
        report('cancelled')
        return 130
    report('completed' if code == 0 else 'cancelled' if code < 0 else 'failed')
    return code if code >= 0 else 128 - code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('emit', help='Send a local task state')
    p.add_argument('--source', choices=SOURCES, required=True)
    p.add_argument('--task', required=True)
    p.add_argument('--status', choices=STATUSES, required=True)
    p.add_argument('--title', default='Current turn')
    p = sub.add_parser('hook', help='Read one client lifecycle payload (always non-blocking on errors)')
    p.add_argument('source', choices=('claude', 'cursor', 'codex', 'grok'))
    p.add_argument('payload', nargs='?')
    p = sub.add_parser('mcp', help='Serve report_task over MCP stdio')
    p.add_argument('--source', choices=SOURCES, required=True)
    for name in ('config', 'install'):
        p = sub.add_parser(name, help='Print / merge lifecycle hook settings')
        p.add_argument('source', choices=('claude', 'cursor', 'grok'))
    sub.add_parser('dsh-patch', help='Print a native dsh plugin patch')
    sub.add_parser('connect-t3', help='Connect to T3 Code through its read-only MCP API')
    p = sub.add_parser('run', help='Observe an explicitly launched command, including Grok or dsh')
    p.add_argument('--source', choices=SOURCES, required=True)
    p.add_argument('--title', default='CLI session')
    p.add_argument('args', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command == 'hook':
        try:
            raw = args.payload if args.payload is not None else sys.stdin.buffer.read(MAX_INPUT + 1)
            if len(raw) <= MAX_INPUT:
                hook(args.source, json.loads(raw))
        except (ValueError, TypeError, OSError):
            pass
        return 0  # Never veto a tool, approval, stop or prompt; no stdout injection.
    if args.command == 'emit':
        emit(args.source, args.task, args.status, args.title)
    elif args.command == 'mcp':
        mcp(args.source)
    elif args.command == 'config':
        print(json.dumps(hook_config(args.source), indent=2))
    elif args.command == 'install':
        install_hooks(args.source)
    elif args.command == 'dsh-patch':
        # JSON is also valid YAML; no shell interpolation or config overwrite.
        home().mkdir(parents=True, exist_ok=True, mode=0o700)
        target = home() / 'dsh-pet.patch.json'
        target.write_text(json.dumps([{'insert': [{'id': 'deepseek-chan-pet', 'name': str(Path(__file__).with_name('dsh.mjs').resolve())}]}], indent=2) + '\n')
        target.chmod(0o600)
        print('Patch ready. Launch your existing profile with:')
        print('dsh --profile YOUR_PROFILE --patch ' + shlex.quote(str(target)))
    elif args.command == 'connect-t3':
        from t3_watch import interactive
        return interactive()
    elif args.command == 'run':
        return run_command(args.source, args.title, args.args)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print('DeepSeek-chan: ' + str(error), file=sys.stderr)
        sys.exit(1)
