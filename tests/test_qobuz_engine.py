import importlib.util
import json
import sqlite3
import tempfile
import unittest
import gc
import os
import signal
import subprocess
import time
from pathlib import Path
from unittest.mock import patch

ENGINE = Path(__file__).resolve().parents[1] / 'mediaremote-adapter/qobuz_engine.py'
spec = importlib.util.spec_from_file_location('engine', ENGINE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class QobuzTelemetryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.player = self.root / 'player-0.json'
        self.db = self.root / 'qobuz.db'
        self.assets = self.root / 'tmp/Assets'
        self.assets.mkdir(parents=True)
        c = sqlite3.connect(self.db)
        c.execute('CREATE TABLE S_Track (id INTEGER, title TEXT, release_artists_names TEXT, track_artists_names TEXT, release_name TEXT, duration INTEGER, release_id TEXT)')
        c.executemany('INSERT INTO S_Track VALUES (?,?,?,?,?,?,?)', [(1, 'Normal', 'Album Artist', 'Track Artist', 'Album One', 250, 'one'), (2, 'Shuffled', 'Release Artist', 'Selected Artist', 'Album Two', 300, 'two')])
        c.commit()
        c.close()
        self.state = {'player': {'data': {'position': {'value': 750, 'timestamp': 1000000}}}, 'playqueue': {'data': {'items': [{'trackId': 1}], 'shuffledItems': [{'trackId': 2}], 'currentIndex': 0, 'shuffled': False, 'repeatMode': 'noRepeat'}}}
        self.patches = [patch.object(engine, 'PLAYER_PATH', str(self.player)), patch.object(engine, 'DB_PATH', str(self.db)), patch.object(engine, 'ASSETS_DIR', str(self.assets)), patch.object(engine, 'get_qobuz_pid', return_value=123), patch.object(engine.time, 'time', return_value=1000.5)]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def snapshot(self):
        self.player.write_text(json.dumps(self.state))
        return engine.get_qobuz_now_playing()['payload']

    def test_subsecond_position_uses_milliseconds(self):
        self.assertEqual(self.snapshot()['elapsedTime'], 0.75)

    def test_shuffle_selects_shuffled_track(self):
        self.state['playqueue']['data']['shuffled'] = True
        self.assertEqual(self.snapshot()['title'], 'Shuffled')

    def test_pause_does_not_claim_playing(self):
        self.state['player']['data']['position']['timestamp'] = 900000
        self.assertFalse(self.snapshot()['playing'])

    def test_delayed_disk_flush_does_not_hide_active_playback(self):
        self.state['player']['data']['position']['timestamp'] = 990000
        self.assertTrue(self.snapshot()['playing'])

    def test_explicit_pause_overrides_recent_position(self):
        logs = self.root / 'logs'
        logs.mkdir()
        (logs / 'rapport_qobuz0.txt').write_text('1970-01-01T00:16:40Z: Status has changed to Stopped \n')
        self.assertFalse(self.snapshot()['playing'])

    def test_old_pause_from_previous_launch_does_not_override_new_sample(self):
        logs = self.root / 'logs'
        logs.mkdir()
        (logs / 'rapport_qobuz0.txt').write_text('1970-01-01T00:15:00Z: Status has changed to Stopped \n')
        self.assertTrue(self.snapshot()['playing'])

    def test_closed_qobuz_emits_idle_and_clears_track(self):
        with patch.object(engine, 'get_qobuz_pid', return_value=None):
            payload = self.snapshot()
        self.assertFalse(payload['playing'])
        self.assertEqual(payload['title'], '')
        self.assertEqual(payload['bundleIdentifier'], 'com.qobuz.desktop')

    def test_artwork_belongs_to_selected_album(self):
        folder = self.assets / 'one'
        folder.mkdir()
        (folder / 'large_cover.png').write_bytes(b'correct')
        other = self.assets / 'other'
        other.mkdir()
        (other / 'large_cover.png').write_bytes(b'wrong')
        import base64
        self.assertEqual(base64.b64decode(self.snapshot()['artworkData']), b'correct')

    def test_track_artist_preferred_over_release_artist(self):
        self.assertEqual(self.snapshot()['artist'], 'Track Artist')

    def test_repeated_snapshots_release_sqlite_file_descriptors(self):
        self.player.write_text(json.dumps(self.state))
        was_enabled = gc.isenabled()
        gc.disable()
        try:
            for _ in range(20):
                engine.get_qobuz_now_playing()
            result = subprocess.run(['/usr/sbin/lsof', '-a', '-p', str(os.getpid()), '-Fn', str(self.db)], capture_output=True, text=True)
            self.assertNotIn('n' + str(self.db), result.stdout)
        finally:
            if was_enabled:
                gc.enable()
            gc.collect()

    def test_stream_exits_after_its_parent_exits(self):
        program = 'import subprocess,sys,time; p=subprocess.Popen([sys.executable,sys.argv[1],"stream"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL); print(p.pid,flush=True); time.sleep(30)'
        parent = subprocess.Popen(['/usr/bin/python3', '-c', program, str(ENGINE)], stdout=subprocess.PIPE, text=True)
        child = int(parent.stdout.readline())
        try:
            time.sleep(.3)
            parent.terminate()
            parent.wait(timeout=2)
            deadline = time.monotonic() + 4
            running = True
            while running and time.monotonic() < deadline:
                p = subprocess.run(['/bin/ps', '-p', str(child), '-o', 'stat='], capture_output=True, text=True)
                running = bool(p.stdout.strip()) and not p.stdout.strip().startswith('Z')
                if running:
                    time.sleep(.1)
            self.assertFalse(running, 'stream survived its parent and became an orphan')
        finally:
            if parent.poll() is None:
                parent.terminate()
                parent.wait(timeout=2)
            try:
                os.kill(child, signal.SIGTERM)
            except ProcessLookupError:
                pass
            parent.stdout.close()


if __name__ == '__main__':
    unittest.main()
