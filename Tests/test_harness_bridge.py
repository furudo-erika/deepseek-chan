import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'integrations'))
import chan


class HarnessChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.env = patch.dict(os.environ, DEEPSEEK_CHAN_HOME=self.temp.name)
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.temp.cleanup()

    def events(self):
        return [json.loads(p.read_text()) for p in (Path(self.temp.name) / 'tasks').glob('*.json')]

    def grok(self, event, **extra):
        chan.hook('grok', dict(sessionId='private-session', promptId='turn-a', hookEventName=event,
                               prompt='SECRET', transcriptPath='/private/log', **extra))

    def test_grok_vetoable_stop_is_not_completion_and_idle_preserves_failure(self):
        self.grok('user_prompt_submit')
        before = self.events()
        self.grok('stop')
        self.assertEqual(before, self.events())
        self.grok('notification', notificationType='permission_prompt')
        self.assertEqual(self.events()[0]['status'], 'waiting')
        self.grok('notification', notificationType='idle_prompt')
        self.assertEqual(self.events()[0]['status'], 'idle')
        self.grok('user_prompt_submit')
        self.grok('stop_failure')
        self.grok('notification', notificationType='idle_prompt')
        self.grok('session_end')
        self.assertEqual(self.events()[0]['status'], 'failed')
        self.assertNotIn('SECRET', json.dumps(self.events()))
        self.assertNotIn('private', json.dumps(self.events()))

    def test_grok_stale_turn_child_and_compatibility_events_are_ignored(self):
        self.grok('user_prompt_submit')
        payload = dict(sessionId='private-session', promptId='turn-b', hookEventName='user_prompt_submit')
        chan.hook('grok', payload)
        before = self.events()
        self.grok('stop_cancelled')
        self.grok('notification', notificationType='idle_prompt')
        self.grok('pre_tool_use', subagentType='helper')
        for source in ('claude', 'cursor'):
            chan.hook(source, dict(payload, hook_event_name='UserPromptSubmit', session_id='private-session'))
        self.assertEqual(before, self.events())
        self.assertEqual(before[0]['turn_id'], hashlib.sha256(b'turn-b').hexdigest())
        chan.hook('grok', dict(payload, hookEventName='stop_cancelled'))
        self.assertEqual(self.events()[0]['status'], 'cancelled')

    def test_grok_install_is_idempotent_and_preserves_other_hooks(self):
        root = Path(self.temp.name)
        target = root / '.grok/hooks/deepseek-chan.json'
        target.parent.mkdir(parents=True)
        target.write_text(json.dumps({'hooks': {'SessionStart': [{'hooks': [{'type': 'command', 'command': 'existing'}]}]}}))
        with patch.object(Path, 'home', return_value=root):
            chan.install_hooks('grok')
            chan.install_hooks('grok')
        hooks = json.loads(target.read_text())['hooks']
        self.assertIn('SessionStart', hooks)
        self.assertNotIn('Stop', hooks)
        self.assertEqual(len(hooks['UserPromptSubmit']), 1)
        self.assertEqual(len(list(target.parent.glob('*.bak'))), 1)
        self.assertEqual(hooks['Notification'][0]['matcher'], 'permission_prompt|idle_prompt')

    def test_dsh_patch_and_grok_fail_open_cli(self):
        script = str(Path(chan.__file__))
        result = subprocess.run([sys.executable, script, 'dsh-patch'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        patch_file = Path(self.temp.name) / 'dsh-pet.patch.json'
        if os.name != 'nt':
            self.assertEqual(patch_file.stat().st_mode & 0o777, 0o600)
        self.assertTrue(Path(json.loads(patch_file.read_text())[0]['insert'][0]['name']).is_file())
        for payload in ['not JSON', '{}', '{"sessionId": "a", "hookEventName": []}']:
            result = subprocess.run([sys.executable, script, 'hook', 'grok'], input=payload, capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stdout), (0, ''))
