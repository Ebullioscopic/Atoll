#!/usr/bin/python3
"""Dedicated Qobuz telemetry. Reads only Qobuz files; never uses MediaRemote."""
import base64
import ctypes
from contextlib import closing
from datetime import datetime
import json
import os
from pathlib import Path
import sqlite3
import signal
import subprocess
import sys
import time

BUNDLE_ID = 'com.qobuz.desktop'
SUPPORT = Path.home() / 'Library/Application Support/Qobuz'
PLAYER_PATH = str(SUPPORT / 'player-0.json')
DB_PATH = str(SUPPORT / 'qobuz.db')
ASSETS_DIR = str(SUPPORT / 'tmp/Assets')
_artwork_cache = {}


def get_qobuz_pid():
    result = subprocess.run(['/usr/bin/pgrep', '-x', 'Qobuz'], capture_output=True, text=True)
    return int(result.stdout.splitlines()[0]) if result.returncode == 0 else None


def idle_snapshot():
    return {'diff': False, 'payload': {'bundleIdentifier': BUNDLE_ID,
        'parentApplicationBundleIdentifier': BUNDLE_ID, 'title': '', 'artist': '',
        'album': '', 'duration': 0, 'elapsedTime': 0, 'playing': False,
        'playbackRate': 0, 'artworkData': None, 'shuffleMode': 1, 'repeatMode': 1}}


def read_track(track_id):
    with closing(sqlite3.connect(Path(DB_PATH).as_uri() + '?mode=ro', uri=True, timeout=0.1)) as conn:
        conn.row_factory = sqlite3.Row
        row = conn.execute('SELECT * FROM S_Track WHERE id = ?', (track_id,)).fetchone()
        if row:
            return dict(row)
        row = conn.execute('SELECT t.title, t.duration, t.data, ar.name AS track_artists_names, a.title AS release_name, t.album_id AS release_id FROM L_Track t LEFT JOIN L_Artist ar ON ar.id=t.artist_id LEFT JOIN L_Album a ON a.id=t.album_id WHERE t.track_id=?', (str(track_id),)).fetchone()
        return dict(row) if row else None


def album_artwork(release_id):
    if not release_id or Path(str(release_id)).name != str(release_id):
        return None
    for name in ('large_cover.png', 'small_cover.png'):
        path = Path(ASSETS_DIR) / str(release_id) / name
        try:
            key = (str(path), path.stat().st_mtime_ns)
            if key not in _artwork_cache:
                _artwork_cache.clear()
                _artwork_cache[key] = base64.b64encode(path.read_bytes()).decode('ascii')
            return _artwork_cache[key]
        except FileNotFoundError:
            continue
    return None


def playback_is_active(position):
    # Samples use milliseconds; persistence can lag by more than 10 seconds.
    # An explicit local pause takes precedence over a recently saved sample.
    stamp = float(position.get('timestamp', 0)) / 1000
    fresh = 0 <= time.time() - stamp < 30
    if not fresh:
        return False
    logs = Path(PLAYER_PATH).parent / 'logs'
    candidates = list(logs.glob('rapport_qobuz*.txt'))
    if candidates:
        latest = max(candidates, key=lambda p: p.stat().st_mtime_ns)
        with latest.open('rb') as f:
            f.seek(max(0, latest.stat().st_size - 65536))
            lines = f.read().decode('utf-8', errors='replace').splitlines()
        for line in reversed(lines):
            if 'Status has changed to ' in line:
                try:
                    event_time = datetime.fromisoformat(line.split(': ', 1)[0].replace('Z', '+00:00')).timestamp()
                except ValueError:
                    continue
                # A stopped event from an earlier launch cannot override a new
                # position sample. Disregard future/incompatible clock values.
                if stamp - 2 <= event_time <= time.time() + 2:
                    return line.rsplit('Status has changed to ', 1)[1].strip() == 'Playing'
                break
    return fresh


