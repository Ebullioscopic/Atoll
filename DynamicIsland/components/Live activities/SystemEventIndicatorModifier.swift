    //
    //  SystemEventIndicatorModifier.swift
    //  DynamicIsland
    //
    //  Created by Richard Kunkli on 12/08/2024.
    //

import SwiftUI
import Defaults

struct SystemEventIndicatorModifier: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat {
        didSet {
            DispatchQueue.main.async {
                self.sendEventBack(value)
                self.vm.objectWillChange.send()
            }
        }
    }
    @Binding var icon: String
    let showSlider: Bool = false
    var sendEventBack: (CGFloat) -> Void
    @Default(.showProgressPercentages) private var showProgressPercentages
    
    var body: some View {
        HStack(spacing: 14) {
            switch (eventType) {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                            .symbolVariant(value > 0 ? .none : .slash)
                            .frame(width: 20, height: 15, alignment: .leading)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                            .opacity(value.isZero ? 0.6 : 1)
                            .scaleEffect(value.isZero ? 0.85 : 1)
                            .frame(width: 20, height: 15, alignment: .leading)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(.white)
                case .backlight:
                    Image(systemName: "keyboard")
                        .contentTransition(.symbolEffect)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(.white)
                case .mic:
                    Image(systemName: "mic")
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                        .frame(width: 20, height: 15)
                        .foregroundStyle(.white)
                default:
                    EmptyView()
            }
            switch eventType {
            case .mic:
                Text(value > 0 ? "Mic unmuted" : "Mic muted")
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
            case .volume:
                VolumeProgressSection(value: $value, showPercentages: showProgressPercentages)
            case .brightness:
                ProgressSection(value: $value, showPercentages: showProgressPercentages)
            case .backlight:
                ProgressSection(value: $value, showPercentages: showProgressPercentages)
            default:
                ProgressSection(value: $value, showPercentages: showProgressPercentages)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .symbolVariant(.fill)
        .imageScale(.large)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker.slash"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
}

struct ProgressSection: View {
    @Binding var value: CGFloat
    var showPercentages: Bool
    var colorMode: ProgressColorMode? = nil
    
    var body: some View {
        HStack(spacing: 8) {
            DraggableProgressBar(value: $value, colorMode: colorMode)
            PercentageLabel(value: value, isVisible: showPercentages)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VolumeProgressSection: View {
    @Binding var value: CGFloat
    var showPercentages: Bool
    
    var body: some View {
        Group {
            if value.isZero {
                Text("muted")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.gray)
                    .contentTransition(.numericText())
            } else {
                ProgressSection(value: $value, showPercentages: showPercentages, colorMode: .volume)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth(duration: 0.2), value: value.isZero)
    }
}

struct PercentageLabel: View {
    let value: CGFloat
    let isVisible: Bool
    @Default(.progressBarStyle) private var progressBarStyle
    
    var body: some View {
        Group {
            if shouldShow {
                Text(formattedValue)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.9))
                    .contentTransition(.numericText())
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
    
    private var shouldShow: Bool {
        isVisible && progressBarStyle != .segmented
    }

    private var formattedValue: String {
        let raw = max(0, min(100, Int(round(value * 100))))
        return String(format: "%3d", raw)
    }
}

enum ProgressColorMode {
    case volume
    case battery
}

private extension ProgressColorMode {
    var colorCodingMode: ColorCodingMode {
        switch self {
        case .volume:
            return .volume
        case .battery:
            return .battery
        }
    }
}

struct DraggableProgressBar: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var value: CGFloat
    var colorMode: ProgressColorMode? = nil
    
    @State private var isDragging = false
    @Default(.progressBarStyle) private var progressBarStyle
    @Default(.useColorCodedVolumeDisplay) private var useColorCodedVolumeDisplay
    @Default(.useColorCodedBatteryDisplay) private var useColorCodedBatteryDisplay
    @Default(.useSmoothColorGradient) private var useSmoothColorGradient
    @Default(.systemEventIndicatorUseAccent) private var useAccentColor
    @Default(.systemEventIndicatorShadow) private var useShadow
    @Default(.inlineHUD) private var inlineHUD
    
    var body: some View {
        VStack {
            GeometryReader { geo in
                Group {
                    if progressBarStyle == .segmented {
                        // Segmented progress bar - completely different layout
                        SegmentedProgressContent(value: value, geometry: geo)
                    } else {
                        // Traditional capsule-based progress bar
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.tertiary)
                            progressFill(width: geo.size.width)
                                .opacity(value.isZero ? 0 : 1)
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = true
                                updateValue(gesture: gesture, in: geo)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.smooth(duration: 0.3)) {
                                isDragging = false
                            }
                        }
                )
            }
            .frame(height: inlineHUD ? (isDragging ? 8 : 5) : (isDragging ? 9 : 6))
        }
    }
    
    private func updateValue(gesture: DragGesture.Value, in geometry: GeometryProxy) {
        let dragPosition = gesture.location.x
        let newValue = dragPosition / geometry.size.width
        
        value = max(0, min(newValue, 1))
    }

    private func progressFill(width: CGFloat) -> some View {
        let clampedWidth = max(0, min(width * value, width))
        let accentColor = Defaults[.accentColor]
        let shadowColor: Color = {
            guard useShadow else { return .clear }
            if useAccentColor {
                return accentColor.ensureMinimumBrightness(factor: 0.7)
            }
            return .white
        }()

        return Group {
            if shouldUseColorCoding, let mode = colorMode?.colorCodingMode {
                Capsule()
                    .fill(ColorCodedProgressBar.shapeStyle(for: value, mode: mode, smoothGradient: useSmoothColorGradient))
                    .frame(width: clampedWidth)
                    .shadow(color: shadowColor, radius: useShadow ? 8 : 0, x: 3)
            } else {
                switch progressBarStyle {
                case .gradient:
                    Capsule()
                        .fill(LinearGradient(
                            colors: useAccentColor
                                ? [accentColor, accentColor.ensureMinimumBrightness(factor: 0.2)]
                                : [.white, .white.opacity(0.2)],
                            startPoint: .trailing,
                            endPoint: .leading
                        ))
                        .frame(width: clampedWidth)
                        .shadow(color: shadowColor, radius: useShadow ? 8 : 0, x: 3)
                case .hierarchical:
                    Capsule()
                        .fill(useAccentColor ? accentColor : .white)
                        .frame(width: clampedWidth)
                        .shadow(color: shadowColor, radius: useShadow ? 8 : 0, x: 3)
                case .segmented:
                    EmptyView()
                }
            }
        }
    }

    private var shouldUseColorCoding: Bool {
        guard let colorMode else { return false }
        guard progressBarStyle != .segmented else { return false }
        switch colorMode {
        case .volume:
            return useColorCodedVolumeDisplay
        case .battery:
            return useColorCodedBatteryDisplay
        }
    }
}

struct SegmentedProgressContent: View {
    let value: CGFloat
    let geometry: GeometryProxy
    
    private let segmentCount = 16
    @State private var glowIndex: Int? = nil
    @State private var lastValue: CGFloat = 0
    
    var body: some View {
        let spacing: CGFloat = 1.5
    let computed = (geometry.size.width - CGFloat(segmentCount - 1) * spacing) / CGFloat(segmentCount)
    let barWidth = max(3.0, computed)
        let activeCount = Int(round(value * CGFloat(segmentCount)))
        
        HStack(spacing: spacing) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(segmentColor(isActive: index < activeCount))
                    .shadow(
                        color: Defaults[.systemEventIndicatorShadow]
                            ? glowShadowColor(for: index < activeCount, index: index)
                            : .clear,
                        radius: Defaults[.systemEventIndicatorShadow]
                            ? (glowIndex == index ? 12 : (index < activeCount ? 4 : 0))
                            : 0,
                        x: 0, y: 0
                    )
                    .frame(width: barWidth)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: activeCount)
                    .scaleEffect(glowIndex == index ? 1.15 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: glowIndex == index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .opacity(value.isZero ? 0 : 1)
        .onChange(of: value) { old, newVal in
            handleGlow(oldValue: old, newValue: newVal)
        }
    }
    
    private func segmentColor(isActive: Bool) -> Color {
        if isActive {
            if Defaults[.systemEventIndicatorUseAccent] {
                return Defaults[.accentColor]
            }
            return .white
        } else {
            return .white.opacity(0.15)
        }
    }
    
    private func glowShadowColor(for isActive: Bool, index: Int) -> Color {
        if isActive {
            if let glowIndex = glowIndex, index == glowIndex {
                return Defaults[.systemEventIndicatorUseAccent]
                    ? Defaults[.accentColor].ensureMinimumBrightness(factor: 0.8)
                    : .white
            } else {
                return Defaults[.systemEventIndicatorUseAccent]
                    ? Defaults[.accentColor].ensureMinimumBrightness(factor: 0.7)
                    : .white
            }
        }
        return .clear
    }
    
    private func handleGlow(oldValue: CGFloat, newValue: CGFloat) {
        defer { lastValue = newValue }
        let oldIndex = Int(round(oldValue * CGFloat(segmentCount)))
        let newIndex = Int(round(newValue * CGFloat(segmentCount)))
        guard oldIndex != newIndex else { return }

        if newIndex > oldIndex {
            animateWave(from: oldIndex, to: newIndex, step: 1)
        } else {
            animateWave(from: oldIndex - 1, to: newIndex - 1, step: -1)
        }
    }
    
    private func animateWave(from start: Int, to end: Int, step: Int) {
        let clampedStart = max(0, min(segmentCount - 1, start))
        let clampedEnd = max(-1, min(segmentCount - 1, end))
        let range = stride(from: clampedStart, through: clampedEnd, by: step)
        var delay: Double = 0
        for i in range {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                    glowIndex = i
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.2) {
                if glowIndex == i {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        glowIndex = nil
                    }
                }
            }
            delay += 0.015
        }
    }
}
