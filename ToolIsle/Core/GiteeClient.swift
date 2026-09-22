// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GiteeUser: Codable, Identifiable, Sendable {
    public let id: Int
    public let login: String
    public let name: String?
}
public struct GiteeRepository: Codable, Identifiable, Sendable, Hashable {
    public let id: Int
    public let fullName: String
    public let name: String
    public let description: String?
    public let defaultBranch: String?
    public let htmlUrl: String?
    public let `private`: Bool?
    public var components: [String] { fullName.split(separator: "/").map(String.init) }
}
public struct GiteeLabel: Codable, Sendable { public let name: String }
public struct GiteeIssue: Codable, Identifiable, Sendable {
    public let id: Int
    public let number: String
    public let title: String
    public let body: String?
    public let state: String
    public let updatedAt: String?
    public let htmlUrl: String?
    public let user: GiteeUser?
    public let labels: [GiteeLabel]?
    // Gitee issue numbers are identifiers such as IABC12, not GitHub integer numbers.
}
public struct GiteeComment: Codable, Identifiable, Sendable {
    public let id: Int
    public let body: String?
    public let user: GiteeUser?
    public let updatedAt: String?
}
public struct GiteeBranch: Codable, Sendable, Identifiable {
    public let name: String
    public var id: String { name }
}
public struct GiteeFile: Codable, Identifiable, Sendable {
    public let type: String
    public let name: String
    public let path: String
    public let content: String?
    public let encoding: String?
    public let size: Int?
    public let htmlUrl: String?
    public var id: String { path }
    public func bytes(maximum: Int = 8_000_000) throws -> Data {
        guard (size ?? 0) <= maximum, encoding == "base64", let content,
              let data = Data(base64Encoded: content.filter { !$0.isWhitespace }), data.count <= maximum else {
            throw GiteeError.invalidContent
        }
        return data
    }
    public func text() throws -> String {
        guard let value = String(data: try bytes(maximum: 2_000_000), encoding: .utf8) else { throw GiteeError.invalidContent }
        return value
    }
}
public enum RepositorySource: String, CaseIterable, Sendable { case subscriptions, starred }
public enum GiteeError: Error, LocalizedError, Equatable {
    case invalidPath, invalidContent, unauthorized, forbidden, notFound, rateLimited(Int), http(Int), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidPath: return "路径无效；请输入仓库内的相对路径。"
        case .invalidContent: return "内容格式不支持或文件过大（文档上限 2 MB，图片上限 8 MB）。"
        case .unauthorized: return "访问令牌无效或已过期，请重新连接账户。"
        case .forbidden: return "没有访问权限，或 API 配额受限；请检查令牌权限后重试。"
        case .notFound: return "资源不存在、已删除或当前账户无权查看。"
        case .rateLimited(let seconds): return "请求过于频繁，请至少等待 \(seconds) 秒后重试。"
        case .http(let code): return "Gitee 请求失败（HTTP \(code)），请稍后重试。"
        case .invalidResponse: return "服务器响应无法解析。"
        }
    }
}
public struct GiteeResource<Value: Sendable>: Sendable {
    public let value: Value
    public let cachedAt: Date?
    public var isOffline: Bool { cachedAt != nil }
}
public enum GiteePath {
    public static func segments(_ path: String) throws -> [String] {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { throw GiteeError.invalidPath }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.contains(".."), !parts.contains(".") else { throw GiteeError.invalidPath }
        return parts
    }
    public static func url(_ components: [String], query: [URLQueryItem] = []) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else { throw GiteeError.invalidPath }
        let path = components.map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        var url = URLComponents(string: "https://gitee.com/api/v5/" + path)!
        url.queryItems = query.isEmpty ? nil : query
        return url.url!
    }
    public static func safeBrowserURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "https", url.host == "gitee.com",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }
}
public protocol GiteeTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
// Reject all redirects. In particular, never forward the access token to another origin.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public final class GiteeNetwork: GiteeTransport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GiteeError.invalidResponse }
        return (data, http)
    }
    deinit { session.invalidateAndCancel() }
}
public actor GiteeClient {
    private let token: String
    private let transport: any GiteeTransport
    private let decoder: JSONDecoder
    private struct Entry: Codable { let data: Data; let savedAt: Date }
    private var cache: [String: Entry] = [:]
    private var cacheURL: URL?
    private var blockedUntil: Date?
    private var active = true
    public init(token: String, transport: any GiteeTransport = GiteeNetwork()) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }
    public func configureDiskCache(directory: URL?, accountID: Int) throws {
        guard active else { throw GiteeError.unauthorized }
        cache.removeAll()
        cacheURL = nil
        guard let directory else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("gitee-\(accountID).json")
        cacheURL = url
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
           let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            cache = decoded.filter { Date().timeIntervalSince($0.value.savedAt) < 7 * 86_400 }
        }
    }
    public func invalidate() throws {
        active = false
        try clearCache()
    }
    public func clearCache() throws {
        cache.removeAll()
        if let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) { try FileManager.default.removeItem(at: cacheURL) }
        cacheURL = nil
    }
    public func user() async throws -> GiteeUser { try await load(["user"], allowOffline: false).value }
    public func repositories(_ source: RepositorySource, page: Int) async throws -> GiteeResource<[GiteeRepository]> {
        try await load(["user", source.rawValue], query: pagination(page))
    }
    private func repositoryPath(_ repo: GiteeRepository) throws -> [String] {
        guard repo.components.count == 2 else { throw GiteeError.invalidPath }
        return ["repos"] + repo.components
    }
    public func issues(_ repo: GiteeRepository, state: String = "all", page: Int = 1) async throws -> GiteeResource<[GiteeIssue]> {
        try await load(repositoryPath(repo) + ["issues"], query: pagination(page) + [.init(name: "state", value: state), .init(name: "sort", value: "updated"), .init(name: "direction", value: "desc")])
    }
    public func issue(_ repo: GiteeRepository, number: String) async throws -> GiteeResource<GiteeIssue> {
        try await load(repositoryPath(repo) + ["issues", number])
    }
    public func comments(_ repo: GiteeRepository, number: String, page: Int) async throws -> GiteeResource<[GiteeComment]> {
        try await load(repositoryPath(repo) + ["issues", number, "comments"], query: pagination(page))
    }
    public func branches(_ repo: GiteeRepository, page: Int) async throws -> GiteeResource<[GiteeBranch]> {
        try await load(repositoryPath(repo) + ["branches"], query: pagination(page))
    }
    public func files(_ repo: GiteeRepository, path: String, ref: String) async throws -> GiteeResource<[GiteeFile]> {
        try await load(repositoryPath(repo) + ["contents"] + GiteePath.segments(path), query: ref.isEmpty ? [] : [.init(name: "ref", value: ref)])
    }
    public func file(_ repo: GiteeRepository, path: String, ref: String) async throws -> GiteeResource<GiteeFile> {
        try await load(repositoryPath(repo) + ["contents"] + GiteePath.segments(path), query: ref.isEmpty ? [] : [.init(name: "ref", value: ref)])
    }
    public func readme(_ repo: GiteeRepository, ref: String) async throws -> GiteeResource<GiteeFile> {
        try await load(repositoryPath(repo) + ["readme"], query: ref.isEmpty ? [] : [.init(name: "ref", value: ref)])
    }
    private func pagination(_ page: Int) -> [URLQueryItem] {
        [.init(name: "page", value: String(max(1, page))), .init(name: "per_page", value: "100")]
    }
    private func load<T: Decodable & Sendable>(_ path: [String], query: [URLQueryItem] = [], allowOffline: Bool = true) async throws -> GiteeResource<T> {
        try Task.checkCancellation()
        guard active else { throw GiteeError.unauthorized }
        if let until = blockedUntil, until > Date() { throw GiteeError.rateLimited(Int(ceil(until.timeIntervalSinceNow))) }
        let url = try GiteePath.url(path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ToolIsle/0.2", forHTTPHeaderField: "User-Agent")
        let data: Data
        do {
            let (body, response) = try await transport.send(request)
            try Task.checkCancellation()
            guard active else { throw GiteeError.unauthorized }
            switch response.statusCode {
            case 200: break
            case 401: try? clearCache(); throw GiteeError.unauthorized
            case 403: try? clearCache(); throw GiteeError.forbidden
            case 404: try? clearCache(); throw GiteeError.notFound
            case 429:
                let seconds = min(3600, max(1, Int(response.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60))
                blockedUntil = Date().addingTimeInterval(Double(seconds))
                throw GiteeError.rateLimited(seconds)
            default: throw GiteeError.http(response.statusCode)
            }
            guard body.count <= 12_000_000 else { throw GiteeError.invalidContent }
            data = body
        } catch let error as URLError {
            try Task.checkCancellation()
            guard active else { throw GiteeError.unauthorized }
            // Never substitute cached data for authentication/authorization errors or cancellation.
            let recoverable: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
            if allowOffline, recoverable.contains(error.code), let entry = cache[url.absoluteString],
               Date().timeIntervalSince(entry.savedAt) < 7 * 86_400 {
                guard let value = try? decoder.decode(T.self, from: entry.data) else { throw GiteeError.invalidResponse }
                return GiteeResource(value: value, cachedAt: entry.savedAt)
            }
            throw error
        }
        guard let value = try? decoder.decode(T.self, from: data) else { throw GiteeError.invalidResponse }
        if allowOffline {
            cache[url.absoluteString] = Entry(data: data, savedAt: Date())
            while cache.count > 100 || cache.values.reduce(0, { $0 + $1.data.count }) > 10_000_000 {
                if let key = cache.min(by: { $0.value.savedAt < $1.value.savedAt })?.key { cache.removeValue(forKey: key) } else { break }
            }
            if let cacheURL, let encoded = try? JSONEncoder().encode(cache) {
                try? encoded.write(to: cacheURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
            }
        }
        return GiteeResource(value: value, cachedAt: nil)
    }
}
