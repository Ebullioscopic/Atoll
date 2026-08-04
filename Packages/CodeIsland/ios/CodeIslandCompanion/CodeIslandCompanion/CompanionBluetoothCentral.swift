import Foundation
@preconcurrency import CoreBluetooth
import os

@MainActor
final class CompanionBluetoothCentral: NSObject, ObservableObject {
    private static let serviceUUID = CBUUID(string: "6D951BA3-8F41-4C45-9D8A-12085E0D7A10")
    private static let notifyCharacteristicUUID = CBUUID(string: "25C1B67B-E903-4A0C-8A78-3EE8AB7317B7")
    private static let restoreIdentifier = "top.fengye.CodeIslandCompanion.bluetooth-central"
    private static let log = Logger(subsystem: "top.fengye.CodeIslandCompanion", category: "bluetooth-central")

    @Published private(set) var scanning = false
    @Published private(set) var connectedPeripheralName: String?
    @Published private(set) var lastError: String?

    var onSummary: ((CompanionBluetoothSummary) -> Void)?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var notifyCharacteristic: CBCharacteristic?
    private var incoming: IncomingSequence?
    private var lastDeliveredSequence: UInt64 = 0
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }

    func start() {
        guard centralManager.state == .poweredOn else { return }
        startScanning()
    }

    func stop() {
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        scanning = false

        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }

        self.peripheral = nil
        notifyCharacteristic = nil
        connectedPeripheralName = nil
        incoming = nil
    }

    private func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        guard !centralManager.isScanning else {
            scanning = true
            return
        }

        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        scanning = true
        lastError = nil
    }

    private func connect(_ discoveredPeripheral: CBPeripheral, advertisedName: String?) {
        if peripheral?.identifier == discoveredPeripheral.identifier {
            return
        }

        peripheral = discoveredPeripheral
        discoveredPeripheral.delegate = self
        connectedPeripheralName = advertisedName ?? discoveredPeripheral.name ?? "CodeIsland Mac"
        centralManager.connect(
            discoveredPeripheral,
            options: [
                CBConnectPeripheralOptionNotifyOnConnectionKey: true,
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
            ]
        )
    }

    private func handleChunk(_ data: Data) {
        guard let chunk = CompanionBluetoothChunk(data: data) else { return }
        guard chunk.sequence >= lastDeliveredSequence else { return }

        if incoming?.sequence != chunk.sequence || incoming?.total != chunk.total {
            incoming = IncomingSequence(sequence: chunk.sequence, total: chunk.total)
        }

        incoming?.chunks[chunk.index] = chunk.body

        guard let incoming, incoming.isComplete else { return }
        let body = incoming.combined()
        self.incoming = nil

        do {
            let summary = try decoder.decode(CompanionBluetoothSummary.self, from: body)
            lastDeliveredSequence = summary.sequence
            lastError = nil
            onSummary?(summary)
        } catch {
            lastError = error.localizedDescription
            Self.log.error("failed to decode BLE summary: \(error.localizedDescription)")
        }
    }
}

