#!/usr/bin/env python3
"""One-time scoped repair. CI commits the resulting source and removes this helper.
No credentials, private project data, original media/display defaults or permissions.
"""
from pathlib import Path
R = Path(__file__).resolve().parents[1]
def edit(path, old, new, n=1):
    p=R/path; s=p.read_text()
    assert s.count(old)==n, (path, s.count(old), old[:100])
    p.write_text(s.replace(old,new))
core='DynamicIsland/ToolIsleFeatures/Gitee/GICore.swift'
p=R/core;s=p.read_text();start=s.index('struct GIRepository:');end=s.index('\nstruct GIIssue:',start)
s=s[:start]+'''/// Minimal namespace metadata; deliberately distinct from the display name.
struct GIRepositorySpace: Codable, Hashable {
    let path: String?
    let login: String?
}

enum GIRepositoryAddress {
    /// Only legacy URL/full_name fallbacks lose the clone suffix. Explicit API
    /// path metadata is authoritative and is never blindly renamed.
    static func legacyPath(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate: String
        if raw.contains("://") {
            guard let c = URLComponents(string: raw),
                  ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
                  GIIssueLinks.hosts.contains(c.host?.lowercased() ?? ""),
                  c.user == nil, c.password == nil,
                  c.port == nil || c.port == (c.scheme == "https" ? 443 : 80),
                  !c.percentEncodedPath.lowercased().contains("%2f"),
                  !c.percentEncodedPath.lowercased().contains("%5c") else { return nil }
            candidate = c.path
        } else if raw.hasPrefix("git@gitee.com:") {
            candidate = String(raw.dropFirst("git@gitee.com:".count))
        } else {
            guard !raw.contains("://"), !raw.contains(":"), !raw.contains("?"), !raw.contains("#") else { return nil }
            candidate = raw
        }
        var parts = candidate.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1].hasSuffix(".git") { parts[1].removeLast(4) }
        guard parts.allSatisfy(validSlug) else { return nil }
        return parts.joined(separator: "/")
    }
    static func validSlug(_ part: String) -> Bool {
        GIIssueLinks.validPart(part) && !part.contains("%") && !part.contains(":") &&
        !part.contains("?") && !part.contains("#") && !part.contains("@") &&
        !part.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) })
    }
}

struct GIRepository: Codable, Identifiable, Hashable {
    let id: Int64
    let full_name: String
    let name: String
    let description: String?
    let html_url: String?
    let repositoryPath: String?
    let namespace: GIRepositorySpace?
    let owner: GIRepositorySpace?
    enum CodingKeys: String, CodingKey {
        case id, full_name, name, description, html_url, namespace, owner
        case repositoryPath = "path"
    }
    init(id: Int64, full_name: String, name: String, description: String?, html_url: String?,
         repositoryPath: String? = nil, namespace: GIRepositorySpace? = nil, owner: GIRepositorySpace? = nil) {
        self.id = id; self.full_name = full_name; self.name = name
        self.description = description; self.html_url = html_url
        self.repositoryPath = repositoryPath; self.namespace = namespace; self.owner = owner
    }
    var path: String {
        let web = html_url.flatMap(GIRepositoryAddress.legacyPath)
        let fallback = GIRepositoryAddress.legacyPath(full_name)
        if let repo = repositoryPath, GIRepositoryAddress.validSlug(repo) {
            let space = [namespace?.path, web?.split(separator: "/").first.map(String.init),
                         fallback?.split(separator: "/").first.map(String.init), owner?.path, owner?.login]
                .compactMap { $0 }.first(where: GIRepositoryAddress.validSlug)
            if let space { return "\\(space)/\\(repo)" }
        }
        return web ?? fallback ?? ""
    }
}
''' +s[end:];p.write_text(s)
edit(core,'        try await get(["repos"] + repository.split(separator: "/").map(String.init) + ["issues"], query:','''        guard repository.split(separator: "/").count == 2,
              repository.split(separator: "/").allSatisfy({ GIRepositoryAddress.validSlug(String($0)) }) else { throw GIServiceError.format }
        return try await get(["repos"] + repository.split(separator: "/").map(String.init) + ["issues"], query:''')
edit(core,'return .issue(GIIssueRoute(repository: "\\(parts[0])/\\(parts[1])", number: parts[3]), fragment:', 'guard let repository = GIRepositoryAddress.legacyPath("\\(parts[0])/\\(parts[1])") else { return .external(url) }\n        return .issue(GIIssueRoute(repository: repository, number: parts[3]), fragment:')
edit(core,'            if e.code == .timedOut { return "连接超时，请重试。" }','''            if e.code == .timedOut { return "连接超时，请重试。" }
            if e.code == .cannotFindHost || e.code == .dnsLookupFailed {
                return "无法解析 Gitee 地址，请检查网络或 DNS 设置。"
            }''')
