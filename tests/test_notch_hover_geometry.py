import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class NotchHoverGeometryTests(unittest.TestCase):
    def test_top_screen_edge_remains_in_notch_activation_area(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            executable = temporary_path / "notch-hover-geometry-regression"
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")
            subprocess.run(
                [
                    "swiftc",
                    str(ROOT / "DynamicIsland/utilities/NotchHoverGeometry.swift"),
                    str(ROOT / "tests/NotchHoverGeometryRegression.swift"),
                    "-o",
                    str(executable),
                ],
                check=True,
                cwd=ROOT,
                env=environment,
            )
            subprocess.run([str(executable)], check=True, cwd=ROOT)


if __name__ == "__main__":
    unittest.main()
