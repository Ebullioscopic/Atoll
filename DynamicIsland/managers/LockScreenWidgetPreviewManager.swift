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

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class LockScreenWidgetPreviewManager: ObservableObject {
    static let shared = LockScreenWidgetPreviewManager()

    @Published private(set) var isPreviewVisible = false

    private var cancellables = Set<AnyCancellable>()
    private var startedDemoTimer = false
    private var previewWindow: NSWindow?
    private var previewWindowDelegate: PreviewWindowDelegate?
    private var previewHostingView: NSHostingView<LockScreenPreviewScene>?
    private var cachedFocusState: FocusPreviewState?

    private init() {
        observeDefaults()
    }

    func togglePreview() {
        if isPreviewVisible {
            hidePreview()
        } else {
            showPreview()
        }
    }

    func showPreview() {
        guard !isPreviewVisible else { return }
        isPreviewVisible = true
        ensurePreviewWindow()
        applyPreviewState()
        renderPreview()
    }

    func hidePreview() {
        guard isPreviewVisible else { return }
        isPreviewVisible = false
        hideAllWidgets()
        restorePreviewState()
        closePreviewWindow()
    }

    private func renderPreview() {
        guard isPreviewVisible else { return }

        ensurePreviewWindow()

        if Defaults[.enableLockScreenTimerWidget] {
            ensureDemoTimerIfNeeded()
        } else {
            stopDemoTimerIfNeeded()
        }

        updatePreviewContent()
    }

    private func hideAllWidgets() {
        stopDemoTimerIfNeeded()
    }

    private func ensureDemoTimerIfNeeded() {
        let timerManager = TimerManager.shared
        guard !timerManager.isTimerActive else { return }
        timerManager.startDemoTimer(duration: 1783)
        startedDemoTimer = true
    }

    private func stopDemoTimerIfNeeded() {
        guard startedDemoTimer else { return }
        TimerManager.shared.forceStopTimer()
        startedDemoTimer = false
    }

    private func observeDefaults() {
        observeKey(.enableLockScreenMediaWidget)
        observeKey(.enableLockScreenWeatherWidget)
        observeKey(.enableLockScreenTimerWidget)
        observeKey(.lockScreenWeatherWidgetStyle)
        observeKey(.lockScreenBatteryWidgetStyle)
        observeKey(.lockScreenWeatherProviderSource)
        observeKey(.lockScreenWeatherTemperatureUnit)
        observeKey(.lockScreenWeatherShowsLocation)
        observeKey(.lockScreenWeatherShowsSunrise)
        observeKey(.lockScreenWeatherShowsAQI)
        observeKey(.lockScreenWeatherAQIScale)
        observeKey(.lockScreenBatteryShowsCharging)
        observeKey(.lockScreenBatteryShowsChargingPercentage)
        observeKey(.lockScreenBatteryShowsBatteryGauge)
        observeKey(.lockScreenBatteryShowsBluetooth)
        observeKey(.lockScreenBatteryUsesLaptopSymbol)
        observeKey(.lockScreenWeatherUsesGaugeTint)
    }

    private func observeKey<T: Defaults.Serializable>(_ key: Defaults.Key<T>) {
        Defaults.publisher(key, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.renderPreview()
            }
            .store(in: &cancellables)
    }

    private func mockWeatherSnapshot() -> LockScreenWeatherSnapshot {
        let unit = Defaults[.lockScreenWeatherTemperatureUnit]
        let temperatureValue: Double = unit == .celsius ? 21 : 72
        let temperatureText = "\(Int(round(temperatureValue)))°"
        let temperatureInfo = LockScreenWeatherSnapshot.TemperatureInfo(
            current: temperatureValue,
            minimum: temperatureValue - 5,
            maximum: temperatureValue + 6,
            unitSymbol: unit.symbol
        )

        let chargingInfo: LockScreenWeatherSnapshot.ChargingInfo? = Defaults[.lockScreenBatteryShowsCharging]
            ? LockScreenWeatherSnapshot.ChargingInfo(
                minutesRemaining: 42,
                isCharging: true,
                isPluggedIn: true,
                batteryLevel: 78
            )
            : nil

        let bluetoothInfo: LockScreenWeatherSnapshot.BluetoothInfo? = Defaults[.lockScreenBatteryShowsBluetooth]
            ? LockScreenWeatherSnapshot.BluetoothInfo(
                deviceName: "AirPods Pro",
                batteryLevel: 74,
                iconName: "airpodspro"
            )
            : nil

        let batteryInfo: LockScreenWeatherSnapshot.BatteryInfo? = Defaults[.lockScreenBatteryShowsBatteryGauge]
            ? LockScreenWeatherSnapshot.BatteryInfo(
                batteryLevel: 63,
                usesLaptopSymbol: Defaults[.lockScreenBatteryUsesLaptopSymbol]
            )
            : nil

        let widgetStyle = Defaults[.lockScreenWeatherWidgetStyle]
        let showLocation = widgetStyle == .inline && Defaults[.lockScreenWeatherShowsLocation]
        let providerSource = Defaults[.lockScreenWeatherProviderSource]
        let showsAQI = Defaults[.lockScreenWeatherShowsAQI] && providerSource.supportsAirQuality
        let scale = Defaults[.lockScreenWeatherAQIScale]
        let airQualityIndex = scale == .us ? 42 : 28
        let airQuality = showsAQI
            ? LockScreenWeatherSnapshot.AirQualityInfo(
                index: airQualityIndex,
                category: .init(index: airQualityIndex, scale: scale),
                scale: scale
            )
            : nil

        let showsSunrise = Defaults[.lockScreenWeatherShowsSunrise] && widgetStyle == .inline
        let sunCycle = LockScreenWeatherSnapshot.SunCycleInfo(
            sunrise: Date().addingTimeInterval(2 * 3600),
            sunset: Date().addingTimeInterval(9 * 3600)
        )

        return LockScreenWeatherSnapshot(
            temperatureText: temperatureText,
            symbolName: "cloud.sun.fill",
            description: "Partly Cloudy",
            locationName: "Cupertino",
            charging: chargingInfo,
            bluetooth: bluetoothInfo,
            battery: batteryInfo,
            showsLocation: showLocation,
            airQuality: airQuality,
            widgetStyle: widgetStyle,
            batteryWidgetStyle: Defaults[.lockScreenBatteryWidgetStyle],
            showsChargingPercentage: Defaults[.lockScreenBatteryShowsChargingPercentage],
            temperatureInfo: temperatureInfo,
            usesGaugeTint: Defaults[.lockScreenWeatherUsesGaugeTint],
            sunCycle: sunCycle,
            showsSunrise: showsSunrise
        )
    }

    private func ensurePreviewWindow() {
        guard let screen = NSScreen.main else { return }

        if let window = previewWindow {
            window.makeKeyAndOrderFront(nil)
            updatePreviewContent()
            return
        }

        let frame = screen.frame
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Lock Screen Preview"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.center()

        let scene = LockScreenPreviewScene(
            screenSize: screen.frame.size,
            weatherSnapshot: mockWeatherSnapshot(),
            showsWeather: Defaults[.enableLockScreenWeatherWidget],
            showsTimer: Defaults[.enableLockScreenTimerWidget],
            showsMediaPanel: Defaults[.enableLockScreenMediaWidget]
        )
        let hosting = NSHostingView(rootView: scene)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        previewHostingView = hosting
        window.contentView = hosting

        let delegate = PreviewWindowDelegate { [weak self] in
            self?.hidePreview()
        }
        previewWindowDelegate = delegate
        window.delegate = delegate

        previewWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func updatePreviewContent() {
        guard let screen = NSScreen.main else { return }
        let scene = LockScreenPreviewScene(
            screenSize: screen.frame.size,
            weatherSnapshot: mockWeatherSnapshot(),
            showsWeather: Defaults[.enableLockScreenWeatherWidget],
            showsTimer: Defaults[.enableLockScreenTimerWidget],
            showsMediaPanel: Defaults[.enableLockScreenMediaWidget]
        )

        if let hosting = previewHostingView {
            hosting.rootView = scene
        } else if let window = previewWindow {
            let hosting = NSHostingView(rootView: scene)
            hosting.frame = NSRect(origin: .zero, size: window.frame.size)
            hosting.autoresizingMask = [.width, .height]
            previewHostingView = hosting
            window.contentView = hosting
        }
    }

    private func closePreviewWindow() {
        previewWindow?.orderOut(nil)
    }

    private func applyPreviewState() {
        applyFocusPreviewState()
    }

    private func restorePreviewState() {
        restoreFocusPreviewState()
    }

    private func applyFocusPreviewState() {
        let manager = DoNotDisturbManager.shared
        if cachedFocusState == nil {
            cachedFocusState = FocusPreviewState(
                isActive: manager.isDoNotDisturbActive,
                name: manager.currentFocusModeName,
                identifier: manager.currentFocusModeIdentifier
            )
        }
        manager.isDoNotDisturbActive = true
        manager.currentFocusModeName = "Do Not Disturb"
        manager.currentFocusModeIdentifier = "com.apple.donotdisturb"
    }

    private func restoreFocusPreviewState() {
        guard let cachedFocusState else { return }
        let manager = DoNotDisturbManager.shared
        manager.isDoNotDisturbActive = cachedFocusState.isActive
        manager.currentFocusModeName = cachedFocusState.name
        manager.currentFocusModeIdentifier = cachedFocusState.identifier
        self.cachedFocusState = nil
    }

}

private struct FocusPreviewState {
    let isActive: Bool
    let name: String
    let identifier: String
}

private final class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct LockScreenPreviewScene: View {
    let screenSize: CGSize
    let weatherSnapshot: LockScreenWeatherSnapshot
    let showsWeather: Bool
    let showsTimer: Bool
    let showsMediaPanel: Bool

    @State private var weatherSize: CGSize = .zero
    @State private var musicSize: CGSize = .zero
    @State private var inlineBaselineHeight: CGFloat = 0
    @StateObject private var panelAnimator = LockScreenPanelAnimator()

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / screenSize.width, proxy.size.height / screenSize.height)
            let contentSize = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)
            let origin = CGPoint(
                x: (proxy.size.width - contentSize.width) / 2,
                y: (proxy.size.height - contentSize.height) / 2
            )

            ZStack(alignment: .topLeading) {
                WallpaperView()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                ZStack(alignment: .topLeading) {
                    if showsMediaPanel {
                        LockScreenMusicPanel(animator: panelAnimator)
                            .fixedSize()
                            .background(PreviewSizeReader(size: $musicSize))
                            .position(centerPoint(for: swiftUIFrame(for: mediaFrame)))
                            .onAppear {
                                panelAnimator.isPresented = true
                            }
                    }

                    if showsTimer {
                        LockScreenTimerWidget()
                            .frame(width: timerFrame.width, height: timerFrame.height)
                            .position(centerPoint(for: swiftUIFrame(for: timerFrame)))
                    }

                    if showsWeather {
                        LockScreenWeatherWidget(snapshot: weatherSnapshot)
                            .fixedSize()
                            .background(PreviewSizeReader(size: $weatherSize))
                            .position(centerPoint(for: swiftUIFrame(for: weatherFrame)))
                            .onChange(of: weatherSize) { _, newSize in
                                if weatherSnapshot.widgetStyle == .inline {
                                    inlineBaselineHeight = max(inlineBaselineHeight, newSize.height)
                                }
                            }
                    }
                }
                .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: origin.x, y: origin.y)
            }
        }
        .ignoresSafeArea()
    }

    private var mediaFrame: CGRect {
        let size = musicSize == .zero ? LockScreenMusicPanel.collapsedSize : musicSize
        let screenFrame = CGRect(origin: .zero, size: screenSize)
        let originX = screenFrame.midX - (size.width / 2)
        let baseOriginY = screenFrame.origin.y + (screenFrame.height / 2) - size.height - 32
        let defaultLowering: CGFloat = -28
        let userOffset = CGFloat(Defaults[.lockScreenMusicVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        var originY = baseOriginY + defaultLowering + clampedOffset

        if showsTimer {
            let maxAllowedTop = timerFrame.minY - 12
            let maxOriginY = maxAllowedTop - size.height
            originY = min(originY, maxOriginY)
        }

        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private var timerFrame: CGRect {
        let size = LockScreenTimerWidget.preferredSize
        let screenFrame = CGRect(origin: .zero, size: screenSize)
        let originX = screenFrame.midX - (size.width / 2)
        let defaultLowering: CGFloat = -18
        let baseY = screenFrame.midY + 24 + defaultLowering

        let offset = CGFloat(min(max(Defaults[.lockScreenTimerVerticalOffset], -160), 160))
        var originY = baseY + offset

        if showsWeather {
            originY = min(originY, weatherFrame.minY - size.height - 20)
        } else {
            let topLimit = screenFrame.maxY - size.height - 72
            originY = min(originY, topLimit)
        }

        let minY = screenFrame.minY + 100
        originY = max(originY, minY)

        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private var weatherFrame: CGRect {
        let size = weatherSize == .zero ? CGSize(width: 220, height: 60) : weatherSize
        let screenFrame = CGRect(origin: .zero, size: screenSize)
        let originX = screenFrame.midX - (size.width / 2)
        let verticalOffset = screenFrame.height * 0.15
        let isCircular = weatherSnapshot.widgetStyle == .circular
        let topMargin: CGFloat = isCircular ? 120 : 48
        let inlineBaseline = max(inlineBaselineHeight, 80)
        let positionHeight = weatherSnapshot.widgetStyle == .inline
            ? max(size.height, inlineBaseline)
            : size.height
        let maxY = screenFrame.maxY - positionHeight - topMargin
        let baseY = min(maxY, screenFrame.midY + verticalOffset)
        let loweredY = baseY - 36

        let inlineLift: CGFloat = weatherSnapshot.widgetStyle == .inline ? 44 : 0
        let circularDrop: CGFloat = isCircular ? 28 : 0
        let sizeDropHeight = positionHeight
        let sizeDrop = max(0, sizeDropHeight - 80) * 0.35
        let userOffset = CGFloat(Defaults[.lockScreenWeatherVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        let adjustedY = loweredY + inlineLift + clampedOffset - circularDrop - sizeDrop
        let upperClampedY = min(maxY, adjustedY)
        let clampedY = max(screenFrame.minY + 80, upperClampedY)

        return CGRect(x: originX, y: clampedY, width: size.width, height: size.height)
    }

    private func swiftUIFrame(for appKitFrame: CGRect) -> CGRect {
        let originY = screenSize.height - appKitFrame.maxY
        return CGRect(x: appKitFrame.origin.x, y: originY, width: appKitFrame.width, height: appKitFrame.height)
    }

    private func centerPoint(for frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

private struct PreviewSizeReader: View {
    @Binding var size: CGSize

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { size = proxy.size }
                .onChange(of: proxy.size) { _, newSize in
                    size = newSize
                }
        }
    }
}

struct WallpaperView: View {
    @State private var wallpaperImage: NSImage?

    var body: some View {
        ZStack {
            if let image = wallpaperImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: loadWallpaper)
    }

    func loadWallpaper() {
        if let url = Bundle.main.url(forResource: "desktop", withExtension: "jpeg"),
           let image = NSImage(contentsOf: url),
           image.size.width > 0,
           image.size.height > 0 {
            self.wallpaperImage = image
            return
        }

        if let image = NSImage(named: "desktop"),
           image.size.width > 0,
           image.size.height > 0 {
            self.wallpaperImage = image
            return
        }

        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let image = NSImage(contentsOf: url),
           image.size.width > 0,
           image.size.height > 0 {
            self.wallpaperImage = image
            return
        }
    }
}
