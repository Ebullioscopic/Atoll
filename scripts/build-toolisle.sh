#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
case "$MODE" in release|debug) ;; *) echo 'Usage: bash scripts/build-toolisle.sh [release|debug]' >&2; exit 2 ;; esac
if [[ "$(uname -s)" != Darwin ]]; then echo 'The macOS application must be built on macOS.' >&2; exit 1; fi
swift build -c "$MODE" --product ToolIsle
BIN="$(swift build -c "$MODE" --show-bin-path)"
APP="$PWD/dist/ToolIsle.app"
mkdir -p dist
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Resources"
cp "$BIN/ToolIsle" "$APP/Contents/MacOS/ToolIsle"
cp -R ToolIsle/App/Resources/. "$APP/Contents/Resources/Resources/"
ICON=AppIcon
BUNDLE_ID=io.github.lideming0815.toolisle
DISPLAY_NAME=ToolIsle
if [[ "$MODE" == debug ]]; then
  ICON=AppIconDev
  BUNDLE_ID=io.github.lideming0815.toolisle.dev
  DISPLAY_NAME='ToolIsle Dev'
  cp ToolIsle/App/Resources/AppIconDev.png "$APP/Contents/Resources/Resources/AppIcon.png"
fi
iconutil -c icns "ToolIsle/App/Resources/$ICON.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# Put all resolved dependency notices next to the bundled GPL/source notices.
python3 - "$APP" "$BUNDLE_ID" "$DISPLAY_NAME" <<'PY'
import pathlib, plistlib, sys
app, identifier, name = sys.argv[1:]
root = pathlib.Path(app)
info = {
 'CFBundleExecutable': 'ToolIsle', 'CFBundleIdentifier': identifier,
 'CFBundleName': name, 'CFBundleDisplayName': name, 'CFBundlePackageType': 'APPL',
 'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '2',
 'CFBundleIconFile': 'AppIcon.icns', 'LSMinimumSystemVersion': '14.0',
 'LSApplicationCategoryType': 'public.app-category.utilities',
 'NSHighResolutionCapable': True,
 'NSHumanReadableCopyright': 'ToolIsle contributors; based on Atoll. See bundled LICENSE and NOTICE.',
 'CFBundleDocumentTypes': [{'CFBundleTypeName':'Markdown document','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['net.daringfireball.markdown']}],
 'UTImportedTypeDeclarations': [{'UTTypeIdentifier':'net.daringfireball.markdown','UTTypeConformsTo':['public.plain-text'],'UTTypeDescription':'Markdown document','UTTypeTagSpecification':{'public.filename-extension':['md','markdown','mdown']}}]
}
with (root/'Contents/Info.plist').open('wb') as f: plistlib.dump(info, f)
notices=[]
for checkout in sorted(pathlib.Path('.build/checkouts').glob('*')):
 for pattern in ['LICENSE*', 'COPYING*', 'NOTICE*']:
  for file in sorted(checkout.glob(pattern)):
   if file.is_file(): notices.append('\n===== '+checkout.name+'/'+file.name+' =====\n'+file.read_text(errors='replace'))
if not notices: raise SystemExit('Dependency licenses were not found; refusing to package.')
(root/'Contents/Resources/Resources/THIRD_PARTY_LICENSES').write_text(''.join(notices))
PY
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ARCH="$(uname -m)"
(cd dist && ditto -c -k --sequesterRsrc --keepParent ToolIsle.app "ToolIsle-0.2.0-$ARCH.zip")
echo "Built $APP ($ARCH). Ad-hoc signing only; not notarized."
