import os
import pathlib
import json
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseFiveContractTests(unittest.TestCase):
    def test_runtime_contracts_execute_without_xctest(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandRuntime", temporary_path, environment)
            bridge = self._compile_bridge(temporary_path, environment)
            self._assert_bridge_process_contract(bridge, environment)
            for source_name in (
                "CodeIslandPhaseFiveBridgeRegression.swift",
                "CodeIslandPhaseFiveListenerRegression.swift",
                "CodeIslandPhaseFiveAdoptionRegression.swift",
                "CodeIslandPhaseFiveRuntimeRegression.swift",
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

    def test_helper_is_built_embedded_signed_and_live_socket_is_required_in_ci(self):
        project = (ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj").read_text()
        ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
        release = (ROOT / ".github" / "workflows" / "release.yml").read_text()

        self.assertIn("codeisland-bridge in Embed Code Island Helper", project)
        self.assertIn("productName = codeisland-bridge;", project)
        self.assertIn("CodeSignOnCopy", project)
        self.assertIn("dstPath = Contents/Helpers;", project)
        self.assertNotIn("codeisland-bridge in Frameworks", project)

        self.assertIn("CODEISLAND_REQUIRE_LIVE_SOCKET: 1", ci)
        self.assertIn("AtollDerivedData", ci)
        self.assertIn("Contents/Helpers/codeisland-bridge", ci)
        self.assertIn("codesign --verify --strict", ci)

        self.assertIn("Contents/Helpers/codeisland-bridge", release)
        self.assertIn("codesign --verify --strict", release)

    def test_atoll_host_exposes_explicit_monitoring_consent_without_decision_controls(self):
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
        capabilities = (
            PACKAGE
            / "Sources"
            / "CodeIslandRuntime"
            / "ProviderCapabilities.swift"
        ).read_text()

        self.assertIn("CodeIslandRuntime.live", host)
        self.assertIn("runtime.start(plan:", host)
        self.assertIn("func activateCodex", host)
        self.assertIn(".consent(confirmedByUser: true)", host)
        self.assertIn("runtime.deactivate()", host)
        self.assertIn("runtime.repair(plan:", host)
        self.assertIn("runtime.shutdown()", host)

        self.assertIn("ProviderCapabilityRegistry.phaseFive", settings)
        self.assertIn("Activate Codex Monitoring", settings)
        self.assertIn("Confirm Codex Monitoring", settings)
        self.assertIn("installationPlan.changes", settings)
        self.assertIn("Questions and approvals stay in Codex", settings)
        self.assertIn("Run /hooks in Codex", settings)
        self.assertIn("Deactivate", settings)
        self.assertIn("Verify & Repair", settings)

        for forbidden in (
            "Approve",
            "Deny",
            "Always Allow",
            "Submit Answer",
            "requestUserInput",
        ):
            self.assertNotIn(forbidden, settings)

        self.assertIn("public static let phaseFive", capabilities)
        self.assertIn("isActivationAvailable: true", capabilities)

    def _compile_bridge(self, temporary_path, environment):
        bridge = temporary_path / "codeisland-bridge"
        subprocess.run(
            [
                "swiftc",
                str(PACKAGE / "Sources" / "CodeIslandBridge" / "main.swift"),
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
                str(bridge),
            ],
            check=True,
            cwd=ROOT,
            env=environment,
        )
        return bridge

    def _assert_bridge_process_contract(self, bridge, environment):
        missing_socket = "/private/tmp/atoll-phase-five-missing.sock"
        base_arguments = [
            str(bridge),
            "--source",
            "codex",
            "--socket",
            missing_socket,
            "--managed-by-atoll",
            "phase-five-test",
        ]
        stop = subprocess.run(
            base_arguments,
            input=json.dumps(
                {
                    "session_id": "thr_stop_process",
                    "hook_event_name": "Stop",
                    "last_assistant_message": "private response",
                }
            ).encode(),
            capture_output=True,
            check=False,
            cwd=ROOT,
            env=environment,
            timeout=5,
        )
        self.assertEqual(0, stop.returncode)
        self.assertEqual(b"{}", stop.stdout)
        self.assertEqual(b"", stop.stderr)

        permission = subprocess.run(
            base_arguments,
            input=json.dumps(
                {
                    "session_id": "thr_permission_process",
                    "hook_event_name": "PermissionRequest",
                    "tool_input": {"command": "private command"},
                }
            ).encode(),
            capture_output=True,
            check=False,
            cwd=ROOT,
            env=environment,
            timeout=5,
        )
        self.assertEqual(0, permission.returncode)
        self.assertEqual(b"", permission.stdout)
        self.assertEqual(b"", permission.stderr)

        # A provider pipe that remains open must not strand Stop without the
        # event-specific JSON Codex requires for a successful hook.
        held_open_stop = subprocess.Popen(
            base_arguments,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=ROOT,
            env=environment,
        )
        held_open_stop.stdin.write(
            json.dumps(
                {
                    "session_id": "thr_stop_held_open",
                    "hook_event_name": "Stop",
                }
            ).encode()
        )
        held_open_stop.stdin.flush()
        held_open_stop.wait(timeout=5)
        held_open_stdout = held_open_stop.stdout.read()
        held_open_stderr = held_open_stop.stderr.read()
        held_open_stop.stdin.close()
        held_open_stop.stdout.close()
        held_open_stop.stderr.close()
        self.assertEqual(0, held_open_stop.returncode)
        self.assertEqual(b"{}", held_open_stdout)
        self.assertEqual(b"", held_open_stderr)

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