extension CompanionBluetoothCentral: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.lastError = nil
                self.startScanning()
            case .poweredOff:
                self.scanning = false
                self.connectedPeripheralName = nil
                self.lastError = L10n.t(zh: "蓝牙已关闭", en: "Bluetooth is off")
            case .unauthorized:
                self.scanning = false
                self.connectedPeripheralName = nil
                self.lastError = L10n.t(zh: "蓝牙权限未授权", en: "Bluetooth permission denied")
            case .unsupported:
                self.scanning = false
                self.connectedPeripheralName = nil
                self.lastError = L10n.t(zh: "这台 iPhone 不支持蓝牙", en: "This iPhone doesn't support Bluetooth")
            case .resetting:
                self.scanning = false
                self.lastError = L10n.t(zh: "蓝牙正在重置", en: "Bluetooth is resetting")
            case .unknown:
                self.scanning = false
            @unknown default:
                self.scanning = false
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []

        Task { @MainActor in
            if let restoredPeripheral = restored.first {
                self.peripheral = restoredPeripheral
                restoredPeripheral.delegate = self
                self.connectedPeripheralName = restoredPeripheral.name ?? "CodeIsland Mac"
                restoredPeripheral.discoverServices([Self.serviceUUID])
            }

            if central.state == .poweredOn {
                self.startScanning()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        Task { @MainActor in
            self.connect(peripheral, advertisedName: name)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            if central.isScanning {
                central.stopScan()
            }
            self.scanning = false
            self.connectedPeripheralName = peripheral.name ?? self.connectedPeripheralName ?? "CodeIsland Mac"
            peripheral.discoverServices([Self.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription ?? L10n.t(zh: "无法连接 Mac 蓝牙摘要通道", en: "Couldn't connect to the Mac's Bluetooth summary channel")
            self.peripheral = nil
            self.notifyCharacteristic = nil
            self.connectedPeripheralName = nil
            self.startScanning()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription
            self.peripheral = nil
            self.notifyCharacteristic = nil
            self.connectedPeripheralName = nil
            self.incoming = nil
            self.startScanning()
        }
    }
}

extension CompanionBluetoothCentral: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
                self.lastError = L10n.t(zh: "没有找到 CodeIsland 蓝牙服务", en: "Couldn't find the CodeIsland Bluetooth service")
                return
            }

            peripheral.discoverCharacteristics([Self.notifyCharacteristicUUID], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.lastError = error.localizedDescription
                return
            }

            guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.notifyCharacteristicUUID }) else {
                self.lastError = L10n.t(zh: "没有找到 CodeIsland 蓝牙通知通道", en: "Couldn't find the CodeIsland Bluetooth notification channel")
                return
            }

            self.notifyCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else {
            let message = error?.localizedDescription
            Task { @MainActor in self.lastError = message }
            return
        }

        Task { @MainActor in
            self.handleChunk(data)
        }
    }
}

struct CompanionBluetoothSummary: Codable {
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
    let sessions: [SessionSummary]?
    let updatedAt: Date

    var statePayload: CompanionStatePayload {
        let status = CompanionStatus(rawValue: status) ?? .idle
        let pendingAction = pendingAction.flatMap(CompanionPendingAction.init(rawValue:))
        let messages = message.map {
            [CompanionMessagePreview(role: .assistant, text: $0)]
        } ?? []
        let question = questionText.map {
            CompanionQuestionPayload(
                header: questionHeader,
                question: $0,
                options: [],
                descriptions: [],
                index: 1,
                total: 1,
                allowsMultipleSelection: false
            )
        }
        let sessionPreviews = (sessions ?? []).map {
            CompanionSessionPreview(
                sessionId: $0.sessionId,
                source: $0.source,
                status: CompanionStatus(rawValue: $0.status) ?? .idle,
                toolName: $0.toolName,
                workspaceName: $0.workspaceName,
                message: $0.message,
                updatedAt: $0.updatedAt
            )
        }

        return CompanionStatePayload(
            version: version,
            sequence: sequence,
            sessionId: sessionId,
            source: source,
            status: status,
            toolName: toolName,
            workspaceName: workspaceName,
            messages: messages,
            pendingAction: pendingAction,
            question: question,
            sessions: sessionPreviews,
            updatedAt: updatedAt
        )
    }
}

private struct IncomingSequence {
    let sequence: UInt64
    let total: Int
    var chunks: [Int: Data] = [:]

    var isComplete: Bool {
        chunks.count == total
    }

    func combined() -> Data {
        var data = Data()
        for index in 0..<total {
            if let chunk = chunks[index] {
                data.append(chunk)
            }
        }
        return data
    }
}

private struct CompanionBluetoothChunk {
    let sequence: UInt64
    let index: Int
    let total: Int
    let body: Data

    init?(data: Data) {
        guard data.count >= 15 else { return nil }
        guard data[0] == 0x43, data[1] == 0x49, data[2] == 0x01 else { return nil }

        let sequence = data.readUInt64(at: 3)
        let index = Int(data.readUInt16(at: 11))
        let total = Int(data.readUInt16(at: 13))
        guard total > 0, total <= 64, index >= 0, index < total else { return nil }

        self.sequence = sequence
        self.index = index
        self.total = total
        self.body = data.subdata(in: 15..<data.count)
    }
}

private extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let value = (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
        return value
    }

    func readUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(self[offset + index])
        }
        return value
    }
}
