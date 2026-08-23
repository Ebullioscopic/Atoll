import plistlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "DynamicIsland" / "DynamicIsland.entitlements"
PROJECT = ROOT / "DynamicIsland.xcodeproj" / "project.pbxproj"
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
TR_INFOPLIST_STRINGS = ROOT / "DynamicIsland" / "tr.lproj" / "InfoPlist.strings"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_notes_sync_is_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        self.assertIn(
            "com.apple.Notes",
            entitlements["com.apple.security.temporary-exception.apple-events"],
        )

    def test_automation_usage_text_names_notes(self):
        project = PROJECT.read_text()

        descriptions = re.findall(
            r'INFOPLIST_KEY_NSAppleEventsUsageDescription = "([^"]+)";', project
        )

        # One per build configuration: a missing one is an automation prompt
        # with no explanation on that configuration.
        self.assertEqual(2, len(descriptions))

        # Matched on the app names rather than the whole sentence. The sentence
        # legitimately grows as Atoll automates more apps, and pinning it word
        # for word only ever fails for the wrong reason; what must not change is
        # that the text says which apps it means.
        for text in descriptions:
            for app in ("Spotify", "Apple Music", "Notes"):
                self.assertIn(app, text)

    def test_turkish_automation_usage_text_names_the_automated_apps(self):
        strings = TR_INFOPLIST_STRINGS.read_text(encoding="utf-8")

        match = re.search(
            r'"NSAppleEventsUsageDescription"\s*=\s*"([^"]+)";', strings
        )
        self.assertIsNotNone(
            match, "tr.lproj/InfoPlist.strings has no NSAppleEventsUsageDescription"
        )
        text = match.group(1)

        # App names stay in Latin script even in the Turkish localization; only
        # "Notes" is actually translated, to "Notlar".
        for app in ("Spotify", "Apple Music", "Notlar", "Terminal", "iTerm2"):
            self.assertIn(app, text)

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )

    def test_release_resigning_preserves_archived_entitlements(self):
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn(
            'codesign -d --entitlements :- "$APP_PATH" > "$ENTITLEMENTS_PATH"',
            workflow,
        )
        self.assertIn('--entitlements "$ENTITLEMENTS_PATH"', workflow)
        self.assertIn(
            'FINAL_ENTITLEMENTS_PATH="$RUNNER_TEMP/${APP_NAME}-final.entitlements"',
            workflow,
        )
        self.assertIn(
            'codesign -d --entitlements :- "$APP_PATH" > "$FINAL_ENTITLEMENTS_PATH"',
            workflow,
        )
        self.assertIn(
            '/usr/libexec/PlistBuddy -c "Print :com.apple.security.device.camera" "$FINAL_ENTITLEMENTS_PATH" | grep -qx "true"',
            workflow,
        )
        self.assertIn(
            '/usr/libexec/PlistBuddy -c "Print :com.apple.security.automation.apple-events" "$FINAL_ENTITLEMENTS_PATH" | grep -qx "true"',
            workflow,
        )

    def test_ci_checks_the_privacy_configuration(self):
        workflow = CI_WORKFLOW.read_text()

        self.assertIn("python3 -m unittest tests.test_privacy_configuration", workflow)


if __name__ == "__main__":
    unittest.main()
