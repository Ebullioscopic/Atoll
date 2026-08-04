import Combine
import Foundation
import MultipeerConnectivity
import os
import CodeIslandCore

@MainActor
final class AppleCompanionPublisher: NSObject, ObservableObject {
    static let shared = AppleCompanionPublisher()

    private static let serviceType = "codeisland"
    private static let log = Logger(subsystem: "com.codeisland", category: "apple-companion")

    @Published private(set) var enabled = false
    @Published private(set) var advertising = false
    @Published private(set) var connectedPeerNames: [String] = []
    @Published private(set) var lastError: String?

    var bluetoothPoweredOn: Bool { bluetooth.poweredOn }
    var bluetoothAdvertising: Bool { bluetooth.advertising }
    var bluetoothSubscribed: Bool { bluetooth.hasSubscribers }

    var onControlCommand: ((BuddyControlCommand) -> Void)?
    var onFocusRequest: ((MascotID) -> Void)?
    var onQuestionAnswer: ((String) -> Void)?

    private weak var appState: AppState?
    private let peerID: MCPeerID
    private lazy var session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    private lazy var advertiser = MCNearbyServiceAdvertiser(
        peer: peerID,
        discoveryInfo: ["protocol": "1"],
        serviceType: Self.serviceType
    )
    private var heartbeatTimer: Timer?
    private var sequence: UInt64 = 0
    private let bluetooth = AppleCompanionBluetoothPeripheral()

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

    private override init() {
        let hostName = Host.current().localizedName ?? "Mac"
        let displayName = "CodeIsland \(hostName)"
        self.peerID = MCPeerID(displayName: String(displayName.prefix(63)))
        super.init()
        self.session.delegate = self
        self.advertiser.delegate = self
    }

    func attach(_ appState: AppState) {
        self.appState = appState
    }

    func configure(enabled: Bool, heartbeatSeconds: Double) {
        self.enabled = enabled
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil

        guard enabled else {
            advertiser.stopAdvertisingPeer()
            bluetooth.configure(enabled: false)
            advertising = false
            connectedPeerNames = []
            session.disconnect()
            return
        }

        lastError = nil
        advertiser.startAdvertisingPeer()
        bluetooth.configure(enabled: true)
        advertising = true
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: max(1.0, heartbeatSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush(reason: "heartbeat")
            }
        }
        flush(reason: "enabled")
    }

    func notifyDirty() {
        flush(reason: "change")
    }

    func reconnect() {
        guard enabled else { return }
        advertiser.stopAdvertisingPeer()
        session.disconnect()
        connectedPeerNames = []
        advertiser.startAdvertisingPeer()
        advertising = true
        bluetooth.configure(enabled: true)
        flush(reason: "reconnect")
    }

    private func flush(reason: String) {
        guard enabled, let appState else { return }
        sequence &+= 1
        let payload = appState.appleCompanionStatePayload(sequence: sequence)

        bluetooth.publish(payload)

        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try encoder.encode(payload)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            Self.log.debug("push(\(reason)): seq=\(payload.sequence) source=\(payload.source) status=\(payload.status.rawValue) peers=\(self.session.connectedPeers.count)")
        } catch {
            lastError = error.localizedDescription
            Self.log.error("push failed: \(error.localizedDescription)")
        }
    }

    private func handleCommand(_ command: AppleCompanionCommandPayload) {
        switch command.type {
        case .requestCurrentState:
            flush(reason: "requested")
        case .approveCurrentPermission:
            onControlCommand?(.approveCurrentPermission)
        case .denyCurrentPermission:
            onControlCommand?(.denyCurrentPermission)
        case .skipCurrentQuestion:
            onControlCommand?(.skipCurrentQuestion)
        case .answerQuestion:
            if let answer = command.answer?.trimmingCharacters(in: .whitespacesAndNewlines),
               !answer.isEmpty {
                onQuestionAnswer?(answer)
            }
        case .focus:
            onFocusRequest?(MascotID(sourceName: command.source) ?? .claude)
        }
    }

    private func refreshConnectedPeers() {
        connectedPeerNames = session.connectedPeers.map(\.displayName).sorted()
    }
}

extension AppleCompanionPublisher: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            guard self.enabled else {
                invitationHandler(false, nil)
                return
            }
            Self.log.info("accepted invitation from \(peerID.displayName)")
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.advertising = false
            self.lastError = error.localizedDescription
            Self.log.error("advertising failed: \(error.localizedDescription)")
        }
    }
}

extension AppleCompanionPublisher: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            self.refreshConnectedPeers()
            if state == .connected {
                self.flush(reason: "peer-connected")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let command = try self.decoder.decode(AppleCompanionCommandPayload.self, from: data)
                self.handleCommand(command)
            } catch {
                self.lastError = "Ignored command from \(peerID.displayName): \(error.localizedDescription)"
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
