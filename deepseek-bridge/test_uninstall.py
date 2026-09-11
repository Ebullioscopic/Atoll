"""Uninstall runs only against a temporary home and fake command boundary."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.dest = self.home / 'Library/Application Support/AtollDeepSeekBridge'; self.dest.mkdir(parents=True)
        self.agent = self.home / 'Library/LaunchAgents/local.atoll.deepseek-bridge.plist'
        self.agent.parent.mkdir(parents=True); self.agent.write_bytes(b'unchanged plist')
        self.backup = self.dest / 'atoll-settings-before.json'
        self.original = {'selectedAIProvider': 'Original Provider', 'localModelEndpoint': None}
        self.backup.write_text(json.dumps(self.original))
        self.config = self.dest / 'config.json'; self.config.write_bytes(b'private sentinel')
        self.commands = []; self.bootout_code = 0; self.default_failure = None

    def run_uninstall(self):
        def run(command, **kwargs):
            self.commands.append(command)
            self.assertIn(command[0], ('/bin/launchctl', '/usr/bin/defaults', 'launchctl', 'defaults'))
            code, stderr = 0, ''
            if command[1] == 'bootout': code = self.bootout_code
            elif command[0].endswith('defaults'):
                if self.default_failure and command[3] == self.default_failure[0]: code, stderr = self.default_failure[1:]
            else: self.fail('Unexpected command')
            return subprocess.CompletedProcess(command, code, stdout='sensitive output', stderr=stderr)
        stdout, stderr = io.StringIO(), io.StringIO()
        original_read = Path.read_text
        def read(path, *args, **kwargs):
            self.assertNotEqual(path, self.config, 'uninstall must not read the key')
            return original_read(path, *args, **kwargs)
        with patch('pathlib.Path.home', return_value=self.home), patch('subprocess.run', side_effect=run), \
             patch('pathlib.Path.read_text', read), contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                runpy.run_path(str(Path(__file__).with_name('uninstall.py')), run_name='__main__')
                code = 0
            except SystemExit as exit: code = exit.code or 0
        return code, stdout.getvalue(), stderr.getvalue()

    def test_success_restores_only_backup_keys_and_retains_backup(self):
        before = self.backup.read_bytes()
        code, stdout, stderr = self.run_uninstall()
        self.assertEqual(code, 0); self.assertEqual(stderr, ''); self.assertIn('restored', stdout)
        self.assertFalse(self.agent.exists()); self.assertEqual(self.backup.read_bytes(), before)
        self.assertEqual(self.config.read_bytes(), b'private sentinel')
        self.assertEqual(self.commands[1:], [
            ['/usr/bin/defaults', 'write', 'com.Ebullioscopic.Atoll', 'selectedAIProvider', '-string', 'Original Provider'],
            ['/usr/bin/defaults', 'delete', 'com.Ebullioscopic.Atoll', 'localModelEndpoint']])

    def test_bootout_failure_preserves_plist_and_does_not_restore_defaults(self):
        self.bootout_code = 5
        code, stdout, stderr = self.run_uninstall()
        self.assertNotEqual(code, 0); self.assertNotIn('restored', stdout)
        self.assertIn('bootout', stderr); self.assertIn('returncode=5', stderr)
        self.assertTrue(self.agent.exists()); self.assertEqual(len(self.commands), 1)
        self.assertTrue(self.backup.exists())

    def test_not_loaded_is_expected_and_still_restores_backup(self):
        self.bootout_code = 3
        code, stdout, stderr = self.run_uninstall()
        self.assertEqual(code, 0); self.assertEqual(stderr, '')
        self.assertIn('already unloaded', stdout); self.assertIn('restored', stdout)
        self.assertFalse(self.agent.exists())

    def test_failed_defaults_write_or_delete_keeps_plist_and_backup_for_retry(self):
        for key in self.original:
            with self.subTest(key=key):
                self.default_failure = (key, 1, 'private failure details')
                code, stdout, stderr = self.run_uninstall()
                self.assertNotEqual(code, 0); self.assertNotIn('restored', stdout)
                self.assertIn(key, stderr); self.assertIn('returncode=1', stderr)
                self.assertNotIn('private', stderr); self.assertNotIn('sensitive', stderr)
                self.assertTrue(self.agent.exists()); self.assertTrue(self.backup.exists())
        self.default_failure = None; self.bootout_code = 3
        self.assertEqual(self.run_uninstall()[0], 0); self.assertFalse(self.agent.exists())

    def test_already_absent_default_is_successful_restoration(self):
        self.default_failure = ('localModelEndpoint', 1,
            'The domain/default pair of (com.Ebullioscopic.Atoll, localModelEndpoint) does not exist')
        self.assertEqual(self.run_uninstall()[0], 0); self.assertFalse(self.agent.exists())

    def test_missing_or_invalid_backup_stops_before_service_changes(self):
        for value in (None, 'not json', '[]', '{}', '{"selectedAIProvider": 7, "localModelEndpoint": null}',
                      '{"selectedAIProvider": null, "localModelEndpoint": null, "api_key": "bad"}'):
            with self.subTest(value=value):
                if value is None: self.backup.unlink(missing_ok=True)
                else: self.backup.write_text(value)
                code, stdout, stderr = self.run_uninstall()
                self.assertNotEqual(code, 0); self.assertNotIn('restored', stdout)
                self.assertIn('backup', stderr)
                self.assertTrue(self.agent.exists()); self.assertEqual(self.commands, [])


if __name__ == '__main__': unittest.main()
