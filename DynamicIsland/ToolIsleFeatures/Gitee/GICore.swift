// ToolIsle Gitee reader. Copyright (C) 2026 ToolIsle contributors.
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct GIUser: Codable, Hashable {
    let id: Int64
    let login: String
    let name: String?
    var displayName: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? login }
}

struct GIRepository: Codable, Identifiable, Hashable {
    let id: Int64
    let full_name: String
    let name: String
    let description: String?
    let html_url: String?
    var path: String { full_name }
}

struct GIIssue: Codable, Identifiable {
    let id: Int64
    let number: String
    let title: String
    let state: String
    let body: String?
    let html_url: String?
    let user: GIUser?
    let updated_at: String?
    let comments: Int?
    var stateTitle: String {
        switch state {
        case "open": return "开启"
        case "progressing": return "进行中"
        case "closed": return "已关闭"
        case "rejected": return "已拒绝"
        default: return state
        }
    }
}

struct GIComment: Codable, Identifiable {
    let id: Int64
    let body: String?
    let user: GIUser?
    let created_at: String?
}

struct GIIssueRoute: Codable, Hashable {
    let repository: String
    let number: String
    var url: URL {
        var result = URL(string: "https://gitee.com")!
        for part in repository.split(separator: "/") { result.appendPathComponent(String(part)) }
        result.appendPathComponent("issues")
        result.appendPathComponent(number)
        return result
    }
    var label: String { "\(repository) #\(number)" }
}

enum GILinkTarget: Equatable {
    case issue(GIIssueRoute, fragment: String?)
    case external(URL)
    case blocked
}

enum GIIssueLinks {
    static let hosts: Set<String> = ["gitee.com", "www.gitee.com"]

    /// Only real user-clicked links reach this resolver. Do not run it over code blocks.
    /// Preserve issue-number case; Gitee identifiers are not integer issue IDs.
    static func resolve(_ raw: String, relativeTo base: URL) -> GILinkTarget {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\\"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: true),
              c.user == nil, c.password == nil else { return .blocked }
        let scheme = c.scheme?.lowercased() ?? ""
        guard ["https", "http", "mailto"].contains(scheme) else { return .blocked }
        // Credentials must never be propagated into browser navigation or logging.
        let sensitive = Set(["access_token", "token", "authorization", "private_token"])
        if (c.queryItems ?? []).contains(where: { sensitive.contains($0.name.lowercased()) }) { return .blocked }
        guard scheme != "mailto" else { return .external(url) }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return .blocked }
        guard hosts.contains(host), c.port == nil || c.port == (scheme == "https" ? 443 : 80) else {
            return .external(url)
        }
        // Reject encoded separators rather than reinterpreting a malformed path.
        let encoded = c.percentEncodedPath.lowercased()
        if encoded.contains("%2f") || encoded.contains("%5c") { return .external(url) }
        let parts = c.path.split(separator: "/").map(String.init)
        guard parts.count == 4, parts[2] == "issues",
              validPart(parts[0]), validPart(parts[1]),
              !parts[3].isEmpty,
              parts[3].unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) && $0.isASCII }) else {
            return .external(url)
        }
        return .issue(GIIssueRoute(repository: "\(parts[0])/\(parts[1])", number: parts[3]), fragment: c.fragment.flatMap { $0.isEmpty ? nil : $0 })
    }

    static func validPart(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
        !value.contains("/") && !value.contains("\\") &&
        !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    /// Known comment anchor spellings; unknown anchors remain available for browser fallback.
    static func commentID(_ fragment: String?) -> Int64? {
        guard let fragment else { return nil }
        for prefix in ["note_", "issuecomment-", "comment-", "comment_"] where fragment.hasPrefix(prefix) {
            return Int64(fragment.dropFirst(prefix.count))
        }
        return nil
    }
}

struct GIVisit: Identifiable {
    let id = UUID()
    let route: GIIssueRoute
    let fragment: String?
    var scrollY: Double = 0
    var anchorHandled = false
    var sourceURL: URL {
        var c = URLComponents(url: route.url, resolvingAgainstBaseURL: false)!
        c.fragment = fragment
        return c.url ?? route.url
    }
}

