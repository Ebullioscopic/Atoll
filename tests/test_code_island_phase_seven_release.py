import os
import json
import pathlib
import re
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "Packages" / "CodeIsland"


class CodeIslandPhaseSevenReleaseTests(unittest.TestCase):
    def test_localization_catalog_packages_core_code_island_copy(self):
        catalog_path = (
            PACKAGE
            / "Sources"
            / "CodeIslandUI"
            / "Resources"
            / "CodeIsland.xcstrings"
        )
        catalog = json.loads(catalog_path.read_text())
        required = {
            "Agent sessions",
            "Approval in origin",
            "Code Island",
            "Codex",
            "Completed",
            "Failed",
            "Input in origin",
            "No active sessions",
            "Open in origin",
            "Session started",
            "Set up Code Island",
            "Working",
        }

        self.assertEqual(catalog["sourceLanguage"], "en")
        self.assertTrue(required.issubset(catalog["strings"]))
        manifest = (PACKAGE / "Package.swift").read_text()
        self.assertIn('.process("Resources/CodeIsland.xcstrings")', manifest)

    def test_every_code_island_interface_literal_is_in_its_catalog(self):
        catalog_path = (
            PACKAGE
            / "Sources"
            / "CodeIslandUI"
            / "Resources"
            / "CodeIsland.xcstrings"
        )
        catalog = json.loads(catalog_path.read_text())
        sources = [
            PACKAGE / "Sources" / "CodeIslandUI" / "CodeIslandUI.swift",
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandSettings.swift",
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandHost.swift",
            ROOT
            / "DynamicIsland"
            / "components"
            / "Notch"
            / "NotchCodeIslandView.swift",
            ROOT
            / "DynamicIsland"
            / "components"
            / "Settings"
            / "SettingsView.swift",
        ]

        localized_literals = set()
        for path in sources:
            source = path.read_text()
            localized_literals.update(
                re.findall(r'ci\("((?:[^"\\]|\\.)*)"\)', source)
            )
            localized_literals.update(
                re.findall(
                    r'CodeIslandLocalization\.string\("((?:[^"\\]|\\.)*)"\)',
                    source,
                )
            )
            self.assertNotRegex(source, r"ci\((?!\s*\"|_ key)")

        settings_source = sources[1].read_text()
        self.assertNotIn("grouping.rawValue", settings_source)
        self.assertNotIn("completion.rawValue", settings_source)

        self.assertTrue(localized_literals)
        self.assertEqual(localized_literals - set(catalog["strings"]), set())

    def test_accessibility_and_reduced_motion_contracts_are_explicit(self):
        mascot = (
            PACKAGE / "Sources" / "CodeIslandUI" / "CodeIslandMascot.swift"
        ).read_text()
        dashboard = (
            PACKAGE / "Sources" / "CodeIslandUI" / "CodeIslandUI.swift"
        ).read_text()
        settings = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandSettings.swift"
        ).read_text()

        self.assertIn("@Environment(\\.accessibilityReduceMotion)", mascot)
        self.assertIn("paused: reduceMotion || animationSpeed == 0", mascot)
        self.assertIn('.accessibilityLabel(ci("Open in origin"))', dashboard)
        self.assertIn('.accessibilityLabel(ci("Animation speed"))', settings)
        self.assertIn('.accessibilityValue(animationSpeedAccessibilityValue)', settings)
        self.assertIn('.accessibilityLabel(ci("Volume"))', settings)
        self.assertIn('.accessibilityValue(soundVolumeAccessibilityValue)', settings)
        self.assertIn("host.refreshFeaturePreferences()", settings)

    def test_dashboard_and_mascot_preferences_reach_atoll_views(self):
        dashboard = (
            PACKAGE / "Sources" / "CodeIslandUI" / "CodeIslandUI.swift"
        ).read_text()
        mascot = (
            PACKAGE / "Sources" / "CodeIslandUI" / "CodeIslandMascot.swift"
        ).read_text()
        notch = (
            ROOT / "DynamicIsland" / "components" / "Notch" / "NotchCodeIslandView.swift"
        ).read_text()

        self.assertIn("grouping: CodeIslandDashboardGrouping", dashboard)
        self.assertIn("CodeIslandDashboardLayout(items: items, grouping: grouping)", dashboard)
        self.assertIn("animationSpeed: Double", mascot)
        self.assertIn("reduceMotion || animationSpeed == 0", mascot)
        self.assertIn("CodeIslandFeaturePreferenceStore.shared", notch)
        self.assertIn("grouping: featurePreferences.snapshot.dashboardGrouping", notch)
        self.assertIn("featurePreferences.snapshot.mascotsEnabled", notch)
        self.assertIn("featurePreferences.snapshot.mascotSpeedPercent", notch)

    def test_settings_expose_feature_controls_and_consent_gated_adoption(self):
        settings = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandSettings.swift"
        ).read_text()

        for contract in (
            "CodeIslandFeaturePreferenceStore.shared",
            'Text(ci("Session behavior"))',
            'Text(ci("Mascot"))',
            'Text(ci("Feature sounds"))',
            'Picker(ci("Session grouping")',
            'Picker(ci("Keep completed sessions")',
            'Toggle(ci("Smart suppression")',
            'Picker(ci("Completion pop-out")',
            'Toggle(ci("Show Dex mascot")',
            'Toggle(ci("Enable feature sounds")',
            "CodeIslandSoundPlayer.shared.play",
            'Toggle(ci("Import compatible feature preferences")',
            "importCompatiblePreferences: importPreferences",
            "_importPreferences = State(initialValue: false)",
            "compatiblePreferences.hasImportableFeaturePreferences",
        ):
            self.assertIn(contract, settings)

        for forbidden in (
            'Button("Approve',
            'Button("Deny',
            'Button("Always Allow',
            'Button("Answer',
        ):
            self.assertNotIn(forbidden, settings)

    def test_atoll_host_owns_preferences_retention_and_sound_timing(self):
        host = (
            ROOT / "DynamicIsland" / "components" / "CodeIsland" / "CodeIslandHost.swift"
        ).read_text()

        self.assertIn("CodeIslandFeaturePreferenceStore.shared", host)
        self.assertIn("runtime.applyRetentionPolicy", host)
        self.assertIn("retentionExpirationTask", host)
        self.assertIn("nextExpirationDate", host)
        self.assertIn("runtime.sessions.contains", host)
        self.assertIn("preferences: featurePreferences.snapshot.presentation", host)
        self.assertIn("CodeIslandSoundPlayer.shared.play", host)
        self.assertIn(
            "featurePreferences.snapshot.presentation.completionPresentation", host
        )
        self.assertLess(
            host.index("activePresentation = CodeIslandHostPresentation"),
            host.index("CodeIslandSoundPlayer.shared.play"),
        )

    def test_selected_sound_resources_are_packaged(self):
        sounds = PACKAGE / "Sources" / "CodeIslandUI" / "Resources" / "Sounds"
        expected = {
            "8bit_approval.wav",
            "8bit_complete.wav",
            "8bit_error.wav",
            "8bit_start.wav",
        }

        self.assertEqual({path.name for path in sounds.glob("*.wav")}, expected)
        manifest = (PACKAGE / "Package.swift").read_text()
        self.assertIn('.copy("Resources/Sounds")', manifest)
        self.assertNotIn("8bit_boot.wav", manifest)
        self.assertNotIn("8bit_submit.wav", manifest)

    def test_release_behavior_contracts(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandRuntime", temporary_path, environment)
            self._compile_module("CodeIslandUI", temporary_path, environment)

            regression = temporary_path / "code-island-phase-seven-release-regression"
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(ROOT / "tests" / "CodeIslandPhaseSevenReleaseRegression.swift"),
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

    def test_atoll_owned_preference_store(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = pathlib.Path(temporary_directory)
            environment = os.environ.copy()
            environment["CLANG_MODULE_CACHE_PATH"] = str(temporary_path / "module-cache")
            environment["SWIFT_MODULECACHE_PATH"] = str(temporary_path / "module-cache")

            self._compile_module("CodeIslandCore", temporary_path, environment)
            self._compile_module("CodeIslandRuntime", temporary_path, environment)

            regression = temporary_path / "code-island-phase-seven-preferences-regression"
            subprocess.run(
                [
                    "swiftc",
                    "-parse-as-library",
                    str(
                        ROOT
                        / "DynamicIsland"
                        / "components"
                        / "CodeIsland"
                        / "CodeIslandFeaturePreferences.swift"
                    ),
                    str(ROOT / "tests" / "CodeIslandPhaseSevenPreferencesRegression.swift"),
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
            arguments.append("-lCodeIslandCore")
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
