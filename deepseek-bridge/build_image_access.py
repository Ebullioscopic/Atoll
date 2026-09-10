"""Build a small AppKit permission helper using Command Line Tools (no Xcode needed)."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
source=Path(__file__).resolve().parent
app=source/'build/Atoll Image Access.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.atoll.image-access','CFBundleName':'Atoll Image Access','CFBundleExecutable':'ImageAccess','CFBundlePackageType':'APPL','LSUIElement':True}))
with tempfile.TemporaryDirectory(prefix='atoll-swift-') as cache:
 subprocess.run(['swiftc','-module-cache-path',cache,str(source/'ImageAccess.swift'),'-o',str(app/'Contents/MacOS/ImageAccess')],check=True)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
print(app)
