#!/usr/bin/env python3
"""Reversible runtime-only upgrade of an existing Atoll bridge. No installer side effects."""
import argparse
import datetime
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time

LABEL = 'local.atoll.deepseek-bridge'
BOOTSTRAP_ATTEMPTS = 5
BOOTSTRAP_RETRY_SECONDS = .5
RUNTIME_FILES = ('bridge.py', 'pi_backend.py', 'pi-tools.ts', 'agent_tools.py',
                 'tool_runner.py', 'images.py', 'jobs.py')


class UpgradeError(Exception):
    pass


def paths(home):
    home = Path(home)
    return (home / 'Library/Application Support/AtollDeepSeekBridge',
            home / ('Library/LaunchAgents/' + LABEL + '.plist'))


def regular(path):
    return path.is_file() and not path.is_symlink()


def installation(home):
    dest, agent = paths(home)
    if dest.is_symlink() or not dest.is_dir() or not regular(dest / 'bridge.py') or not regular(agent):
        raise UpgradeError('Existing bridge runtime and launchd plist are required; nothing was installed.')
    try:
        settings = plistlib.loads(agent.read_bytes())
        args = settings.get('ProgramArguments', [])
        if (settings.get('Label') != LABEL or not isinstance(args, list) or len(args) < 2
                or not all(isinstance(a, str) for a in args)
                or args[1] != str(dest / 'bridge.py')
                or not Path(args[0]).name.startswith('python3')):
            raise ValueError()
        port = 11435
        if '--port' in args: port = int(args[args.index('--port') + 1])
        for arg in args:
            if arg.startswith('--port='): port = int(arg.partition('=')[2])
        if not 1 <= port <= 65535: raise ValueError()
    except (OSError, ValueError, TypeError, AttributeError, IndexError, plistlib.InvalidFileException):
        raise UpgradeError('The existing plist does not describe the expected bridge service.') from None
    return dest, agent, port


def launch(*args):
    try:
        return subprocess.run(['/bin/launchctl', *args], capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        # launchctl output may contain environment variables; never print it.
        raise UpgradeError('launchctl %s timed out (timeout=15s).' % args[0]) from None
    except OSError as error:
        raise UpgradeError('launchctl %s could not run (errno=%s).' % (args[0], error.errno)) from None


def failure_reason(error, action):
    """Preserve our sanitized diagnostics, never raw OS/subprocess exception text."""
    if isinstance(error, UpgradeError): return str(error)
    if isinstance(error, OSError): return '%s failed (errno=%s).' % (action, error.errno)
    return action + ' failed (unexpected error).'


def service():
    return 'gui/%d/%s' % (os.getuid(), LABEL)


def loaded():
    return launch('print', service()).returncode == 0


def health(port=11435):
    """Read only /health on loopback; no proxies, redirects, config reads, or model calls."""
    result = {'reachable': False, 'healthy': False, 'backend': None,
              'configured': None, 'protocol_version': None}
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=2)
    try:
        connection.request('GET', '/health', headers={'Connection': 'close'})
        response = connection.getresponse()
        result['reachable'] = True
        raw = response.read(65537)
        if response.status != 200 or len(raw) > 65536: return result
        body = json.loads(raw)
        if not isinstance(body, dict): return result
        result['backend'] = 'pi' if body.get('backend') == 'pi' else 'unknown'
        result['healthy'] = body.get('status') == 'ok' and result['backend'] == 'pi'
        if type(body.get('configured')) is bool: result['configured'] = body['configured']
        if type(body.get('protocol_version')) is int and 1 <= body['protocol_version'] <= 999:
            result['protocol_version'] = body['protocol_version']
    except (OSError, http.client.HTTPException, ValueError, RecursionError):
        pass
    finally:
        connection.close()
    return result


def check(home):
    dest, _ = paths(home)
    result = {'installed': False, 'loaded': None, 'config_present': (dest / 'config.json').is_file()}
    port = 11435
    try:
        _, _, port = installation(home)
        result['installed'] = True
        result['loaded'] = loaded()
    except UpgradeError as error:
        result['note'] = str(error)
    result['health'] = health(port)
    return result


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_runtime(directory, allow_missing=False):
    for name in RUNTIME_FILES:
        path = directory / name
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise UpgradeError('Runtime path is not a regular file: ' + name)
        if not path.exists():
            if allow_missing: continue
            raise UpgradeError('Source runtime is incomplete: ' + name)
        if not allow_missing and name.endswith('.py'):
            try: compile(path.read_bytes(), name, 'exec')
            except (SyntaxError, ValueError): raise UpgradeError('Invalid Python source: ' + name) from None


