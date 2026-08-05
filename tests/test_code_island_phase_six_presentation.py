import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseSixPresentationTests(unittest.TestCase):
    def test_dashboard_and_presentation_policy_contracts(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandRuntime", temporary_path, environment)
            self._compile_module("CodeIslandUI", temporary_path, environment)

            regression = temporary_path / "code-island-phase-six-presentation-regression"
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(ROOT / "tests" / "CodeIslandPhaseSixPresentationRegression.swift"),
                    "-I",
                    str(temporary_path),
                    "-L",
                    str(temporary_path),
                    "-lCodeIslandCore",
                    "-lCodeIslandRuntime",
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

    def test_atoll_owns_dashboard_handoff_timing_and_arbitration(self):
        host = (
            ROOT / "DynamicIsland" / "components" / "CodeIsland" / "CodeIslandHost.swift"
        ).read_text()
        origin = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandOriginAdapter.swift"
        ).read_text()
        notch = (
            ROOT / "DynamicIsland" / "components" / "Notch" / "NotchCodeIslandView.swift"
        ).read_text()
        content = (ROOT / "DynamicIsland" / "ContentView.swift").read_text()
        bridge = (
            PACKAGE / "Sources" / "CodeIslandBridge" / "main.swift"
        ).read_text()

        self.assertIn("CodeIslandDashboardProjection(sessions: runtime.sessions)", host)
        self.assertIn("CodeIslandPresentationPolicy", host)
        self.assertIn("queuedIntents", host)
        self.assertIn("discardQueuedIntents(for: intent.subject)", host)
        self.assertIn("originAdapter.exactMatch", host)
        self.assertIn("schedulePresentationExpiration(after: 2.0)", host)
        self.assertIn("schedulePresentationExpiration(after: 5.0)", host)
        self.assertIn("schedulePresentationExpiration(after: 4.0)", host)

        self.assertIn("CodeIslandExactOriginMatcher", origin)
        self.assertIn('case "com.apple.terminal"', origin)
        self.assertIn('case "com.googlecode.iterm2"', origin)
        self.assertIn("application-only visibility remains unknown", origin)
        self.assertIn("host.openOrigin(item.origin)", notch)
        self.assertIn("NotchCodeIslandActivityView", notch)
        self.assertIn("CodeIslandCodexMascotView", notch)

        self.assertIn("codeIslandArbitrationSnapshot", content)
        self.assertIn(".systemOrPrivacy", content)
        self.assertIn(".noncritical", content)
        self.assertIn("case codeIsland(CodeIslandHostPresentation)", content)
        self.assertIn("codeIslandStandalonePresentation", content)
        self.assertIn("&& !localSendLiveActivityActive", content)
        self.assertIn(
            "&& !(Defaults[.enableDownloadListener] && downloadManager.isDownloading)",
            content,
        )

        self.assertIn('Darwin.open("/dev/tty"', bridge)
        self.assertIn('bridgeEnvironment["TTY"] = tty', bridge)

        combined = "\n".join((host, origin, notch))
        for forbidden in (
            "NSPanel",
            'Button("Approve',
            'Button("Deny',
            'Button("Always Allow',
            "requestUserInput",
        ):
            self.assertNotIn(forbidden, combined)

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
        if module_name in ("CodeIslandRuntime", "CodeIslandUI"):
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
