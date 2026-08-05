import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class CodeIslandPhaseThreeSettingsTests(unittest.TestCase):
    def test_read_only_settings_destination_is_wired(self):
        settings = (
            ROOT / "DynamicIsland" / "components" / "Settings" / "SettingsView.swift"
        ).read_text()
        settings_page = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "CodeIsland"
            / "CodeIslandSettings.swift"
        ).read_text()
        controller = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "Settings"
            / "SettingsWindowController.swift"
        ).read_text()
        notch = (
            ROOT
            / "DynamicIsland"
            / "components"
            / "Notch"
            / "NotchCodeIslandView.swift"
        ).read_text()

        self.assertIn("case codeIsland", settings)
        self.assertLess(settings.index(".codeIsland,"), settings.index(".terminal,"))
        self.assertIn("case .codeIsland:", settings)
        self.assertIn("CodeIslandSettings()", settings)
        self.assertIn("SettingsDestination", controller)
        self.assertIn("destination: .codeIsland", notch)

        self.assertIn("ProviderCapabilityRegistry.phaseTwo", settings_page)
        self.assertIn("Monitoring", settings_page)
        self.assertIn("Not connected", settings_page)
        self.assertIn("Questions and approvals stay in Codex", settings_page)
        for forbidden in ("Toggle(", "Defaults", ".save(", "ConfigInstaller", "HookServer"):
            self.assertNotIn(forbidden, settings_page)


if __name__ == "__main__":
    unittest.main()
