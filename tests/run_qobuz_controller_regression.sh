#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
task_dir="$(mktemp -d "${TMPDIR:-/tmp}/atoll-qobuz-test.XXXXXX")"
trap 'rm -rf "$task_dir"' EXIT
/usr/bin/python3 - "$root" "$task_dir" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); out=Path(sys.argv[2])
s=(root/'DynamicIsland/MediaControllers/NowPlayingController.swift').read_text()
(out/'Transport.swift').write_text('import Foundation\n'+s[s.index('struct NowPlayingUpdate:'):])
(out/'fixture.py').write_text('''import json,os,time
from pathlib import Path
Path(__file__).with_suffix('.pid').write_text(str(os.getpid()))
while True:
    print(json.dumps({'payload':{'bundleIdentifier':'com.qobuz.desktop','title':'Fixture','playing':False}}),flush=True)
    time.sleep(.05)
''')
PY
/usr/bin/swiftc -swift-version 5 "$root/DynamicIsland/models/PlaybackState.swift" "$root/DynamicIsland/MediaControllers/MediaControllerProtocol.swift" "$root/DynamicIsland/MediaControllers/QobuzMediaController.swift" "$task_dir/Transport.swift" "$root/tests/QobuzControllerRegression.swift" -o "$task_dir/regression"
"$task_dir/regression" "$task_dir/fixture.py"