struct GIHistory {
    private(set) var visits: [GIVisit] = []
    private(set) var position = -1
    var current: GIVisit? { visits.indices.contains(position) ? visits[position] : nil }
    var canBack: Bool { position > 0 }
    var canForward: Bool { position >= 0 && position + 1 < visits.count }
    mutating func push(_ route: GIIssueRoute, fragment: String? = nil) {
        if current?.route == route && current?.fragment == fragment { return }
        if position + 1 < visits.count { visits.removeSubrange((position + 1)..<visits.count) }
        visits.append(GIVisit(route: route, fragment: fragment))
        if visits.count > 100 { visits.removeFirst(visits.count - 100) }
        position = visits.count - 1
    }
    mutating func move(_ offset: Int) {
        guard visits.indices.contains(position + offset) else { return }
        position += offset
    }
    mutating func snapshot(id: UUID, y: Double, anchorHandled: Bool? = nil) {
        guard let i = visits.firstIndex(where: { $0.id == id }) else { return }
        visits[i].scrollY = y.isFinite ? max(0, y) : 0
        if let anchorHandled { visits[i].anchorHandled = anchorHandled }
    }
    mutating func reset() { self = GIHistory() }
}

struct GIListItem: Identifiable {
    let route: GIIssueRoute
    let issue: GIIssue
    var id: GIIssueRoute { route }
}

struct GIPage {
    var issue: GIIssue
    var comments: [GIComment]
    var nextCommentPage: Int
    var hasMoreComments: Bool
    var revision = UUID()
}

enum GIServiceError: Error, LocalizedError {
    case missingToken, forbidden, missing, throttled, response(Int), format, tooLarge, unsafeRedirect
    var errorDescription: String? {
        switch self {
        case .missingToken: return "授权已失效，请重新连接 Gitee。"
        case .forbidden: return "当前账户没有权限，或接口暂时限制访问。请检查令牌权限后重试。"
        case .missing: return "该内容不存在，或当前账户没有访问权限。"
        case .throttled: return "请求过于频繁。请稍后手动重试。"
        case .response(let code): return "Gitee 返回了错误（HTTP \(code)），请稍后重试。"
        case .format: return "无法读取接口返回的内容；可在 Gitee 网页中打开。"
        case .tooLarge: return "内容超过阅读器的安全大小限制，请在 Gitee 网页中打开。"
        case .unsafeRedirect: return "接口发生了重定向。为保护令牌，未跟随该地址。"
        }
    }
    static func message(_ error: Error) -> String {
        if let e = error as? GIServiceError { return e.localizedDescription }
        if let e = error as? URLError {
            if e.code == .notConnectedToInternet || e.code == .networkConnectionLost {
                return "当前离线。已加载内容仍可阅读，联网后可重试。"
            }
            if e.code == .timedOut { return "连接超时，请重试。" }
        }
        // Never show an underlying URLSession error containing a credential-bearing URL.
        return "加载失败，请检查网络后重试。"
    }
}

final class GINoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class GIAPI: @unchecked Sendable {
    private let token: String
    private let session: URLSession
    init(token: String, configuration: URLSessionConfiguration = .ephemeral) {
        self.token = token
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 40
        self.session = URLSession(configuration: configuration, delegate: GINoRedirect(), delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    deinit { session.invalidateAndCancel() }

    func get<T: Decodable>(_ path: [String], query: [URLQueryItem] = []) async throws -> T {
        var url = URL(string: "https://gitee.com/api/v5")!
        for component in path {
            guard GIIssueLinks.validPart(component) else { throw GIServiceError.format }
            url.appendPathComponent(component)
        }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        c.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: c.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ToolIsle-GiteeReader/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GIServiceError.format }
        switch http.statusCode {
        case 200..<300: break
        case 300..<400: throw GIServiceError.unsafeRedirect
        case 401: throw GIServiceError.missingToken
        case 403: throw GIServiceError.forbidden
        case 404: throw GIServiceError.missing
        case 429: throw GIServiceError.throttled
        default: throw GIServiceError.response(http.statusCode)
        }
        guard data.count <= 8 * 1024 * 1024 else { throw GIServiceError.tooLarge }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GIServiceError.format }
    }
    func user() async throws -> GIUser { try await get(["user"]) }
    func repositories(source: String, page: Int) async throws -> [GIRepository] {
        try await get(["user", source == "starred" ? "starred" : "subscriptions"], query: Self.page(page))
    }
    func issues(repository: String, page: Int) async throws -> [GIIssue] {
        try await get(["repos"] + repository.split(separator: "/").map(String.init) + ["issues"], query: Self.page(page) + [
            URLQueryItem(name: "state", value: "all"), URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "direction", value: "desc")
        ])
    }
    func issue(_ route: GIIssueRoute) async throws -> GIIssue { try await get(issuePath(route)) }
    func comments(_ route: GIIssueRoute, page: Int) async throws -> [GIComment] {
        try await get(issuePath(route) + ["comments"], query: Self.page(page))
    }
    private func issuePath(_ route: GIIssueRoute) -> [String] {
        ["repos"] + route.repository.split(separator: "/").map(String.init) + ["issues", route.number]
    }
    static func page(_ number: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "page", value: String(max(1, number))), URLQueryItem(name: "per_page", value: "50")]
    }
}
