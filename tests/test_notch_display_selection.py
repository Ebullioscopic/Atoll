"""Exercise the production selection policy, and verify integration points."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class NotchDisplaySelectionTests(unittest.TestCase):
    def test_production_policy(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = os.environ.copy()
            env['CLANG_MODULE_CACHE_PATH'] = str(Path(tmp) / 'cache')
            env['SWIFT_MODULECACHE_PATH'] = str(Path(tmp) / 'cache')
            binary = str(Path(tmp) / 'display-regression')
            subprocess.run(['swiftc', str(ROOT/'DynamicIsland/helpers/NotchDisplaySelection.swift'),
                str(ROOT/'tests/NotchDisplaySelectionRegression.swift'), '-o', binary], env=env, check=True)
            subprocess.run([binary], check=True)

    def test_window_creation_uses_resolved_screen(self):
        app = (ROOT/'DynamicIsland/DynamicIslandApp.swift').read_text()
        self.assertNotIn('for: NSScreen.main ?? NSScreen.screens.first!', app)
        self.assertIn('guard let selectedScreen = NotchDisplaySelection.screen(', app)
        self.assertIn('for: selectedScreen, with: vm', app)
        self.assertIn('if Defaults[.showOnAllDisplays] {', app)
        self.assertIn('for screen in currentScreens {', app)

    def test_automatic_preference_is_not_persisted_as_current_screen(self):
        code = (ROOT/'DynamicIsland/DynamicIslandViewCoordinator.swift').read_text()
        self.assertIn('@AppStorage("preferred_screen_name") var preferredScreen = ""', code)
        settings = (ROOT/'DynamicIsland/components/Settings/SettingsView.swift').read_text()
        self.assertIn('Text("Automatic (built-in display first)").tag("")', settings)

    def test_app_identity_and_upstream_protocols_preserved(self):
        project = (ROOT/'DynamicIsland.xcodeproj/project.pbxproj').read_text()
        self.assertEqual(project.count('PRODUCT_NAME = ToolIsle;'), 2)
        self.assertEqual(project.count('PRODUCT_MODULE_NAME = Atoll;'), 2)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = com.Ebullioscopic.Atoll;', project)
        self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = com.Ebullioscopic.Atoll.dev;', project)
        self.assertIn('/ToolIsle.app/Contents/MacOS/ToolIsle', project)
        app = (ROOT/'DynamicIsland/DynamicIslandApp.swift').read_text()
        self.assertIn('extensionXPCServiceHost.start()', app)
        self.assertIn('extensionRPCServer.start()', app)
        self.assertIn('startingUpdater: !AppRuntimeEnvironment.isUITesting', app)
        self.assertIn('at: Bundle.main.bundleURL', app)

if __name__ == '__main__':
    unittest.main()
