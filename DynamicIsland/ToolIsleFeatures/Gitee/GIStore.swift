// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import Defaults
import Security

extension Defaults.Keys {
    static let enableGiteeReader = Key<Bool>("toolisle.gitee.enabled", default: false)
}

enum GICredential {
    private static let service = "io.github.lideming0815.toolisle.gitee-reader"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "gitee.com"]
    }
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CredentialError() }
        return value
    }
    static func save(_ token: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            attributes.forEach { q[$0] = $1 }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CredentialError() }
        } else if status != errSecSuccess { throw CredentialError() }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError() }
    }
    struct CredentialError: LocalizedError {
        var errorDescription: String? { "无法访问钥匙串，请确认系统授权后重试。令牌未写入普通配置文件。" }
    }
}

@MainActor
final class GIStore: ObservableObject {
    static let shared = GIStore()
    @Published private(set) var account: GIUser?
    @Published private(set) var demoMode = false
    @Published private(set) var isConnecting = false
    @Published var connectionError: String?
    @Published private(set) var repositories: [GIRepository] = []
    @Published private(set) var selectedRepositories: [GIRepository] = []
    @Published private(set) var loadingRepositories = false
    @Published private(set) var moreRepositories = false
    @Published var repositoryError: String?
    @Published private(set) var items: [GIListItem] = []
    @Published private(set) var loadingList = false
    @Published private(set) var listFailures: [GIRepositoryFailure] = []
    @Published private(set) var lastSync: Date?
    @Published var repositoryFilter = ""
    @Published var query = ""
    @Published var stateFilter = "unfinished"
    @Published var selectedListID: GIIssueRoute?
    @Published private(set) var history = GIHistory()
    @Published private(set) var pages: [GIIssueRoute: GIPage] = [:]
    @Published private(set) var loadingDetail = false
    @Published var detailError: String?
    @Published var notice: String?
    @Published var loadRemoteImages = false
    @Published var textScale = 1.0
    private var api: GIAPI?
    private var epoch = UUID()
    private var authAttempt = UUID()
    private var authTask: Task<Void, Never>?
    private var repositoryTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var repositoryPage = 1
    private var repositorySource = "subscriptions"
    private var nextIssuePages: [String: Int] = [:]
    private var cacheOrder: [GIIssueRoute] = []
    private var cancellables = Set<AnyCancellable>()
    private var attemptedRestore = false

