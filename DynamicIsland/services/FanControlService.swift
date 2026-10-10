import Foundation
import Combine
import AppKit
import Defaults

// Cancels a pending command if the feature is disabled while the macOS
// authorization dialog is open. Unlike the worker, this gate spans both queues.
private final class CoolingCommandGate: @unchecked Sendable {
    private let lock = NSLock()
    private var permittedGeneration: Int?
    func allow(_ generation: Int?) { lock.lock(); permittedGeneration = generation; lock.unlock() }
    func allows(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return permittedGeneration == generation
    }
}

// Mutable worker state is accessed only on its serial queue.
private final class CoolingWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "Atoll.cooling", qos: .utility)
    let helper = CoolingHelperSession()
    let gate = CoolingCommandGate()
    var transport: AppleSMCTransport?
}

@MainActor
final class FanControlService: ObservableObject {
    static let shared = FanControlService()
    typealias Fan = CoolingFan
    enum Status: Equatable { case unavailable(String), discovering, ready }

    @Published private(set) var fans: [Fan] = []
    @Published private(set) var hottestTemperature: Double?
    @Published private(set) var status: Status = .discovering
    @Published private(set) var isApplying = false
    @Published private(set) var controlError: String?
    @Published private(set) var needsReconnect = false
    @Published private(set) var presets: [Int: Double] = [:]

    nonisolated private let worker = CoolingWorker()
    private var timer: Timer?
    private var visible = false
    private var hasSession = false
    private var refreshing = false
    private var generation = 0
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private init() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.shutdown() } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.visible else { return }
                self.start()
            }
        }
    }

    func start() {
        guard Defaults[.enableFanControl] else { return }
        visible = true
        ensureTimer()
        refresh()
    }

    func stop() {
        visible = false
        // Continue heartbeats while a manual preset is active, even when the
        // notch is closed. Losing the app/connection expires control in 15s.
        if !hasSession && !isApplying { timer?.invalidate(); timer = nil }
    }

    private func ensureTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard Defaults[.enableFanControl], (visible || hasSession), !refreshing, !isApplying else { return }
        refreshing = true
        let refreshGeneration = generation
        worker.queue.async { [self, worker] in
            var controlFailure: String?
            do { try worker.helper.heartbeat() }
            catch { controlFailure = error.localizedDescription }
            do {
                if worker.transport == nil { worker.transport = try AppleSMCTransport() }
                let readings = try worker.transport!.discoverAndRead()
                let temperature = try worker.transport!.temperature()
                let connected = worker.helper.isConnected
                let failure = controlFailure
                Task { @MainActor in
                    guard generation == refreshGeneration else { return }
                    fans = readings
                    hottestTemperature = temperature
                    status = readings.isEmpty ? .unavailable("This Mac has no fans.") : .ready
                    hasSession = connected
                    if let failure { controlError = failure; needsReconnect = !connected; presets.removeAll() }
                    for fan in readings {
                        if fan.mode != .manual { presets[fan.id] = nil }
                    }
                    refreshing = false
                    if !visible, !hasSession { timer?.invalidate(); timer = nil }
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in
                    guard generation == refreshGeneration else { return }
                    fans = []; hottestTemperature = nil
                    status = .unavailable(message); refreshing = false
                }
            }
        }
    }

    func apply(_ fraction: Double?, to fanID: Int) {
        guard Defaults[.enableFanControl], !isApplying, !needsReconnect else { return }
        isApplying = true; controlError = nil
        let commandGeneration = generation
        worker.gate.allow(commandGeneration)
        let request = CoolingRequest(command: fraction == nil ? "auto" : "preset", fanID: fanID, fraction: fraction)
        worker.queue.async { [self, worker] in
            var failure: String?
            do { _ = try worker.helper.command(request, shouldProceed: { worker.gate.allows(commandGeneration) }) }
            catch { failure = error.localizedDescription }
            let connected = worker.helper.isConnected
            let errorMessage = failure
            Task { @MainActor in
                guard generation == commandGeneration else { return }
                hasSession = connected; isApplying = false; controlError = errorMessage
                needsReconnect = errorMessage != nil && !connected
                if connected { ensureTimer() }
                if errorMessage == nil { presets[fanID] = fraction }
                else { presets.removeAll() }
                refresh()
            }
        }
    }

    func retryConnection() {
        worker.queue.async { [self, worker] in
            worker.helper.resetAuthorizationFailure()
            Task { @MainActor in needsReconnect = false; controlError = nil }
        }
    }

    func shutdown() {
        generation += 1
        worker.gate.allow(nil)
        isApplying = false; refreshing = false; controlError = nil; needsReconnect = false
        timer?.invalidate(); timer = nil
        hasSession = false; presets.removeAll()
        worker.queue.async { [worker] in worker.helper.close() }
    }
}
