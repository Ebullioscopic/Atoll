import Foundation
import Combine
import AppKit
import Defaults

// Cancels a pending command if the feature is disabled while the macOS
// authorization dialog is open. Unlike the worker, this gate spans both queues.
private final class CoolingCommandGate: @unchecked Sendable {
    private let lock = NSLock()
    private var permittedGeneration: Int?
    /// Updates the generation permitted to apply commands, or cancels all pending generations.
    func allow(_ generation: Int?) { lock.lock(); permittedGeneration = generation; lock.unlock() }
    /// Checks cancellation across queues without exposing unsynchronized mutable state.
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
    @Published private(set) var controlNotice: String?
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

    /// Registers sleep cleanup and resumes read-only polling when a visible panel wakes.
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

    /// Begins polling when Cooling is enabled and its panel becomes visible.
    func start() {
        guard Defaults[.enableFanControl] else { return }
        visible = true
        CoolingHelperRegistration.shared.refresh()
        ensureTimer()
        refresh()
    }

    /// Hides the panel while preserving heartbeats for an active or authorizing control session.
    func stop() {
        visible = false
        // Continue heartbeats while a manual preset is active, even when the
        // notch is closed. Losing the app/connection expires control in 15s.
        if !hasSession && !isApplying { timer?.invalidate(); timer = nil }
    }

    /// Starts two-second polling in common run-loop modes so menus do not suspend the helper lease.
    private func ensureTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Collects read-only readings and renews authorization off the UI thread, ignoring stale generations.
    func refresh() {
        guard Defaults[.enableFanControl], (visible || hasSession), !refreshing, !isApplying else { return }
        refreshing = true
        let refreshGeneration = generation
        let mayConnect = !needsReconnect
        worker.queue.async { [self, worker] in
            var controlFailure: String?
            var heartbeatReply: CoolingReply?
            do {
                if mayConnect { try worker.helper.connectIfPersistentEnabled() }
                heartbeatReply = try worker.helper.heartbeat()
            }
            catch { controlFailure = error.localizedDescription }
            do {
                if worker.transport == nil { worker.transport = try AppleSMCTransport() }
                let readings = try worker.transport!.discoverAndRead()
                let temperature = try worker.transport!.temperature()
                let connected = worker.helper.isConnected
                let failure = controlFailure
                let reply = heartbeatReply
                Task { @MainActor in
                    guard generation == refreshGeneration else { return }
                    fans = readings
                    hottestTemperature = temperature
                    status = readings.isEmpty ? .unavailable("This Mac has no fans.") : .ready
                    hasSession = connected
                    controlNotice = reply?.controlNotice
                    if let effectivePresets = reply?.effectivePresets { presets = effectivePresets }
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

    /// Applies one preset or Auto command through the worker, publishing confirmed success or errors.
    func apply(_ fraction: Double?, to fanID: Int) {
        guard Defaults[.enableFanControl], !isApplying, !needsReconnect else { return }
        guard CoolingHelperRegistration.shared.prepareForCommand() else {
            controlError = CoolingHelperRegistration.shared.error ?? "Approve Atoll’s fan helper in the macOS window, then select your fan speed again."
            return
        }
        // A native setup prompt runs a nested event loop; recheck feature cancellation afterward.
        guard Defaults[.enableFanControl] else { return }
        isApplying = true; controlError = nil
        let commandGeneration = generation
        worker.gate.allow(commandGeneration)
        let request = CoolingRequest(command: fraction == nil ? "auto" : "preset", fanID: fanID, fraction: fraction)
        worker.queue.async { [self, worker] in
            var failure: String?
            var commandReply: CoolingReply?
            do { commandReply = try worker.helper.command(request, shouldProceed: { worker.gate.allows(commandGeneration) }) }
            catch { failure = error.localizedDescription }
            let connected = worker.helper.isConnected
            let errorMessage = failure
            let reply = commandReply
            Task { @MainActor in
                guard generation == commandGeneration else { return }
                hasSession = connected; isApplying = false; controlError = errorMessage
                needsReconnect = errorMessage != nil && !connected
                if connected { ensureTimer() }
                controlNotice = reply?.controlNotice
                if errorMessage == nil {
                    if let effectivePresets = reply?.effectivePresets { presets = effectivePresets }
                    else { presets[fanID] = fraction }
                }
                else { presets.removeAll() }
                refresh()
            }
        }
    }

    /// Reconnects the approved helper after restoring Auto; never reapplies an old manual preset.
    func retryConnection() {
        generation += 1
        let retryGeneration = generation
        worker.gate.allow(nil)
        presets.removeAll(); isApplying = false; refreshing = true
        controlNotice = nil
        worker.queue.async { [self, worker] in
            worker.helper.close()
            var failure: String?
            do { try worker.helper.connectIfPersistentEnabled() }
            catch { failure = error.localizedDescription }
            let message = failure
            let connected = worker.helper.isConnected
            Task { @MainActor in
                guard generation == retryGeneration else { return }
                needsReconnect = message != nil; controlError = message
                hasSession = connected; refreshing = false
                if visible || connected { ensureTimer(); refresh() }
            }
        }
    }

    /// Waits for queued cleanup before changing the registered helper installation.
    func disconnectForHelperChange() async {
        shutdown()
        await withCheckedContinuation { continuation in
            worker.queue.async { continuation.resume() }
        }
    }

    /// Cancels pending work, stops polling, and closes the helper so its fans return to Auto.
    func shutdown() {
        generation += 1
        worker.gate.allow(nil)
        isApplying = false; refreshing = false; controlError = nil; controlNotice = nil; needsReconnect = false
        timer?.invalidate(); timer = nil
        hasSession = false; presets.removeAll()
        fans = []; hottestTemperature = nil; status = .discovering
        worker.queue.async { [worker] in worker.helper.close(); worker.transport = nil }
    }
}
