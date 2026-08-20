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
import KeyboardShortcuts

/// Routes Atoll's clipboard triggers to whichever app the user picked as their clipboard
/// manager (see `ClipboardProvider`).
///
/// Atoll's own manager stays the default. When an external provider is selected, Atoll
/// stops collecting its own history and every clipboard entry point — the notch button,
/// the keyboard shortcut, the coordinator toggle — opens that app instead of Atoll's
/// panel/popover/tab.
///
/// External apps are opened by *reopening* them (`NSWorkspace.openApplication`), which is
/// the same event their own Dock/status-item click sends: Maccy answers
/// `applicationShouldHandleReopen` by toggling its popup, so no Accessibility permission
/// or synthesized hotkey is involved, and a second trigger closes the popup again —
/// matching the toggle semantics of Atoll's own clipboard UI.
@MainActor
final class ClipboardProviderManager: ObservableObject {
    static let shared = ClipboardProviderManager()

    /// Whether the selected external app is installed on this machine.
    @Published private(set) var isDetected: Bool = false

    /// Whether the selected external app is currently running.
    @Published private(set) var isRunning: Bool = false

    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshDetectionStatus()
        setupWorkspaceObservers()
        setupSettingsObserver()
    }

    // MARK: - Resolution (pure, Defaults-only)
    //
    // These are `nonisolated` so sizing helpers and view bodies can ask "is the built-in
    // clipboard UI in play?" without hopping actors or touching published state.

    /// The provider actually in effect. Falls back to the built-in manager when the chosen
    /// app isn't installed, so an uninstalled app never leaves the clipboard feature dead.
    nonisolated static var resolvedProvider: ClipboardProvider {
        let provider = Defaults[.clipboardProvider]
        return isInstalled(provider) ? provider : .builtIn
    }

    /// Atoll collects its own history and shows its own clipboard UI.
    /// Display mode, history size, and the clipboard tabs only apply while this is true.
    nonisolated static var usesBuiltInClipboard: Bool {
        Defaults[.enableClipboardManager] && resolvedProvider == .builtIn
    }

    // MARK: - Trigger routing

    /// Hand a clipboard trigger to the external provider.
    ///
    /// `nonisolated` so the keyboard-shortcut handler and SwiftUI button actions can ask
    /// this without hopping actors; only the published state update goes back to the main
    /// actor.
    ///
    /// - Returns: `true` when an external app took over the trigger; `false` when the
    ///   caller should fall through to Atoll's own clipboard UI.
    @discardableResult
    nonisolated static func handleClipboardTrigger() -> Bool {
        openProviderPopup(resolvedProvider)
    }

    /// Reopen the provider app, which toggles its clipboard popup.
    @discardableResult
    nonisolated static func openProviderPopup(_ provider: ClipboardProvider) -> Bool {
        guard provider.isExternal, let appURL = applicationURL(for: provider) else { return false }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Reuse the running instance — a second instance would not toggle the popup.
        configuration.createsNewApplicationInstance = false

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            Task { @MainActor in
                if let error {
                    NSLog("%@", "📋 Failed to open \(provider.displayName): \(error.localizedDescription)")
                }
                shared.isRunning = app != nil
            }
        }
        return true
    }

    // MARK: - Detection

    // `nonisolated(unsafe)` because the cache is read from nonisolated resolution helpers on
    // whichever thread asks; every access below is serialized by `installationCacheLock`.
    nonisolated(unsafe) private static var installationCache: [String: Bool] = [:]
    private static let installationCacheLock = NSLock()

    /// Cached because view bodies and notch sizing ask this on every layout pass;
    /// the cache is dropped whenever an app is installed, launched, or removed.
    nonisolated static func isInstalled(_ provider: ClipboardProvider) -> Bool {
        guard provider.isExternal else { return true }

        installationCacheLock.lock()
        if let cached = installationCache[provider.rawValue] {
            installationCacheLock.unlock()
            return cached
        }
        installationCacheLock.unlock()

        let installed = applicationURL(for: provider) != nil

        installationCacheLock.lock()
        installationCache[provider.rawValue] = installed
        installationCacheLock.unlock()

        return installed
    }

    nonisolated static func invalidateInstallationCache() {
        installationCacheLock.lock()
        installationCache.removeAll()
        installationCacheLock.unlock()
    }

    nonisolated static func applicationURL(for provider: ClipboardProvider) -> URL? {
        for bundleID in provider.bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    nonisolated static func isRunning(_ provider: ClipboardProvider) -> Bool {
        guard provider.isExternal else { return false }
        let identifiers = Set(provider.bundleIdentifiers)
        return NSWorkspace.shared.runningApplications.contains {
            guard let bundleID = $0.bundleIdentifier else { return false }
            return identifiers.contains(bundleID)
        }
    }

    /// Re-check install/run state of the selected provider (e.g. after an install).
    func refreshDetectionStatus() {
        Self.invalidateInstallationCache()
        let provider = Defaults[.clipboardProvider]
        isDetected = Self.isInstalled(provider) && provider.isExternal
        isRunning = Self.isRunning(provider)
    }

    // MARK: - Built-in monitoring

    /// Keep Atoll's own pasteboard polling in step with the selected provider: there is no
    /// point paying for a timer and a second copy of the history while another app owns it.
    ///
    /// Driven by the settings observer, so switching provider takes effect immediately
    /// rather than waiting for the next notch render.
    func syncBuiltInMonitoring() {
        if Self.usesBuiltInClipboard {
            if !ClipboardManager.shared.isMonitoring {
                ClipboardManager.shared.startMonitoring()
            }
        } else if ClipboardManager.shared.isMonitoring {
            ClipboardManager.shared.stopMonitoring()
        }
    }

    // MARK: - Keyboard shortcut

    /// Release Atoll's clipboard shortcut while another app owns the clipboard.
    ///
    /// Atoll's shortcut defaults to Cmd+Shift+C, which is also Maccy's default popup hotkey.
    /// With both registered, one key press reaches both apps: Maccy opens its popup and
    /// Atoll's reopen toggles it straight back shut, so the popup only flashes. The app that
    /// owns the clipboard owns the hotkey too; the notch icon stays as Atoll's way in.
    ///
    /// Must run after `registerOptionalShortcutHandlers()` — `KeyboardShortcuts.disable`
    /// unregisters the hotkey rather than remembering a disabled state, so a later
    /// registration would silently bring the collision back.
    func syncShortcutRegistration() {
        if Self.usesBuiltInClipboard {
            KeyboardShortcuts.enable(.clipboardHistoryPanel)
        } else {
            KeyboardShortcuts.disable(.clipboardHistoryPanel)
        }
    }

    /// Leave Atoll's own clipboard tab when the feature is handed to another app, so the
    /// notch isn't left sitting on a view that no longer receives anything.
    private func dismissBuiltInClipboardViewIfNeeded() {
        guard !Self.usesBuiltInClipboard else { return }
        let coordinator = DynamicIslandViewCoordinator.shared
        if coordinator.currentView == .clipboard {
            coordinator.currentView = .home
        }
    }

    // MARK: - Observers

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier,
                      ClipboardProvider.allCases.contains(where: { $0.bundleIdentifiers.contains(bundleID) })
                else { return }
                Task { @MainActor in
                    self?.refreshDetectionStatus()
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func setupSettingsObserver() {
        Publishers.Merge(
            Defaults.publisher(.clipboardProvider).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableClipboardManager).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshDetectionStatus()
            self?.syncBuiltInMonitoring()
            self?.syncShortcutRegistration()
            self?.dismissBuiltInClipboardViewIfNeeded()
        }
        .store(in: &cancellables)
    }
}