edit(core,'enum GIServiceError: Error, LocalizedError {','''struct GIRepositoryFailure: Identifiable {
    let repository: String
    let message: String
    let status: Int?
    var id: String { repository }
    init(repository: String, error: Error) {
        self.repository = repository
        self.message = GIServiceError.message(error)
        switch error as? GIServiceError {
        case .missingToken: status = 401
        case .forbidden: status = 403
        case .missing: status = 404
        case .throttled: status = 429
        case .response(let code): status = code
        default: status = nil
        }
    }
}

enum GIServiceError: Error, LocalizedError {''')
store='DynamicIsland/ToolIsleFeatures/Gitee/GIStore.swift'
edit(store,'var listFailures: [String] = []','var listFailures: [GIRepositoryFailure] = []')
edit(store,'self.listFailures.append("\\(repo)：\\(GIServiceError.message(error))")','self.listFailures.append(GIRepositoryFailure(repository: repo, error: error))')
edit(store,'nextIssuePages = Dictionary(uniqueKeysWithValues: selectedRepositories.map { ($0.path, 1) })','nextIssuePages = Dictionary(selectedRepositories.filter { !$0.path.isEmpty }.map { ($0.path, 1) }, uniquingKeysWith: { first, _ in first })')
edit(store,'selectedRepositories = selection.sorted { $0.full_name < $1.full_name }','selectedRepositories = selection.filter { !$0.path.isEmpty }.sorted { $0.full_name < $1.full_name }')
edit(store,'self.repositoryPage = page + 1; self.moreRepositories = repos.count == 50','''self.repositoryPage = page + 1; self.moreRepositories = repos.count == 50
                // Reconcile stored records by repository ID without losing user selections.
                let fresh = Dictionary(repos.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                let previousPaths = self.selectedRepositories.map(\\.path)
                self.selectedRepositories = self.selectedRepositories.map { fresh[$0.id] ?? $0 }
                if let key = self.selectionKey, let data = try? JSONEncoder().encode(self.selectedRepositories) {
                    UserDefaults.standard.set(data, forKey: key)
                }
                if previousPaths != self.selectedRepositories.map(\\.path) { self.refreshIssues(reset: true) }''')
edit(store,'    func open(_ route: GIIssueRoute, fragment:', '''    func retryFailedRepositories() {
        guard !loadingList else { return }
        let pending = Set(listFailures.map(\\.repository))
        for repo in pending { nextIssuePages[repo] = nextIssuePages[repo] ?? 1 }
        refreshIssues(reset: false, only: pending)
    }
    func open(_ route: GIIssueRoute, fragment:''')
edit(store,'func refreshIssues(reset: Bool) {','func refreshIssues(reset: Bool, only: Set<String>? = nil) {')
edit(store,'let requests = nextIssuePages.sorted { $0.key < $1.key }, session = epoch','let requests = nextIssuePages.filter { only == nil || only!.contains($0.key) }.sorted { $0.key < $1.key }, session = epoch')
p=R/'DynamicIsland/ToolIsleFeatures/Gitee/GIIntegration.swift'
p.write_text(p.read_text()+'''
/// A single cross-window route, confined to the optional Gitee feature.
@MainActor
final class GISettingsNavigation: ObservableObject {
    static let shared = GISettingsNavigation()
    @Published var request: UUID?
    func open() {
        request = UUID()
        SettingsWindowController.shared.showWindow()
    }
}
''')
settings='DynamicIsland/components/Settings/SettingsView.swift'
edit(settings,'    case extensions\n    case timer','    case extensions\n    case gitee\n    case timer')
edit(settings,'case .extensions:                                                    return .integrations','case .extensions, .gitee:                                            return .integrations')
edit(settings,'        case .extensions: return String(localized: "Extensions")','        case .extensions: return String(localized: "Extensions")\n        case .gitee: return "Gitee"')
edit(settings,'        case .extensions: return "puzzlepiece.extension"','        case .extensions: return "puzzlepiece.extension"\n        case .gitee: return "text.bubble"')
edit(settings,'        case .extensions: return Color(red: 0.557, green: 0.353, blue: 0.957)','        case .extensions: return Color(red: 0.557, green: 0.353, blue: 0.957)\n        case .gitee: return .indigo')
edit(settings,'        // General\n        SettingsSearchEntry','''        SettingsSearchEntry(tab: .gitee, title: "Gitee 账户与项目", keywords: ["gitee", "issue", "令牌", "账户", "项目", "watch", "star"], highlightID: nil),
        // General
        SettingsSearchEntry''')
