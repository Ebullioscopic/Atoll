// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import Security
import ToolIsleCore

struct KeychainFailure: Error, LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "钥匙串操作失败（\(status)）。" }
}
enum TokenVault {
    static var service: String { (Bundle.main.bundleIdentifier ?? "io.github.lideming0815.toolisle") + ".gitee" }
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "access-token"] }
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainFailure(status: status) }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let values = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var q = query.merging(values) { _, new in new }
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainFailure(status: status) }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(status: status) }
    }
}
@MainActor final class GiteeAccount: ObservableObject {
    @Published private(set) var user: GiteeUser?
    @Published private(set) var client: GiteeClient?
    @Published var busy = false
    @Published var message: String?
    @Published var diskCache = UserDefaults.standard.bool(forKey: "gitee.diskCache")
    private var generation = UUID()
    private var restored = false
    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(TokenVault.service, isDirectory: true)
    }
    func restore() async {
        guard !restored else { return }; restored = true
        do { if let token = try TokenVault.read() { await connect(token, restoring: true) } }
        catch { message = error.localizedDescription }
    }
    func connect(_ input: String, restoring: Bool = false) async {
        guard !busy else { return }
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 4096, !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            message = "请输入有效访问令牌，而不是账号密码。"; return
        }
        let version = UUID(); generation = version
        busy = true; message = nil
        defer { if generation == version { busy = false } }
        let candidate = GiteeClient(token: token)
        do {
            let profile = try await candidate.user()
            try Task.checkCancellation()
            guard version == generation else { return }
            // Finish all suspension points before atomically storing the validated identity.
            var cacheWarning: String?
            do { try await candidate.configureDiskCache(directory: diskCache ? cacheDirectory : nil, accountID: profile.id) }
            catch {
                try? await candidate.configureDiskCache(directory: nil, accountID: profile.id)
                cacheWarning = "已连接，但磁盘缓存不可用：" + error.localizedDescription
            }
            try Task.checkCancellation()
            guard version == generation else { try? await candidate.invalidate(); return }
            try TokenVault.save(token)
            if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "gitee.profile") }
            user = profile; client = candidate; message = cacheWarning
        } catch {
            guard version == generation else { return }
            // A known-revoked saved credential must not unlock an old offline profile later.
            if restoring, error as? GiteeError == .unauthorized {
                try? await candidate.invalidate()
                await disconnect()
                if message == nil { message = GiteeError.unauthorized.localizedDescription }
                return
            }
            if restoring, diskCache, let network = error as? URLError,
               [.notConnectedToInternet, .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(network.code),
               let data = UserDefaults.standard.data(forKey: "gitee.profile"), let profile = try? JSONDecoder().decode(GiteeUser.self, from: data) {
                do {
                    try await candidate.configureDiskCache(directory: cacheDirectory, accountID: profile.id)
                    guard version == generation else { try? await candidate.invalidate(); return }
                    user = profile; client = candidate; message = "当前离线，仅可查看此前缓存的内容；权限状态尚未重新验证。"
                } catch { message = error.localizedDescription }
            } else if !(error is CancellationError) { message = error.localizedDescription }
        }
    }
    func setDiskCache(_ enabled: Bool) async {
        diskCache = enabled; UserDefaults.standard.set(enabled, forKey: "gitee.diskCache")
        guard let client, let user else { return }
        do {
            if !enabled { try await client.clearCache() }
            try await client.configureDiskCache(directory: enabled ? cacheDirectory : nil, accountID: user.id)
        } catch { report(error, from: client) }
    }
    func disconnect() async {
        let version = UUID(); generation = version; busy = true
        let oldClient = client; client = nil; user = nil
        UserDefaults.standard.removeObject(forKey: "gitee.profile")
        UserDefaults.standard.removeObject(forKey: "gitee.lastRead")
        var failures: [String] = []
        do { try TokenVault.delete() } catch { failures.append(error.localizedDescription) }
        do { try await oldClient?.invalidate() } catch { failures.append(error.localizedDescription) }
        do {
            if FileManager.default.fileExists(atPath: cacheDirectory.path) { try FileManager.default.removeItem(at: cacheDirectory) }
        } catch { failures.append(error.localizedDescription) }
        guard version == generation else { return }
        busy = false
        message = failures.isEmpty ? nil : "已退出界面，但部分凭据或缓存清理失败，请重试退出：" + failures.joined(separator: "；")
    }
    func report(_ error: Error, from requester: GiteeClient? = nil) {
        if let requester, client !== requester { return }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        message = error.localizedDescription
        if error as? GiteeError == .unauthorized {
            let version = generation
            Task {
                guard version == generation else { return }
                await disconnect()
                if message == nil { message = GiteeError.unauthorized.localizedDescription }
            }
        }
    }
}
struct GiteeConnectionView: View {
    @EnvironmentObject var account: GiteeAccount
    @State private var token = ""
    var body: some View {
        Form {
            Section("连接 Gitee") {
                Text("使用个人访问令牌连接。ToolIsle 只读取数据，不保存账号密码，也不会上传令牌到项目仓库。")
                SecureField("个人访问令牌", text: $token)
                    .onSubmit { connect() }
                HStack {
                    Button("验证并连接", action: connect).disabled(account.busy || token.isEmpty)
                    if account.busy { ProgressView().controlSize(.small) }
                    Link("打开 Gitee", destination: URL(string: "https://gitee.com")!)
                }
                Text("请在 Gitee 个人设置中创建令牌，并按实际读取需求授予个人资料、仓库、Issues 和评论相关权限。不要在聊天或工单中发送令牌。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("隐私") {
                Toggle("保存离线缓存", isOn: Binding(get: { account.diskCache }, set: { value in Task { await account.setDiskCache(value) } }))
                Text("默认关闭磁盘缓存；开启后以当前账户隔离保存最多 7 天，文件权限仅限当前系统用户。缓存不是加密文件；退出账户会删除。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("清除已保存的连接和缓存") { Task { await account.disconnect() } }.disabled(account.busy)
            }
            if let message = account.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
        }.formStyle(.grouped).frame(maxWidth: 760)
    }
    private func connect() {
        let input = token; token = ""
        Task { await account.connect(input) }
    }
}
