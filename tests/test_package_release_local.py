"""Exercise bundle validation in fresh Python processes without packaging an app."""
from pathlib import Path
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/package-release-local.py'
# Stop at the first external command, including ditto. No copying, signing, or
# image creation can occur, even if validation regresses under optimized Python.
BOOTSTRAP = """
import json
import runpy
import subprocess
import sys
def blocked(command, **kwargs):
    print(json.dumps(command))
    raise SystemExit(73)
subprocess.run = blocked
runpy.run_path(sys.argv[1], run_name='__main__')
"""


class PackageReleaseValidationTests(unittest.TestCase):
    def run_package(self, info, optimization):
        temporary = tempfile.TemporaryDirectory(prefix='atoll-package-test-')
        self.addCleanup(temporary.cleanup)
        workspace = Path(temporary.name).resolve()
        script = workspace / 'Atoll/scripts/package-release-local.py'
        script.parent.mkdir(parents=True)
        script.write_bytes(SCRIPT.read_bytes())
        source = workspace / 'build/DerivedData/Build/Products/Release/Atoll.app'
        plist = source / 'Contents/Info.plist'
        plist.parent.mkdir(parents=True)
        original = plistlib.dumps(info)
        plist.write_bytes(original)
        result = subprocess.run(
            [sys.executable, *optimization, '-c', BOOTSTRAP, str(script)],
            capture_output=True, text=True, timeout=10, cwd=workspace,
        )
        self.assertEqual(plist.read_bytes(), original, 'Source plist must remain unchanged')
        self.assertFalse((workspace / 'dist/Atoll.app').exists(), 'No real app copying')
        return result, workspace, source

    def test_invalid_or_missing_identifier_stops_before_output_or_commands(self):
        for optimization in ([], ['-O'], ['-OO']):
            for info in ({'CFBundleIdentifier': 'com.example.Wrong'}, {}):
                with self.subTest(optimization=optimization, info=info):
                    result, workspace, _ = self.run_package(info, optimization)
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn('Unexpected CFBundleIdentifier in Release build', result.stderr)
                    self.assertEqual(result.stdout, '', 'Must not reach any packaging command')
                    self.assertFalse((workspace / 'dist').exists(), 'Validate before creating output')

    def test_expected_identifier_reaches_copy_in_optimized_python(self):
        for optimization in ([], ['-O'], ['-OO']):
            with self.subTest(optimization=optimization):
                result, workspace, source = self.run_package(
                    {'CFBundleIdentifier': 'com.Ebullioscopic.Atoll'}, optimization,
                )
                self.assertEqual(result.returncode, 73, result.stderr)
                self.assertEqual(result.stderr, '')
                self.assertEqual(json.loads(result.stdout),
                                 ['ditto', str(source), str(workspace / 'dist/Atoll.app')])


if __name__ == '__main__':
    unittest.main()
