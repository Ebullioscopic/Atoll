import pathlib
import platform
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "Requires macOS Mach task accounting")
class MemoryFootprintTests(unittest.TestCase):
    def test_clean_file_mapping_is_not_charged_as_private_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = pathlib.Path(directory) / "memory-footprint"
            subprocess.run(
                ["swiftc",
                 str(ROOT / "DynamicIsland/managers/MemoryUsageMonitor.swift"),
                 str(ROOT / "tests/MemoryFootprintRegression.swift"),
                 "-o", str(executable)],
                check=True, cwd=ROOT,
            )
            subprocess.run([str(executable)], check=True, cwd=ROOT)


if __name__ == "__main__":
    unittest.main()
