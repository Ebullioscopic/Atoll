/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Security
import AppKit

// MARK: - Models

struct TogglProject: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TogglRecentEntry: Codable, Equatable, Identifiable {
    let description: String
    let projectId: Int?
    let projectName: String?

    var id: String { "\(description)|\(projectId ?? 0)" }
}

struct TogglRunningEntry: Codable {
    let id: Int
    let description: String?
    let projectId: Int?
    let start: String
    let duration: Int

    var isRunning: Bool { duration < 0 }
    var parsedStart: Date? { TogglManager.parseDate(start) }

    enum CodingKeys: String, CodingKey {
        case id, description, start, duration
        case projectId = "project_id"
    }
}

// MARK: - Errors

enum TogglError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(401, _): return "Invalid API token"
        case .httpError(403, _): return "Access denied"
        case .httpError(429, _): return "Rate limit exceeded (Toggl free: ~30 req/day)"
        case .httpError(let code, let body): return "Server error (\(code)): \(body)"
        }
    }
}

// MARK: - TogglManager

@MainActor
final class TogglManager: ObservableObject {
    static let shared = TogglManager()

    // MARK: - Published state

    @Published var projects: [TogglProject] = []
    @Published var recentEntries: [TogglRecentEntry] = []
    @Published var isSavingEntry = false
    @Published var saveError: String? = nil
    @Published var isFetchingProjects = false
    @Published var isFetchingCurrentTimer = false
    @Published var connectionStatus: ConnectionStatus = .disconnected

    /// Description and project for the upcoming Toggl entry — pre-filled by the user or recent-entry tap.
    @Published var pendingDescription: String = ""
    @Published var pendingProjectId: Int? = nil

    // MARK: Stopwatch
    @Published var isRunning: Bool = false
    @Published var elapsed: TimeInterval = 0
    private var stopwatchTimer: Timer?
    private var stopwatchStartedAt: Date?

    // MARK: - Non-published state

    @Published private(set) var workspaceId: Int? = nil
    /// Set when syncing a running Toggl entry; used as the POST `start` instead of the local timer start.
    private(set) var syncedOriginalStart: Date? = nil

    private struct PendingEntry {
        let description: String
        let projectId: Int?
        let start: Date
        let stop: Date
    }
    private var pendingRetryEntry: PendingEntry? = nil
    var hasPendingRetry: Bool { pendingRetryEntry != nil }

    // MARK: - Persistence keys

    private let keychainAccount = "com.atoll.toggl.apiToken"
    private let workspaceIdKey  = "togglWorkspaceId"
    private let projectsKey     = "togglProjectsJSON"
    private let recentEntriesKey = "togglRecentEntriesJSON"

    // MARK: - Connection status

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Init

    private init() {
        loadLocalData()
        setupSleepObserver()
    }

    // MARK: - Token management

    var apiToken: String { readKeychain() ?? "" }
    var hasToken: Bool { !apiToken.isEmpty }
    var isReady: Bool { connectionStatus == .connected && workspaceId != nil }

    func saveToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard writeKeychain(trimmed) else {
            connectionStatus = .error("Could not save token to Keychain")
            return
        }
        connectionStatus = .connecting

