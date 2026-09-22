// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ToolIsleCore

struct GiteeWorkspace: View {
    @EnvironmentObject var account: GiteeAccount
    @State private var source: RepositorySource = .subscriptions
    @State private var repos: [GiteeRepository] = []
    @State private var selection: GiteeRepository?
    @State private var query = ""
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var offline: Date?
    var body: some View {
        Group {
            if let client = account.client, let user = account.user {
                NavigationSplitView {
                    VStack(spacing: 8) {
                        Picker("项目来源", selection: $source) { Text("Watch").tag(RepositorySource.subscriptions); Text("Star").tag(RepositorySource.starred) }.pickerStyle(.segmented).disabled(loading)
                        TextField("筛选已加载的仓库", text: $query).textFieldStyle(.roundedBorder)
                        List(selection: $selection) {
                            ForEach(repos.filter { query.isEmpty || $0.fullName.localizedCaseInsensitiveContains(query) }) { repo in
                                VStack(alignment: .leading) {
                                    Text(repo.fullName).lineLimit(2)
                                    if repo.private == true { Label("私有", systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
                                }.tag(repo)
                            }
                        }
                        HStack {
                            Text("已加载 \(repos.count)").font(.caption)
                            Spacer()
                            Button("刷新") { Task { await load(client, reset: true) } }.disabled(loading)
                            if more { Button("更多") { Task { await load(client, reset: false) } }.disabled(loading) }
                            if loading { ProgressView().controlSize(.small) }
                        }
                        CachedNotice(date: offline)
                    }.padding(10).navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } detail: {
                    VStack(spacing: 0) {
                        if let message = account.message {
                            HStack { Text(message).font(.caption).foregroundStyle(.orange); Spacer(); Button("关闭") { account.message = nil } }.padding(8)
                        }
                        if let repo = selection {
                            RepositoryWorkspace(repo: repo, client: client).id("\(user.id)/\(repo.id)")
                        } else { ContentUnavailableView("选择仓库", systemImage: "tray", description: Text("从 Watch 或 Star 项目中选择仓库，查看 Issues 和文档。")) }
                    }
                }
                .task(id: "\(source.rawValue)/\(user.id)") { await load(client, reset: true) }
                .toolbar {
                    ToolbarItem { Menu(user.name ?? user.login) {
                        Toggle("磁盘离线缓存", isOn: Binding(get: { account.diskCache }, set: { value in Task { await account.setDiskCache(value) } }))
                        Button("退出并清理缓存") { Task { await account.disconnect() } }
                    } }
                }
            } else { GiteeConnectionView() }
        }.task { await account.restore() }
    }
    private func load(_ client: GiteeClient, reset: Bool) async {
        let requestedSource = source
        if !reset && loading { return }
        if reset { repos = []; selection = nil; page = 1; more = true }
        loading = true
        defer { loading = false }
        do {
            let resource = try await client.repositories(requestedSource, page: page)
            try Task.checkCancellation()
            guard account.client === client, requestedSource == source else { return }
            let ids = Set(repos.map(\.id)); repos += resource.value.filter { !ids.contains($0.id) }
            more = resource.value.count == 100; page += 1; offline = resource.cachedAt
        } catch { account.report(error, from: client) }
    }
}
struct CachedNotice: View {
    let date: Date?
    var body: some View {
        if let date { Text("离线缓存 · \(date.formatted(date: .abbreviated, time: .shortened))，不是实时数据").font(.caption).foregroundStyle(.orange) }
    }
}
struct RepositoryWorkspace: View {
    let repo: GiteeRepository
    let client: GiteeClient
    @State private var tab = 0
    @State private var documentPath: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(repo.fullName).font(.headline)
                Spacer()
                Picker("内容", selection: $tab) { Text("Issues").tag(0); Text("Markdown / 文件").tag(1) }.pickerStyle(.segmented).frame(width: 250)
                if let url = GiteePath.safeBrowserURL(repo.htmlUrl) { Link("Gitee", destination: url) }
            }.padding(.horizontal)
            if tab == 0 {
                IssuesBrowser(repo: repo, client: client) { path in documentPath = path; tab = 1 }
            } else { RepositoryFiles(repo: repo, client: client, initialPath: documentPath).id(documentPath ?? "root") }
        }.padding(.top, 8)
    }
}
struct IssuesBrowser: View {
    @EnvironmentObject var account: GiteeAccount
    let repo: GiteeRepository
    let client: GiteeClient
    let openDocument: (String) -> Void
    @State private var issues: [GiteeIssue] = []
    @State private var selection: Int?
    @State private var state = "all"
    @State private var search = ""
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var offline: Date?
    @State private var read: [String: String] = (UserDefaults.standard.dictionary(forKey: "gitee.lastRead") as? [String: String]) ?? [:]
    var body: some View {
        HSplitView {
            VStack {
                Picker("状态", selection: $state) {
                    Text("全部").tag("all"); Text("待办").tag("open"); Text("进行中").tag("progressing"); Text("已关闭").tag("closed"); Text("已拒绝").tag("rejected")
                }.disabled(loading)
                TextField("筛选已加载标题或标签", text: $search).textFieldStyle(.roundedBorder)
                List(selection: $selection) {
                    ForEach(issues.filter { issue in search.isEmpty || issue.title.localizedCaseInsensitiveContains(search) || (issue.labels ?? []).contains { $0.name.localizedCaseInsensitiveContains(search) } }) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if read[key(issue)] != (issue.updatedAt ?? "new") { Circle().fill(.blue).frame(width: 6, height: 6).accessibilityLabel("未读更新") }
                                Text(issue.title).lineLimit(3)
                            }
                            Text("#\(issue.number) · \(issue.state)").font(.caption).foregroundStyle(.secondary)
                            if let labels = issue.labels, !labels.isEmpty { Text(labels.map(\.name).joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                        }.padding(.vertical, 3).tag(issue.id)
                    }
                }
                HStack {
                    Text("已加载 \(issues.count)").font(.caption)
                    Button("刷新") { Task { await load(reset: true) } }.disabled(loading)
                    if more { Button("更多") { Task { await load(reset: false) } }.disabled(loading) }
                    if loading { ProgressView().controlSize(.small) }
                }
                CachedNotice(date: offline)
            }.padding(8).frame(minWidth: 250, idealWidth: 300, maxWidth: 380)
            if let issue = issues.first(where: { $0.id == selection }) {
                IssueReader(repo: repo, number: issue.number, client: client, openDocument: openDocument).id(issue.number)
            } else { ContentUnavailableView("选择 Issue", systemImage: "text.bubble").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: state) { await load(reset: true) }
        .onChange(of: selection) { _, id in
            if let issue = issues.first(where: { $0.id == id }) { read[key(issue)] = issue.updatedAt ?? "new"; UserDefaults.standard.set(read, forKey: "gitee.lastRead") }
        }
    }
    private func key(_ issue: GiteeIssue) -> String { "\(account.user?.id ?? 0)/\(repo.id)/\(issue.number)" }
    private func load(reset: Bool) async {
        let requestedState = state
        if !reset && loading { return }
        if reset { page = 1; issues = []; selection = nil; more = true }
        loading = true; defer { loading = false }
        do {
            let result = try await client.issues(repo, state: requestedState, page: page)
            try Task.checkCancellation(); guard account.client === client, requestedState == state else { return }
            let ids = Set(issues.map(\.id)); issues += result.value.filter { !ids.contains($0.id) }
            more = result.value.count == 100; page += 1; offline = result.cachedAt
        } catch { account.report(error, from: client) }
    }
}
struct IssueReader: View {
    @EnvironmentObject var account: GiteeAccount
    let repo: GiteeRepository
    let number: String
    let client: GiteeClient
    let openDocument: (String) -> Void
    @State private var issue: GiteeIssue?
    @State private var comments: [GiteeComment] = []
    @State private var page = 1
    @State private var more = true
    @State private var loading = false
    @State private var offline: Date?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let issue {
                    Text(issue.title).font(.title2).textSelection(.enabled)
                    HStack {
                        Text("#\(issue.number) · \(issue.state)").foregroundStyle(.secondary)
                        if let url = GiteePath.safeBrowserURL(issue.htmlUrl) { Link("在 Gitee 打开", destination: url) }
                        Button("刷新详情") { Task { await reload() } }.disabled(loading)
                    }
                    CachedNotice(date: offline)
                    MarkdownBody(text: issue.body ?? "（无正文）", context: .repository(repo, client: client, ref: repo.defaultBranch ?? "", path: "README.md"), openDocument: openDocument)
                    Divider(); Text("评论 · 已加载 \(comments.count)").font(.headline)
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(comment.user?.name ?? comment.user?.login ?? "用户").font(.headline)
                            MarkdownBody(text: comment.body ?? "", context: .repository(repo, client: client, ref: repo.defaultBranch ?? "", path: "README.md"), openDocument: openDocument)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if more { Button("加载评论") { Task { await loadComments() } }.disabled(loading) }
                } else if !loading { Text("详情加载失败，可重试。"); Button("重试") { Task { await reload() } } }
                if loading { ProgressView() }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.task { await reload() }
    }
    private func reload() async {
        loading = true; defer { loading = false }
        do {
            let result = try await client.issue(repo, number: number); try Task.checkCancellation()
            issue = result.value; offline = result.cachedAt; page = 1; comments = []; more = true
            await loadComments()
        } catch { account.report(error, from: client) }
    }
    private func loadComments() async {
        loading = true; defer { loading = false }
        do {
            let result = try await client.comments(repo, number: number, page: page); try Task.checkCancellation()
            let ids = Set(comments.map(\.id)); comments += result.value.filter { !ids.contains($0.id) }
            page += 1; more = result.value.count == 100
            if let cached = result.cachedAt { offline = cached }
        } catch { account.report(error, from: client) }
    }
}
struct RepositoryFiles: View {
    @EnvironmentObject var account: GiteeAccount
    let repo: GiteeRepository
    let client: GiteeClient
    let initialPath: String?
    @State private var ref = ""
    @State private var displayedRef = ""
    @State private var path = ""
    @State private var branches: [GiteeBranch] = []
    @State private var entries: [GiteeFile] = []
    @State private var file: GiteeFile?
    @State private var text = ""
    @State private var loading = false
    @State private var offline: Date?
    @State private var failure: String?
    var body: some View {
        VStack {
            HStack {
                TextField("分支 / Tag / Commit", text: $ref).frame(width: 170)
                Menu("分支") { ForEach(branches) { branch in Button(branch.name) { ref = branch.name; Task { await browse("") } } }; Text("也可直接输入完整分支名") }
                TextField("仓库内路径", text: $path).onSubmit { Task { await openPath() } }
                Button("打开") { Task { await openPath() } }.disabled(loading)
                Button("README") { Task { await readme() } }.disabled(loading)
                Button("根目录") { Task { await browse("") } }.disabled(loading)
            }.textFieldStyle(.roundedBorder).padding(.horizontal)
            CachedNotice(date: offline)
            if let failure { Text(failure).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal) }
            if loading { ProgressView() }
            if let file {
                MarkdownReader(text: text, title: file.path, context: .repository(repo, client: client, ref: displayedRef, path: file.path)) { next in
                    path = next; ref = displayedRef; Task { await openPath() }
                }.id("\(displayedRef)/\(file.path)")
            } else {
                List(entries) { entry in
                    Button {
                        if entry.type == "dir" { Task { await browse(entry.path) } }
                        else { path = entry.path; Task { await openPath() } }
                    } label: { Label(entry.name, systemImage: entry.type == "dir" ? "folder" : "doc.text").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                }
            }
        }.task {
            ref = repo.defaultBranch ?? ""
            do { branches = try await client.branches(repo, page: 1).value } catch { account.report(error, from: client) }
            if let initialPath { path = initialPath; await openPath() } else { await readme() }
        }
    }
    private func display(_ result: GiteeResource<GiteeFile>, ref requestedRef: String) throws {
        let rendered = try result.value.text()
        displayedRef = requestedRef; file = result.value; path = result.value.path; text = rendered; offline = result.cachedAt
    }
    private func readme() async {
        loading = true; failure = nil; defer { loading = false }
        do { let requestedRef = ref; let result = try await client.readme(repo, ref: requestedRef); try Task.checkCancellation(); try display(result, ref: requestedRef) }
        catch { failure = error.localizedDescription; account.report(error, from: client) }
    }
    private func browse(_ directory: String) async {
        loading = true; failure = nil; defer { loading = false }
        do {
            let result = try await client.files(repo, path: directory, ref: ref); try Task.checkCancellation()
            file = nil; entries = result.value.sorted { ($0.type == "dir" && $1.type != "dir") || ($0.type == $1.type && $0.name.localizedStandardCompare($1.name) == .orderedAscending) }; path = directory; offline = result.cachedAt
        } catch { failure = error.localizedDescription; account.report(error, from: client) }
    }
    private func openPath() async {
        if path.isEmpty { await browse(""); return }
        loading = true; failure = nil; defer { loading = false }
        do { let requestedRef = ref; let result = try await client.file(repo, path: path, ref: requestedRef); try Task.checkCancellation(); try display(result, ref: requestedRef) }
        catch { failure = error.localizedDescription; account.report(error, from: client) }
    }
}
