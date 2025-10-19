//
//  SystemHUDManager.swift
//  DynamicIsland
//
//  Created by GitHub Copilot on 06/09/25.
//

import Foundation
import Defaults
import Combine

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: DynamicIslandViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        // Use Defaults publisher instead of @Default property wrapper
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    await self.startSystemHUD()
                } else {
                    await self.stopSystemHUD()
                }
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
        
        if Defaults[.enableSystemHUD] {
            Task { @MainActor in
                await startSystemHUD()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    @MainActor
    private func startSystemHUD() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        await stopSystemHUD() // Stop any existing observer
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)
        changesObserver?.startObserving()
        
        // Disable system HUD if possible
        disableSystemHUD()
        
        print("System HUD replacement started")
        isSystemOperationInProgress = false
    }
    
    @MainActor
    private func stopSystemHUD() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        
        // Re-enable system HUD
        enableOriginalSystemHUD()
        
        print("System HUD replacement stopped")
        isSystemOperationInProgress = false
    }
    
    private func disableSystemHUD() {
        print("🔇 Disabling system HUD (OSDUIHelper running: \(SystemOSDManager.isOSDUIHelperRunning()))")
        // Disable the system HUD using SystemOSDManager
        SystemOSDManager.disableSystemHUD()
    }
    
    private func enableOriginalSystemHUD() {
        print("🔊 Re-enabling system HUD (OSDUIHelper running: \(SystemOSDManager.isOSDUIHelperRunning()))")
        // Re-enable the system HUD using SystemOSDManager
        SystemOSDManager.enableSystemHUD()
        
        // Check status after a reasonable delay, using async to avoid blocking
        Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds instead of 1
            let isRunning = await SystemOSDManager.isOSDUIHelperRunningAsync()
            print("🔍 OSDUIHelper status after re-enable: \(isRunning ? "✅ Running" : "❌ Not running")")
        }
    }
    
    // MARK: - Media Key Event Handling
    
    /// Handle volume key press events from MediaKeyApplication
    public func handleVolumeKeyEvent() {
        changesObserver?.handleVolumeKeyEvent()
    }
    
    /// Handle brightness key press events from MediaKeyApplication
    public func handleBrightnessKeyEvent() {
        changesObserver?.handleBrightnessKeyEvent()
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemHUD()
        }
        // Emergency restore is available via SystemHUDManager.emergencyRestoreSystemHUD() if needed
    }
    
    /// Emergency restore function - call this if system HUD is not working
    public static func emergencyRestoreSystemHUD() {
        print("🚨 Emergency system HUD restore initiated")
        SystemHUDDebugger.forceRestartOSDUIHelper()
    }
}