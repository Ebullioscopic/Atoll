import Combine
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var iconName: String {
        let normalizedName = name.lowercased()

        if normalizedName.contains("airpods") {
            return "airpodspro"
        }

        if normalizedName.contains("macbook") {
            return "laptopcomputer"
        }

        if normalizedName.contains("headphone") || normalizedName.contains("headset") {
            return "headphones"
        }

        if normalizedName.contains("beats") {
            return "headphones"
        }

        if normalizedName.contains("homepod") {
            return "hifispeaker.2"
        }

        switch transportType {
        case kAudioDeviceTransportTypeBluetooth:
            if normalizedName.contains("speaker") {
                return "speaker.wave.2"
            }
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "tv"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeFireWire:
            return "hifispeaker.2"
        case kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeVirtual:
            return "speaker.wave.2"
        case kAudioDeviceTransportTypeBuiltIn:
            return normalizedName.contains("display") ? "tv" : "speaker.wave.2"
        default:
            return "speaker.wave.2"
        }
    }
}

final class AudioRouteManager: ObservableObject {
    static let shared = AudioRouteManager()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = 0

    private let queue = DispatchQueue(label: "com.dynamicisland.audio-route", qos: .userInitiated)

    private init() {
        refreshDevices()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: .systemAudioRouteDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var activeDevice: AudioOutputDevice? {
        devices.first { $0.id == activeDeviceID }
    }

    func refreshDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            let defaultID = self.fetchDefaultOutputDevice()
            let deviceInfos = self.fetchOutputDeviceIDs().compactMap(self.makeDeviceInfo)
            let sortedDevices = deviceInfos.sorted { lhs, rhs in
                if lhs.id == defaultID { return true }
                if rhs.id == defaultID { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.activeDeviceID = defaultID
                self.devices = sortedDevices
            }
        }
    }

    func select(device: AudioOutputDevice) {
        queue.async { [weak self] in
            guard let self else { return }
            self.setDefaultOutputDevice(device.id)
        }
    }

    // MARK: - Private

    @objc private func handleRouteChange() {
        refreshDevices()
    }

    private func fetchOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        if status != noErr {
            return []
        }
        return deviceIDs
    }

    private func makeDeviceInfo(for deviceID: AudioDeviceID) -> AudioOutputDevice? {
        guard deviceHasOutputChannels(deviceID) else { return nil }
        let name = deviceName(for: deviceID) ?? "Unknown Device"
        let transport = transportType(for: deviceID)
        return AudioOutputDevice(id: deviceID, name: name, transportType: transport)
    }

    private func deviceHasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else {
            return false
        }

        let audioBufferListPointer = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferListPointer)
        let channelCount = audioBuffers.reduce(0) { $0 + Int($1.mNumberChannels) }
        return channelCount > 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name)
        guard status == noErr else { return nil }
        return name as String
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var type: UInt32 = kAudioDeviceTransportTypeUnknown
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &type)
        return status == noErr ? type : kAudioDeviceTransportTypeUnknown
    }

    private func fetchDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        return status == noErr ? deviceID : 0
    }

    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var target = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &target
        )
        if status == noErr {
            DispatchQueue.main.async { [weak self] in
                self?.activeDeviceID = deviceID
            }
            refreshDevices()
        }
    }
}
