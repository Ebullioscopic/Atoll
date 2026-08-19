/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Combine
import CoreAudio
import CoreGraphics
import Foundation
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
    /// Guards the three fields below. They are written from `callbackQueue` when the
    /// default device changes, and read synchronously by the public API (setVolume,
    /// getVolume, setMuted, …) on whatever thread the caller is on. The computed
    /// accessors keep every existing call site unchanged.
    private let deviceStateLock = NSLock()
    private var _currentDeviceID: AudioDeviceID = 0
    private var _volumeElement: AudioObjectPropertyElement?
    private var _muteElement: AudioObjectPropertyElement?

    private var currentDeviceID: AudioDeviceID {
        get { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; return _currentDeviceID }
        set { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; _currentDeviceID = newValue }
    }

    private var volumeElement: AudioObjectPropertyElement? {
        get { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; return _volumeElement }
        set { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; _volumeElement = newValue }
    }

    private var muteElement: AudioObjectPropertyElement? {
        get { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; return _muteElement }
        set { deviceStateLock.lock(); defer { deviceStateLock.unlock() }; _muteElement = newValue }
    }

    private var listenersInstalled = false
    private var volumeListenerRegistrations: [VolumeListenerRegistration] = []
    private let silenceThreshold: Float = 0.001 // Treat very low values as mute requests.

    private struct VolumeListenerRegistration {
        let deviceID: AudioDeviceID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

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
        let currentlyMuted = isMuted

        if clamped <= silenceThreshold {
            if !currentlyMuted {
                setMuted(true)
            }
        } else if currentlyMuted {
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
        // Remove any previously registered listeners (e.g. from a prior output
        // device) before re-installing, otherwise the old HAL listeners leak and
        // deliver duplicate notifications on every route change.
        removeVolumeListeners()

        if let element = resolveElement(selector: kAudioDevicePropertyVolumeScalar, deviceID: deviceID) {
            volumeElement = element
            addVolumeListener(selector: kAudioDevicePropertyVolumeScalar, element: element, deviceID: deviceID)
        }

        if let element = resolveElement(selector: kAudioDevicePropertyMute, deviceID: deviceID) {
            muteElement = element
            addVolumeListener(selector: kAudioDevicePropertyMute, element: element, deviceID: deviceID)
        }
    }

    private func addVolumeListener(selector: AudioObjectPropertySelector, element: AudioObjectPropertyElement, deviceID: AudioDeviceID) {
        var address = makeAddress(selector: selector, element: element)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.notifyCurrentState()
        }
        let status = AudioObjectAddPropertyListenerBlock(deviceID, &address, callbackQueue, block)
        if status == noErr {
            volumeListenerRegistrations.append(VolumeListenerRegistration(deviceID: deviceID, address: address, block: block))
        } else {
            NSLog("⚠️ Failed to install volume/mute listener for selector \(selector): \(status)")
        }
    }

    private func removeVolumeListeners() {
        for var registration in volumeListenerRegistrations {
            let status = AudioObjectRemovePropertyListenerBlock(
                registration.deviceID,
                &registration.address,
                callbackQueue,
                registration.block
            )
            if status != noErr {
                NSLog("⚠️ Failed to remove volume/mute listener: \(status)")
            }
        }
        volumeListenerRegistrations.removeAll()
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

    // Computed on each access rather than cached: these are called synchronously
    // from the public API on arbitrary threads while `refreshPropertyElements()`
    // runs on `callbackQueue`, so a shared cache would race. The probe is cheap.
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
    private var currentBrightnessAnimationDuration: TimeInterval = 0.18
    private let brightnessAnimationSteps = 10
    private let minimumBrightnessAnimationDuration: TimeInterval = 0.08
    private let maximumBrightnessAnimationDuration: TimeInterval = 0.3
    private let brightnessAnimationDurationScale: TimeInterval = 1.6
    private var lastEmittedBrightness: Float = 0.5
    private var pendingAdjustTarget: Float?
    private let coreBrightnessClient = CoreBrightnessDisplayClient.shared
    private var pollTimer: Timer?
    /// The energy gate, mirrored into a plain Bool. The tick used to read it via
    /// `MainActor.assumeIsolated`, which traps if the timer was ever scheduled off
    /// the main thread — `Timer` fires on the run loop it was scheduled on, so that
    /// safety depended on a startup detail rather than on anything enforced here.
    private var backgroundWorkSuspended = false
    private var gateCancellable: AnyCancellable?
    // Fast, self-terminating poll used only inside the user-initiated window
    // (after a brightness key press) to capture the settled value.
    private let pollInterval: TimeInterval = 0.15
    // Slower continuous poll used only as a fallback when CoreBrightness
    // notifications are unavailable. Gated by ActivityGate per tick.
    private let fallbackPollInterval: TimeInterval = 0.5
    private var continuousFallbackPolling = false
    private let pollChangeThreshold: Float = 0.005

    // MARK: - User-initiated brightness gate
    // When true, brightness changes detected via polling / notifications will
    // trigger the HUD. Auto-resets after `userInitiatedWindow` seconds.
    private var userInitiatedBrightnessChange = false
    private var userInitiatedResetTimer: Timer?
    private let userInitiatedWindow: TimeInterval = 1.5
    private var didLogPollingFallback = false

    // MARK: - Emission throttling
    // Prevent notification storms when the animation timer fires rapidly.
    private var lastEmissionDate: Date = .distantPast
    private let minimumEmissionInterval: TimeInterval = 0.04  // ~25 fps max

    private init() {
        registerExternalNotifications()
        lastEmittedBrightness = currentBrightness
    }

    func start() {
        if coreBrightnessClient.isAvailable {
            NSLog("✅ SystemBrightnessController: CoreBrightnessDisplayClient is available — using notification-driven detection")
        } else {
            NSLog("⚠️ SystemBrightnessController: CoreBrightnessDisplayClient unavailable; will rely on DisplayServices / IODisplay + polling fallback")
        }
        notifyCurrentBrightness()
        // Only start continuous polling as a fallback when CoreBrightness
        // notifications are unavailable.  When CoreBrightness IS available the
        // distributed notifications (registerExternalNotifications) handle
        // detection and we stay fully event-driven — a short windowed poll is
        // started on demand from markUserInitiated() after a key press.
        if !coreBrightnessClient.isAvailable {
            continuousFallbackPolling = true
            startPolling(interval: fallbackPollInterval)
        }
    }

    func stop() {
        onBrightnessChange = nil
        brightnessAnimationTimer?.invalidate()
        brightnessAnimationTimer = nil
        pollTimer?.invalidate()
        pollTimer = nil
        gateCancellable?.cancel()
        gateCancellable = nil
        userInitiatedResetTimer?.invalidate()
        userInitiatedResetTimer = nil
        userInitiatedBrightnessChange = false
        continuousFallbackPolling = false
        pendingAdjustTarget = nil
    }

    func adjust(by delta: Float) {
        markUserInitiated()

        // Do not synchronously query CoreBrightness/DisplayServices here. This
        // method is reached from hardware-key handling, and those calls can be
        // slow enough for macOS to disable the event tap. beginBrightnessAnimation
        // still refreshes the system baseline after the tap callback has returned.
        let inFlightTarget = brightnessAnimationTimer == nil ? nil : brightnessAnimationTarget
        let base = pendingAdjustTarget ?? inFlightTarget ?? lastEmittedBrightness
        pendingAdjustTarget = max(0, min(1, base + delta))

        DispatchQueue.main.async { [weak self] in
            guard let self, let target = self.pendingAdjustTarget else { return }
            self.pendingAdjustTarget = nil
            self.beginBrightnessAnimation(to: target)
        }
    }

    func setBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        markUserInitiated()
        DispatchQueue.main.async { [weak self] in
            self?.beginBrightnessAnimation(to: clamped)
        }
    }

    // MARK: - User-initiated helpers

    /// Marks the current brightness change as user-initiated (key press).
    /// Automatically resets after `userInitiatedWindow` seconds.
    private func markUserInitiated() {
        userInitiatedBrightnessChange = true
        // In the event-driven (CoreBrightness) path we normally never poll.
        // Run a short, self-terminating poll during the user window so the
        // brightness the display settles on is still captured for the HUD,
        // then stop again. The continuous fallback poll (if active) is left
        // untouched.
        if !continuousFallbackPolling {
            startPolling(interval: pollInterval)
        }
        userInitiatedResetTimer?.invalidate()
        userInitiatedResetTimer = Timer.scheduledTimer(withTimeInterval: userInitiatedWindow, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.userInitiatedBrightnessChange = false
            // Tear down the windowed poll; keep the continuous fallback running.
            if !self.continuousFallbackPolling {
                self.pollTimer?.invalidate()
                self.pollTimer = nil
                self.gateCancellable?.cancel()
                self.gateCancellable = nil
            }
        }
    }

    var currentBrightness: Float {
        if let level = coreBrightnessClient.currentBrightness() {
            return level
        }
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

    private func syncWithSystemBrightnessIfNeeded() {
        // Align our internal baseline with the actual system brightness so that
        // subsequent adjustments apply deltas from the true value (important when
        // auto-brightness has changed the level behind our back).
        let systemLevel = currentBrightness
        if abs(systemLevel - lastEmittedBrightness) > 0.001 {
            // Only update the baseline — don't emit to avoid spurious HUD flashes.
            lastEmittedBrightness = systemLevel
        }
    }

    private func beginBrightnessAnimation(to target: Float) {
        brightnessAnimationTimer?.invalidate()

        // Refresh baseline from system in case auto-brightness adjusted it.
        syncWithSystemBrightnessIfNeeded()

        let start = lastEmittedBrightness
        if abs(start - target) <= 0.0005 {
            applyBrightness(target)
            emitBrightnessChange(value: target)
            return
        }

        brightnessAnimationStart = start
        brightnessAnimationTarget = target
        brightnessAnimationStartDate = Date()
        currentBrightnessAnimationDuration = animationDuration(forDelta: abs(target - start))

        let interval = currentBrightnessAnimationDuration / Double(brightnessAnimationSteps)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard let startDate = self.brightnessAnimationStartDate else {
                timer.invalidate()
                self.brightnessAnimationTimer = nil
                return
            }
            let elapsed = Date().timeIntervalSince(startDate)
            let progress = min(elapsed / self.currentBrightnessAnimationDuration, 1)
            let eased = self.ease(progress)
            let value = self.brightnessAnimationStart + (self.brightnessAnimationTarget - self.brightnessAnimationStart) * Float(eased)
            self.applyBrightness(value)
            if progress >= 1 {
                // Final value — force-emit to guarantee the UI reaches the target.
                self.emitBrightnessChange(value: value, force: true)
                timer.invalidate()
                self.brightnessAnimationTimer = nil
            } else {
                // Intermediate step — throttled emission.
                self.emitBrightnessChange(value: value)
            }
        }
        brightnessAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    private func animationDuration(forDelta delta: Float) -> TimeInterval {
        let scaled = minimumBrightnessAnimationDuration + TimeInterval(delta) * brightnessAnimationDurationScale
        return min(maximumBrightnessAnimationDuration, max(minimumBrightnessAnimationDuration, scaled))
    }

    private func applyBrightness(_ value: Float) {
        let clamped = max(0, min(1, value))
        if coreBrightnessClient.setBrightness(clamped) {
            return
        }
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

    private func emitBrightnessChange(value: Float, force: Bool = false) {
        let clamped = max(0, min(1, value))
        lastEmittedBrightness = clamped

        // Throttle rapid emissions to avoid notification storms when the
        // animation timer fires ~10 times per step during key-spam.
        if !force {
            let now = Date()
            guard now.timeIntervalSince(lastEmissionDate) >= minimumEmissionInterval else { return }
            lastEmissionDate = now
        }

        let dispatchBlock = { [weak self] in
            guard let self else { return }
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
        guard let status = DisplayServicesDynamic.shared.setBrightness(displayID: displayID, value: value) else {
            return false
        }
        if status == kIOReturnSuccess {
            return true
        }
        // Attempt to refresh display ID in case the main display changed
        displayID = CGMainDisplayID()
        guard let retry = DisplayServicesDynamic.shared.setBrightness(displayID: displayID, value: value) else {
            NSLog("⚠️ DisplayServicesSetBrightness unavailable after display refresh")
            return false
        }
        if retry != kIOReturnSuccess {
            NSLog("⚠️ DisplayServicesSetBrightness failed: \(retry)")
            return false
        }
        return true
    }

    private func getBrightnessViaDisplayServices() -> Float? {
        guard let result = DisplayServicesDynamic.shared.getBrightness(displayID: displayID) else {
            return nil
        }
        if result.status == kIOReturnSuccess {
            return result.value
        }
        displayID = CGMainDisplayID()
        guard let retry = DisplayServicesDynamic.shared.getBrightness(displayID: displayID) else {
            NSLog("⚠️ DisplayServicesGetBrightness unavailable after display refresh")
            return nil
        }
        if retry.status == kIOReturnSuccess {
            return retry.value
        }
        NSLog("⚠️ DisplayServicesGetBrightness failed: \(retry.status)")
        return nil
    }

    private func registerExternalNotifications() {
        guard !notificationsInstalled else { return }
        let names = [
            Notification.Name("com.apple.BezelEngine.BrightnessChanged"),
            Notification.Name("com.apple.BezelServices.BrightnessChanged"),
            Notification.Name("com.apple.controlcenter.display.brightness"),
            Notification.Name("com.apple.CoreBrightness.DisplayBrightnessChanged")
        ]
        observers = names.map { name in
            DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                // Always keep our baseline in sync with the actual system brightness
                // so that subsequent key-press deltas are accurate, but only fire the
                // HUD callback when the change was user-initiated (key press).
                let system = self.currentBrightness
                if self.userInitiatedBrightnessChange {
                    self.notifyCurrentBrightness()
                } else {
                    // Silently absorb auto-brightness change — update baseline only.
                    self.lastEmittedBrightness = max(0, min(1, system))
                }
            }
        }
        notificationsInstalled = true
    }

    private func startPolling(interval: TimeInterval) {
        guard pollTimer == nil else { return }
        NSLog("ℹ️ SystemBrightnessController: Starting %@ brightness polling (interval: %.2fs)",
              continuousFallbackPolling ? "fallback" : "windowed", interval)
        // The gate's published projection is @MainActor, so subscribe from there.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.gateCancellable = ActivityGate.shared.$shouldSuspendBackgroundWork
                .sink { [weak self] suspended in self?.backgroundWorkSuspended = suspended }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Energy gate: skip ticks while the screen/system is asleep.
            if self.backgroundWorkSuspended { return }
            // Skip polling while an animation is actively running — the
            // animation timer already handles emission during key presses.
            guard self.brightnessAnimationTimer == nil else { return }
            let system = self.currentBrightness
            guard abs(system - self.lastEmittedBrightness) > self.pollChangeThreshold else { return }

            if self.userInitiatedBrightnessChange {
                // User recently pressed a brightness key — show the HUD.
                if !self.didLogPollingFallback {
                    NSLog("ℹ️ SystemBrightnessController: Brightness change detected via polling (value: %.3f)", system)
                    self.didLogPollingFallback = true
                }
                self.emitBrightnessChange(value: system)
            } else {
                // Auto-brightness or external change — absorb silently.
                self.lastEmittedBrightness = max(0, min(1, system))
            }
        }
        timer.tolerance = interval * 0.2
        pollTimer = timer
    }

    deinit {
        brightnessAnimationTimer?.invalidate()
        gateCancellable?.cancel()
        pollTimer?.invalidate()
        userInitiatedResetTimer?.invalidate()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}
