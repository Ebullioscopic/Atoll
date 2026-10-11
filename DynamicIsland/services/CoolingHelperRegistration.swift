import Foundation
import Combine
import ServiceManagement

/// Presents explicit, removable one-time background-helper setup in Cooling settings.
@MainActor final class CoolingHelperRegistration: ObservableObject {
    static let shared = CoolingHelperRegistration()
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    @Published private(set) var busy = false

    /// Refreshes OS consent state when settings opens or becomes active again.
    func refresh() {
        let previous = status
        status = CoolingPersistentSupport.service.status
        if status == .enabled, previous != .enabled { FanControlService.shared.retryConnection() }
    }

    /// Registers only the bundled fan daemon; macOS retains control of administrator approval.
    func install() {
        guard !busy else { return }
        error = nil
        do {
            _ = try CoolingXPC.signingTeam()
            try CoolingPersistentSupport.service.register()
            FanControlService.shared.shutdown()
            error = nil
        } catch {
            refresh()
            if status != .requiresApproval { self.error = error.localizedDescription }
        }
        refresh()
        if status == .enabled || status == .requiresApproval { FanControlService.shared.shutdown() }
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Opens the macOS approval pane without changing security settings or supplying a password.
    func openApproval() { SMAppService.openSystemSettingsLoginItems() }

    /// Disconnects fan ownership before unregistering the persistent daemon.
    func remove() {
        guard !busy else { return }
        busy = true
        Task {
            await FanControlService.shared.disconnectForHelperChange()
            do {
                try await CoolingPersistentSupport.service.unregister()
                error = nil
                FanControlService.shared.retryConnection()
            }
            catch { self.error = error.localizedDescription }
            busy = false; refresh()
        }
    }
}
