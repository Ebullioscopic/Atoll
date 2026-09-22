#!/usr/bin/env python3
"""Idempotent, narrowly scoped integration for the existing Atoll Xcode target.
No unrelated defaults, services, permissions, display policy or updater are changed.
"""
from pathlib import Path
import subprocess
ROOT = Path(__file__).resolve().parents[1]
BASE = '9527eed3a9dcf64edbea65374de6c643265b68d3'

def replace(path, old, new, count=1):
    p = ROOT/path
    value = p.read_text()
    if new in value: return
    if value.count(old) != count:
        raise RuntimeError(f'Unexpected source context: {path}, expected {count}, got {value.count(old)}')
    p.write_text(value.replace(old, new))

def main():
    subprocess.run(['git','merge-base','--is-ancestor',BASE,'HEAD'],cwd=ROOT,check=True)
    replace('DynamicIsland/enums/generic.swift', '    case extensionExperience\n}', '    case extensionExperience\n    case giteeIssues\n}')
    replace('DynamicIsland/ContentView.swift', '                            case .extensionExperience:\n', '                            case .giteeIssues:\n                                GINotchView()\n                            case .extensionExperience:\n')
    replace('DynamicIsland/ContentView.swift', '        if coordinator.currentView == .timer {\n', '        if coordinator.currentView == .giteeIssues {\n            return CGSize(width: baseSize.width, height: max(baseSize.height, 250))\n        }\n\n        if coordinator.currentView == .timer {\n')
    replace('DynamicIsland/DynamicIslandViewCoordinator.swift', '.terminal, .extensionExperience]', '.terminal, .extensionExperience, .giteeIssues]')
    replace('DynamicIsland/DynamicIslandViewCoordinator.swift', '        // Observe all tab-affecting settings to enforce minimum notch width\n', '''        // Only the new feature is reset when its opt-in switch is turned off.
        Defaults.publisher(.enableGiteeReader, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if !change.newValue, self?.currentView == .giteeIssues { self?.currentView = .home }
            }.store(in: &cancellables)

        // Observe all tab-affecting settings to enforce minimum notch width
''')
    replace('DynamicIsland/components/Tabs/TabSelectionView.swift', '    @Namespace var animation\n', '    @Default(.enableGiteeReader) private var enableGiteeReader\n    @Namespace var animation\n')
    replace('DynamicIsland/components/Tabs/TabSelectionView.swift', '        return tabsArray\n', '''        if enableGiteeReader {
            tabsArray.append(TabModel(label: "Gitee", icon: "text.bubble", view: .giteeIssues))
        }
        return tabsArray
''')
    replace('DynamicIsland/components/Tabs/TabSelectionView.swift', '        .clipShape(Capsule())\n', '        .clipShape(Capsule())\n        .modifier(GITabOverflow(enabled: enableGiteeReader))\n')
    replace('DynamicIsland/DynamicIslandApp.swift', '            CheckForUpdatesView(updater: updaterController.updater)\n', '''            Button("Gitee Issues…") { GIReaderWindowController.shared.show() }
            CheckForUpdatesView(updater: updaterController.updater)
''')
    replace('DynamicIsland/DynamicIslandApp.swift', '    func applicationDidFinishLaunching(_ notification: Notification) {\n', '''    func applicationDidFinishLaunching(_ notification: Notification) {
        // Explicit fixture-only preview. No behavior changes during ordinary launches.
        if ProcessInfo.processInfo.arguments.contains("--gitee-reader-demo") || ProcessInfo.processInfo.arguments.contains("--gitee-reader-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                GIStore.shared.startDemo()
                GIReaderWindowController.shared.show()
            }
        }
''')
    replace('DynamicIsland/DynamicIslandApp.swift', '        } else if coordinator.currentView == .terminal {\n', '        } else if coordinator.currentView == .giteeIssues {\n            baseSize.height = max(baseSize.height, 250)\n        } else if coordinator.currentView == .terminal {\n')
    replace('DynamicIsland/components/Settings/SettingsView.swift', '        Form {\n            Section {\n                Defaults.Toggle(key: .enableMinimalisticUI)', '        Form {\n            GIReaderSettingsSection()\n            Section {\n                Defaults.Toggle(key: .enableMinimalisticUI)')
    replace('DynamicIsland.xcodeproj/project.pbxproj', 'CURRENT_PROJECT_VERSION = 1638;', 'CURRENT_PROJECT_VERSION = 1639;', count=2)
    replace('DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift', '    required init?(coder: NSCoder) { nil }', '    required init?(coder: NSCoder) { return nil }')
    replace('DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift', '            Defaults.Toggle("启用 Gitee 阅读", key: .enableGiteeReader)', '            Defaults.Toggle(key: .enableGiteeReader) { Text("启用 Gitee 阅读") }')
    replace('DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift', '    var path: String { full_name }', '''    var path: String {
        if let raw = html_url, let url = URL(string: raw),
           GIIssueLinks.hosts.contains(url.host?.lowercased() ?? "") {
            let parts = url.path.split(separator: "/")
            if parts.count == 2 { return parts.joined(separator: "/") }
        }
        return full_name
    }''')
    replace('DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift', '        if current?.route == route && current?.fragment == fragment { return }', '        if current?.route == route && current?.fragment == nil && fragment == nil { return }')
    replace('DynamicIsland/ToolIsleFeatures/Gitee/GIStore.swift', '        if !force, pages[visit.route] != nil { return }', '''        if !force, let cached = pages[visit.route] {
            if let anchor = GIIssueLinks.commentID(visit.fragment), !visit.anchorHandled,
               !cached.comments.contains(where: { $0.id == anchor }), cached.hasMoreComments {
                // Fall through to the bounded anchor-aware load below.
            } else { return }
        }''')
    print('Minimal integration applied. Review git diff before committing.')

if __name__ == '__main__': main()
