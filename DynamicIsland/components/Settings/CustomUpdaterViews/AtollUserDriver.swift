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
import Sparkle
import SwiftUI

/// Custom Sparkle user driver that presents SwiftUI-based update windows
/// instead of Sparkle's default AppKit UI.
///
/// This driver handles all update lifecycle events: discovery, download progress,
/// extraction, installation, errors, and the "no update available" state.
@MainActor
class AtollUserDriver: NSObject, @preconcurrency SPUUserDriver {
    
    // MARK: - Window Management
    
    private var updateWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    
    /// The current update state, observed by SwiftUI views.
    private let updateState = UpdateUIState()
    
    // MARK: - SPUUserDriver Protocol
    
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Auto-allow automatic update checks
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }
    
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        updateState.phase = .checking
        updateState.cancelAction = cancellation
        presentWindow(with: UpdateCheckingView(state: updateState))
    }
    
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateState.phase = .updateFound
        updateState.appcastItem = appcastItem
        updateState.userUpdateState = state
        updateState.updateReply = reply
        
        presentWindow(with: UpdateFoundView(state: updateState))
    }
    
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Parse release notes HTML/text and display them
        if let html = String(data: downloadData.data, encoding: .utf8) {
            updateState.releaseNotesHTML = html
        }
    }
    
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        updateState.releaseNotesHTML = nil
    }
    
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updateState.phase = .upToDate
        updateState.acknowledgeAction = acknowledgement
        presentWindow(with: UpdateNotFoundView(state: updateState))
    }
    
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updateState.phase = .error
        updateState.errorMessage = error.localizedDescription
        updateState.acknowledgeAction = acknowledgement
        presentWindow(with: UpdateErrorView(state: updateState))
    }
    
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        updateState.phase = .downloading
        updateState.progress = 0
        updateState.cancelAction = cancellation
        presentWindow(with: UpdateProgressView(state: updateState))
    }
    
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        updateState.totalBytes = expectedContentLength
    }
    
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        updateState.downloadedBytes += length
        if updateState.totalBytes > 0 {
            updateState.progress = Double(updateState.downloadedBytes) / Double(updateState.totalBytes)
        }
    }
    
    func showDownloadDidStartExtractingUpdate() {
        updateState.phase = .extracting
        updateState.progress = 0
    }
    
    func showExtractionReceivedProgress(_ progress: Double) {
        updateState.progress = progress
    }
    
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateState.phase = .readyToInstall
        updateState.updateReply = reply
    }
    
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        updateState.phase = .installing
        // If app hasn't terminated yet, we just show the progress.
        // Sparkle handles the quit/relaunch flow.
    }
    
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        updateState.phase = .installed
        updateState.acknowledgeAction = acknowledgement
        acknowledgement()
        dismissWindow()
    }
    
    func showUpdateInFocus() {
        updateWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func dismissUpdateInstallation() {
        dismissWindow()
    }
    
    // MARK: - Window Presentation
    
    private func presentWindow<V: View>(with view: V) {
        dismissWindow()
        
        let hostingController = NSHostingController(rootView: AnyView(view))
        self.hostingController = hostingController
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Atoll Update"
        window.styleMask = [.titled, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 460, height: 380))
        window.center()
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        
        self.updateWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func dismissWindow() {
        updateWindow?.close()
        updateWindow = nil
        hostingController = nil
    }
}

// MARK: - Update State

/// Observable state object shared between the user driver and SwiftUI views.
@MainActor
class UpdateUIState: ObservableObject {
    @Published var phase: UpdatePhase = .idle
    @Published var progress: Double = 0
    @Published var totalBytes: UInt64 = 0
    @Published var downloadedBytes: UInt64 = 0
    @Published var errorMessage: String?
    @Published var releaseNotesHTML: String?
    @Published var appcastItem: SUAppcastItem?
    @Published var userUpdateState: SPUUserUpdateState?
    
    var cancelAction: (() -> Void)?
    var acknowledgeAction: (() -> Void)?
    var updateReply: ((SPUUserUpdateChoice) -> Void)?
    
    var downloadSpeedString: String {
        let bytes = downloadedBytes
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
    
    var totalSizeString: String {
        let mb = Double(totalBytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}

enum UpdatePhase: Equatable {
    case idle
    case checking
    case updateFound
    case downloading
    case extracting
    case readyToInstall
    case installing
    case installed
    case upToDate
    case error
    
    var displayName: String {
        switch self {
        case .idle:           return String(localized: "Idle")
        case .checking:       return String(localized: "Checking for updates…")
        case .updateFound:    return String(localized: "Update Available")
        case .downloading:    return String(localized: "Downloading…")
        case .extracting:     return String(localized: "Extracting…")
        case .readyToInstall: return String(localized: "Ready to Install")
        case .installing:     return String(localized: "Installing…")
        case .installed:      return String(localized: "Installed")
        case .upToDate:       return String(localized: "Up to Date")
        case .error:          return String(localized: "Error")
        }
    }
}

// MARK: - Checking View (shown during initial check)

struct UpdateCheckingView: View {
    @ObservedObject var state: UpdateUIState
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(.circular)
            
            Text("Checking for updates…")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text("Looking for a new version of Atoll")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Cancel") {
                state.cancelAction?()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(width: 460, height: 380)
        .background(.ultraThinMaterial)
    }
}

#Preview("Checking") {
    UpdateCheckingView(state: {
        let s = UpdateUIState()
        s.phase = .checking
        return s
    }())
}
