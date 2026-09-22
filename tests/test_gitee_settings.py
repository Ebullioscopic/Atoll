import unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
class GiteeSettingsTests(unittest.TestCase):
    def test_general_settings_remain_unmodified(self):
        s=(R/'DynamicIsland/components/Settings/SettingsView.swift').read_text()
        section=s[s.index('struct GeneralSettings:'):s.index('struct Charge:')]
        self.assertNotIn('GIReaderSettingsSection',section)
        self.assertNotIn('enableGiteeReader',section)
    def test_dedicated_sidebar(self):
        s=(R/'DynamicIsland/components/Settings/SettingsView.swift').read_text()
        for marker in ['case gitee','SettingsForm(tab: .gitee)','GIDedicatedSettingsView()','case .extensions, .gitee:','SettingsSearchEntry(tab: .gitee']:
            self.assertIn(marker,s)
    def test_reader_routes_to_settings(self):
        s=(R/'DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift').read_text()
        self.assertNotIn('GIAccountView',s)
        self.assertNotIn('.sheet(isPresented: $settings)',s)
        self.assertIn('GISettingsNavigation.shared.open()',s)
        self.assertIn('failure.status',s)
    def test_read_only_and_selection_migration(self):
        s=(R/'DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift').read_text()
        self.assertIn('request.httpMethod = "GET"',s)
        self.assertIn('GINoRedirect',s)
        self.assertIn('struct GIRepositoryFailure',s)
        s=(R/'DynamicIsland/ToolIsleFeatures/Gitee/GIStore.swift').read_text()
        self.assertIn('retryFailedRepositories',s)
        self.assertIn('fresh[$0.id] ?? $0',s)
if __name__ == '__main__': unittest.main()
