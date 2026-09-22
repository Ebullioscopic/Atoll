#!/usr/bin/env python3
from pathlib import Path
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift')
s=p.read_text()
old='''        if ProcessInfo.processInfo.arguments.contains("--gitee-notch-preview"), GIStore.shared.demoMode {
            window?.orderOut(nil)
            GINotchPreviewProbe.run()
        }
'''
assert s.count(old)==1
s=s.replace(old,'')
old='''                                .padding(.horizontal, 8).padding(.vertical, 5)'''
assert s.count(old)==1
s=s.replace(old,'''                                .padding(.horizontal, 8).padding(.vertical, 3)''')
a=s.index('struct GINotchView: View {');b=s.index('struct GIReaderRootView: View {',a)
s=s[:a]+s[a:b].replace('VStack(alignment: .leading, spacing: 6)', 'VStack(alignment: .leading, spacing: 4)')+s[b:]
a=s.index('/// Explicit synthetic regression only.')
s=s[:a]+r'''/// Explicit synthetic regression only. Never runs on a normal application launch.
/// The real delegate is passed from the existing demo launch closure: SwiftUI may
/// install a delegate adaptor, so NSApp.delegate must not be cast to AppDelegate.
@MainActor
enum GINotchPreviewProbe {
    static func run(app: AppDelegate) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--gitee-notch-preview"), GIStore.shared.demoMode,
              let output = ProcessInfo.processInfo.environment["TOOLISLE_NOTCH_PREVIEW_RESULT"] else { return }
        GIReaderWindowController.shared.window?.orderOut(nil)
        NSApp.appearance = NSAppearance(named: args.contains("--notch-dark") ? .darkAqua : .aqua)
        Defaults[.enableMinimalisticUI] = false
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.firstLaunch = false
        coordinator.alwaysShowTabs = true
        if args.contains("--notch-filtered") { GIStore.shared.query = "fixture-no-match" }
        coordinator.currentView = .giteeIssues
        let models = [app.vm] + Array(app.viewModels.values)
        for vm in models { vm.open(); vm.setAutoCloseSuppression(true, token: UUID()) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let window = app.window ?? app.windows.values.first
            let value: [String: Any] = [
                "synthetic_data": true, "private_account_tested": false,
                "window_id": window?.windowNumber ?? -1,
                "width": Double(window?.frame.width ?? 0), "height": Double(window?.frame.height ?? 0),
                "gitee_selected": coordinator.currentView == .giteeIssues,
                "loaded": GIStore.shared.items.count, "filtered": GIStore.shared.filteredItems.count,
                "outer_appearance": args.contains("--notch-dark") ? "dark" : "light"
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: value, options: .prettyPrinted)
                try data.write(to: URL(fileURLWithPath: output))
            } catch {
                try? String(describing: error).write(toFile: output + ".error", atomically: true, encoding: .utf8)
            }
        }
    }
}
'''
p.write_text(s)
p=Path('DynamicIsland/DynamicIslandApp.swift');s=p.read_text()
old='''                GIStore.shared.startDemo()
                GIReaderWindowController.shared.show()
'''
assert s.count(old)==1
s=s.replace(old,old+'''                GINotchPreviewProbe.run(app: self)
''')
p.write_text(s)
print('Kept ordinary launch unchanged; real delegate only supplied by existing explicit demo/smoke branch.')
