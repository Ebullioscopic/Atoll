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

import AppKit
import Combine
import Defaults
import Foundation
import SQLite3

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var currentNotification: MessageNotification?
    @Published var notifications: [MessageNotification] = []
    @Published var shouldOpenNotch: Bool = false
    @Published var isActive: Bool = false

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastCheckDate: Date = Date().addingTimeInterval(-300)
    private var cancellables = Set<AnyCancellable>()

    private let maxNotifications = 20

    private var dbPath: String {
        let user = NSUserName()
        return "/Users/\(user)/Library/Group Containers/group.com.apple.usernoted/db2/db"
    }

    private let tempDBPath = "/tmp/atoll_notifications.db"

    private init() {
        Defaults.publisher(.enableMessageNotifications)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                if change.newValue {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)

        if Defaults[.enableMessageNotifications] {
            start()
        }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        startMonitoring()
        checkForNewNotifications()
    }

    func stop() {
        isActive = false
        stopMonitoring()
    }

    private func startMonitoring() {
        stopMonitoring()

        fileDescriptor = open(dbPath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.checkForNewNotifications()
            }
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source.resume()
        dispatchSource = source
    }

    private func stopMonitoring() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func copyDatabase() -> Bool {
        let fileManager = FileManager.default
        let walPath = dbPath + "-wal"
        let tempWalPath = tempDBPath + "-wal"

        try? fileManager.removeItem(atPath: tempDBPath)
        try? fileManager.removeItem(atPath: tempWalPath)

        do {
            try fileManager.copyItem(atPath: dbPath, toPath: tempDBPath)
            if fileManager.fileExists(atPath: walPath) {
                try fileManager.copyItem(atPath: walPath, toPath: tempWalPath)
            }
            return true
        } catch {
            return false
        }
    }

    private func checkForNewNotifications() {
        guard isActive else { return }
        guard copyDatabase() else { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let cutoff = lastCheckDate.timeIntervalSinceReferenceDate
        let query = "SELECT data, delivered_date FROM record WHERE delivered_date > ? ORDER BY delivered_date DESC LIMIT 20"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        var newNotifications: [MessageNotification] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let dataBlob = sqlite3_column_blob(stmt, 0) else { continue }
            let dataLength = Int(sqlite3_column_bytes(stmt, 0))
            let data = Data(bytes: dataBlob, count: dataLength)

            if let notification = parseNotificationData(data) {
                newNotifications.append(notification)
            }
        }

        if !newNotifications.isEmpty {
            lastCheckDate = Date()

            for notification in newNotifications.reversed() {
                notifications.insert(notification, at: 0)
            }

            if notifications.count > maxNotifications {
                notifications = Array(notifications.prefix(maxNotifications))
            }

            currentNotification = newNotifications.first
            shouldOpenNotch = Defaults[.autoExpandNotifications]
        }
    }

    private func parseNotificationData(_ data: Data) -> MessageNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            return nil
        }

        let sender = plist["titl"] as? String ?? plist["subt"] as? String ?? "Unknown"
        let content = plist["body"] as? String ?? ""
        let bundleId = plist["bide"] as? String ?? ""

        guard !sender.isEmpty || !content.isEmpty else { return nil }

        let appIcon: NSImage? = if !bundleId.isEmpty {
            NSWorkspace.shared.icon(forFile:
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)?.path ?? ""
            )
        } else {
            nil
        }

        return MessageNotification(
            sender: sender,
            content: content,
            profilePicture: nil,
            appIcon: appIcon,
            appBundleId: bundleId,
            timestamp: Date()
        )
    }

    func dismissCurrent() {
        shouldOpenNotch = false
        currentNotification = nil
    }

    func clearAll() {
        notifications.removeAll()
        currentNotification = nil
        shouldOpenNotch = false
    }
}
