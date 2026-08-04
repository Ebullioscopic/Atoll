import Foundation
import WatchConnectivity
import os

@MainActor
final class WatchBridge: NSObject {
    var commandHandler: ((CompanionCommandPayload) -> Void)?

    private static let log = Logger(subsystem: "top.fengye.CodeIslandCompanion", category: "watch-bridge")

    private var latestState: CompanionStatePayload?
    private var activationState: WCSessionActivationState = .notActivated

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(_ state: CompanionStatePayload?) {
        latestState = state
        flushLatestState(reason: "publish")
    }

    private func flushLatestState(reason: String) {
        guard let state = latestState, WCSession.isSupported() else { return }
        guard activationState == .activated else {
            Self.log.debug("deferred watch sync before activation: \(reason)")
            return
        }

        do {
            let data = try encoder.encode(state)
            let message: [String: Any] = ["state": data]
            try WCSession.default.updateApplicationContext(message)

            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil)
            }
        } catch {
            Self.log.error("watch sync failed: \(error.localizedDescription)")
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            if let error {
                Self.log.error("watch session activation failed: \(error.localizedDescription)")
            }
            self.flushLatestState(reason: "activation")
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.flushLatestState(reason: "reachability")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.flushLatestState(reason: "watch-state")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    private nonisolated func receive(_ message: [String: Any]) {
        guard let data = message["command"] as? Data else { return }

        Task { @MainActor in
            do {
                let command = try decoder.decode(CompanionCommandPayload.self, from: data)
                commandHandler?(command)
            } catch {
                // Ignore malformed watch commands.
            }
        }
    }
}
