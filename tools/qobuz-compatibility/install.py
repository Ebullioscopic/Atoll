#!/usr/bin/python3
"""Guarded compatibility install for /Applications/Atoll.app 2.3.3 on Intel.
The source-built .qobuz provider does not need this binary compatibility layer.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import signal
import struct
import subprocess
import tempfile
import time

APP = Path('/Applications/Atoll.app/Contents')
ROOT = Path(__file__).resolve().parents[2]
FILES = ['MacOS/Atoll', 'Resources/qobuz_engine.py', 'Resources/mediaremote-adapter.pl', 'Resources/qobuz_controls', 'Frameworks/QobuzControls.dylib']


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def stop_owned_processes():
    processes = subprocess.check_output(['/bin/ps', '-axo', 'pid,command'], text=True)
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2:
            continue
        pid, command = fields
        owned = command == str(APP/'MacOS/Atoll') or (str(APP/'Resources/qobuz_engine.py')+' stream' in command and 'python' in command)
        if owned:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
    time.sleep(.3)


def patched_binary():
    data = bytearray((APP/'MacOS/Atoll').read_bytes())
    if data[:4] != bytes.fromhex('cafebabe'):
        raise RuntimeError('Unexpected Mach-O format; refusing to patch')
    count = struct.unpack_from('>I', data, 4)[0]
    base = None
    for index in range(count):
        cpu, _, offset, _, _ = struct.unpack_from('>IIIII', data, 8+index*20)
        if cpu == 0x01000007:
            base = offset
    if base is None:
        raise RuntimeError('x86_64 slice missing')
    point = base + 0x62e1a6
    before = bytes(data[point:point+14])
    if before not in (bytes.fromhex('48bf10000000000000d0488d5705'), bytes.fromhex('48bf11000000000000d0488d5704')):
        raise RuntimeError('Provider initializer differs from tested 2.3.3; refusing patch')
    literal = base + 0xc84280
    if bytes(data[literal:literal+16]) not in (b'com.amazon.music', b'com.qobuz.deskto'):
        raise RuntimeError('Provider string location differs; refusing patch')
    data[literal:literal+18] = b'com.qobuz.desktop\0'
    data[point+2] = 17
    data[point+13] = 4
    ncmd, size = struct.unpack_from('<II', data, base+16)
    name = b'@executable_path/../Frameworks/QobuzControls.dylib\0'
    if name not in bytes(data[base+32:base+32+size]):
        length = (24+len(name)+7)&~7
        end = base+32+size
        if end+length > base+0x2a20 or data[end:end+length] != b'\0'*length:
            raise RuntimeError('Insufficient verified header padding')
        command = (struct.pack('<IIIIII', 0xc, length, 24, 0, 0x10000, 0x10000)+name).ljust(length,b'\0')
        data[end:end+length] = command
        struct.pack_into('<II', data, base+16, ncmd+1, size+length)
    return data


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('--backup-dir', required=True, type=Path)
    options = args.parse_args()
    info = plistlib.loads((APP/'Info.plist').read_bytes())
    if platform.machine() != 'x86_64' or info.get('CFBundleIdentifier') != 'com.Ebullioscopic.Atoll' or info.get('CFBundleShortVersionString') != '2.3.3':
        raise RuntimeError('This compatibility installer is restricted to tested Intel Atoll 2.3.3')
    run(['/usr/bin/python3', '--version'], stdout=subprocess.DEVNULL)
    patched = patched_binary()  # All binary guards run before mutation.
    backup = options.backup_dir.resolve()
    backup.mkdir(parents=True, exist_ok=False)
    manifest = []
    for relative in FILES:
        source = APP/relative
        manifest.append({'path':relative,'existed':source.exists()})
        if source.exists():
            target = backup/relative; target.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,target)
    (backup/'manifest.json').write_text(json.dumps(manifest,indent=2))
    stop_owned_processes()
    try:
        with tempfile.TemporaryDirectory(prefix='atoll-qobuz-build-') as scratch:
            scratch = Path(scratch)
            dylib = scratch/'QobuzControls.dylib'; helper = scratch/'qobuz_controls'
            run(['/usr/bin/clang','-dynamiclib','-fblocks','-O2','-framework','CoreFoundation','-install_name','@executable_path/../Frameworks/QobuzControls.dylib',str(ROOT/'tools/qobuz-compatibility/QobuzControls.c'),'-o',str(dylib)])
            run(['/usr/bin/swiftc','-O','-module-cache-path',str(scratch/'module-cache'),str(ROOT/'mediaremote-adapter/qobuz_controls.swift'),'-o',str(helper)])
            (APP/'Frameworks').mkdir(exist_ok=True)
            for source, relative in [(dylib,'Frameworks/QobuzControls.dylib'),(helper,'Resources/qobuz_controls'),(ROOT/'mediaremote-adapter/qobuz_engine.py','Resources/qobuz_engine.py'),(ROOT/'tools/qobuz-compatibility/legacy-mediaremote-adapter.pl','Resources/mediaremote-adapter.pl')]:
                shutil.copy2(source,APP/relative); (APP/relative).chmod(0o755)
            (APP/'MacOS/Atoll').write_bytes(patched); (APP/'MacOS/Atoll').chmod(0o755)
            run(['/usr/bin/codesign','--force','--sign','-',str(APP/'Frameworks/QobuzControls.dylib')])
            run(['/usr/bin/codesign','--force','--sign','-',str(APP/'Resources/qobuz_controls')])
            run(['/usr/bin/codesign','--force','--sign','-',str(APP.parent)])
            run(['/usr/bin/codesign','--verify','--deep','--strict',str(APP.parent)])
        run(['/usr/bin/defaults','write','com.Ebullioscopic.Atoll','atollQobuzLegacyProviderSlot','-bool','true'])
        run(['/usr/bin/open',str(APP.parent)])
        print('Verified compatibility install; backup: '+str(backup))
    except Exception:
        for item in manifest:
            target = APP/item['path']
            if item['existed']:
                shutil.copy2(backup/item['path'],target)
            elif target.exists():
                target.unlink()
        run(['/usr/bin/codesign','--force','--sign','-',str(APP.parent)])
        raise


if __name__ == '__main__':
    main()
