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
import Foundation

enum FullDiskAccessAuthorization {
    private static let probeURLs: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")
    ]

    static func hasPermission() -> Bool {
        for url in probeURLs {
            if canReadProtectedResource(at: url) {
                return true
            }
        }
        return false
    }

    private static func canReadProtectedResource(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
            return true
        } catch {
            return false
        }
    }
}

enum ShelfFolderAccessAuthorization {
    private static var documentsDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private static var downloadsDirectoryURL: URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    static func hasDocumentsAccess() -> Bool {
        canReadDirectory(at: documentsDirectoryURL)
    }

    static func hasDownloadsAccess() -> Bool {
        canReadDirectory(at: downloadsDirectoryURL)
    }

    static func hasDocumentsAndDownloadsAccess() -> Bool {
        hasDocumentsAccess() && hasDownloadsAccess()
    }

    static func requestAccessProbe() {
        if let documentsDirectoryURL {
            _ = try? FileManager.default.contentsOfDirectory(at: documentsDirectoryURL, includingPropertiesForKeys: nil)
        }

        if let downloadsDirectoryURL {
            _ = try? FileManager.default.contentsOfDirectory(at: downloadsDirectoryURL, includingPropertiesForKeys: nil)
        }
    }

    private static func canReadDirectory(at url: URL?) -> Bool {
        guard let url else { return false }

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class FullDiskAccessPermissionStore: ObservableObject {
    static let shared = FullDiskAccessPermissionStore()

    @Published private(set) var isAuthorized: Bool = FullDiskAccessAuthorization.hasPermission()

    private var pollingTask: Task<Void, Never>?

    private init() {}

    deinit {
        pollingTask?.cancel()
    }

    func refreshStatus() {
        updateAuthorizationStatus(to: FullDiskAccessAuthorization.hasPermission())
    }

    func requestAccessPrompt() {
#if os(macOS)
        let alert = NSAlert()
        alert.messageText = String(localized: "Full Disk Access Required")
        alert.informativeText = String(localized: "Dynamic Island needs Full Disk Access to detect custom Focus indicators and power the Shelf. Click Continue to open Full Disk Access settings, then press the + button and select Dynamic Island (we'll reveal it in Finder for you).")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            openSystemSettings()
            revealAppBundleInFinder()
        }
#endif
        beginPollingForStatusChanges()
    }

    func openSystemSettings() {
#if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private func revealAppBundleInFinder() {
#if os(macOS)
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
#endif
    }

    private func beginPollingForStatusChanges() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let status = FullDiskAccessAuthorization.hasPermission()

                await MainActor.run {
                    self.updateAuthorizationStatus(to: status)
                }

                if status {
                    break
                }
            }
        }
    }

    private func updateAuthorizationStatus(to newValue: Bool) {
        guard newValue != isAuthorized else { return }
        isAuthorized = newValue
    }
}

@MainActor
final class ShelfFolderAccessPermissionStore: ObservableObject {
    static let shared = ShelfFolderAccessPermissionStore()

    @Published private(set) var hasDocumentsAccess: Bool = ShelfFolderAccessAuthorization.hasDocumentsAccess()
    @Published private(set) var hasDownloadsAccess: Bool = ShelfFolderAccessAuthorization.hasDownloadsAccess()

    var hasDocumentsAndDownloadsAccess: Bool {
        hasDocumentsAccess && hasDownloadsAccess
    }

    private var pollingTask: Task<Void, Never>?

    private init() {}

    deinit {
        pollingTask?.cancel()
    }

    func refreshStatus() {
        updateStatus(
            documents: ShelfFolderAccessAuthorization.hasDocumentsAccess(),
            downloads: ShelfFolderAccessAuthorization.hasDownloadsAccess()
        )
    }

    func requestAccessPrompt() {
        ShelfFolderAccessAuthorization.requestAccessProbe()
        beginPollingForStatusChanges()
    }

    func openSystemSettings() {
#if os(macOS)
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for candidate in urls {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
#endif
    }

    private func beginPollingForStatusChanges() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }

            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 500_000_000)

                let docs = ShelfFolderAccessAuthorization.hasDocumentsAccess()
                let downloads = ShelfFolderAccessAuthorization.hasDownloadsAccess()

                await MainActor.run {
                    self.updateStatus(documents: docs, downloads: downloads)
                }

                if docs && downloads {
                    break
                }
            }
        }
    }

    private func updateStatus(documents: Bool, downloads: Bool) {
        if hasDocumentsAccess != documents {
            hasDocumentsAccess = documents
        }

        if hasDownloadsAccess != downloads {
            hasDownloadsAccess = downloads
        }
    }
}
