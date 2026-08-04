import Foundation
@preconcurrency import CoreBluetooth
import os
import CodeIslandCore

@MainActor
final class AppleCompanionBluetoothPeripheral: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "6D951BA3-8F41-4C45-9D8A-12085E0D7A10")
    static let notifyCharacteristicUUID = CBUUID(string: "25C1B67B-E903-4A0C-8A78-3EE8AB7317B7")

    private static let log = Logger(subsystem: "com.codeisland", category: "apple-companion-ble")
    private static let maxChunkPayloadBytes = 120

    @Published private(set) var poweredOn = false
    @Published private(set) var advertising = false
    @Published private(set) var hasSubscribers = false
    @Published private(set) var lastError: String?

    /// Created on first ENABLE only. Instantiating CBPeripheralManager triggers
    /// the Bluetooth TCC authorization flow, so the disabled path must never
    /// touch it — users who never turn the iPhone companion on shouldn't get a
    /// Bluetooth permission prompt at launch.
    private var peripheralManager: CBPeripheralManager?
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var latestChunks: [Data] = []
    private var pendingChunks: [Data] = []
    private var enabled = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func configure(enabled: Bool) {
        self.enabled = enabled

        guard enabled else {
            peripheralManager?.stopAdvertising()
            peripheralManager?.removeAllServices()
            advertising = false
            hasSubscribers = false
            pendingChunks = []
            latestChunks = []
            return
        }

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        rebuildServiceIfReady()
    }

    func publish(_ payload: AppleCompanionStatePayload) {
        guard enabled else { return }

        do {
            let summary = AppleCompanionBluetoothSummary(payload: payload)
            let data = try encoder.encode(summary)
            latestChunks = Self.makeChunks(sequence: payload.sequence, data: data)
            lastError = nil

            if hasSubscribers {
                sendLatestChunks()
            }
        } catch {
            lastError = error.localizedDescription
            Self.log.error("failed to encode BLE summary: \(error.localizedDescription)")
        }
    }

    private func rebuildServiceIfReady() {
        guard enabled, let peripheralManager, peripheralManager.state == .poweredOn else { return }

        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()

        let characteristic = CBMutableCharacteristic(
            type: Self.notifyCharacteristicUUID,
            properties: [.notify],
            value: nil,
            permissions: []
        )
        let service = CBMutableService(type: Self.serviceUUID, primary: true)
        service.characteristics = [characteristic]
        notifyCharacteristic = characteristic
        peripheralManager.add(service)
    }

    private func startAdvertisingIfReady() {
        guard enabled, poweredOn, !advertising, let peripheralManager else { return }

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "CodeIsland"
        ])
        advertising = true
    }

    private func sendLatestChunks() {
        pendingChunks = latestChunks
        drainPendingChunks()
    }

    private func drainPendingChunks() {
        guard let notifyCharacteristic, hasSubscribers, let peripheralManager else { return }

        while !pendingChunks.isEmpty {
            let chunk = pendingChunks[0]
            guard peripheralManager.updateValue(chunk, for: notifyCharacteristic, onSubscribedCentrals: nil) else {
                return
            }
            pendingChunks.removeFirst()
        }
    }

    private static func makeChunks(sequence: UInt64, data: Data) -> [Data] {
        let chunkSize = maxChunkPayloadBytes
        let total = max(1, Int(ceil(Double(data.count) / Double(chunkSize))))

        return (0..<total).map { index in
            let start = index * chunkSize
            let end = min(start + chunkSize, data.count)
            let body = data.subdata(in: start..<end)

            var chunk = Data()
            chunk.append(0x43)
            chunk.append(0x49)
            chunk.append(0x01)
            chunk.appendUInt64(sequence)
            chunk.appendUInt16(UInt16(index))
            chunk.appendUInt16(UInt16(total))
            chunk.append(body)
            return chunk
        }
    }
}

extension AppleCompanionBluetoothPeripheral: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn:
                self.poweredOn = true
                self.lastError = nil
                self.rebuildServiceIfReady()
            case .poweredOff:
                self.poweredOn = false
                self.advertising = false
                self.hasSubscribers = false
                self.lastError = "蓝牙已关闭"
            case .unauthorized:
                self.poweredOn = false
                self.advertising = false
                self.lastError = "蓝牙权限未授权"
            case .unsupported:
                self.poweredOn = false
                self.advertising = false
                self.lastError = "这台 Mac 不支持蓝牙"
            case .resetting:
                self.poweredOn = false
                self.advertising = false
                self.lastError = "蓝牙正在重置"
            case .unknown:
                self.poweredOn = false
                self.advertising = false
            @unknown default:
                self.poweredOn = false
                self.advertising = false
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                Self.log.error("failed to add BLE service: \(error.localizedDescription)")
                return
            }

            self.startAdvertisingIfReady()
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let error {
                self.advertising = false
                self.lastError = error.localizedDescription
                Self.log.error("failed to advertise BLE service: \(error.localizedDescription)")
                return
            }

            self.advertising = true
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.hasSubscribers = true
            self.sendLatestChunks()
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        Task { @MainActor in
            self.hasSubscribers = false
            self.pendingChunks = []
        }
    }

    nonisolated func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        Task { @MainActor in
            self.drainPendingChunks()
        }
    }
}

private struct AppleCompanionBluetoothSummary: Codable {
    struct SessionSummary: Codable {
        let sessionId: String?
        let source: String
        let status: String
        let toolName: String?
        let workspaceName: String?
        let message: String?
        let updatedAt: Date
    }

    let version: Int
    let sequence: UInt64
    let sessionId: String?
    let source: String
    let status: String
    let toolName: String?
    let workspaceName: String?
    let message: String?
    let pendingAction: String?
    let questionHeader: String?
    let questionText: String?
    let sessions: [SessionSummary]
    let updatedAt: Date

    init(payload: AppleCompanionStatePayload) {
        version = 1
        sequence = payload.sequence
        sessionId = payload.sessionId.map { Self.truncate($0, limit: 96) }
        source = payload.source
        status = payload.status.rawValue
        toolName = payload.toolName.map { Self.truncate($0, limit: 64) }
        workspaceName = payload.workspaceName.map { Self.truncate($0, limit: 64) }
        message = payload.messages.last.map { Self.truncate($0.text, limit: 220) }
        pendingAction = payload.pendingAction?.rawValue
        questionHeader = payload.question?.header.map { Self.truncate($0, limit: 40) }
        questionText = payload.question.map { Self.truncate($0.question, limit: 180) }
        sessions = payload.sessions.prefix(5).map {
            SessionSummary(
                sessionId: $0.sessionId.map { Self.truncate($0, limit: 96) },
                source: $0.source,
                status: $0.status.rawValue,
                toolName: $0.toolName.map { Self.truncate($0, limit: 48) },
                workspaceName: $0.workspaceName.map { Self.truncate($0, limit: 48) },
                message: $0.message.map { Self.truncate($0, limit: 120) },
                updatedAt: $0.updatedAt
            )
        }
        updatedAt = payload.updatedAt
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(max(0, limit - 1))) + "…"
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
