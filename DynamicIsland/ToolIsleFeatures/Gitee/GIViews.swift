// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

@MainActor
final class GIReaderWindowController: NSWindowController {
    static let shared = GIReaderWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 660),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Gitee Issues · ToolIsle"
        window.minSize = NSSize(width: 740, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: GIReaderRootView())
        window.center()
        window.setFrameAutosaveName("ToolIsle.GiteeReader.Window")
        super.init(window: window)
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.hidesOnDeactivate = false
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
    }
    required init?(coder: NSCoder) { return nil }
    func show(route: GIIssueRoute? = nil) {
        if let route { GIStore.shared.open(route, fromList: true) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.arguments.contains("--gitee-notch-preview"), GIStore.shared.demoMode {
            window?.orderOut(nil)
            GINotchPreviewProbe.run()
        }
        // Explicit synthetic UI preview only; ordinary launches are unchanged.
        if ProcessInfo.processInfo.arguments.contains("--gitee-settings-preview") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { GISettingsNavigation.shared.open() }
        }
    }
}

struct GINotchView: View {
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

struct GIReaderRootView: View {
    @ObservedObject private var store = GIStore.shared
    @Default(.enableGiteeReader) private var enabled
        @State private var showList = true
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !enabled {
                VStack(spacing: 18) {
                    Image(systemName: "text.bubble").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text("阅读项目中的讨论").font(.title2.weight(.semibold))
                    Text("在 Atoll 中查看 Gitee Issue，并沿着关联链接连续阅读。\n仅在启用并连接账户后请求 Gitee；不读取本地文件。")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("前往 Gitee 设置") { GISettingsNavigation.shared.open() }.buttonStyle(.borderedProminent)
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.account == nil {
                GIEmptyState(symbol: "person.badge.key", title: "尚未连接 Gitee", detail: "账户、查看项目和阅读偏好统一在设置侧栏的 Gitee 页面管理。") {
                    Button("打开 Gitee 设置") { GISettingsNavigation.shared.open() }.buttonStyle(.borderedProminent)
                }
            } else {
                HSplitView {
                    if showList { GIIssueListView().frame(minWidth: 240, idealWidth: 280, maxWidth: 320) }
                    detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 420)
                .onAppear { store.activate() }
        .onChange(of: enabled) { _, value in if value { store.activate() } }
    }
    private var header: some View {
        HStack(spacing: 12) {
            Button { showList.toggle() } label: { Image(systemName: "sidebar.left") }
                .help(showList ? "收起列表" : "返回列表").disabled(store.account == nil)
            Button { store.moveHistory(-1) } label: { Image(systemName: "chevron.left") }
                .disabled(!store.history.canBack).help("后退，恢复阅读位置").keyboardShortcut("[", modifiers: .command)
            Button { store.moveHistory(1) } label: { Image(systemName: "chevron.right") }
                .disabled(!store.history.canForward).help("前进").keyboardShortcut("]", modifiers: .command)
            Text(store.demoMode ? "Gitee · 离线演示" : "Gitee Issues").font(.headline)
            Spacer(minLength: 8)
            if let visit = store.visit {
                Menu { 
                    Button("缩小正文") { store.textScale = max(0.85, store.textScale - 0.1) }
                    Button("放大正文") { store.textScale = min(1.6, store.textScale + 0.1) }
                    Toggle("加载 Gitee 远程图片", isOn: $store.loadRemoteImages)
                    Divider()
                    Button("复制 Issue 链接") { GIPasteboard.copy(visit.sourceURL.absoluteString) }
                } label: { Image(systemName: "textformat.size") }.help("阅读选项")
                Button { store.loadCurrent(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(store.loadingDetail || store.demoMode).help("刷新当前 Issue").keyboardShortcut("r", modifiers: .command)
                Button { store.browserOpen() } label: { Image(systemName: "arrow.up.right.square") }.help("在 Gitee 中打开")
            }
            Button { GISettingsNavigation.shared.open() } label: { Image(systemName: "gearshape") }
                .help("打开设置中的 Gitee 页面")
        }
        .buttonStyle(.borderless).controlSize(.regular)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }
    @ViewBuilder private var detail: some View {
        if let visit = store.visit {
            VStack(spacing: 0) {
                HStack {
                    Text(visit.route.repository).lineLimit(1).truncationMode(.middle)
                    Text("#\(visit.route.number)").monospaced()
                    Spacer()
                    if !store.selectedRepositories.contains(where: { $0.path == visit.route.repository }) {
                        Label("关联项目", systemImage: "link").help("仅按需读取，不会自动加入查看列表")
                    }
                    if store.loadingDetail { ProgressView().controlSize(.small) }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
                if let notice = store.notice {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(notice).textSelection(.enabled)
                        Spacer(minLength: 0)
                        Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭提示")
                    }.font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                }
                Divider()
                if let page = store.currentPage {
                    GIWebReader(visit: visit, page: page, store: store)
                    Divider()
                    HStack {
                        Text("已加载 \(page.comments.count) 条评论").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if page.hasMoreComments {
                            Button("加载更多评论") { store.moreComments() }.disabled(store.loadingDetail)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 9)
                } else if let error = store.detailError {
                    GIEmptyState(symbol: "exclamationmark.bubble", title: "暂时无法打开", detail: error) {
                        HStack {
                            Button("重试") { store.loadCurrent(force: true) }
                            Button("在 Gitee 打开") { store.browserOpen() }
                        }
                    }
                } else {
                    VStack(spacing: 14) { ProgressView(); Text("正在加载 Issue 与评论…").foregroundStyle(.secondary) }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            GIEmptyState(symbol: "text.bubble", title: "选择一个 Issue", detail: "从左侧选择讨论。正文中的关联 Issue 会在这里打开，原列表不会切换。") {
                Button("选择查看项目…") { GISettingsNavigation.shared.open() }
            }
        }
    }
}

private struct GIIssueListView: View {
    @ObservedObject private var store = GIStore.shared
    @State private var showFailures = false
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("项目", selection: $store.repositoryFilter) {
                    Text("全部已选项目").tag("")
                    ForEach(store.selectedRepositories) { Text($0.full_name).tag($0.path) }
                }.labelsHidden()
                TextField("搜索已加载的标题或编号", text: $store.query)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("搜索已加载的 Issue")
                HStack {
                    Picker("状态", selection: $store.stateFilter) {
                        Text("未完成").tag("unfinished"); Text("全部状态").tag("all")
                        Text("开启").tag("open"); Text("进行中").tag("progressing")
                        Text("已关闭").tag("closed"); Text("已拒绝").tag("rejected")
                    }.labelsHidden()
                    Button { store.refreshIssues(reset: true) } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(store.loadingList || store.demoMode).help("刷新已选项目")
                }
            }.padding(12)
            Divider()
            if store.filteredItems.isEmpty {
                VStack(spacing: 10) {
                    if store.loadingList { ProgressView().controlSize(.small) }
                    Text(store.loadingList ? "正在读取项目…" : (store.selectedRepositories.isEmpty ? "请先选择查看项目" : (!store.listFailures.isEmpty && store.items.isEmpty ? "项目读取失败，请查看下方原因或重试" : "已加载范围内没有匹配结果")))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding<GIIssueRoute?>(get: { store.selectedListID }, set: { value in
                    if let value { store.open(value, fromList: true) }
                })) {
                    ForEach(store.filteredItems) { item in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.issue.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            HStack(spacing: 5) {
                                Text(item.route.repository).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                Text(item.issue.stateTitle)
                            }.font(.caption2).foregroundStyle(.secondary)
                            Text("#\(item.issue.number) · \(String((item.issue.updated_at ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(item.route)
                            .contextMenu { Button("复制链接") { GIPasteboard.copy(item.route.url.absoluteString) } }
                    }
                }.listStyle(.inset)
            }
            Divider()
            VStack(spacing: 7) {
                HStack {
                    Text("筛选已加载的 \(store.items.count) 条").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if store.loadingList { ProgressView().controlSize(.mini) }
                    if store.hasMoreIssues {
                        Button("加载更多") { store.refreshIssues(reset: false) }.controlSize(.small).disabled(store.loadingList)
                    }
                }
                if !store.listFailures.isEmpty {
                    Button("\(store.listFailures.count) 个项目读取失败 · 查看原因") { showFailures = true }
                        .font(.caption).popover(isPresented: $showFailures) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("项目读取诊断", systemImage: "exclamationmark.triangle").font(.headline)
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 16) {
                                        ForEach(store.listFailures) { failure in
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(failure.repository).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                                if let status = failure.status { Text("HTTP \(status)").font(.caption).foregroundStyle(.secondary) }
                                                Text(failure.message).font(.callout).textSelection(.enabled)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }.frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }.frame(maxHeight: 250)
                                Divider()
                                HStack {
                                    Button("Gitee 设置…") { showFailures = false; GISettingsNavigation.shared.open() }
                                    Spacer()
                                    Button("重试失败项目") { showFailures = false; store.retryFailedRepositories() }
                                        .disabled(store.loadingList)
                                }
                            }.padding(16).frame(width: 400)
                                .background(Color(nsColor: .windowBackgroundColor))
                        }
                } else if let date = store.lastSync {
                    HStack { Text("最近成功刷新"); Text(date, style: .time); Spacer() }.font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(10)
        }
    }
}

struct GIConnectionView: View {
    @ObservedObject private var store = GIStore.shared
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("连接 Gitee", systemImage: "person.badge.key").font(.title2.weight(.semibold))
            Text("输入个人访问令牌。阅读器只发送读取请求；令牌本身的权限仍由 Gitee 中的授权范围决定。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("个人访问令牌", text: $token).textFieldStyle(.roundedBorder)
                .onSubmit { submit() }.disabled(store.isConnecting)
            if let error = store.connectionError { Text(error).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button(store.isConnecting ? "正在验证…" : "验证并连接") { submit() }
                    .buttonStyle(.borderedProminent).disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isConnecting)
                if store.isConnecting { ProgressView().controlSize(.small) }
            }
            Text("令牌保存在本机钥匙串。正文与评论仅在内存缓存，退出账户或关闭功能后清除；不会发给 AI，也不会显示在锁屏。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Button("在 Gitee 管理令牌") { NSWorkspace.shared.open(URL(string: "https://gitee.com/profile/personal_access_tokens")!) }
                Spacer()
                if store.account == nil { Button("先体验离线演示") { token = ""; store.startDemo() } }
            }.controlSize(.small)
        }
    }
    private func submit() { let value = token; token = ""; store.connect(value) }
}

private struct GIEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 32)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).textSelection(.enabled)
                .frame(maxWidth: 390)
            actions()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum GIPasteboard {
    static func copy(_ string: String) {
        guard string.utf8.count <= 2 * 1024 * 1024 else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

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
