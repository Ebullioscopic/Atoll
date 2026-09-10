"""Upgrade tests use temporary installations and fake launchd; never the installed service."""
import contextlib
import io
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import upgrade


class UpgradeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / 'home'
        self.source = Path(self.tmp.name) / 'source'; self.source.mkdir()
        self.dest = self.home / 'Library/Application Support/AtollDeepSeekBridge'
        self.dest.mkdir(parents=True)
        self.plist = self.home / 'Library/LaunchAgents/local.atoll.deepseek-bridge.plist'
        self.plist.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps({'Label': 'local.atoll.deepseek-bridge',
            'ProgramArguments': ['/usr/bin/python3', str(self.dest / 'bridge.py')]}))
        for name in upgrade.RUNTIME_FILES:
            (self.source / name).write_text('# new ' + name + '\n' if name.endswith('.py') else '// new\n')
            if name != 'jobs.py': (self.dest / name).write_text('# old ' + name + '\n')
        self.protected = {'config.json': b'{"api_key":"DO-NOT-EXPOSE","model":"old"}',
                          'settings.json': b'original settings', 'pi-agent/settings.json': b'original Pi settings', 'configure.py': b'original configure',
                          'Atoll Image Access.app/Contents/permissions': b'original permissions'}
        for name, content in self.protected.items():
            target = self.dest / name; target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content); target.chmod(0o600)
        self.loaded = True; self.calls = []; self.fail_bootstrap = 0
        def launch(args, **kwargs):
            self.calls.append(args)
            command = args[1]
            code = 0
            if command == 'print': code = 0 if self.loaded else 1
            elif command == 'bootout': self.loaded = False
            elif command == 'bootstrap':
                if self.fail_bootstrap: self.fail_bootstrap -= 1; code = 1
                else: self.loaded = True
            else: self.fail('Unexpected launchd command: ' + command)
            return subprocess.CompletedProcess(args, code, stdout='sensitive service environment', stderr='secret')
        self.addCleanup(patch.stopall)
        patch('upgrade.subprocess.run', side_effect=launch).start()
        patch('upgrade.health', return_value={'reachable': True, 'healthy': True, 'backend': 'pi',
                                             'configured': True, 'protocol_version': 2}).start()
        self.sleep = patch('upgrade.time.sleep').start()

    def assert_protected(self):
        for name, content in self.protected.items():
            self.assertEqual((self.dest / name).read_bytes(), content)
            self.assertEqual((self.dest / name).stat().st_mode & 0o777, 0o600)
        self.assertEqual(plistlib.loads(self.plist.read_bytes())['Label'], 'local.atoll.deepseek-bridge')

    def test_runtime_upgrade_backup_and_reversible_rollback(self):
        plist_before = self.plist.read_bytes()
        result = upgrade.apply(self.source, self.home)
        backup = Path(result['backup'])
        self.assertTrue(backup.is_dir())
        self.assertNotIn('config.json', [p.name for p in backup.iterdir()])
        self.assertEqual((backup / 'bridge.py').read_text(), '# old bridge.py\n')
        for name in upgrade.RUNTIME_FILES:
            self.assertEqual((self.dest / name).read_bytes(), (self.source / name).read_bytes())
        self.assert_protected(); self.assertEqual(self.plist.read_bytes(), plist_before)
        self.assertEqual([c[1] for c in self.calls if c[1] != 'print'], ['bootout', 'bootstrap'])
        rollback = upgrade.apply(self.source, self.home, rollback=backup)
        self.assertNotEqual(rollback['backup'], result['backup'])
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assertFalse((self.dest / 'jobs.py').exists())
        self.assert_protected()

    def test_unloaded_installation_stays_unloaded(self):
        self.loaded = False
        result = upgrade.apply(self.source, self.home)
        self.assertFalse(result['restarted'])
        self.assertTrue(all(call[1] == 'print' for call in self.calls))
        self.assert_protected()

    def test_refuses_missing_or_mismatched_installation_before_writes(self):
        for missing in ('plist', 'bridge'):
            target = self.plist if missing == 'plist' else self.dest / 'bridge.py'
            content = target.read_bytes(); target.unlink()
            with self.assertRaises(upgrade.UpgradeError): upgrade.apply(self.source, self.home)
            target.write_bytes(content)
        self.plist.write_bytes(plistlib.dumps({'Label': 'some.other.service', 'ProgramArguments': ['elsewhere']}))
        with self.assertRaises(upgrade.UpgradeError): upgrade.apply(self.source, self.home)
        self.assertFalse((self.dest / 'runtime-backups').exists())
        self.assertTrue(all(call[1] == 'print' for call in self.calls))

    def test_restart_failure_restores_old_runtime_and_original_service(self):
        self.fail_bootstrap = 5
        with self.assertRaisesRegex(upgrade.UpgradeError, 'restored') as failure:
            upgrade.apply(self.source, self.home)
        self.assertIn('bootstrap', str(failure.exception))
        self.assertIn('returncode=1', str(failure.exception))
        self.assertIn('attempts=5', str(failure.exception))
        self.assertNotIn('secret', str(failure.exception))
        self.assertNotIn('sensitive', str(failure.exception))
        self.assertEqual(len([c for c in self.calls if c[1] == 'bootstrap']), 6)
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assertFalse((self.dest / 'jobs.py').exists())
        self.assertTrue(self.loaded)
        self.assert_protected()

    def test_transient_bootstrap_failure_retries_then_keeps_upgrade(self):
        self.fail_bootstrap = 1
        result = upgrade.apply(self.source, self.home)
        self.assertTrue(result['restarted'])
        self.assertTrue(self.loaded)
        self.assertEqual([c[1] for c in self.calls if c[1] != 'print'],
                         ['bootout', 'bootstrap', 'bootstrap'])
        self.sleep.assert_called_once_with(.5)
        for name in upgrade.RUNTIME_FILES:
            self.assertEqual((self.dest / name).read_bytes(), (self.source / name).read_bytes())
        self.assertEqual((Path(result['backup']) / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assert_protected()

    def test_exhausted_upgrade_and_recovery_retries_report_both_failures(self):
        self.fail_bootstrap = 10
        with self.assertRaisesRegex(upgrade.UpgradeError, 'recovery was incomplete') as failure:
            upgrade.apply(self.source, self.home)
        message = str(failure.exception)
        self.assertEqual(message.count('returncode=1'), 2)
        self.assertEqual(message.count('attempts=5'), 2)
        self.assertNotIn('secret', message)
        self.assertNotIn('sensitive', message)
        self.assertEqual(len([c for c in self.calls if c[1] == 'bootstrap']), 10)
        self.assertEqual(self.sleep.call_count, 8)
        self.assertFalse(self.loaded)
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assert_protected()

    def test_bootout_failure_reports_returncode_without_changing_runtime(self):
        real_launch = upgrade.launch
        def launch(*args):
            if args[0] == 'bootout':
                return subprocess.CompletedProcess(args, 5, stdout='sensitive', stderr='secret')
            return real_launch(*args)
        with patch('upgrade.launch', side_effect=launch):
            with self.assertRaisesRegex(upgrade.UpgradeError, 'bootout failed .*returncode=5') as failure:
                upgrade.apply(self.source, self.home)
        self.assertNotIn('secret', str(failure.exception))
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assertFalse((self.dest / 'jobs.py').exists())
        self.assertTrue(self.loaded)
        self.assert_protected()

    def test_launch_errors_only_report_action_and_timeout_or_errno(self):
        for error, expected in (
            (subprocess.TimeoutExpired(['private command'], 15, output='secret', stderr='sensitive'), 'timeout=15s'),
            (OSError(13, 'secret'), 'errno=13'),
        ):
            with self.subTest(expected=expected), patch('upgrade.subprocess.run', side_effect=error):
                with self.assertRaises(upgrade.UpgradeError) as failure:
                    upgrade.restart(self.plist, 11435, require_v2=True)
                message = str(failure.exception)
                self.assertIn('bootstrap', message)
                self.assertIn(expected, message)
                self.assertNotIn('secret', message)
                self.assertNotIn('sensitive', message)
                self.assertNotIn('private', message)
        self.sleep.assert_not_called()

    def test_partial_copy_failure_restores_runtime(self):
        original = upgrade.os.replace
        failed = []
        def replace(source, target):
            if Path(target) == self.dest / 'pi_backend.py' and not failed:
                failed.append(True); raise OSError('simulated partial write failure')
            return original(source, target)
        with patch('upgrade.os.replace', side_effect=replace):
            with self.assertRaisesRegex(upgrade.UpgradeError, 'restored'):
                upgrade.apply(self.source, self.home)
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assertFalse((self.dest / 'jobs.py').exists())
        self.assertTrue(self.loaded)
        self.assert_protected()

    def test_check_is_read_only_and_does_not_print_secrets(self):
        before = {str(p.relative_to(self.home)): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        result = upgrade.check(self.home)
        self.assertTrue(result['installed']); self.assertTrue(result['loaded'])
        self.assertTrue(result['health']['configured']); self.assertEqual(result['health']['backend'], 'pi')
        self.assertNotIn('DO-NOT-EXPOSE', json.dumps(result))
        self.assertNotIn('sensitive', json.dumps(result))
        after = {str(p.relative_to(self.home)): p.read_bytes() for p in self.home.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        self.assertTrue(all(call[1] == 'print' for call in self.calls))

    def test_backup_manifest_cannot_restore_config_or_outside_files(self):
        backup = Path(upgrade.apply(self.source, self.home)['backup'])
        manifest_path = backup / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['files']['config.json'] = {'sha256': 'bogus'}
        manifest_path.write_text(json.dumps(manifest))
        calls = len(self.calls)
        with self.assertRaises(upgrade.UpgradeError): upgrade.apply(self.source, self.home, rollback=backup)
        self.assertTrue(all(c[1] == 'print' for c in self.calls[calls:]))
        self.assert_protected()

    def test_symlink_runtime_target_is_rejected(self):
        target = self.dest / 'jobs.py'
        outside = self.home / 'outside.py'; outside.write_text('unchanged')
        target.symlink_to(outside)
        with self.assertRaises(upgrade.UpgradeError): upgrade.apply(self.source, self.home)
        self.assertEqual(outside.read_text(), 'unchanged')
        self.assertTrue(all(call[1] == 'print' for call in self.calls))

    def test_failed_health_check_rolls_back_after_stopping_new_service(self):
        with patch('upgrade.health', side_effect=[{'healthy': False, 'protocol_version': None},
                                                {'healthy': True, 'protocol_version': None}]), \
             patch('upgrade.time.monotonic', side_effect=[0, 20, 21]):
            with self.assertRaisesRegex(upgrade.UpgradeError, 'restored'):
                upgrade.apply(self.source, self.home)
        self.assertEqual((self.dest / 'bridge.py').read_text(), '# old bridge.py\n')
        self.assertTrue(self.loaded)
        self.assertEqual([c[1] for c in self.calls if c[1] != 'print'],
                         ['bootout', 'bootstrap', 'bootout', 'bootstrap'])
        self.assert_protected()

    def test_cli_check_cannot_invoke_upgrade(self):
        output = io.StringIO()
        with patch('upgrade.Path.home', return_value=self.home), \
             patch('upgrade.apply', side_effect=AssertionError('check attempted upgrade')), \
             contextlib.redirect_stdout(output):
            self.assertEqual(upgrade.main(['--check']), 0)
        result = json.loads(output.getvalue())
        self.assertTrue(result['health']['configured'])
        self.assertNotIn('DO-NOT-EXPOSE', output.getvalue())
        self.assertFalse((self.dest / 'runtime-backups').exists())

    def test_incomplete_source_does_not_stop_service(self):
        (self.source / 'pi-tools.ts').unlink()
        with self.assertRaises(upgrade.UpgradeError): upgrade.apply(self.source, self.home)
        self.assertTrue(self.loaded)
        self.assertFalse((self.dest / 'runtime-backups').exists())
        self.assertTrue(all(c[1] == 'print' for c in self.calls))


class HealthTests(unittest.TestCase):
    def test_loopback_health_filters_secrets_and_does_not_follow_redirects(self):
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        import threading
        requests = []
        class Handler(BaseHTTPRequestHandler):
            redirect = False
            def log_message(self, *args): pass
            def do_GET(self):
                requests.append(self.path)
                self.send_response(302 if self.redirect else 200)
                self.send_header('Location', 'https://example.invalid/must-not-follow')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'ok', 'backend': 'pi', 'configured': True,
                    'protocol_version': 2, 'api_key': 'DO-NOT-EXPOSE', 'model': 'SECRET-MODEL'}).encode())
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            result = upgrade.health(server.server_port)
            self.assertEqual(result, {'reachable': True, 'healthy': True, 'backend': 'pi',
                                     'configured': True, 'protocol_version': 2})
            self.assertNotIn('SECRET', json.dumps(result))
            Handler.redirect = True
            self.assertFalse(upgrade.health(server.server_port)['healthy'])
            self.assertEqual(requests, ['/health', '/health'])
        finally:
            server.shutdown(); server.server_close(); thread.join(2)


if __name__ == '__main__': unittest.main()
