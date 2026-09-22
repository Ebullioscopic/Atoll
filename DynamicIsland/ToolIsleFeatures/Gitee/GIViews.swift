// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

@MainActor
final class GIReaderWindowController: NSWindowController {
    static let shared = GIReaderWindowController()
    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Gitee Issues · ToolIsle"
        window.minSize = NSSize(width: 740, height: 480)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: GIReaderRootView())
        window.center()
        window.setFrameAutosaveName("ToolIsle.GiteeReader.Window")
        super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func show(route: GIIssueRoute? = nil) {
        if let route { GIStore.shared.open(route, fromList: true) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct GIReaderSettingsSection: View {
    var body: some View {
        Section("Gitee Issues") {
            Defaults.Toggle("启用 Gitee 阅读", key: .enableGiteeReader)
            Text("只读查看关注项目的 Issue。不会更改默认首页、媒体、锁屏或文件暂存行为。")
                .font(.caption).foregroundStyle(.secondary)
            Button("账户与项目设置…") { GIReaderWindowController.shared.show() }
        }
    }
}

struct GINotchView: View {
    @ObservedObject private var store = GIStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gitee Issues", systemImage: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.loadingList { ProgressView().controlSize(.mini) }
                Button { GIReaderWindowController.shared.show() } label: {
                    Image(systemName: "arrow.up.right.square")
                }.buttonStyle(.plain).help("打开完整阅读窗口")
            }
            if store.account == nil {
                Text("连接 Gitee，阅读关注项目的 Issue。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("连接与设置…") { GIReaderWindowController.shared.show() }.controlSize(.small)
            } else if store.items.isEmpty {
                Text(store.loadingList ? "正在加载已选项目…" : "尚无已加载的 Issue")
                    .font(.caption).foregroundStyle(.secondary)
                Button("选择项目 / 查看详情…") { GIReaderWindowController.shared.show() }.controlSize(.small)
            } else {
                ForEach(Array(store.filteredItems.prefix(3))) { item in
                    Button { GIReaderWindowController.shared.show(route: item.route) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.issue.state == "closed" ? "checkmark.circle" : "circle.dotted")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(item.issue.title).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.issue.stateTitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(item.route.label)
                }
                Button("查看全部 · 已加载 \(store.items.count) 条") { GIReaderWindowController.shared.show() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            if !store.listFailures.isEmpty { Text("部分项目加载失败，请打开阅读窗口查看。 ").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.activate() }
    }
}

struct GIReaderRootView: View {
    @ObservedObject private var store = GIStore.shared
    @Default(.enableGiteeReader) private var enabled
    @State private var settings = false
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
                    Button("启用 Gitee 阅读") { enabled = true; store.activate() }.buttonStyle(.borderedProminent)
                }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.account == nil {
                GIConnectionView().frame(maxWidth: 440).padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    if showList { GIIssueListView().frame(minWidth: 240, idealWidth: 300, maxWidth: 370) }
                    detail.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 420)
        .sheet(isPresented: $settings) { GIAccountView() }
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
            Button { settings = true } label: { Image(systemName: "person.crop.circle") }
                .help("账户与查看项目")
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
                Button("选择查看项目…") { settings = true }
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
                    Text(store.loadingList ? "正在读取项目…" : (store.selectedRepositories.isEmpty ? "请先选择查看项目" : "已加载范围内没有匹配结果"))
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
                            ScrollView { Text(store.listFailures.joined(separator: "\n\n")).textSelection(.enabled).padding(16) }
                                .frame(width: 360, height: 240)
                        }
                } else if let date = store.lastSync {
                    HStack { Text("最近完整刷新"); Text(date, style: .time); Spacer() }.font(.caption2).foregroundStyle(.secondary)
                }
            }.padding(10)
        }
    }
}

private struct GIConnectionView: View {
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

private struct GIAccountView: View {
    @ObservedObject private var store = GIStore.shared
    @Default(.enableGiteeReader) private var enabled
    @Environment(\.dismiss) private var dismiss
    @State private var source = "subscriptions"
    @State private var selection: [Int64: GIRepository] = [:]
    @State private var filter = ""
    @State private var changeAccount = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Gitee 账户与项目").font(.title3.weight(.semibold))
                Spacer()
                Toggle("启用", isOn: $enabled).toggleStyle(.switch).controlSize(.small)
            }
            if enabled, let account = store.account {
                HStack {
                    Label(account.displayName, systemImage: "person.crop.circle")
                    Spacer()
                    if store.demoMode {
                        Button("退出演示") { store.deactivate() }
                    } else {
                        Button("更换令牌") { changeAccount.toggle() }
                        Button("退出账户") { store.disconnect() }
                    }
                }
                if changeAccount && !store.demoMode { GIConnectionView() }
                Text("勾选需要查看的项目。此处增删只影响本机列表，不会修改 Gitee 的 Watch 或 Star。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("项目来源", selection: $source) {
                    Text("Watch 关注").tag("subscriptions"); Text("Star 收藏").tag("starred")
                }.pickerStyle(.segmented).disabled(store.demoMode)
                TextField("筛选已加载项目", text: $filter).textFieldStyle(.roundedBorder)
                List {
                    ForEach(store.repositories.filter { filter.isEmpty || $0.full_name.localizedCaseInsensitiveContains(filter) }) { repo in
                        Toggle(isOn: Binding(get: { selection[repo.id] != nil }, set: { value in selection[repo.id] = value ? repo : nil })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.full_name).lineLimit(1)
                                if let description = repo.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }.toggleStyle(.checkbox).padding(.vertical, 3)
                    }
                }.frame(minHeight: 160, maxHeight: .infinity)
                if let error = store.repositoryError {
                    HStack { Text(error).font(.caption); Button("重试") { store.refreshRepositories(source: source, reset: true) } }
                }
                HStack {
                    Text("已选 \(selection.count) 个 · 已加载 \(store.repositories.count) 个").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.loadingRepositories { ProgressView().controlSize(.small) }
                    if store.moreRepositories { Button("加载更多项目") { store.refreshRepositories(source: source, reset: false) }.disabled(store.loadingRepositories) }
                }
            } else if enabled {
                GIConnectionView()
                Spacer(minLength: 0)
            } else {
                Text("关闭后不发送 Gitee 请求，并清除内存中的阅读内容。钥匙串令牌保留，可重新启用或在连接后退出账户。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            Divider()
            HStack {
                Text("本期仅阅读 Issue 与评论").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("完成") {
                    if enabled, store.account != nil, Set(selection.keys) != Set(store.selectedRepositories.map(\.id)) {
                        store.applySelection(Array(selection.values))
                    }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 560, height: 600)
        .onAppear { selection = Dictionary(uniqueKeysWithValues: store.selectedRepositories.map { ($0.id, $0) }) }
        .onChange(of: store.account?.id) { _, _ in
            selection = Dictionary(uniqueKeysWithValues: store.selectedRepositories.map { ($0.id, $0) }); changeAccount = false
        }
        .onChange(of: source) { _, value in store.refreshRepositories(source: value, reset: true) }
        .onChange(of: enabled) { _, value in if value { store.activate() } }
    }
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
