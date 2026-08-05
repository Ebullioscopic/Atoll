import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseThreeDashboardTests(unittest.TestCase):
    def test_persistent_tab_and_dashboard_contract(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandUI", temporary_path, environment)

            regression = temporary_path / "code-island-phase-three-dashboard-regression"
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(ROOT / "tests" / "CodeIslandPhaseThreeDashboardRegression.swift"),
                    "-I",
                    str(temporary_path),
                    "-L",
                    str(temporary_path),
                    "-lCodeIslandCore",
                    "-lCodeIslandUI",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    str(temporary_path),
                    "-o",
                    str(regression),
                ],
                check=True,
                cwd=ROOT,
                env=environment,
            )
            subprocess.run([str(regression)], check=True, cwd=ROOT, env=environment)

        notch_views = (ROOT / "DynamicIsland" / "enums" / "generic.swift").read_text()
        tabs = (
            ROOT / "DynamicIsland" / "components" / "Tabs" / "TabSelectionView.swift"
        ).read_text()
        content = (ROOT / "DynamicIsland" / "ContentView.swift").read_text()

        self.assertLess(notch_views.index("case codeIsland"), notch_views.index("case terminal"))
        self.assertLess(
            tabs.index('label: "Code Island"'),
            tabs.index('label: "Terminal"'),
        )
        self.assertIn("case .codeIsland:", content)
        self.assertIn("NotchCodeIslandView()", content)

    @staticmethod
    def _compile_module(module_name, temporary_path, environment):
        source_directory = PACKAGE / "Sources" / module_name
        sources = sorted(str(path) for path in source_directory.glob("*.swift"))
        arguments = [
            "swiftc",
            "-parse-as-library",
            "-emit-module",
            "-emit-library",
            "-module-name",
            module_name,
            "-emit-module-path",
            str(temporary_path / f"{module_name}.swiftmodule"),
            "-I",
            str(temporary_path),
            "-L",
            str(temporary_path),
        ]
        if module_name == "CodeIslandUI":
            arguments.extend(["-lCodeIslandCore"])
        arguments.extend(
            [
                *sources,
                "-Xlinker",
                "-install_name",
                "-Xlinker",
                f"@rpath/lib{module_name}.dylib",
                "-o",
                str(temporary_path / f"lib{module_name}.dylib"),
            ]
        )
        subprocess.run(arguments, check=True, cwd=ROOT, env=environment)


if __name__ == "__main__":
    unittest.main()
