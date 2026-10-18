from datetime import datetime, timezone
from pathlib import Path
import sys
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'integrations'))
from t3_watch import Client, Observer, validate_url


class T3Checks(unittest.TestCase):
    def test_connection_url_validation(self):
        for url in ('http://localhost:3773/mcp', 'http://[::1]:3773/mcp', 'https://t3.example/mcp/'):
            self.assertEqual(validate_url(url), url.rstrip('/'))
        for url in ('http://remote.example/mcp', 'https://user:pass@host/mcp', 'file:///mcp', 'https://host/mcp?token=secret', 'https://host/mcp#secret', 'https://host/other'):
            with self.assertRaises(ValueError):
                validate_url(url)

    def test_baseline_heartbeat_state_changes_and_metadata_only(self):
        sent, now = [], [1000.0]
        watch = Observer('http://localhost:3773/mcp', lambda *args: sent.append(args), lambda: now[0])
        def row(ident, status, run='r1', updated=1000):
            return dict(threadId=ident, status=status, latestRunId=run, title='SECRET TITLE',
                        updatedAt=datetime.fromtimestamp(updated, timezone.utc).isoformat())
        watch.update([row('old', 'completed'), row('active', 'running'), row('fresh', 'idle', None)])
        self.assertEqual([s[2] for s in sent], ['working'])
        watch.update([row('active', 'running')])
        self.assertEqual(len(sent), 1)
        now[0] += 60
        watch.update([row('active', 'running')])
        self.assertEqual(len(sent), 2)
        watch.update([row('active', 'waiting')])
        watch.update([row('active', 'completed')])
        watch.update([row('active', 'completed')])
        self.assertEqual([s[2] for s in sent], ['working', 'working', 'waiting', 'completed'])
        watch.update([row('fresh', 'completed'), row('quick', 'completed', updated=1060), row('historical', 'completed', updated=900)])
        self.assertEqual(len(sent), 6)
        watch.update([row('active', 'completed', 'r2')])
        self.assertEqual(len(sent), 7)
        watch.update([row('active', 'future-status')])
        self.assertEqual(len(sent), 7)
        self.assertTrue(all(s[0] == 't3' and len(s[1]) == 64 and s[3].startswith('T3 thread ') for s in sent))
        self.assertNotIn('SECRET', str(sent))

    def test_terminal_mappings_and_idle_is_not_success(self):
        sent = []
        watch = Observer('https://host/mcp', lambda *args: sent.append(args))
        for raw, expected in [('failed', 'failed'), ('cancelled', 'cancelled'), ('interrupted', 'cancelled'), ('rolled_back', 'cancelled'), ('idle', 'idle')]:
            watch.update([dict(threadId='a', latestRunId='r', status='running')])
            watch.update([dict(threadId='a', latestRunId='r', status=raw)])
            self.assertEqual(sent[-1][2], expected)

    def test_stdio_metadata_roundtrip_and_read_only_allowlist(self):
        program = '''
import json, sys
for line in sys.stdin:
    r = json.loads(line)
    if 'id' not in r: continue
    method = r['method']
    if method == 'initialize': result = {'protocolVersion': '2025-03-26', 'capabilities': {'tools': {}}}
    elif method == 'tools/list': result = {'tools': [{'name': 't3_project_list'}, {'name': 't3_thread_list'}]}
    elif r['params']['name'] == 't3_project_list': result = {'structuredContent': {'projects': [{'id': 'p', 'title': 'Example'}]}}
    else: result = {'content': [{'type': 'text', 'text': json.dumps({'threads': [{'threadId': 't', 'status': 'running', 'latestRunId': 'r'}]})}]}
    print(json.dumps({'jsonrpc': '2.0', 'id': r['id'], 'result': result}), flush=True)
'''
        client = Client([sys.executable, '-u', '-c', program])
        try:
            self.assertIn('capabilities', client.request('initialize', {}))
            client.notify('notifications/initialized')
            self.assertEqual(len(client.request('tools/list', {})['tools']), 2)
            self.assertEqual(client.tool('t3_project_list', {})['projects'][0]['id'], 'p')
            threads = client.tool('t3_thread_list', {'projectId': 'p'})['threads']
            sent = []
            Observer('https://host/mcp', lambda *args: sent.append(args)).update(threads)
            self.assertEqual(sent[0][2], 'working')
            with self.assertRaises(ValueError):
                client.tool('t3_thread_send', {'prompt': 'MUST NOT SEND'})
        finally:
            client.close()
        self.assertIsNotNone(client.process.poll())
        self.assertFalse(client.reader.is_alive())

    def test_timeout_and_disconnect_do_not_manufacture_task_outcomes(self):
        client = Client([sys.executable, '-c', 'import time; time.sleep(5)'])
        try:
            with self.assertRaisesRegex(RuntimeError, 'timed out'):
                client.request('initialize', {}, timeout=.05)
        finally:
            client.close()
        client = Client([sys.executable, '-c', 'pass'])
        try:
            client.process.wait(timeout=2)
            client.reader.join(timeout=2)
            with self.assertRaises(RuntimeError):
                client.request('initialize', {})
        finally:
            client.close()
