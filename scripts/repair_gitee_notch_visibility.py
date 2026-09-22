#!/usr/bin/env python3
"""One-time narrowly scoped repair. The workflow commits the resulting Swift diff.
No API, credential, selection persistence, settings or original Atoll services change.
"""
from pathlib import Path
p = Path('DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift')
s = p.read_text()
a = s.index('struct GINotchView: View {')
b = s.index('struct GIReaderRootView: View {', a)
s = s[:a] + r'''struct GINotchView: View {
    @ObservedObject private var store = GIStore.shared
    private let secondary = Color.white.opacity(0.70)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Gitee Issues", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                if store.demoMode { Text("演示").font(.caption2).foregroundStyle(secondary) }
                Spacer(minLength: 4)
                if store.loadingList || store.isConnecting {
                    ProgressView().controlSize(.mini).tint(.white)
                        .accessibilityLabel("正在加载 Gitee")
                }
                Button { store.refreshIssues(reset: true) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("刷新已选项目")
                    .disabled(store.account == nil || store.loadingList || store.demoMode)
                Button { GISettingsNavigation.shared.open() } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("Gitee 独立设置")
            }
            .frame(height: 24)
            .accessibilityIdentifier("gitee-notch-header")

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 6) {
                    if store.account == nil {
                        if store.isConnecting {
                            message("正在连接 Gitee…", detail: "正在验证账户并恢复查看项目。")
                        } else if let error = store.connectionError {
                            message("Gitee 连接失败", detail: error)
                            action("检查账户设置") { GISettingsNavigation.shared.open() }
                        } else {
                            message("尚未连接 Gitee", detail: "连接账户后查看关注项目的 Issue。")
                            action("连接与设置…") { GISettingsNavigation.shared.open() }
                        }
                    } else if store.selectedRepositories.isEmpty {
                        message("尚未选择查看项目", detail: "在 Gitee 设置中从 Watch / Star 勾选项目。")
                        action("选择查看项目…") { GISettingsNavigation.shared.open() }
                    } else if store.items.isEmpty {
                        if store.loadingList {
                            message("正在加载 Issues…", detail: "已选择 \(store.selectedRepositories.count) 个项目。")
                        } else if !store.listFailures.isEmpty {
                            message("项目读取失败", detail: "\(store.listFailures.count) 个项目未能加载；设置中可查看具体原因。")
                            action("重试失败项目") { store.retryFailedRepositories() }
                        } else {
                            message("暂无已加载的 Issue", detail: "当前已加载范围没有 Issue，可以刷新或检查项目选择。")
                            action("检查查看项目") { GISettingsNavigation.shared.open() }
                        }
                    } else if store.filteredItems.isEmpty {
                        message("当前筛选没有匹配的 Issue", detail: "已加载 \(store.items.count) 条，均被项目、状态或搜索条件过滤。")
                        action("清除筛选，显示已加载 Issues") {
                            store.query = ""; store.repositoryFilter = ""; store.stateFilter = "all"
                        }
                    } else {
                        ForEach(Array(store.filteredItems.prefix(3))) { item in
                            Button { GIReaderWindowController.shared.show(route: item.route) } label: {
                                HStack(alignment: .center, spacing: 8) {
                                    Image(systemName: item.issue.state == "closed" ? "checkmark.circle" : "circle.dotted")
                                        .font(.system(size: 13)).foregroundStyle(secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.issue.title).font(.system(size: 12, weight: .medium))
                                            .lineLimit(1).foregroundStyle(.white)
                                        Text(item.route.label).font(.system(size: 10))
                                            .foregroundStyle(secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Text(item.issue.stateTitle).font(.system(size: 10))
                                        .foregroundStyle(secondary).fixedSize()
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help(item.issue.title + " · " + item.route.label)
                            .accessibilityIdentifier("gitee-notch-issue-\(item.route.number)")
                        }
                    }
                    if !store.items.isEmpty && !store.listFailures.isEmpty {
                        Label("\(store.listFailures.count) 个项目加载失败，其余结果已保留", systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("gitee-notch-content")

            HStack {
                Text(store.items.isEmpty ? "只读查看" : "筛选后 \(store.filteredItems.count) / 已加载 \(store.items.count)")
                    .font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                Spacer(minLength: 4)
                Button { GIReaderWindowController.shared.show() } label: {
                    Label("打开阅读窗口", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .medium))
                }.buttonStyle(.plain).help("查看完整 Issue、评论与关联跳转")
                    .accessibilityIdentifier("gitee-notch-open-reader")
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        // Atoll's notch is always black. System light appearance previously
        // rendered primary labels black on black. Keep this override LOCAL;
        // preferredColorScheme would also change enclosing presentations.
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        // Fit below the original header within the existing 250pt Gitee panel.
        // A finite budget keeps controls visible and long/error content scrollable.
        .frame(height: 190, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("gitee-notch-surface")
        .onAppear { store.activate() }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            Text(detail).font(.system(size: 11)).foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.top, 5).accessibilityIdentifier("gitee-notch-state")
    }
    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform).buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

''' + s[b:]
# Reuse the existing explicit demo harness; no ordinary launch path is changed.
needle='''        NSApp.activate(ignoringOtherApps: true)
        // Explicit synthetic UI preview only; ordinary launches are unchanged.'''
replacement='''        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--gitee-notch-preview"), GIStore.shared.demoMode {
            window?.orderOut(nil)
            GINotchPreviewProbe.run()
        }
        // Explicit synthetic UI preview only; ordinary launches are unchanged.'''
assert s.count(needle)==1
s=s.replace(needle,replacement)
s += r'''
/// Explicit synthetic regression only. Never runs on a normal application launch.
@MainActor
private enum GINotchPreviewProbe {
    static func run() {
        guard let app = AppDelegate.shared,
              let output = ProcessInfo.processInfo.environment["TOOLISLE_NOTCH_PREVIEW_RESULT"] else { return }
        let args = ProcessInfo.processInfo.arguments
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
                "width": window?.frame.width ?? 0, "height": window?.frame.height ?? 0,
                "gitee_selected": coordinator.currentView == .giteeIssues,
                "loaded": GIStore.shared.items.count, "filtered": GIStore.shared.filteredItems.count,
                "outer_appearance": args.contains("--notch-dark") ? "dark" : "light"
            ]
            if let data = try? JSONSerialization.data(withJSONObject: value, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: output))
            }
        }
    }
}
'''
p.write_text(s)
p=Path('DynamicIsland.xcodeproj/project.pbxproj');s=p.read_text()
assert s.count('CURRENT_PROJECT_VERSION = 1640;')==2
p.write_text(s.replace('CURRENT_PROJECT_VERSION = 1640;', 'CURRENT_PROJECT_VERSION = 1641;'))
print('Changed only GINotchView, explicit demo probe, and build number.')
