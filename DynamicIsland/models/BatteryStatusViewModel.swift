/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

enum BatteryTemporaryHUDKind: Equatable {
    case charging
    case lowBattery
    case fullBattery
}

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: DynamicIslandAnimations = DynamicIslandAnimations()
    private let lowBatteryAlertSoundPlayer = AudioPlayer()

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""
    @Published private(set) var activeTemporaryHUDKind: BatteryTemporaryHUDKind?
    @Published private(set) var activeTemporaryHUDToken: UUID = UUID()
    @Published private(set) var activeTemporaryHUDTargetScreenName: String?
    @Published private(set) var activeTemporaryHUDLevelOverride: Int?
    @Published private(set) var activeTemporaryHUDLowPowerModeOverride: Bool?

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            let wasPluggedIn = self.isPluggedIn
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
            }
            if !wasPluggedIn && isPluggedIn {
                presentTemporaryBatteryHUDIfNeeded(kind: .charging)
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            let previousLevel = self.levelBattery
            withAnimation {
                self.levelBattery = level
            }
            self.handleLowBatteryAlertIfNeeded(previousLevel: previousLevel, newLevel: level)
            self.handleFullBatteryAlertIfNeeded(previousLevel: previousLevel, newLevel: level)

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            let wasEnabled = self.isInLowPowerMode
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = String(localized: "Low Power: \(self.isInLowPowerMode ? String(localized: "On") : String(localized: "Off"))")
            }
            if !wasEnabled && isEnabled {
                presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery)
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? String(localized: "Charging battery")
                    : (self.levelBattery < self.maxCapacity ? String(localized: "Not charging") : String(localized: "Full charge"))
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
        }
    }

    private func presentTemporaryBatteryHUDIfNeeded(kind: BatteryTemporaryHUDKind) {
        presentTemporaryBatteryHUDIfNeeded(kind: kind, force: false)
    }

    func triggerTestHUD(kind: BatteryTemporaryHUDKind) {
        let previewLevel: Int

        switch kind {
        case .charging:
            previewLevel = max(12, min(95, Int(levelBattery.rounded())))
        case .lowBattery:
            previewLevel = max(5, min(20, Defaults[.lowBatteryHUDThreshold]))
        case .fullBattery:
            previewLevel = 100
        }

        presentTemporaryBatteryHUDIfNeeded(
            kind: kind,
            force: true,
            levelOverride: previewLevel,
            lowPowerModeOverride: kind == .lowBattery ? isInLowPowerMode : nil
        )
    }

    private func presentTemporaryBatteryHUDIfNeeded(
        kind: BatteryTemporaryHUDKind,
        force: Bool,
        levelOverride: Int? = nil,
        lowPowerModeOverride: Bool? = nil
    ) {
        guard force || Defaults[.showPowerStatusNotifications] else { return }

        let duration: Int
        let isEnabled: Bool

        switch kind {
        case .charging:
            duration = Defaults[.chargingBatteryHUDDuration]
            isEnabled = Defaults[.showChargingBatteryHUD]
        case .lowBattery:
            duration = Defaults[.lowBatteryHUDDuration]
            isEnabled = Defaults[.showLowBatteryHUD]
        case .fullBattery:
            duration = Defaults[.fullBatteryHUDDuration]
            isEnabled = Defaults[.showFullBatteryHUD]
        }

        guard force || isEnabled else { return }

        activeTemporaryHUDKind = kind
        activeTemporaryHUDToken = UUID()
        activeTemporaryHUDTargetScreenName = resolvedTemporaryHUDTargetScreenName()
        activeTemporaryHUDLevelOverride = levelOverride
        activeTemporaryHUDLowPowerModeOverride = lowPowerModeOverride
        coordinator.toggleExpandingView(
            status: true,
            type: .battery,
            autoHideDuration: TimeInterval(max(1, duration))
        )
    }

    private func resolvedTemporaryHUDTargetScreenName() -> String? {
        if Defaults[.showOnAllDisplays] {
            return nil
        }

        let preferredNames = [
            coordinator.selectedScreen,
            coordinator.preferredScreen,
            NSScreen.main?.localizedName
        ]
        .compactMap { $0 }

        for candidate in preferredNames where NSScreen.screens.contains(where: { $0.localizedName == candidate }) {
            return candidate
        }

        return NSScreen.screens.first?.localizedName
    }

    private func preferredDynamicIslandTargetScreenName() -> String? {
        let mainScreenName = NSScreen.main?.localizedName
        let preferredNames = [coordinator.selectedScreen, coordinator.preferredScreen]

        for candidate in preferredNames where shouldUseDynamicIslandMode(for: candidate) {
            return candidate
        }

        if let externalDynamicIslandScreen = NSScreen.screens.first(where: {
            $0.localizedName != mainScreenName && shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return externalDynamicIslandScreen.localizedName
        }

        if let anyDynamicIslandScreen = NSScreen.screens.first(where: {
            shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return anyDynamicIslandScreen.localizedName
        }

        return nil
    }

    private func handleLowBatteryAlertIfNeeded(previousLevel: Float, newLevel: Float) {
        guard !isPluggedIn, !isCharging else { return }
        guard newLevel < previousLevel else { return }
        let threshold = Float(Defaults[.lowBatteryHUDThreshold])
        guard previousLevel > threshold && newLevel <= threshold else { return }

        self.statusText = String(localized: "Low battery")
        presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery)
        if Defaults[.playLowBatteryAlertSound] {
            playLowBatteryAlertSound()
        }
    }

    private func handleFullBatteryAlertIfNeeded(previousLevel: Float, newLevel: Float) {
        guard newLevel > previousLevel else { return }
        let threshold = Float(Defaults[.fullBatteryHUDThreshold])
        guard previousLevel < threshold && newLevel >= threshold else { return }

        self.statusText = String(localized: "Full charge")
        presentTemporaryBatteryHUDIfNeeded(kind: .fullBattery)
    }

    private func playLowBatteryAlertSound() {
        lowBatteryAlertSoundPlayer.play(fileName: "lowbattery", fileExtension: "mp3")
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
