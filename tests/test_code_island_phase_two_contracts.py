import json
import os
import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseTwoContractTests(unittest.TestCase):
    def test_phase_two_contracts_execute_without_xctest(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = self._swift_environment(temporary_path)
            self._compile_core(temporary_path, environment)
            self._compile_runtime(temporary_path, environment)
            bridge = self._compile_bridge(temporary_path, environment)

            self._assert_fixture_behavior(bridge, environment)

            regression = self._compile_regression(temporary_path, environment)
            subprocess.run([str(regression)], check=True, cwd=ROOT, env=environment)

    def test_active_phase_two_sources_preserve_the_frozen_boundaries(self):
        active_sources = []
        for source_directory in (
            PACKAGE / "Sources" / "CodeIslandCore",
            PACKAGE / "Sources" / "CodeIslandRuntime",
            PACKAGE / "Sources" / "CodeIslandBridge",
        ):
            active_sources.extend(source_directory.glob("*.swift"))

        combined = "\n".join(path.read_text() for path in active_sources)
        bridge = (PACKAGE / "Sources" / "CodeIslandBridge" / "main.swift").read_text()
        project = (ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj").read_text()

        for forbidden in (
            "CodexAppServerClient",
            "requestUserInput",
            "SessionPersistence",
            "DiagnosticsExporter",
            "NWListener",
            "NSPanel",
        ):
            self.assertNotIn(forbidden, combined)

        self.assertNotIn("FileHandle.standardOutput.write", bridge)
        self.assertNotIn("hookSpecificOutput", bridge)
        self.assertIn("Packages/CodeIsland", project)
        self.assertIn("CodeIslandRuntime", project)
        self.assertNotIn("codeisland-bridge in Frameworks", project)

    @staticmethod
    def _swift_environment(temporary_path):
        environment = os.environ.copy()
        environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
        environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")
        return environment

    def _compile_core(self, temporary_path, environment):
        sources = sorted(
            str(path) for path in (PACKAGE / "Sources" / "CodeIslandCore").glob("*.swift")
        )
        self._run_swiftc(
            [
                "-parse-as-library",
                "-emit-module",
                "-emit-library",
                "-module-name",
                "CodeIslandCore",
                "-emit-module-path",
                str(temporary_path / "CodeIslandCore.swiftmodule"),
                *sources,
                "-Xlinker",
                "-install_name",
                "-Xlinker",
                "@rpath/libCodeIslandCore.dylib",
                "-o",
                str(temporary_path / "libCodeIslandCore.dylib"),
            ],
            environment,
        )

    def _compile_runtime(self, temporary_path, environment):
        sources = sorted(
            str(path) for path in (PACKAGE / "Sources" / "CodeIslandRuntime").glob("*.swift")
        )
        self._run_swiftc(
            [
                "-parse-as-library",
                "-emit-module",
                "-emit-library",
                "-module-name",
                "CodeIslandRuntime",
                "-emit-module-path",
                str(temporary_path / "CodeIslandRuntime.swiftmodule"),
                "-I",
                str(temporary_path),
                "-L",
                str(temporary_path),
                "-lCodeIslandCore",
                *sources,
                "-Xlinker",
                "-install_name",
                "-Xlinker",
                "@rpath/libCodeIslandRuntime.dylib",
                "-o",
                str(temporary_path / "libCodeIslandRuntime.dylib"),
            ],
            environment,
        )

    def _compile_bridge(self, temporary_path, environment):
        bridge = temporary_path / "codeisland-bridge"
        self._run_swiftc(
            [
                str(PACKAGE / "Sources" / "CodeIslandBridge" / "main.swift"),
                *self._linker_arguments(temporary_path),
                "-o",
                str(bridge),
            ],
            environment,
        )
        return bridge

    def _compile_regression(self, temporary_path, environment):
        regression = temporary_path / "code-island-phase-two-regression"
        self._run_swiftc(
            [
                "-parse-as-library",
                str(ROOT / "tests" / "CodeIslandPhaseTwoRegression.swift"),
                *self._linker_arguments(temporary_path),
                "-o",
                str(regression),
            ],
            environment,
        )
        return regression

    def _assert_fixture_behavior(self, bridge, environment):
        fixture_directory = (
            PACKAGE / "Tests" / "CodeIslandRuntimeTests" / "Fixtures" / "Codex"
        )
        fixtures = [
            json.loads(path.read_text())
            for path in sorted(fixture_directory.glob("*.json"))
        ]
        self.assertEqual(
            {
                "atoll-missing",
                "atoll-shutdown",
                "observer-timeout",
                "origin-allows",
                "origin-cancels",
                "origin-denies",
                "origin-question",
            },
            {fixture["scenario"] for fixture in fixtures},
        )

        completions = {}
        origin_outcomes = {}
        for fixture in fixtures:
            result = self._invoke_bridge(bridge, environment, fixture)
            self.assertEqual(0, result.returncode, fixture["scenario"])
            self.assertEqual(b"", result.stdout, fixture["scenario"])
            self.assertEqual(b"", result.stderr, fixture["scenario"])
            completions[fixture["scenario"]] = (
                result.returncode,
                result.stdout,
                result.stderr,
            )

            if "originOutcome" in fixture:
                origin_outcomes[fixture["scenario"]] = self._simulate_native_origin(
                    fixture,
                    result,
                )

        self.assertEqual(completions["origin-allows"], completions["origin-denies"])
        self.assertEqual("allow", origin_outcomes["origin-allows"])
        self.assertEqual("deny", origin_outcomes["origin-denies"])
        self.assertEqual("cancelled", origin_outcomes["origin-cancels"])
        self.assertEqual("answered", origin_outcomes["origin-question"])

    def _invoke_bridge(self, bridge, environment, fixture):
        if fixture["inputMode"] == "complete":
            return subprocess.run(
                [str(bridge), "--source", "codex"],
                input=json.dumps(fixture["payload"]).encode(),
                capture_output=True,
                check=False,
                cwd=ROOT,
                env=environment,
                timeout=5,
            )

        self.assertEqual("stalled", fixture["inputMode"])
        stalled = subprocess.Popen(
            [str(bridge), "--source", "codex"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=ROOT,
            env=environment,
        )
        try:
            return_code = stalled.wait(timeout=3)
            return subprocess.CompletedProcess(
                stalled.args,
                return_code,
                stdout=stalled.stdout.read(),
                stderr=stalled.stderr.read(),
            )
        finally:
            if stalled.poll() is None:
                stalled.kill()
                stalled.wait()
            for stream in (stalled.stdin, stalled.stdout, stalled.stderr):
                if stream is not None:
                    stream.close()

    def _simulate_native_origin(self, fixture, bridge_result):
        payload = fixture["payload"]
        native_surface = (
            payload.get("hook_event_name") == "PermissionRequest"
            or payload.get("method") == "item/tool/requestUserInput"
        )
        self.assertTrue(native_surface, fixture["scenario"])
        self.assertEqual(0, bridge_result.returncode, fixture["scenario"])
        self.assertEqual(b"", bridge_result.stdout, fixture["scenario"])
        return fixture["originOutcome"]

    @staticmethod
    def _linker_arguments(temporary_path):
        return [
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
        ]

    @staticmethod
    def _run_swiftc(arguments, environment):
        subprocess.run(
            ["swiftc", *arguments],
            check=True,
            cwd=ROOT,
            env=environment,
        )


if __name__ == "__main__":
    unittest.main()
