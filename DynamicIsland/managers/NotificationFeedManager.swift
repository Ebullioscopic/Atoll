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

import Combine
import Defaults
import Foundation
import SQLite3

struct FeedItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let timestamp: Date
    let category: FeedItemCategory

    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

enum FeedItemCategory {
    case notification
    case hermesSession
}

@MainActor
class NotificationFeedManager: ObservableObject {
    static let shared = NotificationFeedManager()

    @Published var feedItems: [FeedItem] = []

    private let maxItems = 50
    private var hermesTimer: Timer?
    private var lastHermesCheck: Date = Date().addingTimeInterval(-3600)
    private var cancellables = Set<AnyCancellable>()

    private var hermesDBPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.hermes/state.db"
    }

    private init() {
        Defaults.publisher(.enableNotificationFeed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue {
                    self?.startHermesMonitoring()
                } else {
                    self?.stopHermesMonitoring()
                }
            }
            .store(in: &cancellables)

        if Defaults[.enableNotificationFeed] {
            startHermesMonitoring()
        }
    }

    func appendNotification(_ notification: MessageNotification) {
        guard Defaults[.enableNotificationFeed] else { return }
        let item = FeedItem(
            title: notification.sender,
            subtitle: notification.filteredContent,
            timestamp: notification.timestamp,
            category: .notification
        )
        feedItems.insert(item, at: 0)
        trimItems()
    }

    func clearFeed() {
        feedItems.removeAll()
    }

    private func trimItems() {
        if feedItems.count > maxItems {
            feedItems = Array(feedItems.prefix(maxItems))
        }
    }

    // MARK: - Hermes Session Monitoring

    private func startHermesMonitoring() {
        stopHermesMonitoring()
        checkHermesSessions()
        hermesTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkHermesSessions()
            }
        }
    }

    private func stopHermesMonitoring() {
        hermesTimer?.invalidate()
        hermesTimer = nil
    }

    private func checkHermesSessions() {
        guard FileManager.default.fileExists(atPath: hermesDBPath) else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(hermesDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let cutoff = lastHermesCheck.timeIntervalSince1970
        let query = """
            SELECT title, ended_at FROM sessions
            WHERE ended_at > ? AND status = 'completed'
            ORDER BY ended_at DESC LIMIT 10
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        var newItems: [FeedItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let title: String
            if let cStr = sqlite3_column_text(stmt, 0) {
                title = String(cString: cStr)
            } else {
                title = "Untitled"
            }
            let endedAt = sqlite3_column_double(stmt, 1)
            let timestamp = Date(timeIntervalSince1970: endedAt)

            newItems.append(FeedItem(
                title: "Hermes completed: \(title)",
                subtitle: "",
                timestamp: timestamp,
                category: .hermesSession
            ))
        }

        if !newItems.isEmpty {
            let maxTimestamp = newItems.map { $0.timestamp }.max() ?? Date()
            lastHermesCheck = maxTimestamp
            for item in newItems.reversed() {
                feedItems.insert(item, at: 0)
            }
            trimItems()
        }
    }
}
