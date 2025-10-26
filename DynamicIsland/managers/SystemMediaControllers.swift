import Foundation
import CoreAudio
import CoreGraphics
import IOKit

extension Notification.Name {
    static let systemVolumeDidChange = Notification.Name("DynamicIsland.systemVolumeDidChange")
    static let systemBrightnessDidChange = Notification.Name("DynamicIsland.systemBrightnessDidChange")
    static let systemAudioRouteDidChange = Notification.Name("DynamicIsland.systemAudioRouteDidChange")
}

final class HUDSuppressionCoordinator {
    static let shared = HUDSuppressionCoordinator()

    private let queue = DispatchQueue(label: "com.dynamicisland.hud-suppression")
    private var volumeSuppressedUntil: Date?

    func suppressVolumeHUD(for interval: TimeInterval) {
        guard interval > 0 else { return }
        queue.sync {
            let proposed = Date().addingTimeInterval(interval)
            if let current = volumeSuppressedUntil {
                volumeSuppressedUntil = max(current, proposed)
            } else {
                volumeSuppressedUntil = proposed
            }
        }
    }

    var shouldSuppressVolumeHUD: Bool {
        queue.sync {
            guard let expiration = volumeSuppressedUntil else {
                return false
            }
            if Date() < expiration {
                return true
            }
            volumeSuppressedUntil = nil
            return false
        }
    }
}

final class SystemVolumeController {
    static let shared = SystemVolumeController()

    var onVolumeChange: ((Float, Bool) -> Void)?
    var onRouteChange: (() -> Void)?

    private let callbackQueue = DispatchQueue(label: "com.dynamicisland.volume-listener")
    private var currentDeviceID: AudioDeviceID = 0
    private var listenersInstalled = false
    private var volumeElement: AudioObjectPropertyElement?
    private var muteElement: AudioObjectPropertyElement?

