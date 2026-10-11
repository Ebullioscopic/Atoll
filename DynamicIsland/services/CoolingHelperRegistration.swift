import AppKit
import Defaults
import Foundation
import Combine
import ServiceManagement

/// Offers native helper setup during onboarding or first use, with removable authorization.
@MainActor final class CoolingHelperRegistration: ObservableObject {
    static let shared = CoolingHelperRegistration()
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var error: String?
    @Published private(set) var busy = false

    private var declinedThisLaunch = false
    private static let offeredKey = "coolingHelperSetupOffered"

    /// Offers setup once when an opted-in user first launches this build or enables Cooling.
    func offerAutomaticSetupIfNeeded() {
        guard Defaults[.enableFanControl], !UserDefaults.standard.bool(forKey: Self.offeredKey),
              (try? CoolingXPC.signingTeam()) != nil else { return }
        refresh()
        guard status == .notRegistered || status == .notFound else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        offerSetup()
    }

    /// Prepares an explicit fan command; declining setup retains session authorization for this launch.
    func prepareForCommand() -> Bool {
        guard !busy else { return false }
        refresh()
        guard (try? CoolingXPC.signingTeam()) != nil else { return true }
        if status == .notRegistered || status == .notFound {
            if !declinedThisLaunch { offerSetup() }
        } else if status == .requiresApproval { openApproval() }
        refresh()
        return status == .enabled || (declinedThisLaunch && error == nil)
    }

    /// Presents a native consent prompt instead of requiring an installation control in settings.
    private func offerSetup() {
        guard !busy else { return }
        busy = true
        let alert = NSAlert()
        alert.messageText = "Set up fan control?"
        alert.informativeText = "Approve Atoll’s fan helper once to control fan speeds without another password after restarting Atoll or your Mac. macOS will open its approval settings."
        alert.addButton(withTitle: "Set Up Fan Control")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        let response = alert.runModal()
        busy = false
        if response == .alertFirstButtonReturn {
            install()
            if let error {
                let failure = NSAlert()
                failure.messageText = "Fan control setup failed"
                failure.informativeText = error
                failure.runModal()
            }
        } else { declinedThisLaunch = true; error = nil }
    }

    /// Refreshes OS consent state when settings opens or becomes active again.
    func refresh() {
        let previous = status
        status = CoolingPersistentSupport.service.status
        if status == .enabled, previous != .enabled { FanControlService.shared.retryConnection() }
    }

    /// Registers only the bundled fan daemon; macOS retains control of administrator approval.
    private func install() {
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
