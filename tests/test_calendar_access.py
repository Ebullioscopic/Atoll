import pathlib
import platform
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "Requires EventKit")
class CalendarAccessTests(unittest.TestCase):
    def test_calendar_and_reminder_permissions_are_independent(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = pathlib.Path(directory) / "calendar-access"
            subprocess.run([
                "swiftc", str(ROOT / "DynamicIsland/helpers/CalendarAccess.swift"),
                str(ROOT / "tests/CalendarAccessRegression.swift"), "-o", str(executable),
            ], check=True, cwd=ROOT)
            subprocess.run([str(executable)], check=True, cwd=ROOT)


if __name__ == "__main__":
    unittest.main()
