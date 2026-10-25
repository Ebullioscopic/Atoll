import Foundation
import Darwin
import SystemConfiguration

/// Receives fan-only messages on one authenticated connection and dispatches them serially.
private final class CoolingDaemonEndpoint: NSObject, CoolingXPCProtocol {
    weak var host: CoolingDaemonHost?
    let generation: UUID
    /// Associates an endpoint with the active controller generation.
    init(host: CoolingDaemonHost, generation: UUID) { self.host = host; self.generation = generation }
    /// Rejects malformed/oversized JSON before invoking any hardware operation.
    func execute(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard request.count <= 4096, let value = try? JSONDecoder().decode(CoolingRequest.self, from: request), let host else {
            reply(CoolingXPC.encode(CoolingReply(ok: false, message: "Invalid fan-control request."))); return
        }
        host.queue.async {
            guard host.generation == self.generation, let engine = host.engine else {
                reply(CoolingXPC.encode(CoolingReply(ok: false, message: "The fan-control connection closed."))); return
            }
            var consoleUID: uid_t = 0
            _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
            guard host.connection?.effectiveUserIdentifier == consoleUID, consoleUID > 0 else {
                host.close(); reply(CoolingXPC.encode(CoolingReply(ok: false, message: "Fan control belongs to the active Mac user."))); return
            }
            reply(CoolingXPC.encode(engine.execute(value)))
        }
    }
}

/// Owns at most one controller; an idle installed daemon keeps no SMC connection or manual target.
private final class CoolingDaemonHost: NSObject, NSXPCListenerDelegate {
    let queue = DispatchQueue(label: "Atoll.cooling.daemon", qos: .utility)
    var engine: CoolingDaemonEngine?
    var generation: UUID?
    var connection: NSXPCConnection?
    private var timer: DispatchSourceTimer?

    /// Starts a low-frequency watchdog on the same queue as all fan writes and cleanup.
    func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, let engine = self.engine else { return }
            var consoleUID: uid_t = 0
            _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
            if consoleUID == 0 || self.connection?.effectiveUserIdentifier != consoleUID || !engine.tick() { self.close() }
        }
        self.timer = timer; timer.resume()
    }

    /// Accepts only the current console user; the listener checks signing identity before this callback.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection candidate: NSXPCConnection) -> Bool {
        var consoleUID: uid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
        guard consoleUID > 0, candidate.effectiveUserIdentifier == consoleUID else { return false }
        return queue.sync {
            // Do not let another connection displace a live fan owner.
            guard connection == nil else { return false }
            let id = UUID()
            generation = id; engine = CoolingDaemonEngine(); connection = candidate
            candidate.exportedInterface = NSXPCInterface(with: CoolingXPCProtocol.self)
            candidate.exportedObject = CoolingDaemonEndpoint(host: self, generation: id)
            let cleanup = { [weak self] in
                guard let self else { return }
                self.queue.async { if self.generation == id { self.close() } }
            }
            candidate.invalidationHandler = cleanup
            candidate.interruptionHandler = cleanup
            candidate.resume()
            return true
        }
    }

    /// Restores owned fans before releasing the authenticated connection.
    func close() {
        engine?.close(); engine = nil; generation = nil
        let old = connection; connection = nil; old?.invalidate()
    }
}

/// Launches the root daemon with mutual signing checks and graceful SIGTERM restoration.
func runCoolingDaemon() throws {
    guard geteuid() == 0 else { throw CoolingSMC.Error.permission }
    let requirement = try CoolingXPC.requirement(identifier: CoolingXPC.appIdentifier)
    let host = CoolingDaemonHost()
    let listener = NSXPCListener(machServiceName: CoolingXPC.serviceName)
    listener.setConnectionCodeSigningRequirement(requirement)
    listener.delegate = host
    host.startWatchdog()
    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
    let sources = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
        let source = DispatchSource.makeSignalSource(signal: number, queue: host.queue)
        source.setEventHandler { host.close(); exit(0) }
        source.resume(); return source
    }
    listener.resume()
    withExtendedLifetime((host, listener, sources)) { dispatchMain() }
}
