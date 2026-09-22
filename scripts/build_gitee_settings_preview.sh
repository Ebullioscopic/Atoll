#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${RUNNER_TEMP:=${TMPDIR:-/tmp}/toolisle-gitee-build}"
export RUNNER_TEMP
OUT="$RUNNER_TEMP/gitee-fix-output"
export OUT
mkdir -p "$OUT"
{ sw_vers; xcodebuild -version; uname -m; git rev-parse HEAD; } > "$OUT/environment.txt"
python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle tests.test_notch_display_selection 2>&1 | tee "$OUT/upstream-tests.txt"
python3 -m unittest discover -s tests -p 'test_gitee_settings.py' 2>&1 | tee "$OUT/settings-tests.txt"
for test in GiteeReaderRegression GiteeRepositoryPathRegression; do
  swiftc DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift "tests/$test.swift" -o "$RUNNER_TEMP/$test"
  "$RUNNER_TEMP/$test" | tee "$OUT/$test.txt"
done
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -downloadComponent MetalToolchain
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$RUNNER_TEMP/GiteeFixDerivedData" \
  -disableAutomaticPackageResolution ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='' CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp=none' 2>&1 | tee "$OUT/build.log"
PKG="$RUNNER_TEMP/ToolIsleGiteeFix"
export PKG
mkdir -p "$PKG"
ditto "$RUNNER_TEMP/GiteeFixDerivedData/Build/Products/Release/ToolIsle.app" "$PKG/ToolIsle.app"
export APP="$PKG/ToolIsle.app"
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist"
python3 - <<'PY' | tee "$OUT/package-audit.json"
import os,json,plistlib,hashlib,shutil
from pathlib import Path
app=Path(os.environ['APP']); r=app/'Contents/Resources'; info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleExecutable']=='ToolIsle' and info['CFBundleDisplayName']=='ToolIsle'
assert str(info['CFBundleVersion'])=='1640'
for name in ('gitee-markdown.js','gitee-markdown-licenses.txt'):
    src=Path('DynamicIsland/ToolIsleFeatures/Gitee/Resources')/name
    assert (r/name).read_bytes()==src.read_bytes(),name
assert (r/'gitee-markdown-licenses.txt').stat().st_size>2000
movies=list(Path('DynamicIsland/BluetoothHUDAnimations').glob('*.mov'));assert len(movies)==8
for src in movies:
    data=src.read_bytes();assert len(data)>100000 and not data.startswith(b'version https://git-lfs')
    (r/'BluetoothHUDAnimations').mkdir(exist_ok=True)
    shutil.copy2(src,r/src.name);shutil.copy2(src,r/'BluetoothHUDAnimations'/src.name)
ent=plistlib.loads((Path(os.environ['OUT'])/'entitlements.plist').read_bytes())
assert 'com.ebullioscopic.Atoll.xpc' in ent.get('com.apple.security.mach-services',[])
print(json.dumps({'name':info['CFBundleDisplayName'],'bundle_id':info['CFBundleIdentifier'],'build':info['CFBundleVersion'],'minimum_os':info.get('LSMinimumSystemVersion'),'real_movies':len(movies),'original_permissions_retained':True,'notarized':False},indent=2))
PY
codesign --force --sign '-' --timestamp=none --options runtime --entitlements "$OUT/entitlements.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tee "$OUT/codesign.txt"
python3 - <<'PY'
import os,json,subprocess,time,socket
from pathlib import Path
out=Path(os.environ['OUT']);binary=Path(os.environ['APP'])/'Contents/MacOS/ToolIsle'
def stop(p):
    p.terminate()
    try:p.wait(timeout=10)
    except subprocess.TimeoutExpired:p.kill();p.wait()
with (out/'normal-launch.log').open('w') as log:
    p=subprocess.Popen([str(binary)],stdout=log,stderr=subprocess.STDOUT)
    time.sleep(15);alive=p.poll() is None;rpc=False
    try:
        with socket.create_connection(('127.0.0.1',9020),timeout=3):rpc=True
    except OSError:pass
    if alive:stop(p)
    (out/'normal-launch.json').write_text(json.dumps({'alive_after_15_seconds':alive,'original_rpc_port_open':rpc,'ui_testing_mode':False,'physical_multidisplay_tested':False},indent=2))
    assert alive,'Original app failed normal startup'
env=os.environ.copy();env['TOOLISLE_GITEE_SMOKE_RESULT']=str(out/'webkit-navigation.json')
with (out/'reader-smoke.log').open('w') as log:
    p=subprocess.Popen([str(binary),'--gitee-reader-smoke'],env=env,stdout=log,stderr=subprocess.STDOUT)
    for _ in range(65):
        if (out/'webkit-navigation.json').exists() or p.poll() is not None:break
        time.sleep(1)
    if p.poll() is None:stop(p)
    assert (out/'webkit-navigation.json').exists(),'WebKit navigation did not finish'
    r=json.loads((out/'webkit-navigation.json').read_text())
    assert r['linked']['title']=='共享模块：跨仓库问题跟踪'
    assert r['restored']['title']=='Gitee Issue 阅读与关联跳转' and abs(r['restored']['y']-600)<12
    assert r['selected_repository_unchanged'] and r['selected_issue_unchanged']
with (out/'settings-preview.log').open('w') as log:
    p=subprocess.Popen([str(binary),'--gitee-reader-demo','--gitee-settings-preview'],stdout=log,stderr=subprocess.STDOUT)
    time.sleep(14);assert p.poll() is None
    subprocess.run(['/usr/sbin/screencapture','-x',str(out/'gitee-settings-preview.png')],check=False)
    stop(p)
(out/'private-account-validation.json').write_text(json.dumps({'executed':False,'reason':'No user credentials are provided to this public CI. Local direct requests failed DNS resolution before reaching Gitee.','synthetic_tests_are_not_live_account_validation':True},indent=2))
PY
cp LICENSE NOTICE COPYRIGHT_ASSETS "$PKG/"
cp DynamicIsland/ToolIsleFeatures/Gitee/Resources/gitee-markdown-licenses.txt "$PKG/"
cp TOOLISLE-GITEE-SETTINGS-FIX.md "$PKG/README-先读.md"
ditto -c -k --sequesterRsrc --keepParent "$PKG" "$OUT/ToolIsle-2.3.3-gitee.2-macOS-arm64.zip"
hdiutil create -volname 'ToolIsle Gitee Fix' -srcfolder "$PKG" -ov -format UDZO "$OUT/ToolIsle-2.3.3-gitee.2-macOS-arm64.dmg"
git archive --format=zip --prefix=ToolIsle-gitee-fix/ -o "$OUT/ToolIsle-gitee.2-source.zip" HEAD
git diff --binary 48ed165374f43ba419cba6f6eee0e0e97caff049 HEAD > "$OUT/gitee-settings-path.patch"
git rev-parse HEAD > "$OUT/source-commit.txt"
cp TOOLISLE-GITEE-SETTINGS-FIX.md "$OUT/"
(cd "$OUT"; shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