        do {
            let wsId = try await fetchWorkspaceId(token: trimmed)
            workspaceId = wsId
            UserDefaults.standard.set(wsId, forKey: workspaceIdKey)
            connectionStatus = .connected
            Task { await self.fetchProjects() }
            Task { await self.fetchRecentEntries() }
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    func disconnect() {
        // Stop any in-flight stopwatch first so no elapsed interval survives to a
        // later stopStopwatch() save once auth state is gone.
        resetStopwatch()
        deleteKeychain()
        workspaceId = nil
        projects = []
        recentEntries = []
        pendingDescription = ""
        pendingProjectId = nil
        connectionStatus = .disconnected
        for key in [workspaceIdKey, projectsKey, recentEntriesKey] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Projects

    func fetchProjects() async {
        guard hasToken else { return }
        isFetchingProjects = true
        defer { isFetchingProjects = false }

        do {
            let fetched: [TogglProject] = try await apiGET("/api/v9/me/projects")
            projects = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            persist(projects, key: projectsKey)
        } catch {
            // Keep cached list on failure
        }
    }

    // MARK: - Recent entries

    private func fetchRecentEntries() async {
        guard hasToken else { return }

        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))

        struct RawEntry: Codable {
            let description: String?
            let projectId: Int?
            enum CodingKeys: String, CodingKey {
                case description
                case projectId = "project_id"
            }
        }

        do {
            let entries: [RawEntry] = try await apiGET("/api/v9/me/time_entries?since=\(since)")
            var seen = Set<String>()
            var deduped: [TogglRecentEntry] = []
            for entry in Array(entries.prefix(20)).reversed() {
                let desc = entry.description ?? ""
                let key  = "\(desc)|\(entry.projectId ?? 0)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let name = projects.first { $0.id == entry.projectId }?.name
                deduped.append(TogglRecentEntry(description: desc, projectId: entry.projectId, projectName: name))
            }
            recentEntries = Array(deduped.suffix(3))
            persist(recentEntries, key: recentEntriesKey)
        } catch {
            // Keep cached list on failure
        }
    }

    // MARK: - Save entry

    func saveEntry(description: String, projectId: Int?, start: Date, stop: Date) async {
        guard hasToken, let wsId = workspaceId else { return }

        let entry = PendingEntry(description: description, projectId: projectId, start: start, stop: stop)
        isSavingEntry = true
        saveError = nil

        do {
            try await postTimeEntry(entry: entry, workspaceId: wsId)
            isSavingEntry = false
            pendingRetryEntry = nil
            prependRecentEntry(TogglRecentEntry(
                description: description,
                projectId: projectId,
                projectName: projects.first { $0.id == projectId }?.name
            ))
        } catch {
            isSavingEntry = false
            pendingRetryEntry = entry
            saveError = error.localizedDescription
        }
    }

    func retryPendingEntry() async {
        guard let entry = pendingRetryEntry, let wsId = workspaceId else { return }
        isSavingEntry = true
        saveError = nil

        do {
            try await postTimeEntry(entry: entry, workspaceId: wsId)
            isSavingEntry = false
            pendingRetryEntry = nil
            prependRecentEntry(TogglRecentEntry(
                description: entry.description,
                projectId: entry.projectId,
                projectName: projects.first { $0.id == entry.projectId }?.name
            ))
        } catch {
            isSavingEntry = false
            saveError = error.localizedDescription
        }
    }

    // MARK: - Sync running timer

    func fetchCurrentTimer() async -> TogglRunningEntry? {
        guard hasToken else { return nil }
        isFetchingCurrentTimer = true
        defer { isFetchingCurrentTimer = false }

        do {
            let entry: TogglRunningEntry? = try await apiGETNullable("/api/v9/me/time_entries/current")
            return entry?.isRunning == true ? entry : nil
        } catch {
            return nil
        }
    }

    // MARK: - Stopwatch

    func startStopwatch() {
        stopwatchTimer?.invalidate()
        // stopwatchStartedAt is the wall-clock moment when elapsed was 0.
        // Pre-seeding elapsed (e.g. from a Toggl sync) shifts this backwards.
        stopwatchStartedAt = Date().addingTimeInterval(-elapsed)
        isRunning = true
        stopwatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let start = self.stopwatchStartedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
    }

    func stopStopwatch() async {
        stopwatchTimer?.invalidate()
        stopwatchTimer = nil
        isRunning = false
        guard elapsed > 0 else { return }
        let stop = Date()
        let start = syncedOriginalStart ?? stopwatchStartedAt ?? Date().addingTimeInterval(-elapsed)
        let desc = pendingDescription
        let pid  = pendingProjectId
        elapsed = 0
        stopwatchStartedAt = nil
        clearSyncedStart()
        await saveEntry(description: desc, projectId: pid, start: start, stop: stop)
    }

