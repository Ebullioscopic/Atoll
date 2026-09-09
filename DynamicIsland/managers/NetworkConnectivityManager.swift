/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import CoreWLAN
import Foundation
import Network

enum ConnectivityHUDState: Equatable {
    case hidden
    case noConnection
    case wifi(name: String)
    case hotspot(name: String)

    var isVisible: Bool {
        self != .hidden
    }

    var isConnectedNetwork: Bool {
        switch self {
        case .wifi, .hotspot:
            return true
        case .hidden, .noConnection:
            return false
        }
    }
}

/// Watches the Mac's default network route and turns meaningful connectivity
/// changes into short-lived HUD presentations.
final class NetworkConnectivityManager: NSObject, ObservableObject, CWEventDelegate {
    static let shared = NetworkConnectivityManager()

    @Published private(set) var hudState: ConnectivityHUDState = .hidden

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.atoll.network-connectivity", qos: .utility)
    private let wiFiClient = CWWiFiClient.shared()

    private var hasStarted = false
    private var hasReceivedInitialPath = false
    private var lastConnectionSatisfied = false
    private var lastPathUsedWiFi = false
    private var lastConnectionWasHotspot = false
    private var lastWiFiName: String?
    private var noConnectionDismissed = false
    private var hideWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    func startMonitoring() {
        guard !hasStarted else { return }
        hasStarted = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isSatisfied = path.status == .satisfied
            let usesWiFi = isSatisfied && path.usesInterfaceType(.wifi)
            let isHotspot = usesWiFi && path.isExpensive
            let wiFiName = usesWiFi ? Self.currentWiFiName(using: self.wiFiClient) : nil

            DispatchQueue.main.async { [weak self] in
                self?.handlePathUpdate(
                    isSatisfied: isSatisfied,
                    usesWiFi: usesWiFi,
                    isHotspot: isHotspot,
                    wiFiName: wiFiName
                )
            }
        }

        wiFiClient.delegate = self
        try? wiFiClient.startMonitoringEvent(with: .ssidDidChange)
        try? wiFiClient.startMonitoringEvent(with: .linkDidChange)
        pathMonitor.start(queue: monitorQueue)
    }

    func stopMonitoring() {
        guard hasStarted else { return }
        hasStarted = false
        pathMonitor.cancel()
        try? wiFiClient.stopMonitoringEvent(with: .ssidDidChange)
        try? wiFiClient.stopMonitoringEvent(with: .linkDidChange)
        wiFiClient.delegate = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    func dismissNoConnection() {
        guard hudState == .noConnection else { return }
        noConnectionDismissed = true
        hudState = .hidden
    }

    func openNetworkSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshWiFiIdentity()
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshWiFiIdentity()
    }

    private func refreshWiFiIdentity() {
        monitorQueue.async { [weak self] in
            guard let self else { return }
            let name = Self.currentWiFiName(using: self.wiFiClient)
            DispatchQueue.main.async { [weak self] in
                self?.handleWiFiIdentityChange(name)
            }
        }
    }

    private func handlePathUpdate(
        isSatisfied: Bool,
        usesWiFi: Bool,
        isHotspot: Bool,
        wiFiName: String?
    ) {
        dispatchPrecondition(condition: .onQueue(.main))

        let wasInitialUpdate = !hasReceivedInitialPath
        let shouldAnnounceWiFi = !wasInitialUpdate
            && isSatisfied
            && usesWiFi
            && (
                !lastConnectionSatisfied
                    || !lastPathUsedWiFi
                    || isHotspot != lastConnectionWasHotspot
                    || (wiFiName != nil && wiFiName != lastWiFiName)
            )

        hasReceivedInitialPath = true

        if !isSatisfied {
            lastConnectionSatisfied = false
            lastPathUsedWiFi = false
            lastConnectionWasHotspot = false
            lastWiFiName = nil
            hideWorkItem?.cancel()
            hideWorkItem = nil
            if !noConnectionDismissed {
                hudState = .noConnection
            }
            return
        }

        noConnectionDismissed = false
        lastConnectionSatisfied = true
        lastPathUsedWiFi = usesWiFi

        if usesWiFi {
            let resolvedName = wiFiName ?? lastWiFiName
            if shouldAnnounceWiFi {
                showConnection(named: resolvedName, isHotspot: isHotspot)
            } else if wasInitialUpdate || wiFiName != nil {
                lastWiFiName = resolvedName
                lastConnectionWasHotspot = isHotspot
                if hudState == .noConnection {
                    hudState = .hidden
                }
            }
        } else {
            lastWiFiName = nil
            lastConnectionWasHotspot = false
            hideWorkItem?.cancel()
            hideWorkItem = nil
            hudState = .hidden
        }
    }

    private func handleWiFiIdentityChange(_ name: String?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasReceivedInitialPath, lastConnectionSatisfied, lastPathUsedWiFi else { return }
        guard let name, !name.isEmpty else { return }
        guard name != lastWiFiName else { return }
        showConnection(named: name, isHotspot: lastConnectionWasHotspot)
    }

    private func showConnection(named name: String?, isHotspot: Bool) {
        let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let displayName, !displayName.isEmpty {
            resolvedName = displayName
        } else {
            resolvedName = isHotspot
                ? String(localized: "Personal Hotspot")
                : String(localized: "Wi-Fi Network")
        }
        lastWiFiName = displayName
        lastConnectionWasHotspot = isHotspot
        hudState = isHotspot ? .hotspot(name: resolvedName) : .wifi(name: resolvedName)

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.hudState.isConnectedNetwork else { return }
            self.hudState = .hidden
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }

    /// CoreWLAN is the preferred source. `networksetup` is a permission-free
    /// fallback for macOS configurations where SSID access is privacy-redacted.
    private static func currentWiFiName(using client: CWWiFiClient) -> String? {
        if let name = client.interface()?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        guard let interfaceName = client.interface()?.interfaceName, !interfaceName.isEmpty else {
            return nil
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getairportnetwork", interfaceName]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let result = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let separator = result.firstIndex(of: ":") else {
            return nil
        }

        let name = result[result.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.localizedCaseInsensitiveContains("not associated") else {
            return nil
        }
        return name
    }
}
