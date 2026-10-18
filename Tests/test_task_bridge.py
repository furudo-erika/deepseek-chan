import concurrent.futures
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'integrations/chan.py'
spec = importlib.util.spec_from_file_location('chan', SCRIPT)
chan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chan)


class BridgeChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, {'DEEPSEEK_CHAN_HOME': self.temp.name})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def events(self):
        return [json.loads(p.read_text()) for p in (Path(self.temp.name) / 'tasks').glob('*.json')]

    def call(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True, **kwargs)

    def test_atomic_concurrent_updates_and_cap(self):
        def write(i):
            return self.call('emit', '--source', 'pi', '--task', str(i), '--status', 'working')
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            self.assertTrue(all(r.returncode == 0 for r in pool.map(write, range(140))))
        self.assertEqual(len(self.events()), 128)
        self.assertTrue(all(e['status'] == 'working' for e in self.events()))
        self.assertEqual((Path(self.temp.name) / 'tasks').stat().st_mode & 0o777, 0o700)
        for f in (Path(self.temp.name) / 'tasks').glob('*.json'):
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)

    def test_latest_snapshot_and_source_isolation(self):
        chan.emit('codex', '../../escape', 'working')
        chan.emit('codex', '../../escape', 'completed')
        chan.emit('claude', '../../escape', 'waiting')
        self.assertEqual(len(self.events()), 2)
        self.assertEqual({e['status'] for e in self.events()}, {'completed', 'waiting'})
        self.assertFalse((Path(self.temp.name).parent / 'escape').exists())

    def test_hook_mapping_and_private_payload_is_dropped(self):
        base = {'session_id': 'private-session', 'prompt': 'SECRET PROMPT', 'transcript_path': '/secret/log', 'tool_input': {'secret': 'KEY'}}
        for hook, status in [('UserPromptSubmit', 'working'), ('Stop', 'completed'), ('StopFailure', 'failed')]:
            chan.hook('claude', dict(base, hook_event_name=hook))
            self.assertEqual(self.events()[0]['status'], status)
        chan.hook('claude', dict(base, hook_event_name='Notification', notification_type='permission_prompt'))
        self.assertEqual(self.events()[0]['status'], 'waiting')
        old = self.events()
        chan.hook('claude', dict(base, hook_event_name='Notification', notification_type='idle_prompt'))
        self.assertEqual(self.events(), old)
        self.assertNotIn('SECRET', json.dumps(self.events()))
        self.assertNotIn('/secret', json.dumps(self.events()))
        self.assertNotIn('private-session', json.dumps(self.events()))
        for native, status in [('completed', 'completed'), ('error', 'failed'), ('aborted', 'cancelled')]:
            chan.hook('cursor', dict(conversation_id='cursor-id', hook_event_name='stop', status=native))
            self.assertEqual(next(e for e in self.events() if e['source'] == 'cursor')['status'], status)
        chan.hook('codex', {'type': 'agent-turn-complete', 'thread-id': 'a', 'last-assistant-message': 'SECRET'})
        self.assertEqual(next(e for e in self.events() if e['source'] == 'codex')['status'], 'completed')
        self.assertNotIn('SECRET', json.dumps(self.events()))

    def test_bad_hooks_never_block_client_or_write_stdout(self):
        for value in ['{bad', '[]', '{"hook_event_name":"Stop"}', 'x' * (chan.MAX_INPUT + 10)]:
            result = self.call('hook', 'claude', input=value)
            self.assertEqual((result.returncode, result.stdout), (0, ''))

    def test_install_preserves_and_backs_up_config_and_is_idempotent(self):
        root = Path(self.temp.name)
        target = root / '.claude/settings.json'
        target.parent.mkdir()
        original = {'env': {'KEEP': 'yes'}, 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo existing'}]}]}}
        target.write_text(json.dumps(original))
        with patch.object(Path, 'home', return_value=root):
            chan.install_hooks('claude')
            chan.install_hooks('claude')
        result = json.loads(target.read_text())
        self.assertEqual(result['env'], original['env'])
        self.assertEqual(result['hooks']['Stop'][0], original['hooks']['Stop'][0])
        self.assertEqual(len(result['hooks']['Stop']), 2)
        self.assertEqual(len(list(target.parent.glob('*.bak'))), 1)

    def test_cursor_install_preserves_other_hooks_and_rejects_unknown_version(self):
        root = Path(self.temp.name)
        target = root / '.cursor/hooks.json'
        target.parent.mkdir()
        original = {'version': 1, 'hooks': {'stop': [{'command': 'echo existing'}]}}
        target.write_text(json.dumps(original))
        with patch.object(Path, 'home', return_value=root):
            chan.install_hooks('cursor')
            chan.install_hooks('cursor')
        self.assertEqual(len(json.loads(target.read_text())['hooks']['stop']), 2)
        target.write_text('{"version": 99, "hooks": {}}')
        before = target.read_text()
        with patch.object(Path, 'home', return_value=root), self.assertRaises(ValueError):
            chan.install_hooks('cursor')
        self.assertEqual(target.read_text(), before)

    def test_mcp_real_stdio_lifecycle_and_validation(self):
        requests = [
            {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {'protocolVersion': '2025-03-26'}},
            {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
            {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
            {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {'name': 'report_task', 'arguments': {'task_id': 'unit', 'title': 'Icon check', 'status': 'working'}}},
            {'jsonrpc': '2.0', 'id': 4, 'method': 'tools/call', 'params': {'name': 'report_task', 'arguments': {'task_id': 'unit', 'title': 'Icon check', 'status': 'bogus'}}},
            {'jsonrpc': '2.0', 'id': 5, 'method': 'ping'},
        ]
        result = self.call('mcp', '--source', 'codex', input='\n'.join(json.dumps(r) for r in requests) + '\n')
        self.assertEqual(result.returncode, 0)
        responses = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual([r['id'] for r in responses], [1, 2, 3, 4, 5])
        self.assertEqual(responses[1]['result']['tools'][0]['name'], 'report_task')
        self.assertFalse(responses[2]['result']['isError'])
        self.assertTrue(responses[3]['result']['isError'])
        self.assertEqual(self.events()[0]['status'], 'working')

    def test_process_exit_codes_and_stdio_preserved(self):
        for code in (0, 7):
            result = self.call('run', '--source', 'grok', '--', sys.executable, '-c', 'import sys; print("child output"); sys.exit(' + str(code) + ')')
            self.assertEqual(result.returncode, code)
            self.assertEqual(result.stdout, 'child output\n')
        self.assertEqual({e['status'] for e in self.events()}, {'completed', 'failed'})

    def test_bad_fields_and_symlink_lock_rejected(self):
        for title in ['', 'x' * 81]:
            with self.assertRaises(ValueError):
                chan.emit('codex', 'a', 'working', title)
        target = Path(self.temp.name) / 'untouched'
        target.write_text('keep')
        (Path(self.temp.name) / '.writer.lock').symlink_to(target)
        with self.assertRaises(OSError):
            chan.emit('codex', 'a', 'working')
        self.assertEqual(target.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