    func resetStopwatch() {
        stopwatchTimer?.invalidate()
        stopwatchTimer = nil
        isRunning = false
        elapsed = 0
        stopwatchStartedAt = nil
        clearSyncedStart()
        clearSaveError()
    }

    // MARK: - Helpers

    func setSyncedStart(_ date: Date) { syncedOriginalStart = date }
    func clearSyncedStart() { syncedOriginalStart = nil }
    func clearSaveError() { saveError = nil; pendingRetryEntry = nil }

    // MARK: - Sleep detection

    private func setupSleepObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRunning {
                    await self.stopStopwatch()
                }
            }
        }
    }

    // MARK: - Date helpers

    nonisolated static func parseDate(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: s)
    }

    // MARK: - Networking

    private func fetchWorkspaceId(token: String) async throws -> Int {
        struct Me: Codable {
            let defaultWorkspaceId: Int
            enum CodingKeys: String, CodingKey { case defaultWorkspaceId = "default_workspace_id" }
        }
        let me: Me = try await apiGET("/api/v9/me", token: token)
        return me.defaultWorkspaceId
    }

    private func postTimeEntry(entry: PendingEntry, workspaceId: Int) async throws {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let duration = max(1, Int(entry.stop.timeIntervalSince(entry.start).rounded()))
        let stopDate = entry.start.addingTimeInterval(TimeInterval(duration))
        var body: [String: Any] = [
            "description": entry.description,
            "start": fmt.string(from: entry.start),
            "stop": fmt.string(from: stopDate),
            "duration": duration,
            "workspace_id": workspaceId,
            "created_with": "Atoll",
            "tags": [String]()
        ]
        if let pid = entry.projectId { body["project_id"] = pid }
        try await apiPOST("/api/v9/workspaces/\(workspaceId)/time_entries", body: body)
    }

    private func apiGET<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        let data = try await networkRequest(path: path, method: "GET", body: nil, token: token)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func apiGETNullable<T: Decodable>(_ path: String) async throws -> T? {
        let data = try await networkRequest(path: path, method: "GET", body: nil, token: nil)
        return try JSONDecoder().decode(T?.self, from: data)
    }

    private func apiPOST(_ path: String, body: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await networkRequest(path: path, method: "POST", body: bodyData, token: nil)
    }

    private func networkRequest(path: String, method: String, body: Data?, token: String?) async throws -> Data {
        guard let url = URL(string: "https://api.track.toggl.com\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authHeader(token: token ?? apiToken), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            // Body goes into the error for programmatic handling, but is not logged —
            // it can echo request payloads or account details.
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[Toggl] HTTP \(code) \(method) \(path)")
            throw TogglError.httpError(code, body)
        }
        return data
    }

    private func authHeader(token: String) -> String {
        let encoded = Data("\(token):api_token".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Persistence

    private func loadLocalData() {
        let wsId = UserDefaults.standard.integer(forKey: workspaceIdKey)
        workspaceId = wsId == 0 ? nil : wsId

        if let data = UserDefaults.standard.data(forKey: projectsKey),
           let decoded = try? JSONDecoder().decode([TogglProject].self, from: data) {
            projects = decoded
        }
        if let data = UserDefaults.standard.data(forKey: recentEntriesKey),
           let decoded = try? JSONDecoder().decode([TogglRecentEntry].self, from: data) {
            recentEntries = decoded
        }
        if hasToken {
            connectionStatus = workspaceId != nil ? .connected : .disconnected
        }
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func prependRecentEntry(_ entry: TogglRecentEntry) {
        var updated = recentEntries.filter { $0.id != entry.id }
        updated.insert(entry, at: 0)
        recentEntries = Array(updated.prefix(3))
        persist(recentEntries, key: recentEntriesKey)
    }

    // MARK: - Keychain

    private func writeKeychain(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let del: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(del as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Toggl] Keychain write failed (OSStatus \(status))")
        }
        return status == errSecSuccess
    }

    private func readKeychain() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(q as CFDictionary)
    }
}
