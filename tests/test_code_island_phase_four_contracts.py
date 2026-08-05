import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseFourContractTests(unittest.TestCase):
    def test_phase_four_runtime_contracts_execute_without_xctest(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandRuntime", temporary_path, environment)

            for source_name in (
                "CodeIslandPhaseFourDiscoveryRegression.swift",
                "CodeIslandPhaseFourActivationRegression.swift",
                "CodeIslandPhaseFourInstallerRegression.swift",
                "CodeIslandPhaseFourSocketRegression.swift",
            ):
                regression = temporary_path / pathlib.Path(source_name).stem
                subprocess.run(
                    [
                        "swiftc",
                        "-parse-as-library",
                        str(ROOT / "tests" / source_name),
                        "-I",
                        str(temporary_path),
                        "-L",
                        str(temporary_path),
                        "-lCodeIslandCore",
                        "-lCodeIslandRuntime",
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

    def test_read_only_adoption_preview_survives_phase_five_activation(self):
        host = (
            ROOT / "DynamicIsland" / "components" / "CodeIsland" / "CodeIslandHost.swift"
        ).read_text()
        settings = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandSettings.swift"
        ).read_text()
        runtime = (
            ROOT
            / "Packages"
            / "CodeIsland"
            / "Sources"
            / "CodeIslandRuntime"
            / "CodeIslandRuntime.swift"
        ).read_text()
        project = (ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj").read_text()

        self.assertIn("CodeIslandReadOnlyDiscovery", host)
        self.assertIn("discoveryAssessment", host)
        self.assertIn("func refreshDiscovery()", host)
        self.assertIn("refreshDiscovery()", host[host.index("func start()") :])

        self.assertIn("host.discoveryAssessment", settings)
        self.assertIn("installationPlan.changes", settings)
        self.assertIn("Existing CodeIsland", settings)
        self.assertIn("Quit CodeIsland before setup", settings)
        self.assertIn("Questions and approvals stay in Codex", settings)
        self.assertIn("ProviderCapabilityRegistry.phaseFive", settings)
        self.assertIn("Confirm Codex Monitoring", settings)

        for forbidden in (
            "CodeIslandActivationCoordinator",
            "CodexManagedInstallation",
            "Always Allow",
        ):
            self.assertNotIn(forbidden, settings)

        self.assertNotIn('Toggle(ci("Activate Codex Monitoring")', settings)
        self.assertIn('Button(ci("Activate Codex Monitoring")', settings)

        self.assertIn("public static let isEnabledByDefault = false", runtime)
        self.assertIn("CodeIslandRuntime.live", host)
        self.assertIn("codeisland-bridge in Embed Code Island Helper", project)

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
        if module_name == "CodeIslandRuntime":
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
