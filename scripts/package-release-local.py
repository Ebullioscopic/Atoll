#!/usr/bin/env python3
"""Package an existing arm64 Release build for local use (no notarization)."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import hashlib

project = Path(__file__).resolve().parents[1]
workspace = project.parent
source = workspace / 'build/DerivedData/Build/Products/Release/Atoll.app'
output = workspace / 'dist'
if not source.is_dir():
    raise SystemExit('Build Release first with scripts/build-release-local.command')
output.mkdir(exist_ok=True)
app = output / 'Atoll.app'
if app.exists():
    raise SystemExit('dist/Atoll.app already exists; retain or move it before packaging again.')
subprocess.run(['ditto', str(source), str(app)], check=True)
info_path = app / 'Contents/Info.plist'
with info_path.open('rb') as handle:
    info = plistlib.load(handle)
assert info['CFBundleIdentifier'] == 'com.Ebullioscopic.Atoll'
info['SUEnableAutomaticChecks'] = False
info['SUAllowsAutomaticUpdates'] = False
info['AtollLocalBuild'] = True
with info_path.open('wb') as handle:
    plistlib.dump(info, handle)
version = info['CFBundleShortVersionString']
with tempfile.TemporaryDirectory(prefix='atoll-release-') as temporary:
    temp = Path(temporary)
    with (project / 'DynamicIsland/DynamicIsland.entitlements').open('rb') as handle:
        entitlements = plistlib.load(handle)
    def expand(value):
        if isinstance(value, str):
            return value.replace('$(PRODUCT_BUNDLE_IDENTIFIER)', info['CFBundleIdentifier'])
        if isinstance(value, list):
            return [expand(item) for item in value]
        if isinstance(value, dict):
            return {key: expand(item) for key, item in value.items()}
        return value
    entitlements_path = temp / 'Atoll.entitlements'
    with entitlements_path.open('wb') as handle:
        plistlib.dump(expand(entitlements), handle)
    # Sign nested code first, then the main executable with its own capabilities.
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--force', '--options', 'runtime', '--entitlements',
                    str(entitlements_path), '--sign', '-', str(app)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    stage = temp / 'image'
    stage.mkdir()
    subprocess.run(['ditto', str(app), str(stage / 'Atoll.app')], check=True)
    (stage / 'Applications').symlink_to('/Applications')
    (stage / '安装说明.txt').write_text(
        '将 Atoll.app 拖入 Applications 即可安装。\n'
        '这是 Apple Silicon 本机 Release 定制版，使用本机临时签名，未做 Apple 公证。\n'
        '打开 Atoll 后，从菜单选择“打开聊天助手”。\n'
        '本机 pi 桥接地址为 http://127.0.0.1:11435，需本机已有桥接服务。\n'
        '聊天窗口支持 Esc 关闭、文字缩放和窗口放大/还原。\n', encoding='utf-8')
    dmg = output / f'Atoll-{version}-local-arm64.dmg'
    subprocess.run(['hdiutil', 'create', '-volname', 'Atoll', '-srcfolder', str(stage),
                    '-format', 'UDZO', str(dmg)], check=True)
    subprocess.run(['hdiutil', 'verify', str(dmg)], check=True)
    digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
    (output / 'SHA256SUMS.txt').write_text(f'{digest}  {dmg.name}\n')
    print(f'Packaged: {app}\nInstaller: {dmg}')