    private let candidateElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain,
        AudioObjectPropertyElement(1),
        AudioObjectPropertyElement(2)
    ]

    private init() {
        currentDeviceID = resolveDefaultDevice()
        refreshPropertyElements()
        installDefaultDeviceListener()
        installVolumeListeners(for: currentDeviceID)
        notifyCurrentState()
    }

    func start() {
        // Listeners are installed during init, nothing else required.
    }

    func stop() {
        // We keep listeners alive for the app lifetime; clearing closures prevents UI updates.
        onVolumeChange = nil
        onRouteChange = nil
    }

    func adjust(by delta: Float) {
        guard delta != 0 else { return }
        if isMuted {
            setMuted(false)
        }
        var newValue = currentVolume + delta
        newValue = max(0, min(1, newValue))
        setVolume(newValue)
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    var currentVolume: Float {
        getVolume()
    }

    var isMuted: Bool {
        getMuteState()
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        if isMuted && clamped > 0 {
            setMuted(false)
        }

        let elements = volumeElements()

        if elements.isEmpty {
            var volume = clamped
            let status = setData(selector: kAudioDevicePropertyVolumeScalar, data: &volume)
            if status != noErr {
                NSLog("⚠️ Failed to set volume: \(status)")
            }
        } else {
            for element in elements {
                var volume = clamped
                let status = setData(selector: kAudioDevicePropertyVolumeScalar, element: element, data: &volume)
                if status != noErr {
                    NSLog("⚠️ Failed to set volume for element \(element): \(status)")
                } else {
                    cache(element: element, for: kAudioDevicePropertyVolumeScalar)
                }
            }
        }
        notifyCurrentState()
    }

    func setMuted(_ muted: Bool) {
        var muteFlag: UInt32 = muted ? 1 : 0
        let elements = muteElements()

        if elements.isEmpty {
            let status = setData(selector: kAudioDevicePropertyMute, data: &muteFlag)
            if status != noErr {
                NSLog("⚠️ Failed to set mute state: \(status)")
            }
            return
        }

        for element in elements {
            var value = muteFlag
            let status = setData(selector: kAudioDevicePropertyMute, element: element, data: &value)
            if status != noErr {
                NSLog("⚠️ Failed to set mute state for element \(element): \(status)")
            } else {
                cache(element: element, for: kAudioDevicePropertyMute)
            }
        }
    }

    // MARK: - Private

    private func resolveDefaultDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout.size(ofValue: deviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        if status != noErr {
            NSLog("⚠️ Unable to fetch default audio device: \(status)")
        }
        return deviceID
    }

    private func installDefaultDeviceListener() {
        guard !listenersInstalled else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            callbackQueue
        ) { [weak self] _, _ in
            guard let self else { return }
            self.handleDefaultDeviceChanged()
        }
        if status != noErr {
            NSLog("⚠️ Failed to install default device listener: \(status)")
        }
        listenersInstalled = true
    }

    private func installVolumeListeners(for deviceID: AudioDeviceID) {
        if let element = resolveElement(selector: kAudioDevicePropertyVolumeScalar, deviceID: deviceID) {
            volumeElement = element
            var address = makeAddress(selector: kAudioDevicePropertyVolumeScalar, element: element)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue) { [weak self] _, _ in
                self?.notifyCurrentState()
            }
        }

        if let element = resolveElement(selector: kAudioDevicePropertyMute, deviceID: deviceID) {
            muteElement = element
            var address = makeAddress(selector: kAudioDevicePropertyMute, element: element)
            AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue) { [weak self] _, _ in
                self?.notifyCurrentState()
            }
        }
    }

    private func handleDefaultDeviceChanged() {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.currentDeviceID = self.resolveDefaultDevice()
            self.refreshPropertyElements()
            self.installVolumeListeners(for: self.currentDeviceID)
            self.notifyCurrentState()
            DispatchQueue.main.async {
                self.onRouteChange?()
                NotificationCenter.default.post(name: .systemAudioRouteDidChange, object: nil)
            }
        }
    }

    private func notifyCurrentState() {
        let volume = getVolume()
        let muted = getMuteState()
        DispatchQueue.main.async {
            self.onVolumeChange?(volume, muted)
            NotificationCenter.default.post(name: .systemVolumeDidChange, object: nil, userInfo: ["value": volume, "muted": muted])
        }
    }

    private func getVolume() -> Float {
        let elements = volumeElements()

        if elements.isEmpty {
            var volume = Float32(0)
            let status = getData(selector: kAudioDevicePropertyVolumeScalar, data: &volume)
            if status != noErr {
                NSLog("⚠️ Unable to fetch volume: \(status)")
            }
            return volume
        }

        var masterVolume: Float?
        var accumulator: Float = 0
        var count: Float = 0

        for element in elements {
            var value = Float32(0)
            let status = getData(selector: kAudioDevicePropertyVolumeScalar, element: element, data: &value)
            if status == noErr {
                if element == kAudioObjectPropertyElementMaster {
                    masterVolume = value
                }
                accumulator += value
                count += 1
            }
        }

        if let masterVolume {
            return masterVolume
        }

        if count > 0 {
            return accumulator / count
        }

        var fallback = Float32(0)
        let status = getData(selector: kAudioDevicePropertyVolumeScalar, data: &fallback)
        if status != noErr {
            NSLog("⚠️ Unable to fetch fallback volume: \(status)")
        }
        return fallback
    }

    private func getMuteState() -> Bool {
        let elements = muteElements()

        if elements.isEmpty {
            var mute: UInt32 = 0
            let status = getData(selector: kAudioDevicePropertyMute, data: &mute)
            if status != noErr {
                return false
            }
            return mute != 0
        }

        var retrieved = false
        var allMuted = true

        for element in elements {
            var value: UInt32 = 0
            let status = getData(selector: kAudioDevicePropertyMute, element: element, data: &value)
            if status == noErr {
                retrieved = true
                if value == 0 {
                    allMuted = false
                }
            }
        }

        if retrieved {
            return allMuted
        }

        var fallback: UInt32 = 0
        let status = getData(selector: kAudioDevicePropertyMute, data: &fallback)
        if status != noErr {
            return false
        }
        return fallback != 0
    }

    private func refreshPropertyElements() {
        volumeElement = resolveElement(selector: kAudioDevicePropertyVolumeScalar, deviceID: currentDeviceID)
        muteElement = resolveElement(selector: kAudioDevicePropertyMute, deviceID: currentDeviceID)
    }

    private func resolveElement(selector: AudioObjectPropertySelector, deviceID: AudioDeviceID) -> AudioObjectPropertyElement? {
        for element in candidateElements {
            var address = makeAddress(selector: selector, element: element)
            if propertyExists(deviceID: deviceID, address: &address) {
                return element
            }
        }
        return nil
    }

    private func preferredElements(for selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        if let cached = cachedElement(for: selector) {
            return [cached] + candidateElements.filter { $0 != cached }
        }
        return candidateElements
    }

    private func cachedElement(for selector: AudioObjectPropertySelector) -> AudioObjectPropertyElement? {
        switch selector {
        case kAudioDevicePropertyVolumeScalar:
            return volumeElement
        case kAudioDevicePropertyMute:
            return muteElement
        default:
            return nil
        }
    }

    private func cache(element: AudioObjectPropertyElement, for selector: AudioObjectPropertySelector) {
        switch selector {
        case kAudioDevicePropertyVolumeScalar:
            volumeElement = element
        case kAudioDevicePropertyMute:
            muteElement = element
        default:
            break
        }
    }

    private func makeAddress(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func propertyExists(deviceID: AudioDeviceID, address: inout AudioObjectPropertyAddress) -> Bool {
        withUnsafePointer(to: &address) { pointer in
            AudioObjectHasProperty(deviceID, pointer)
        }
    }

    private func getData<T>(selector: AudioObjectPropertySelector, data: inout T) -> OSStatus {
        var lastStatus: OSStatus = kAudioHardwareUnspecifiedError
        for element in preferredElements(for: selector) {
            var address = makeAddress(selector: selector, element: element)
            guard propertyExists(deviceID: currentDeviceID, address: &address) else { continue }
            var size = UInt32(MemoryLayout<T>.size)
            lastStatus = AudioObjectGetPropertyData(currentDeviceID, &address, 0, nil, &size, &data)
            if lastStatus == noErr {
                cache(element: element, for: selector)
                return lastStatus
            }
        }
        return lastStatus
    }

    private func setData<T>(selector: AudioObjectPropertySelector, data: inout T) -> OSStatus {
        var lastStatus: OSStatus = kAudioHardwareUnspecifiedError
        for element in preferredElements(for: selector) {
            var address = makeAddress(selector: selector, element: element)
            guard propertyExists(deviceID: currentDeviceID, address: &address) else { continue }
            let size = UInt32(MemoryLayout<T>.size)
            lastStatus = AudioObjectSetPropertyData(currentDeviceID, &address, 0, nil, size, &data)
            if lastStatus == noErr {
                cache(element: element, for: selector)
                return lastStatus
            }
        }
        return lastStatus
    }

    private func getData<T>(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, data: inout T) -> OSStatus {
        var address = makeAddress(selector: selector, element: element)
        guard propertyExists(deviceID: currentDeviceID, address: &address) else {
            return kAudioHardwareUnknownPropertyError
        }
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(currentDeviceID, &address, 0, nil, &size, &data)
    }

    private func setData<T>(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, data: inout T) -> OSStatus {
        var address = makeAddress(selector: selector, element: element)
        guard propertyExists(deviceID: currentDeviceID, address: &address) else {
            return kAudioHardwareUnknownPropertyError
        }
        let size = UInt32(MemoryLayout<T>.size)
        return AudioObjectSetPropertyData(currentDeviceID, &address, 0, nil, size, &data)
    }

    private func volumeElements() -> [AudioObjectPropertyElement] {
        candidateElements.filter { element in
            var address = makeAddress(selector: kAudioDevicePropertyVolumeScalar, element: element)
            return propertyExists(deviceID: currentDeviceID, address: &address)
        }
    }

    private func muteElements() -> [AudioObjectPropertyElement] {
        candidateElements.filter { element in
            var address = makeAddress(selector: kAudioDevicePropertyMute, element: element)
            return propertyExists(deviceID: currentDeviceID, address: &address)
        }
    }
}