def backup_runtime(dest):
    root = dest / 'runtime-backups'
    if root.is_symlink(): raise UpgradeError('Backup directory must not be a symlink.')
    root.mkdir(mode=0o700, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ-')
    backup = Path(tempfile.mkdtemp(prefix=stamp, dir=root))
    files = {}
    for name in RUNTIME_FILES:
        path = dest / name
        if path.exists():
            shutil.copy2(path, backup / name)
            files[name] = {'sha256': sha(backup / name)}
        else:
            files[name] = None
    manifest = backup / 'manifest.json'
    manifest.write_text(json.dumps({'version': 1, 'files': files}, indent=2) + '\n')
    manifest.chmod(0o600)
    return backup


def read_backup(dest, backup):
    backup = Path(backup).expanduser()
    root = dest / 'runtime-backups'
    if not backup.is_absolute(): backup = root / backup
    if (root.is_symlink() or backup.is_symlink() or backup.resolve().parent != root.resolve()
            or not regular(backup / 'manifest.json')):
        raise UpgradeError('Rollback must name a timestamped backup inside runtime-backups.')
    try:
        manifest = json.loads((backup / 'manifest.json').read_text())
        files = manifest['files']
        if manifest['version'] != 1 or not isinstance(files, dict) or set(files) != set(RUNTIME_FILES):
            raise ValueError()
        if files['bridge.py'] is None: raise ValueError()
        for name, entry in files.items():
            if entry is not None and (not regular(backup / name) or not isinstance(entry, dict)
                                      or entry.get('sha256') != sha(backup / name)):
                raise ValueError()
    except (OSError, ValueError, KeyError, TypeError):
        raise UpgradeError('Backup manifest or runtime checksums are invalid; nothing was restored.') from None
    return backup, files


def replace_runtime(dest, source, files):
    # Stage all files before changing any installed pathname. Each replacement
    # is atomic; the caller keeps the service stopped for the whole transaction.
    with tempfile.TemporaryDirectory(prefix='.runtime-stage-', dir=dest) as directory:
        stage = Path(directory)
        for name in RUNTIME_FILES:
            if files[name] is not None: shutil.copy2(source / name, stage / name)
        for name in RUNTIME_FILES:
            target = dest / name
            if files[name] is None:
                if target.exists(): target.unlink()
            else:
                os.replace(stage / name, target)


def bootout():
    result = launch('bootout', service())
    if result.returncode:
        raise UpgradeError('launchctl bootout failed (returncode=%d).' % result.returncode)


def restart(agent, port, require_v2):
    # Like install.py, tolerate launchd still removing the booted-out label.
    # A successful bootstrap proceeds to health verification, never another
    # bootstrap. Both upgrade and recovery use this same bounded retry policy.
    for attempt in range(1, BOOTSTRAP_ATTEMPTS + 1):
        result = launch('bootstrap', 'gui/%d' % os.getuid(), str(agent))
        if result.returncode == 0: break
        if attempt == BOOTSTRAP_ATTEMPTS:
            raise UpgradeError('launchctl bootstrap failed (returncode=%d, attempts=%d).' %
                               (result.returncode, attempt))
        time.sleep(BOOTSTRAP_RETRY_SECONDS)
    deadline = time.monotonic() + 12
    while True:
        status = health(port)
        if status['healthy'] and (not require_v2 or status['protocol_version'] == 2): return
        if time.monotonic() >= deadline: break
        time.sleep(.25)
    raise UpgradeError('Bridge health check failed (timeout=12s, expected=%s).' %
                       ('healthy protocol v2' if require_v2 else 'healthy backend'))


def apply(source, home, rollback=None):
    """Mutating operation. CLI defaults to real paths; tests use temporary homes."""
    source = Path(source)
    dest, agent, port = installation(home)
    if source.resolve() == dest.resolve():
        raise UpgradeError('Run the upgrade script from the source checkout, not the installed runtime.')
    validate_runtime(dest, allow_missing=True)
    if rollback is None:
        validate_runtime(source)
        desired = {name: True for name in RUNTIME_FILES}
    else:
        source, desired = read_backup(dest, rollback)
    # Serialize upgrades/rollbacks without deleting the lock inode between runs.
    lock_path = dest / '.runtime-upgrade.lock'
    if lock_path.is_symlink(): raise UpgradeError('Upgrade lock must not be a symlink.')
    with lock_path.open('a') as lock:
        try: fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise UpgradeError('Another bridge upgrade or rollback is in progress.') from None
        validate_runtime(dest, allow_missing=True)
        was_loaded = loaded()
        backup = backup_runtime(dest)
        if was_loaded: bootout()
        action = 'runtime replacement'
        try:
            replace_runtime(dest, source, desired)
            action = 'service restart'
            if was_loaded: restart(agent, port, require_v2=rollback is None)
        except Exception as error:
            reason = failure_reason(error, action)
            recovery_action = 'recovery service inspection/stop'
            try:
                # A bootstrap may succeed before health verification fails.
                # Stop that copy before restoring files; never change other jobs.
                if was_loaded and loaded(): bootout()
                recovery_action = 'runtime recovery'
                old_source, old_files = read_backup(dest, backup)
                replace_runtime(dest, old_source, old_files)
                recovery_action = 'recovery service restart'
                if was_loaded: restart(agent, port, require_v2=False)
            except Exception as recovery_error:
                raise UpgradeError('Upgrade failed and automatic recovery was incomplete. Cause: %s Recovery: %s Runtime backup: %s' %
                                   (reason, failure_reason(recovery_error, recovery_action), backup)) from None
            raise UpgradeError('Upgrade failed; previous runtime and service state were restored. Cause: %s Backup: %s' %
                               (reason, backup)) from None
        return {'action': 'rollback' if rollback is not None else 'upgrade',
                'backup': str(backup), 'restarted': was_loaded, 'service': LABEL}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--check', action='store_true', help='Read-only installation, launchd, and loopback health status; never reads the key')
    mode.add_argument('--rollback', metavar='BACKUP', help='Restore a runtime backup path or timestamped backup directory name')
    args = parser.parse_args(argv)
    try:
        if args.check:
            result = check(Path.home())
            print(json.dumps(result, indent=2))
            return 0 if result['installed'] and result['health']['healthy'] else 1
        result = apply(Path(__file__).resolve().parent, Path.home(), rollback=args.rollback)
        print(json.dumps(result, indent=2))
        return 0
    except (UpgradeError, OSError) as error:
        # Suppress raw OS/subprocess diagnostics, which may contain sensitive data.
        import sys
        print(str(error) if isinstance(error, UpgradeError) else 'Runtime upgrade could not access required files.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
