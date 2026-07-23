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

import SwiftUI
import AppKit
import Defaults

/// Process-wide cache of resolved app icons keyed by file path.
/// `NSCache` is thread-safe, so it can be shared across the synchronous
/// call sites below (which run on the main thread during SwiftUI renders)
/// without extra locking. App icons rarely change during a session, so
/// caching removes redundant, main-thread `NSWorkspace` lookups on every
/// view refresh.
private let appIconPathCache = NSCache<NSString, NSImage>()

private func cachedIcon(forFile path: String) -> NSImage {
    if let cached = appIconPathCache.object(forKey: path as NSString) {
        return cached
    }
    let icon = NSWorkspace.shared.icon(forFile: path)
    appIconPathCache.setObject(icon, forKey: path as NSString)
    return icon
}

struct AppIcons {

    func getIcon(file path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path)
        else { return nil }

        return cachedIcon(forFile: path)
    }

    func getIcon(bundleID: String) -> NSImage? {
        // Use the POSIX path, not absoluteString ("file://…"): getIcon(file:)
        // guards on fileExists(atPath:), which only accepts POSIX paths, so
        // absoluteString made this lookup always return nil.
        guard let path = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleID
        )?.path
        else { return nil }

        return getIcon(file: path)
    }
    
        /// Easily read Info.plist as a Dictionary from any bundle by accessing .infoDictionary on Bundle
    func bundle(forBundleID: String) -> Bundle? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: forBundleID)
        else { return nil }
        
        return Bundle(url: url)
    }
    
}

func AppIcon(for bundleID: String) -> Image {
    let workspace = NSWorkspace.shared

    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        return Image(nsImage: cachedIcon(forFile: appURL.path))
    }

    return Image(nsImage: workspace.icon(for: .applicationBundle))
}


func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared

    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        return cachedIcon(forFile: appURL.path)
    }
    return nil
}

/// Loads the selected app-icon image (Defaults lookup + on-disk image read).
/// Safe to call off the main thread — it performs no UI mutation. The
/// `NSImage(contentsOf:)` read is real disk I/O, so the launch path resolves
/// this off-main and only assigns `applicationIconImage` back on the main actor.
func loadSelectedAppIconImage() -> NSImage? {
    let customIcons = Defaults[.customAppIcons]
    if let selectedID = Defaults[.selectedAppIconID],
       let icon = customIcons.first(where: { $0.id.uuidString == selectedID }),
       let image = NSImage(contentsOf: icon.fileURL) {
        return image
    }

    let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
    return NSImage(named: fallbackName)
}

func applySelectedAppIcon() {
    if let image = loadSelectedAppIconImage() {
        NSApp.applicationIconImage = image
    }
}