final class SystemBrightnessController {
    static let shared = SystemBrightnessController()

    var onBrightnessChange: ((Float) -> Void)?

    private let notificationCenter = NotificationCenter.default
    private var observers: [NSObjectProtocol] = []
    private var notificationsInstalled = false
    private var displayID: CGDirectDisplayID = CGMainDisplayID()
    private var brightnessAnimationTimer: Timer?
    private var brightnessAnimationStart: Float = 0
    private var brightnessAnimationTarget: Float = 0
    private var brightnessAnimationStartDate: Date?
    private let brightnessAnimationDuration: TimeInterval = 0.18
    private let brightnessAnimationSteps = 10
    private var lastEmittedBrightness: Float = 0.5

    private init() {
        registerExternalNotifications()
        lastEmittedBrightness = currentBrightness
    }

    func start() {
        notifyCurrentBrightness()
    }

    func stop() {
        onBrightnessChange = nil
        brightnessAnimationTimer?.invalidate()
        brightnessAnimationTimer = nil
    }

    func adjust(by delta: Float) {
        setBrightness(currentBrightness + delta)
    }

    func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        DispatchQueue.main.async {
            self.beginBrightnessAnimation(to: clamped)
        }
    }

    var currentBrightness: Float {
        if let level = getBrightnessViaDisplayServices() {
            return level
        }
        guard let service = displayService() else { return 0.5 }
        var brightness: Float = 0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        IOObjectRelease(service)
        if result != kIOReturnSuccess {
            return 0.5
        }
        return brightness
    }

    private func notifyCurrentBrightness() {
        let brightness = currentBrightness
        emitBrightnessChange(value: brightness)
    }

    private func beginBrightnessAnimation(to target: Float) {
        brightnessAnimationTimer?.invalidate()

        let start = lastEmittedBrightness
        if abs(start - target) <= 0.0005 {
            applyBrightness(target)
            emitBrightnessChange(value: target)
            return
        }

        brightnessAnimationStart = start
        brightnessAnimationTarget = target
        brightnessAnimationStartDate = Date()

        let interval = brightnessAnimationDuration / Double(brightnessAnimationSteps)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { return }
            guard let startDate = self.brightnessAnimationStartDate else {
                timer.invalidate()
                self.brightnessAnimationTimer = nil
                return
            }
            let elapsed = Date().timeIntervalSince(startDate)
            let progress = min(elapsed / self.brightnessAnimationDuration, 1)
            let eased = self.ease(progress)
            let value = self.brightnessAnimationStart + (self.brightnessAnimationTarget - self.brightnessAnimationStart) * Float(eased)
            self.applyBrightness(value)
            self.emitBrightnessChange(value: value)
            if progress >= 1 {
                timer.invalidate()
                self.brightnessAnimationTimer = nil
            }
        }
        brightnessAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    private func applyBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        if setBrightnessViaDisplayServices(clamped) {
            return
        }
        guard let service = displayService() else { return }
        let status = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
        IOObjectRelease(service)
        if status != kIOReturnSuccess {
            NSLog("⚠️ Failed to set brightness via IODisplay: \(status)")
        }
    }

    private func emitBrightnessChange(value: Float) {
        let clamped = max(0, min(1, value))
        lastEmittedBrightness = clamped
        let dispatchBlock = {
            self.onBrightnessChange?(clamped)
            self.notificationCenter.post(name: .systemBrightnessDidChange, object: nil, userInfo: ["value": clamped])
        }
        if Thread.isMainThread {
            dispatchBlock()
        } else {
            DispatchQueue.main.async(execute: dispatchBlock)
        }
    }

    private func ease(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    private func displayService() -> io_service_t? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        let service = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        return service
    }

    private func setBrightnessViaDisplayServices(_ value: Float) -> Bool {
        let status = DisplayServicesSetBrightness(displayID, value)
        if status == kIOReturnSuccess {
            return true
        }
        // Attempt to refresh display ID in case the main display changed
        displayID = CGMainDisplayID()
        let retry = DisplayServicesSetBrightness(displayID, value)
        if retry != kIOReturnSuccess {
            NSLog("⚠️ DisplayServicesSetBrightness failed: \(retry)")
            return false
        }
        return true
    }

    private func getBrightnessViaDisplayServices() -> Float? {
        var brightness: Float = 0
        let status = DisplayServicesGetBrightness(displayID, &brightness)
        if status == kIOReturnSuccess {
            return brightness
        }
        displayID = CGMainDisplayID()
        let retry = DisplayServicesGetBrightness(displayID, &brightness)
        if retry == kIOReturnSuccess {
            return brightness
        }
        NSLog("⚠️ DisplayServicesGetBrightness failed: \(retry)")
        return nil
    }

    private func registerExternalNotifications() {
        guard !notificationsInstalled else { return }
        let names = [
            Notification.Name("com.apple.BezelEngine.BrightnessChanged"),
            Notification.Name("com.apple.BezelServices.BrightnessChanged"),
            Notification.Name("com.apple.controlcenter.display.brightness")
        ]
        observers = names.map { name in
            DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.notifyCurrentBrightness()
            }
        }
        notificationsInstalled = true
    }

    deinit {
        brightnessAnimationTimer?.invalidate()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}

@_silgen_name("DisplayServicesGetBrightness")
private func DisplayServicesGetBrightness(_ display: UInt32, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
private func DisplayServicesSetBrightness(_ display: UInt32, _ brightness: Float) -> Int32