edit(settings,'    @State private var selectedTab: SettingsTab = .general','    @State private var selectedTab: SettingsTab = .general\n    @ObservedObject private var giteeSettingsNavigation = GISettingsNavigation.shared')
edit(settings,'        .frame(width: 700)\n        .onChange(of: searchText)', '''        .frame(width: 700)
        .onReceive(giteeSettingsNavigation.$request) { request in
            guard request != nil else { return }
            searchText = ""
            selectedTab = .gitee
            giteeSettingsNavigation.request = nil
        }
        .onChange(of: searchText)''')
edit(settings,'            // Integrations\n            .extensions,','            // Integrations\n            .extensions,\n            .gitee,')
edit(settings,'        case .extensions:\n            SettingsForm(tab: .extensions)', '''        case .gitee:
            SettingsForm(tab: .gitee) {
                GIDedicatedSettingsView()
            }
        case .extensions:
            SettingsForm(tab: .extensions)''')
edit(settings,'            GIReaderSettingsSection()\n','')
edit('DynamicIsland.xcodeproj/project.pbxproj','CURRENT_PROJECT_VERSION = 1639;', 'CURRENT_PROJECT_VERSION = 1640;',n=2)
views='DynamicIsland/ToolIsleFeatures/Gitee/GIViews.swift'
p=R/views;s=p.read_text();start=s.index('struct GIReaderSettingsSection:');end=s.index('struct GINotchView:',start);s=s[:start]+s[end:]
s=s.replace('@State private var settings = false\n','').replace('.sheet(isPresented: $settings) { GIAccountView() }\n','')
s=s.replace('settings = true','GISettingsNavigation.shared.open()')
s=s.replace('Image(systemName: "person.crop.circle") }\n                .help("账户与查看项目")','Image(systemName: "gearshape") }\n                .help("打开设置中的 Gitee 页面")')
s=s.replace('Button("连接与设置…") { GIReaderWindowController.shared.show() }','Button("连接与设置…") { GISettingsNavigation.shared.open() }')
s=s.replace('Button("选择项目 / 查看详情…") { GIReaderWindowController.shared.show() }','Button("选择查看项目…") { GISettingsNavigation.shared.open() }')
s=s.replace('Button("启用 Gitee 阅读") { enabled = true; store.activate() }','Button("前往 Gitee 设置") { GISettingsNavigation.shared.open() }')
s=s.replace('''                GIConnectionView().frame(maxWidth: 440).padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)''','''                GIEmptyState(symbol: "person.badge.key", title: "尚未连接 Gitee", detail: "账户、查看项目和阅读偏好统一在设置侧栏的 Gitee 页面管理。") {
                    Button("打开 Gitee 设置") { GISettingsNavigation.shared.open() }.buttonStyle(.borderedProminent)
                }''')
start=s.index('private struct GIAccountView:');end=s.index('private struct GIEmptyState',start);s=s[:start]+s[end:]
s=s.replace('private struct GIConnectionView:','struct GIConnectionView:')
old='''                            ScrollView { Text(store.listFailures.joined(separator: "\\n\\n")).textSelection(.enabled).padding(16) }
                                .frame(width: 360, height: 240)'''
new='''                            VStack(alignment: .leading, spacing: 12) {
                                Label("项目读取诊断", systemImage: "exclamationmark.triangle").font(.headline)
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 16) {
                                        ForEach(store.listFailures) { failure in
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(failure.repository).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                                if let status = failure.status { Text("HTTP \\(status)").font(.caption).foregroundStyle(.secondary) }
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
                                .background(Color(nsColor: .windowBackgroundColor))'''
assert old in s;s=s.replace(old,new)
s=s.replace('store.selectedRepositories.isEmpty ? "请先选择查看项目" : "已加载范围内没有匹配结果"','store.selectedRepositories.isEmpty ? "请先选择查看项目" : (!store.listFailures.isEmpty && store.items.isEmpty ? "项目读取失败，请查看下方原因或重试" : "已加载范围内没有匹配结果")')
p.write_text(s)
# The legacy installer must not restore the old General settings section on reruns.
(R/'scripts/integrate_gitee_reader.py').write_text('''#!/usr/bin/env python3
"""Historical integration is already committed; do not replay it over current source."""
from pathlib import Path
assert (Path(__file__).resolve().parents[1]/"DynamicIsland/ToolIsleFeatures/Gitee/GISettingsView.swift").exists()
print("Gitee integration already committed. No source was modified.")
''')
print('Scoped repository-path/settings repair applied. Review the resulting source diff.')
