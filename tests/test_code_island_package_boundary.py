import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
ATOLL_PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"


class CodeIslandPackageBoundaryTests(unittest.TestCase):
    def test_package_exposes_internal_modules_without_standalone_app(self):
        manifest = (PACKAGE / "Package.swift").read_text()

        for product in ("CodeIslandCore", "CodeIslandRuntime", "CodeIslandUI"):
            self.assertRegex(
                manifest,
                rf"\.library\(\s*name:\s*\"{product}\"",
            )
        self.assertRegex(
            manifest,
            r"\.executable\(\s*name:\s*\"codeisland-bridge\"",
        )
        self.assertNotRegex(
            manifest,
            r"\.executable(?:Target)?\(\s*name:\s*\"CodeIsland\"",
        )
        self.assertNotIn("Sparkle", manifest)

    def test_standalone_application_shell_is_absent(self):
        forbidden_files = {
            "AppDelegate.swift",
            "CodeIslandApp.swift",
            "PanelWindowController.swift",
            "SettingsWindowController.swift",
            "StatusItemController.swift",
            "UpdateChecker.swift",
        }
        matches = sorted(
            str(path.relative_to(PACKAGE))
            for path in PACKAGE.rglob("*.swift")
            if path.name in forbidden_files
        )

        self.assertEqual([], matches)

    def test_deferred_platform_and_service_code_is_absent(self):
        for relative_path in ("android-watch", "apple-companion", "hardware", "ios"):
            self.assertFalse((PACKAGE / relative_path).exists(), relative_path)

        forbidden_files = {
            "AppleCompanionBluetoothPeripheral.swift",
            "AppleCompanionPayload.swift",
            "AppleCompanionPublisher.swift",
            "BuddyView.swift",
            "ESP32BridgeManager.swift",
            "ESP32FocusCoordinator.swift",
            "ESP32Protocol.swift",
            "ESP32StatePublisher.swift",
            "RemoteHost.swift",
            "RemoteInstaller.swift",
            "RemoteManager.swift",
            "SSHForwarder.swift",
        }
        matches = sorted(
            str(path.relative_to(PACKAGE))
            for path in PACKAGE.rglob("*.swift")
            if path.name in forbidden_files
        )

        self.assertEqual([], matches)

        forbidden_resources = {
            "codeisland-opencode-remote.js",
            "codeisland-remote-hook.py",
        }
        resource_matches = sorted(
            str(path.relative_to(PACKAGE))
            for path in PACKAGE.rglob("*")
            if path.name in forbidden_resources
        )

        self.assertEqual([], resource_matches)

    def test_active_codex_responder_is_not_part_of_the_package(self):
        forbidden_files = {
            "AppState+CodexAppServer.swift",
            "CodexAppServerClient.swift",
        }
        matches = sorted(
            str(path.relative_to(PACKAGE))
            for path in PACKAGE.rglob("*.swift")
            if path.name in forbidden_files
        )
        bridge = (PACKAGE / "Sources/CodeIslandBridge/main.swift").read_text()

        self.assertEqual([], matches)
        self.assertNotIn("requestUserInput", bridge)
        self.assertNotIn("PermissionRequest", bridge)
        self.assertNotIn("recv(", bridge)
        self.assertIn("exit(EXIT_SUCCESS)", bridge)

    def test_upstream_provenance_and_license_are_recorded(self):
        ledger = (PACKAGE / "UPSTREAM.md").read_text()
        notice = (ROOT / "NOTICE").read_text()

        self.assertIn("https://github.com/wxtsky/CodeIsland.git", ledger)
        self.assertIn("9e3a1eb1844f0b8bf05193228a6ffa41a013dec2", ledger)
        self.assertIn("git subtree", ledger)
        self.assertIn("2026-08-04", ledger)
        self.assertIn("Core migration staging", ledger)
        self.assertIn("AppState", ledger)
        self.assertIn("DiagnosticsExporter", ledger)
        self.assertIn("CodeIslandTests", ledger)
        self.assertIn("SessionPersistence", ledger)
        self.assertTrue((PACKAGE / "LICENSE").exists())
        self.assertIn("CodeIsland", notice)
        self.assertIn("Packages/CodeIsland/LICENSE", notice)

    def test_only_authorized_sources_are_active_outside_quarantine(self):
        manifest = (PACKAGE / "Package.swift").read_text()

        self.assertFalse((PACKAGE / "Sources/CodeIsland").exists())
        self.assertTrue((PACKAGE / "Sources/CodeIslandCore/Upstream").is_dir())
        self.assertTrue((PACKAGE / "Sources/CodeIslandRuntime/Upstream").is_dir())
        self.assertTrue((PACKAGE / "Sources/CodeIslandUI/Upstream").is_dir())
        self.assertGreaterEqual(manifest.count('exclude: ["Upstream"]'), 3)

        active_core_sources = sorted(
            path.name
            for path in (PACKAGE / "Sources/CodeIslandCore").glob("*.swift")
        )
        self.assertEqual(
            [
                "CodeIslandCore.swift",
                "SessionMetadata.swift",
                "SessionProjection.swift",
            ],
            active_core_sources,
        )

        active_runtime_sources = sorted(
            path.name
            for path in (PACKAGE / "Sources/CodeIslandRuntime").glob("*.swift")
        )
        self.assertEqual(
            [
                "ActivityIntent.swift",
                "CodeIslandRuntime.swift",
                "CodexHookAdapter.swift",
                "NonOwningHookCompletion.swift",
                "ProviderCapabilities.swift",
                "SessionMetadataStore.swift",
            ],
            active_runtime_sources,
        )

        active_ui_sources = sorted(
            path.name
            for path in (PACKAGE / "Sources/CodeIslandUI").glob("*.swift")
        )
        self.assertEqual(["CodeIslandUI.swift"], active_ui_sources)

    def test_standalone_distribution_artifacts_are_absent(self):
        forbidden_paths = (
            ".github",
            ".omg",
            "AppIcon.icon",
            "Assets.xcassets",
            "CodeIsland.entitlements",
            "Info.plist",
            "Package.resolved",
            "appcast.xml",
            "build.sh",
            "scripts",
        )
        matches = [path for path in forbidden_paths if (PACKAGE / path).exists()]

        self.assertEqual([], matches)

    def test_ci_validates_the_package_boundary_and_swift_package(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn(
            "python3 -m unittest tests.test_code_island_package_boundary",
            workflow,
        )
        for phase_three_test in (
            "tests.test_code_island_phase_three_dashboard",
            "tests.test_code_island_phase_three_activity",
            "tests.test_code_island_phase_three_settings",
        ):
            self.assertIn(phase_three_test, workflow)
        self.assertIn("swift test --package-path Packages/CodeIsland", workflow)

    def test_phase_three_modules_are_linked_without_a_second_executable(self):
        project = ATOLL_PROJECT.read_text()

        self.assertIn("Packages/CodeIsland", project)
        self.assertIn("CodeIslandCore", project)
        self.assertIn("CodeIslandRuntime", project)
        self.assertIn("CodeIslandUI", project)
        self.assertNotIn("codeisland-bridge in Frameworks", project)


if __name__ == "__main__":
    unittest.main()
