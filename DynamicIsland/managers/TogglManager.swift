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
import Defaults

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
    let workspaceId: Int?

    var isRunning: Bool { duration < 0 }
    var parsedStart: Date? { TogglManager.parseDate(start) }

    enum CodingKeys: String, CodingKey {
        case id, description, start, duration
        case projectId = "project_id"
        case workspaceId = "workspace_id"
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
    /// ID of the running Toggl entry this timer was synced from. Stop/save must stop
    /// that entry instead of creating a second one.
    private(set) var syncedEntryId: Int? = nil
    /// Workspace of the synced entry, so it is stopped in the workspace it was started in.
    private(set) var syncedWorkspaceId: Int? = nil

    private struct PendingEntry: Identifiable, Codable {
        var id = UUID()
        let description: String
        let projectId: Int?
        let start: Date
        let stop: Date
    }

    /// A remote stop that failed and must be retried. Kept apart from new stopwatch entries.
    private struct RemoteStop: Codable {
        let workspaceId: Int
        let entryId: Int
        let description: String
        let projectId: Int?
    }

    /// Completed entries whose POST failed, each retried independently.
    /// Pending work is saved to disk on every change, so it survives a restart.
    private var pendingRetryEntries: [PendingEntry] = [] {
        didSet {
            persist(pendingRetryEntries, key: pendingEntriesKey)
            refreshPendingFlag()
        }
    }
    /// Failed remote stops, one per entry, so one failure never replaces another.
    private var pendingRemoteStops: [RemoteStop] = [] {
        didSet {
            persist(pendingRemoteStops, key: pendingStopKey)
            refreshPendingFlag()
        }
    }
    /// Set while a retry runs, so a second Retry cannot post the same entry twice.
    private var isRetryInFlight = false
    /// True while any failed entry or stop is waiting for a retry.
    @Published private(set) var hasPendingRetry = false

    /// Updates `hasPendingRetry` from the queued entries and stops.
    private func refreshPendingFlag() {
        let pending = !pendingRetryEntries.isEmpty || !pendingRemoteStops.isEmpty
        if hasPendingRetry != pending { hasPendingRetry = pending }
    }

    /// Bumped on every auth change, so results from an older Save or Disconnect are ignored.
    private var authGeneration = 0
    /// Bumped on every local start or stop, so a sync that finishes after one is discarded.
    private var localActionGeneration = 0

    // MARK: - Persistence keys

    private let keychainAccount = "com.atoll.toggl.apiToken"
    private let workspaceIdKey  = "togglWorkspaceId"
    private let projectsKey     = "togglProjectsJSON"
    private let recentEntriesKey = "togglRecentEntriesJSON"
    private let pendingEntriesKey = "togglPendingEntriesJSON"
    private let pendingStopKey = "togglPendingStopJSON"

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

    /// Validates and stores the API token in the Keychain, then resolves the default workspace and loads projects and recent entries.
    func saveToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        authGeneration += 1
        let generation = authGeneration
        guard writeKeychain(trimmed) else {
            connectionStatus = .error("Could not save token to Keychain")
            return
        }
        connectionStatus = .connecting

        do {
            let wsId = try await fetchWorkspaceId(token: trimmed)
            guard generation == authGeneration else { return }
            workspaceId = wsId
            UserDefaults.standard.set(wsId, forKey: workspaceIdKey)
            connectionStatus = .connected
            Task { await self.fetchProjects() }
            Task { await self.fetchRecentEntries() }
        } catch {
            guard generation == authGeneration else { return }
            connectionStatus = .error(error.localizedDescription)
        }
    }

    /// Clears the token, workspace, cached projects and any stopwatch state, returning the manager to its disconnected state.
    func disconnect() {
        // Invalidate any Save that is still waiting for Toggl, so it cannot restore a connection.
        authGeneration += 1
        // Stop any in-flight stopwatch first so no elapsed interval survives to a
        // later stopStopwatch() save once auth state is gone.
        resetStopwatch()
        // Disconnecting discards unsaved work; the UI asks for confirmation first.
        clearSaveError()
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

    /// Fetches the workspace projects, sorted by name, and caches them. Keeps the cached list on failure.
    func fetchProjects() async {
        guard hasToken else { return }
        let generation = authGeneration
        isFetchingProjects = true
        defer { isFetchingProjects = false }

        do {
            let fetched: [TogglProject] = try await apiGET("/api/v9/me/projects")
            // Ignore a response that arrives after Disconnect or a newer Save.
            guard generation == authGeneration else { return }
            projects = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            persist(projects, key: projectsKey)
        } catch {
            // Keep cached list on failure
        }
    }

    // MARK: - Recent entries

    /// Loads the last 7 days of time entries and keeps the three most recent distinct ones.
    private func fetchRecentEntries() async {
        guard hasToken else { return }
        let generation = authGeneration

        let fmt = ISO8601DateFormatter()
        let now = Date()
        let startDate = fmt.string(from: now.addingTimeInterval(-7 * 86400))
        let endDate = fmt.string(from: now)

        struct RawEntry: Codable {
            let description: String?
            let projectId: Int?
            enum CodingKeys: String, CodingKey {
                case description
                case projectId = "project_id"
            }
        }

        do {
            let entries: [RawEntry] = try await apiGET("/api/v9/me/time_entries?start_date=\(startDate)&end_date=\(endDate)")
            guard generation == authGeneration else { return }
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

    /// Posts a completed time entry to Toggl. On failure the entry is kept for retry.
    func saveEntry(description: String, projectId: Int?, start: Date, stop: Date) async {
        guard hasToken, let wsId = workspaceId else { return }

        let entry = PendingEntry(description: description, projectId: projectId, start: start, stop: stop)
        isSavingEntry = true
        saveError = nil

        do {
            try await postTimeEntry(entry: entry, workspaceId: wsId)
            isSavingEntry = false
            prependRecentEntry(TogglRecentEntry(
                description: description,
                projectId: projectId,
                projectName: projects.first { $0.id == projectId }?.name
            ))
        } catch {
            isSavingEntry = false
            // Keep this entry alongside any earlier unsaved ones; each is retried on its own.
            pendingRetryEntries.append(entry)
            saveError = error.localizedDescription
        }
    }

    /// Retries the failed remote stop and each failed entry, removing each one only after its own save succeeds.
    func retryPendingEntry() async {
        guard !isRetryInFlight else { return }
        isRetryInFlight = true
        defer { isRetryInFlight = false }
        let previousError = saveError
        saveError = nil
        for stop in pendingRemoteStops {
            await performRemoteStop(stop)
        }
        // Keep the stop error until the stop succeeds, even when no entry retry fails.
        let stopError = pendingRemoteStops.isEmpty ? nil : saveError
        guard let wsId = workspaceId else {
            saveError = stopError ?? previousError
            return
        }
        isSavingEntry = true
        saveError = nil

        var lastError: Error?
        for entry in pendingRetryEntries {
            do {
                try await postTimeEntry(entry: entry, workspaceId: wsId)
                pendingRetryEntries.removeAll { $0.id == entry.id }
                prependRecentEntry(TogglRecentEntry(
                    description: entry.description,
                    projectId: entry.projectId,
                    projectName: projects.first { $0.id == entry.projectId }?.name
                ))
            } catch {
                lastError = error
            }
        }
        isSavingEntry = false
        saveError = lastError?.localizedDescription ?? stopError
    }

    // MARK: - Sync running timer

    /// Returns the currently running Toggl entry, or nil if none is running or the request fails.
    func fetchCurrentTimer() async throws -> TogglRunningEntry? {
        guard hasToken else { throw URLError(.userAuthenticationRequired) }
        isFetchingCurrentTimer = true
        defer { isFetchingCurrentTimer = false }

        let entry: TogglRunningEntry? = try await apiGETNullable("/api/v9/me/time_entries/current")
        return entry?.isRunning == true ? entry : nil
    }

    /// Fetches the running Toggl entry and adopts its description, project, start and ID.
    /// Returns `.superseded` if a local timer or stopwatch started or stopped while the request was pending.
    func adoptRunningEntry() async -> AdoptResult {
        let generation = localActionGeneration
        let fetched: TogglRunningEntry?
        do {
            fetched = try await fetchCurrentTimer()
        } catch {
            guard generation == localActionGeneration else { return .superseded }
            return .failed(message: error.localizedDescription)
        }
        guard generation == localActionGeneration, Defaults[.togglEnabled] else { return .superseded }
        guard let entry = fetched, let parsedStart = entry.parsedStart else {
            return .nothingRunning
        }
        pendingDescription = entry.description ?? ""
        pendingProjectId = entry.projectId
        setSyncedStart(parsedStart, entryId: entry.id, workspaceId: entry.workspaceId)
        return .adopted(elapsed: max(0, Date().timeIntervalSince(parsedStart)))
    }

    enum AdoptResult {
        case adopted(elapsed: TimeInterval)
        case nothingRunning
        /// The request failed, so it is unknown whether an entry is running.
        case failed(message: String)
        case superseded
    }

    /// Detaches the synced entry and returns the stop to send for it. Runs synchronously, so the
    /// ID is captured before any later timer start can clear it. Returns nil when nothing is synced.
    private func detachSyncedStop() -> RemoteStop? {
        guard let entryId = syncedEntryId, let wsId = syncedWorkspaceId ?? workspaceId else {
            clearSyncedStart()
            return nil
        }
        let stop = RemoteStop(workspaceId: wsId, entryId: entryId, description: pendingDescription, projectId: pendingProjectId)
        clearSyncedStart()
        return stop
    }

    /// Stops the Toggl entry this timer was synced from, so it does not keep running remotely.
    /// A failed stop is kept for retry.
    func stopSyncedEntry() async {
        guard let stop = detachSyncedStop() else { return }
        await performRemoteStop(stop)
    }

    /// Stops the synced Toggl entry without waiting, capturing its ID immediately.
    func stopSyncedEntryInBackground() {
        guard let stop = detachSyncedStop() else { return }
        Task { await performRemoteStop(stop) }
    }

    /// Sends the stop request for a remote entry. A failed stop is kept for retry.
    private func performRemoteStop(_ stop: RemoteStop) async {
        guard hasToken else {
            removePendingStop(stop)
            return
        }
        do {
            try await apiPATCH("/api/v9/workspaces/\(stop.workspaceId)/time_entries/\(stop.entryId)/stop")
            removePendingStop(stop)
            prependRecentEntry(TogglRecentEntry(
                description: stop.description,
                projectId: stop.projectId,
                projectName: projects.first { $0.id == stop.projectId }?.name
            ))
        } catch let TogglError.httpError(code, _) where (400..<500).contains(code) && ![401, 403, 429].contains(code) {
            // Toggl rejected the stop because the entry is already stopped. Nothing left to retry.
            removePendingStop(stop)
        } catch {
            if !pendingRemoteStops.contains(where: { $0.entryId == stop.entryId }) {
                pendingRemoteStops.append(stop)
            }
            saveError = "Couldn't stop the Toggl timer: \(error.localizedDescription)"
        }
    }

    /// Drops the pending stop for this entry only, leaving any other failed stops queued.
    private func removePendingStop(_ stop: RemoteStop) {
        pendingRemoteStops.removeAll { $0.entryId == stop.entryId }
    }

    // MARK: - Stopwatch

    /// Starts the stopwatch from its current elapsed value, ticking once per second.
    func startStopwatch() {
        markLocalActivity()
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

    /// Stops the stopwatch. A synced entry is stopped remotely; otherwise the elapsed interval is saved as a new entry.
    func stopStopwatch() async {
        markLocalActivity()
        stopwatchTimer?.invalidate()
        stopwatchTimer = nil
        isRunning = false
        if syncedEntryId != nil {
            elapsed = 0
            stopwatchStartedAt = nil
            await stopSyncedEntry()
            return
        }
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

    /// Stops the stopwatch and clears its elapsed time and synced entry without saving anything. Failed saves stay queued.
    func resetStopwatch() {
        markLocalActivity()
        stopwatchTimer?.invalidate()
        stopwatchTimer = nil
        isRunning = false
        elapsed = 0
        stopwatchStartedAt = nil
        clearSyncedStart()
        // Failed saves and stops are kept, so Retry stays available after a reset.
    }

    // MARK: - Helpers

    /// Records that a local timer or stopwatch started or stopped, invalidating sync requests still in flight.
    func markLocalActivity() { localActionGeneration += 1 }

    /// Call whenever the local timer is started, replaced or stopped, from any control. Invalidates in-flight
    /// syncs and stops the Toggl entry the replaced timer was synced from, unless the stopwatch owns it.
    func localTimerChanged() {
        markLocalActivity()
        guard !isRunning else { return }
        stopSyncedEntryInBackground()
    }

    /// Records the start, entry ID and workspace of a Toggl entry the timer was synced from.
    func setSyncedStart(_ date: Date, entryId: Int? = nil, workspaceId: Int? = nil) {
        syncedOriginalStart = date
        syncedEntryId = entryId
        syncedWorkspaceId = workspaceId
    }
    /// Forgets the synced Toggl entry.
    func clearSyncedStart() {
        syncedOriginalStart = nil
        syncedEntryId = nil
        syncedWorkspaceId = nil
    }
    /// Drops the save error and every entry waiting to be retried.
    func clearSaveError() { saveError = nil; pendingRetryEntries.removeAll(); pendingRemoteStops.removeAll() }

    // MARK: - Sleep detection

    /// Saves a running stopwatch when the Mac goes to sleep.
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

    /// Parses an ISO 8601 timestamp with or without fractional seconds.
    nonisolated static func parseDate(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: s)
    }

    // MARK: - Networking

    /// Returns the default workspace ID for the account that owns the token.
    private func fetchWorkspaceId(token: String) async throws -> Int {
        struct Me: Codable {
            let defaultWorkspaceId: Int
            enum CodingKeys: String, CodingKey { case defaultWorkspaceId = "default_workspace_id" }
        }
        let me: Me = try await apiGET("/api/v9/me", token: token)
        return me.defaultWorkspaceId
    }

    /// Posts a completed time entry to the given workspace. The duration is at least one second.
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

    /// Sends a GET request and decodes the JSON response.
    private func apiGET<T: Decodable>(_ path: String, token: String? = nil) async throws -> T {
        let data = try await networkRequest(path: path, method: "GET", body: nil, token: token)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Sends a GET request whose response may be null.
    private func apiGETNullable<T: Decodable>(_ path: String) async throws -> T? {
        let data = try await networkRequest(path: path, method: "GET", body: nil, token: nil)
        return try JSONDecoder().decode(T?.self, from: data)
    }

    /// Sends a PATCH request with no body.
    private func apiPATCH(_ path: String) async throws {
        _ = try await networkRequest(path: path, method: "PATCH", body: nil, token: nil)
    }

    /// Sends a POST request with a JSON body.
    private func apiPOST(_ path: String, body: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await networkRequest(path: path, method: "POST", body: bodyData, token: nil)
    }

    /// Sends an authenticated request to the Toggl API and returns the response body. Throws on a non-2xx status.
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

    /// Builds the Basic authorization header for an API token.
    private func authHeader(token: String) -> String {
        let encoded = Data("\(token):api_token".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    // MARK: - Persistence

    /// Restores the workspace, projects and recent entries saved on disk.
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
        if let data = UserDefaults.standard.data(forKey: pendingEntriesKey),
           let decoded = try? JSONDecoder().decode([PendingEntry].self, from: data) {
            pendingRetryEntries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: pendingStopKey) {
            if let decoded = try? JSONDecoder().decode([RemoteStop].self, from: data) {
                pendingRemoteStops = decoded
            } else if let legacy = try? JSONDecoder().decode(RemoteStop.self, from: data) {
                // Older builds stored a single pending stop.
                pendingRemoteStops = [legacy]
            }
        }
        if hasPendingRetry {
            saveError = "Some Toggl entries from your last session were not saved."
        }
        if hasToken {
            connectionStatus = workspaceId != nil ? .connected : .disconnected
        }
    }

    /// Encodes a value and saves it in UserDefaults under the given key.
    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Moves an entry to the front of the recent list, keeping three.
    private func prependRecentEntry(_ entry: TogglRecentEntry) {
        var updated = recentEntries.filter { $0.id != entry.id }
        updated.insert(entry, at: 0)
        recentEntries = Array(updated.prefix(3))
        persist(recentEntries, key: recentEntriesKey)
    }

    // MARK: - Keychain

    /// Replaces the API token in the Keychain. Returns whether it was saved.
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

    /// Reads the API token from the Keychain, or nil if none is stored.
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

    /// Removes the API token from the Keychain.
    private func deleteKeychain() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(q as CFDictionary)
    }
}
