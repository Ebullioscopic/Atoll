// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Defaults
import SwiftUI

/// A normal settings sidebar destination. No account UI is embedded in General.
struct GIDedicatedSettingsView: View {
    @ObservedObject private var store = GIStore.shared
    @Default(.enableGiteeReader) private var enabled
    @State private var source = "subscriptions"
    @State private var filter = ""
    @State private var changeToken = false
    @State private var confirmDisconnect = false
    private var filteredRepositories: [GIRepository] {
        store.repositories.filter { filter.isEmpty || $0.full_name.localizedCaseInsensitiveContains(filter) || $0.path.localizedCaseInsensitiveContains(filter) }
    }
    private var selectedIDs: Set<Int64> { Set(store.selectedRepositories.map(\.id)) }

    var body: some View {
        Form {
            Section {
                Toggle("启用 Gitee Issue 阅读", isOn: $enabled)
                    .accessibilityIdentifier("gitee-settings-enabled")
                Text("只读查看关注项目的 Issue 与评论，不更改 Atoll 原有的媒体、刘海、锁屏或文件暂存行为。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Gitee") }
            if enabled {
                Section("账户") {
                    if let account = store.account {
                        LabeledContent("当前账户", value: account.displayName)
                        if !store.demoMode { Text("@\(account.login)").font(.caption).foregroundStyle(.secondary) }
                        if store.demoMode {
                            Text("离线演示：非真实项目，不请求 Gitee。").font(.caption).foregroundStyle(.secondary)
                            Button("退出演示并连接账户") { store.deactivate() }
                        } else {
                            HStack {
                                Button(changeToken ? "取消更换" : "更换令牌…") { changeToken.toggle() }
                                Spacer()
                                Button("退出账户…", role: .destructive) { confirmDisconnect = true }
                            }
                            if changeToken { GIConnectionView() }
                            if let error = store.connectionError, !changeToken {
                                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    } else { GIConnectionView() }
                }
                if store.account != nil {
                    selectedSection
                    repositorySection
                    Section("阅读") {
                        Toggle("加载 Gitee 远程图片", isOn: $store.loadRemoteImages)
                        Text("图片默认关闭。开启后只加载允许来源的图片，不向图片地址附加账户令牌。需要额外鉴权的图片请在 Gitee 打开。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("正文字号")
                            Slider(value: $store.textScale, in: 0.85...1.6, step: 0.05)
                            Text("\(Int((store.textScale * 100).rounded()))%")
                                .monospacedDigit().frame(width: 45, alignment: .trailing)
                        }
                        Button("打开 Issue 阅读窗口") { GIReaderWindowController.shared.show() }
                    }
                }
            } else {
                Section {
                    Text("功能关闭时不请求 Gitee，并清除内存中的正文与评论。账户令牌仍保留在本机钥匙串中。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("移除已保存的账户令牌…", role: .destructive) { confirmDisconnect = true }
                    if let error = store.connectionError { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("关于与隐私") {
                Text("令牌仅保存在本机钥匙串；此模块不向 AI 或锁屏传递 Issue 内容。查看项目选择只影响本机，不修改平台 Watch / Star。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Markdown 组件许可证…") {
                    if let url = Bundle.main.url(forResource: "gitee-markdown-licenses", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.activate() }
        .onChange(of: enabled) { _, value in if value { store.activate() } }
        .onChange(of: store.account?.id) { _, _ in changeToken = false; source = "subscriptions" }
        .onChange(of: source) { _, value in store.refreshRepositories(source: value, reset: true) }
        .confirmationDialog("移除本机保存的 Gitee 令牌并清除阅读会话？", isPresented: $confirmDisconnect) {
            Button("退出账户并移除令牌", role: .destructive) { store.disconnect() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("不会修改 Gitee 上的项目、Issue、Watch 或 Star。之后可重新连接。")
        }
    }
    private var selectedSection: some View {
        Section("已选查看项目 · \(store.selectedRepositories.count)") {
            if store.selectedRepositories.isEmpty {
                Text("从下方 Watch / Star 列表选择需要查看的项目。").foregroundStyle(.secondary)
            } else {
                ForEach(store.selectedRepositories) { repo in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repo.full_name).lineLimit(2)
                            Text(repo.path.isEmpty ? "无法解析仓库路径，请刷新项目列表" : repo.path)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer(minLength: 8)
                        Button { setSelected(repo, false) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("仅从本机查看列表移除")
                    }
                }
                Button(store.loadingList ? "正在验证读取…" : "刷新已选项目 Issues") { store.refreshIssues(reset: true) }
                    .disabled(store.loadingList || store.demoMode)
                if !store.listFailures.isEmpty {
                    ForEach(store.listFailures) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.repository).font(.caption.weight(.medium)).textSelection(.enabled)
                            Text(failure.message + (failure.status.map { "（HTTP \($0)）" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    Button("重试失败项目") { store.retryFailedRepositories() }.disabled(store.loadingList)
                } else if let time = store.lastSync {
                    LabeledContent("最近成功读取") { Text(time, style: .time) }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var repositorySection: some View {
        Section("添加查看项目") {
            Picker("项目来源", selection: $source) {
                Text("Watch 关注").tag("subscriptions")
                Text("Star 收藏").tag("starred")
            }.pickerStyle(.segmented).disabled(store.demoMode)
            HStack {
                TextField("搜索已加载项目", text: $filter).textFieldStyle(.roundedBorder)
                Button { store.refreshRepositories(source: source, reset: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(store.loadingRepositories || store.demoMode).help("刷新项目来源")
            }
            if store.loadingRepositories && store.repositories.isEmpty {
                ProgressView("正在加载项目…").controlSize(.small)
            } else if filteredRepositories.isEmpty && store.repositoryError == nil {
                Text(filter.isEmpty ? "这个来源暂未返回项目。可切换 Watch / Star 或刷新。" : "已加载范围内没有匹配项目。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(filteredRepositories) { repo in
                        Toggle(isOn: Binding(get: { selectedIDs.contains(repo.id) }, set: { setSelected(repo, $0) })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(repo.full_name).lineLimit(2)
                                Text(repo.path.isEmpty ? "仓库地址无效" : repo.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.toggleStyle(.checkbox).disabled(repo.path.isEmpty)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }.frame(height: min(240, max(60, CGFloat(filteredRepositories.count) * 54)))
            HStack {
                Text("已加载 \(store.repositories.count) 个 · 勾选后立即保存").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.moreRepositories {
                    Button("加载更多") { store.refreshRepositories(source: source, reset: false) }.disabled(store.loadingRepositories)
                }
            }
            if let error = store.repositoryError {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
    private func setSelected(_ repo: GIRepository, _ selected: Bool) {
        var values = store.selectedRepositories.filter { $0.id != repo.id }
        if selected { values.append(repo) }
        store.applySelection(values)
    }
}