    private init() {
        Defaults.publisher(.enableGiteeReader, options: []).receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if !change.newValue { self?.deactivate() }
            }.store(in: &cancellables)
    }
    var visit: GIVisit? { history.current }
    var currentPage: GIPage? { visit.flatMap { pages[$0.route] } }
    var hasMoreIssues: Bool { !nextIssuePages.isEmpty }
    var filteredItems: [GIListItem] {
        items.filter { item in
            (repositoryFilter.isEmpty || item.route.repository == repositoryFilter) &&
            (stateFilter == "all" || (stateFilter == "unfinished" ? ["open", "progressing"].contains(item.issue.state) : item.issue.state == stateFilter)) &&
            (query.isEmpty || item.issue.title.localizedCaseInsensitiveContains(query) || item.route.label.localizedCaseInsensitiveContains(query))
        }
    }
    private var selectionKey: String? { account.map { "toolisle.gitee.selection.\($0.id)" } }

    /// Called only by the opt-in reader surfaces, never by application launch.
    func activate() {
        guard Defaults[.enableGiteeReader], !attemptedRestore, account == nil, !isConnecting else { return }
        attemptedRestore = true
        do { if let token = try GICredential.read() { connect(token) } }
        catch { connectionError = "无法读取钥匙串。请重新连接 Gitee。" }
    }
    func connect(_ input: String) {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Defaults[.enableGiteeReader], !token.isEmpty else { return }
        guard token.count <= 4096, !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            connectionError = "令牌格式不正确。"; return
        }
        authTask?.cancel()
        let attempt = UUID(); authAttempt = attempt
        isConnecting = true; connectionError = nil
        authTask = Task { [weak self] in
            guard let self else { return }
            let client = GIAPI(token: token)
            do {
                let user = try await client.user()
                guard !Task.isCancelled, self.authAttempt == attempt, Defaults[.enableGiteeReader] else { client.cancel(); return }
                try GICredential.save(token)
                self.clearSession()
                self.api = client
                self.account = user
                self.attemptedRestore = true
                if let key = self.selectionKey, let data = UserDefaults.standard.data(forKey: key),
                   let selection = try? JSONDecoder().decode([GIRepository].self, from: data) { self.selectedRepositories = selection }
                self.refreshRepositories(source: "subscriptions", reset: true)
                if !self.selectedRepositories.isEmpty { self.refreshIssues(reset: true) }
            } catch {
                client.cancel()
                if self.authAttempt == attempt && !Task.isCancelled {
                    self.connectionError = (error as? GICredential.CredentialError)?.localizedDescription ?? GIServiceError.message(error)
                }
            }
            if self.authAttempt == attempt { self.isConnecting = false }
        }
    }
    func disconnect() {
        do { try GICredential.delete() }
        catch { connectionError = "无法移除钥匙串中的令牌，请重试。"; return }
        if let key = selectionKey { UserDefaults.standard.removeObject(forKey: key) }
        deactivate()
        attemptedRestore = true
    }
    func deactivate() {
        authAttempt = UUID(); authTask?.cancel(); isConnecting = false
        clearSession(); attemptedRestore = false
    }
    private func clearSession() {
        epoch = UUID()
        repositoryTask?.cancel(); listTask?.cancel(); detailTask?.cancel()
        api?.cancel(); api = nil; account = nil; demoMode = false
        repositories = []; selectedRepositories = []; items = []; pages = [:]; cacheOrder = []
        nextIssuePages = [:]; history.reset(); selectedListID = nil
        repositoryPage = 1; moreRepositories = false
        loadingRepositories = false; loadingList = false; loadingDetail = false
        query = ""; repositoryFilter = ""; stateFilter = "unfinished"
        listFailures = []; repositoryError = nil; detailError = nil; notice = nil; lastSync = nil
        loadRemoteImages = false
    }
    func refreshRepositories(source: String, reset: Bool) {
        guard Defaults[.enableGiteeReader], !demoMode, let client = api else { return }
        if loadingRepositories && !reset { return }
        repositoryTask?.cancel()
        repositorySource = source == "starred" ? "starred" : "subscriptions"
        if reset { repositories = []; repositoryPage = 1; moreRepositories = false }
        loadingRepositories = true; repositoryError = nil
        let session = epoch, page = repositoryPage, requestedSource = repositorySource
        repositoryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let repos = try await client.repositories(source: requestedSource, page: page)
                guard !Task.isCancelled, self.epoch == session else { return }
                var unique = Dictionary(self.repositories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                for repo in repos { unique[repo.id] = repo }
                self.repositories = unique.values.sorted { $0.full_name.localizedStandardCompare($1.full_name) == .orderedAscending }
                self.repositoryPage = page + 1; self.moreRepositories = repos.count == 50
                // Reconcile stored records by repository ID without losing user selections.
                let fresh = Dictionary(repos.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                let previousPaths = self.selectedRepositories.map(\.path)
                self.selectedRepositories = self.selectedRepositories.map { fresh[$0.id] ?? $0 }
                if let key = self.selectionKey, let data = try? JSONEncoder().encode(self.selectedRepositories) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                if previousPaths != self.selectedRepositories.map(\.path) { self.refreshIssues(reset: true) }
            } catch {
                guard !Task.isCancelled, self.epoch == session else { return }
                self.repositoryError = GIServiceError.message(error)
            }
            if self.epoch == session && !Task.isCancelled { self.loadingRepositories = false }
        }
    }
    func applySelection(_ selection: [GIRepository]) {
        selectedRepositories = selection.filter { !$0.path.isEmpty }.sorted { $0.full_name < $1.full_name }
        if !selectedRepositories.contains(where: { $0.path == repositoryFilter }) { repositoryFilter = "" }
        if !demoMode, let key = selectionKey, let data = try? JSONEncoder().encode(selectedRepositories) {
            UserDefaults.standard.set(data, forKey: key)
        }
        refreshIssues(reset: true)
    }
    func refreshIssues(reset: Bool, only: Set<String>? = nil) {
        guard Defaults[.enableGiteeReader], !demoMode, let client = api else { return }
        if loadingList && !reset { return }
        listTask?.cancel()
        if reset { nextIssuePages = Dictionary(selectedRepositories.filter { !$0.path.isEmpty }.map { ($0.path, 1) }, uniquingKeysWith: { first, _ in first }) }
        let requests = nextIssuePages.filter { only == nil || only!.contains($0.key) }.sorted { $0.key < $1.key }, session = epoch
        let selected = Set(selectedRepositories.map(\.path))
        if reset { items.removeAll { !selected.contains($0.route.repository) } }
        guard !requests.isEmpty else { loadingList = false; return }
        loadingList = true; listFailures = []
        listTask = Task { [weak self] in
            guard let self else { return }
            var merged = Dictionary(self.items.map { ($0.route, $0) }, uniquingKeysWith: { a, _ in a })
            for (repo, page) in requests {
                guard !Task.isCancelled, self.epoch == session else { return }
                do {
                    let issues = try await client.issues(repository: repo, page: page)
                    guard !Task.isCancelled, self.epoch == session else { return }
                    if reset { merged = merged.filter { $0.key.repository != repo } }
                    for issue in issues {
                        let route = GIIssueRoute(repository: repo, number: issue.number)
                        merged[route] = GIListItem(route: route, issue: issue)
                    }
                    self.nextIssuePages[repo] = issues.count == 50 ? page + 1 : nil
                } catch {
                    guard !Task.isCancelled, self.epoch == session else { return }
                    self.listFailures.append(GIRepositoryFailure(repository: repo, error: error))
                }
                self.items = merged.values.sorted {
                    if $0.issue.updated_at == $1.issue.updated_at { return $0.route.label < $1.route.label }
                    return ($0.issue.updated_at ?? "") > ($1.issue.updated_at ?? "")
                }
            }
            if self.epoch == session && !Task.isCancelled {
                self.loadingList = false
                if self.listFailures.isEmpty { self.lastSync = Date() }
            }
        }
    }
    func retryFailedRepositories() {
        guard !loadingList else { return }
        let pending = Set(listFailures.map(\.repository))
        for repo in pending { nextIssuePages[repo] = nextIssuePages[repo] ?? 1 }
        refreshIssues(reset: false, only: pending)
    }
    func open(_ route: GIIssueRoute, fragment: String? = nil, fromList: Bool = false) {
        if fromList { selectedListID = route }
        history.push(route, fragment: fragment)
        notice = nil
        loadCurrent(force: false)
    }
    func moveHistory(_ offset: Int) {
        history.move(offset); notice = nil; loadCurrent(force: false)
    }
    func snapshot(id: UUID, y: Double, anchorHandled: Bool? = nil) {
        history.snapshot(id: id, y: y, anchorHandled: anchorHandled)
    }
    func handleLink(_ raw: String, visitID: UUID) {
        guard Defaults[.enableGiteeReader], let visit, visit.id == visitID else { return }
        // The issue's server URL may reflect a moved repository; use it only on a verified Gitee origin.
        let canonical = currentPage?.issue.html_url.flatMap(URL.init(string:))
        let base = canonical.flatMap { GIIssueLinks.hosts.contains($0.host?.lowercased() ?? "") ? $0 : nil } ?? visit.route.url
        switch GIIssueLinks.resolve(raw, relativeTo: base) {
        case .issue(let route, let fragment): open(route, fragment: fragment)
        case .external(let url): NSWorkspace.shared.open(url)
        case .blocked: notice = "此链接的协议、地址或参数不安全，未打开。"
        }
    }
    func browserOpen() {
        guard let visit else { return }
        NSWorkspace.shared.open(visit.sourceURL)
    }
    func loadCurrent(force: Bool) {
        detailTask?.cancel(); loadingDetail = false; detailError = nil
        guard Defaults[.enableGiteeReader], let visit else { return }
        if demoMode { loadDemo(visit.route); return }
        if !force, let cached = pages[visit.route] {
            if let anchor = GIIssueLinks.commentID(visit.fragment), !visit.anchorHandled,
               !cached.comments.contains(where: { $0.id == anchor }), cached.hasMoreComments {
                // Fall through to the bounded anchor-aware load below.
            } else { return }
        }
        guard let client = api else { detailError = "请先连接 Gitee。"; return }
        loadingDetail = true
        let session = epoch, visitID = visit.id, route = visit.route
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let issue = try await client.issue(route)
                var comments: [GIComment] = []
                var nextPage = 1, hasMore = true
                var commentWarning: String?
                repeat {
                    do {
                        let page = try await client.comments(route, page: nextPage)
                        comments.append(contentsOf: page)
                        hasMore = page.count == 50; nextPage += 1
                    } catch {
                        if Task.isCancelled { return }
                        commentWarning = "正文已加载，评论未能完整加载：\(GIServiceError.message(error))"
                        break
                    }
                    guard !Task.isCancelled, self.epoch == session, self.visit?.id == visitID else { return }
                    guard let anchor = GIIssueLinks.commentID(visit.fragment), !comments.contains(where: { $0.id == anchor }) else { break }
                } while hasMore && comments.count < 1000
                guard !Task.isCancelled, self.epoch == session, self.visit?.id == visitID else { return }
                var seen = Set<Int64>(); comments = comments.filter { seen.insert($0.id).inserted }
                self.pages[route] = GIPage(issue: issue, comments: comments, nextCommentPage: nextPage, hasMoreComments: hasMore)
                self.touchCache(route)
                self.notice = commentWarning
                if let anchor = GIIssueLinks.commentID(visit.fragment), !comments.contains(where: { $0.id == anchor }) {
                    self.notice = "未找到指定评论，可能已删除或超出已加载范围。原链接已保留，可在 Gitee 打开。"
                }
            } catch {
                guard !Task.isCancelled, self.epoch == session, self.visit?.id == visitID else { return }
                self.detailError = GIServiceError.message(error)
                // A failed permission recheck must not continue displaying a previously cached private page.
                self.pages[route] = nil
            }
            if self.epoch == session && self.visit?.id == visitID && !Task.isCancelled { self.loadingDetail = false }
        }
    }
    func moreComments() {
        guard !loadingDetail, let visit, var page = currentPage, page.hasMoreComments, let client = api else { return }
        guard page.comments.count < 1000 else { notice = "已加载 1000 条评论。更多内容请在 Gitee 打开。"; return }
        detailTask?.cancel(); loadingDetail = true
        let session = epoch, visitID = visit.id
        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                let extra = try await client.comments(visit.route, page: page.nextCommentPage)
                guard !Task.isCancelled, self.epoch == session, self.visit?.id == visitID else { return }
                var ids = Set(page.comments.map(\.id))
                page.comments.append(contentsOf: extra.filter { ids.insert($0.id).inserted })
                page.nextCommentPage += 1; page.hasMoreComments = extra.count == 50; page.revision = UUID()
                self.pages[visit.route] = page
            } catch {
                guard !Task.isCancelled, self.epoch == session, self.visit?.id == visitID else { return }
                self.notice = GIServiceError.message(error)
            }
            if self.epoch == session && self.visit?.id == visitID && !Task.isCancelled { self.loadingDetail = false }
        }
    }
    private func touchCache(_ route: GIIssueRoute) {
        cacheOrder.removeAll { $0 == route }; cacheOrder.append(route)
        while cacheOrder.count > 30 { pages[cacheOrder.removeFirst()] = nil }
    }

    /// Explicit synthetic preview: no Gitee requests, no writes to the stored credential or selection.
    func startDemo() {
        deactivate(); Defaults[.enableGiteeReader] = true
        demoMode = true; attemptedRestore = true
        account = GIUser(id: -1, login: "demo", name: "离线演示 · 非真实项目")
        let repos = [GIRepository(id: -1, full_name: "toolisle-demo/workbench", name: "Workbench", description: "演示项目", html_url: nil),
                     GIRepository(id: -2, full_name: "toolisle-demo/shared", name: "Shared", description: "跨仓库跳转示例", html_url: nil)]
        repositories = repos; selectedRepositories = [repos[0]]
        items = [GIListItem(route: Self.demoA, issue: Self.demoIssue(Self.demoA))]
        lastSync = Date(); open(Self.demoA, fromList: true)
    }
    static let demoA = GIIssueRoute(repository: "toolisle-demo/workbench", number: "IDEMOA")
    static let demoB = GIIssueRoute(repository: "toolisle-demo/shared", number: "IDEMOB")
    private func loadDemo(_ route: GIIssueRoute) {
        guard route == Self.demoA || route == Self.demoB else { detailError = "演示模式不请求网络。此目标不在演示数据中。"; return }
        guard pages[route] == nil else { return }
        let comments = [GIComment(id: 101, body: "这是演示评论。点击[关联 Issue B](\(Self.demoB.url.absoluteString)#note_202)可跨仓库定位到评论。", user: account, created_at: "2026-09-22T08:00:00+08:00"),
                        GIComment(id: 202, body: "### 定位成功\n这条评论用来验证带锚点的跳转。\n\n[返回 Issue A](\(Self.demoA.url.absoluteString))，也可使用窗口左上角后退按钮恢复原阅读位置。", user: account, created_at: "2026-09-22T08:30:00+08:00")]
        pages[route] = GIPage(issue: Self.demoIssue(route), comments: comments, nextCommentPage: 2, hasMoreComments: false)
    }
    static func demoIssue(_ route: GIIssueRoute) -> GIIssue {
        let body = route == demoA ? "## 在 Atoll 中连续阅读 Issue\n这是**离线演示数据**，用于验收布局与链接，未连接真实 Gitee 账户。\n\n### 关联阅读\n先向下滚动，再点击[另一个仓库的 Issue B](\(demoB.url.absoluteString)#note_202)。使用后退应恢复当前位置，左侧项目筛选不变。\n\n| 能力 | 状态 |\n| --- | --- |\n| 原版 Atoll | 保留 |\n| Markdown 表格、代码 | 支持 |\n| 本地文件读取 | 不在本期范围 |\n\n- [x] 单窗口阅读\n- [x] 关联 Issue 导航\n- [ ] 实际 Gitee 账户与多屏验收\n\n```swift\nlet destination = GIIssueRoute(repository: \"team/project\", number: \"IABC12\")\n// 代码中的 https://gitee.com/example/demo/issues/I123 不自动导航。\n```\n\n> 阅读内容使用稳定背景；原刘海窗口仍由 Atoll 管理。\n\n![演示图片](https://foruda.gitee.com/images/toolisle-fixture.png)\n\n### 阅读位置测试\n" + Array(repeating: "阅读正文和评论时，可选择并复制文字。后台任务不会抢占焦点或切换刘海页面。\n\n", count: 10).joined() + "[跨仓库跳转到 B 的评论](\(demoB.url.absoluteString)#note_202)\n\n[普通网页](https://gitee.com)在浏览器打开。" : "## 关联 Issue B\n这是另一个**未加入查看列表**的项目，点击关联链接只加载详情，不改变左侧列表，也不自动关注。\n\n[继续阅读 A](\(demoA.url.absoluteString))\n\n### 评论定位\n链接中的 `#note_202` 应滚动到下方对应评论。"
        return GIIssue(id: route == demoA ? 1 : 2, number: route.number,
                       title: route == demoA ? "Gitee Issue 阅读与关联跳转" : "共享模块：跨仓库问题跟踪",
                       state: "progressing", body: body, html_url: route.url.absoluteString,
                       user: GIUser(id: -1, login: "demo", name: "演示维护者"), updated_at: "2026-09-22T08:30:00+08:00", comments: 2)
    }
}