def get_qobuz_now_playing():
    if not get_qobuz_pid():
        return idle_snapshot()
    try:
        state = json.loads(Path(PLAYER_PATH).read_text())
        queue = state['playqueue']['data']
        items = queue.get('shuffledItems') if queue.get('shuffled') else queue.get('items')
        index = queue.get('currentIndex', -1)
        if not items or not isinstance(index, int) or not 0 <= index < len(items):
            return idle_snapshot()
        track = read_track(items[index]['trackId'])
        if not track:
            return idle_snapshot()
        position = state['player']['data'].get('position', {})
        playing = playback_is_active(position)
        payload = idle_snapshot()['payload']
        payload.update(title=track.get('title') or '',
            artist=track.get('track_artists_names') or track.get('release_artists_names') or '',
            album=track.get('release_name') or '', duration=float(track.get('duration') or 0),
            elapsedTime=float(position.get('value', 0)) / 1000,
            playing=playing, playbackRate=1.0 if playing else 0.0,
            artworkData=album_artwork(track.get('release_id')),
            shuffleMode=3 if queue.get('shuffled') else 1,
            repeatMode={'noRepeat': 1, 'repeatAll': 3, 'repeatOne': 2}.get(queue.get('repeatMode'), 1),
            timestamp=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(float(position.get('timestamp', 0)) / 1000)),
            timestampEpochMicros=float(position.get('timestamp', 0)) * 1000)
        return {'diff': False, 'payload': payload}
    except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
        print('Qobuz telemetry: ' + str(error), file=sys.stderr, flush=True)
        return idle_snapshot()


def send_qobuz_command(command):
    # Targeted process events cannot control the foreground browser/messenger.
    pid = get_qobuz_pid()
    if not pid:
        return False
    playing = get_qobuz_now_playing()['payload']['playing']
    if command == 0 and playing or command == 1 and not playing:
        return True
    keys = {0: (49, 0), 1: (49, 0), 2: (49, 0), 4: (124, 0x100000), 5: (123, 0x100000)}
    if command not in keys:
        return False
    cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
    cf = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
    cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
    cg.CGEventSetFlags.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
    cg.CGEventPostToPid.argtypes = [ctypes.c_int, ctypes.c_void_p]
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    key, flags = keys[command]
    for down in (True, False):
        event = cg.CGEventCreateKeyboardEvent(None, key, down)
        if not event:
            return False
        cg.CGEventSetFlags(event, flags)
        cg.CGEventPostToPid(pid, event)
        cf.CFRelease(event)
    return True


if __name__ == '__main__':
    action = sys.argv[1] if len(sys.argv) > 1 else 'get'
    if action == 'get':
        print(json.dumps(get_qobuz_now_playing()), flush=True)
    elif action == 'stream':
        owner_pid = os.getppid()
        selection = next((a.split('=', 1)[1] for a in sys.argv[2:] if a.startswith('--provider-selection=')), None)
        try:
            while owner_pid > 1 and os.getppid() == owner_pid:
                if selection:
                    try:
                        result = subprocess.run(['/usr/bin/defaults', 'read', 'com.Ebullioscopic.Atoll', 'mediaController'], capture_output=True, text=True, timeout=1)
                        if result.returncode == 0 and result.stdout.strip() != selection:
                            break
                    except subprocess.TimeoutExpired:
                        pass
                print(json.dumps(get_qobuz_now_playing()), flush=True)
                time.sleep(1)
        except BrokenPipeError:
            os._exit(0)
    elif action == 'send':
        sys.exit(0 if send_qobuz_command(int(sys.argv[2])) else 1)
    elif action in ('seek', 'shuffle', 'repeat'):
        helper = Path(__file__).with_name('qobuz_controls')
        if not helper.is_file():
            print('Dedicated Qobuz accessibility helper is missing', file=sys.stderr)
            sys.exit(2)
        child = subprocess.Popen([str(helper), action, sys.argv[2]])
        def stop_child(signum, _frame):
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            sys.exit(128 + signum)
        signal.signal(signal.SIGTERM, stop_child)
        signal.signal(signal.SIGINT, stop_child)
        try:
            sys.exit(child.wait(timeout=4))
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
            print('Dedicated Qobuz control timed out', file=sys.stderr)
            sys.exit(1)
    else:
        # Unsupported controls must never fall through to global Now Playing.
        sys.exit(2)
