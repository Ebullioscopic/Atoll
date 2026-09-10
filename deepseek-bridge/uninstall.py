#!/usr/bin/env python3
"""Stop the bridge and restore its two backed-up Atoll preferences."""
import errno
import json
import os
from pathlib import Path
import subprocess
import sys

LABEL = 'local.atoll.deepseek-bridge'
DOMAIN = 'com.Ebullioscopic.Atoll'
SETTING_KEYS = ('selectedAIProvider', 'localModelEndpoint')


class UninstallError(Exception):
    pass


def run(command):
    try:
        return subprocess.run(command, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired:
        raise UninstallError('%s %s timed out; retry uninstall after checking the service.' %
                             (Path(command[0]).name, command[1])) from None
    except OSError as error:
        raise UninstallError('%s %s could not run (errno=%s).' %
                             (Path(command[0]).name, command[1], error.errno)) from None


def read_backup(path):
    # Validate before stopping launchd or changing preferences. The backup is
    # retained on every outcome, so partial restores can safely be retried.
    try:
        if path.is_symlink(): raise ValueError()
        settings = json.loads(path.read_text())
        if not isinstance(settings, dict) or set(settings) != set(SETTING_KEYS): raise ValueError()
        if any(value is not None and not isinstance(value, str) for value in settings.values()):
            raise ValueError()
        return settings
    except (OSError, ValueError, RecursionError):
        raise UninstallError('Settings backup is missing or invalid; no service or preference changes made.') from None


def already_absent(result, key):
    # defaults exits 1 for both a missing preference and real failures. Accept
    # only its explicit missing-key/domain diagnostics, never any generic rc=1.
    return result.returncode == 1 and (
        '(%s, %s) does not exist' % (DOMAIN, key) in result.stderr
        or 'Domain (%s) not found.' % DOMAIN in result.stderr)


def uninstall(home):
    dest = home / 'Library/Application Support/AtollDeepSeekBridge'
    agent = home / ('Library/LaunchAgents/' + LABEL + '.plist')
    settings = read_backup(dest / 'atoll-settings-before.json')
    stopped = run(['/bin/launchctl', 'bootout', 'gui/%d/%s' % (os.getuid(), LABEL)])
    # launchctl's ESRCH is the expected outcome for an already-unloaded job.
    if stopped.returncode not in (0, errno.ESRCH):
        raise UninstallError('launchctl bootout failed (returncode=%d); startup plist and preferences unchanged.' %
                             stopped.returncode)
    for key in SETTING_KEYS:
        value = settings[key]
        command = ['/usr/bin/defaults', 'delete', DOMAIN, key] if value is None else [
            '/usr/bin/defaults', 'write', DOMAIN, key, '-string', value]
        result = run(command)
        if result.returncode and not (value is None and already_absent(result, key)):
            raise UninstallError('defaults %s failed for %s (returncode=%d); startup plist and backup retained for retry.' %
                                 (command[1], key, result.returncode))
    # Keep the plist if restoring either preference fails. Never claim complete
    # removal while the process might still be loaded or defaults were not set.
    try:
        agent.unlink(missing_ok=True)
    except OSError as error:
        raise UninstallError('Could not remove startup plist (errno=%s); settings backup retained.' % error.errno) from None
    state = 'Service already unloaded' if stopped.returncode == errno.ESRCH else 'Service stopped'
    return state + ' and startup removed. Previous Atoll settings restored. Local configuration and settings backup retained.'


def main():
    try:
        print(uninstall(Path.home()))
        return 0
    except UninstallError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
