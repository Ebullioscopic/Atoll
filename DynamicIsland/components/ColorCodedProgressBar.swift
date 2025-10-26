//
//  ColorCodedProgressBar.swift
//  DynamicIsland
//
//  Created for color-coded battery and volume displays
//  Provides smooth gradient transitions from red to green (or reversed)
//

import SwiftUI
import Defaults

enum ColorCodingMode {
    case volume
    case battery
    
    func intensity(for value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        switch self {
        case .volume:
            return clamped
        case .battery:
            return 1 - clamped
        }
    }
}

struct ColorCodedProgressBar: View {
    let value: CGFloat  // 0.0 to 1.0
    let mode: ColorCodingMode
    let width: CGFloat
    let height: CGFloat
    let smoothGradient: Bool  // If true: smooth gradient, if false: discrete colors
    
    init(value: CGFloat, mode: ColorCodingMode = .battery, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) {
        self.value = min(max(value, 0), 1)  // Clamp between 0 and 1
        self.mode = mode
        self.width = width
        self.height = height
        self.smoothGradient = smoothGradient
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: width, height: height)
                
                // Filled track with color gradient or solid color
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(fillStyle)
                    .frame(width: width * value, height: height)
            }
        }
        .frame(width: width, height: height)
    }
    
    private var fillStyle: AnyShapeStyle {
        let intensity = mode.intensity(for: value)
        if smoothGradient {
            return AnyShapeStyle(ColorCodedPalette.gradient(for: intensity))
        } else {
            return AnyShapeStyle(ColorCodedPalette.discreteColor(for: intensity))
        }
    }
}

// MARK: - Convenience Extensions

extension ColorCodedProgressBar {
    /// Creates a battery-style progress bar (green at high, red at low)
    static func battery(value: CGFloat, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) -> some View {
        ColorCodedProgressBar(value: value, mode: .battery, width: width, height: height, smoothGradient: smoothGradient)
    }
    
    /// Creates a volume-style progress bar (red at high, green at low)
    static func volume(value: CGFloat, width: CGFloat = 100, height: CGFloat = 4, smoothGradient: Bool = true) -> some View {
        ColorCodedProgressBar(value: value, mode: .volume, width: width, height: height, smoothGradient: smoothGradient)
    }

    /// Shared helper for other progress bar implementations that need the same palette.
    static func shapeStyle(for value: CGFloat, mode: ColorCodingMode, smoothGradient: Bool) -> AnyShapeStyle {
        let intensity = mode.intensity(for: min(max(value, 0), 1))
        if smoothGradient {
            return AnyShapeStyle(ColorCodedPalette.gradient(for: intensity))
        }
        return AnyShapeStyle(ColorCodedPalette.discreteColor(for: intensity))
    }

    /// Returns the palette color that matches the configured thresholds. Useful for non-linear indicators.
    static func paletteColor(for value: CGFloat, mode: ColorCodingMode, smoothGradient: Bool) -> Color {
        let normalized = min(max(value, 0), 1)
        let intensity = mode.intensity(for: normalized)
        return ColorCodedPalette.color(for: intensity, smooth: smoothGradient)
    }
}

// MARK: - Palette Helpers

private enum ColorCodedPalette {
    private static let greenComponents: (CGFloat, CGFloat, CGFloat) = (0.2, 0.78, 0.35)
    private static let yellowComponents: (CGFloat, CGFloat, CGFloat) = (0.93, 0.75, 0.2)
    private static let redComponents: (CGFloat, CGFloat, CGFloat) = (0.95, 0.36, 0.3)

    static func color(for intensity: CGFloat, smooth: Bool) -> Color {
        if smooth {
            return smoothColor(for: intensity)
        }
        return discreteColor(for: intensity)
    }
    
    static func discreteColor(for intensity: CGFloat) -> Color {
        let clamped = min(max(intensity, 0), 1)
        switch clamped {
        case ..<0.6:
            return color(from: greenComponents)
        case ..<0.85:
            return color(from: yellowComponents)
        default:
            return color(from: redComponents)
        }
    }
    
    static func gradient(for intensity: CGFloat) -> LinearGradient {
        let endColor = smoothColor(for: intensity)
        let startColor = smoothColor(for: max(intensity - 0.15, 0))
        return LinearGradient(colors: [startColor, endColor], startPoint: .leading, endPoint: .trailing)
    }
    
    private static func smoothColor(for intensity: CGFloat) -> Color {
        let clamped = min(max(intensity, 0), 1)
        switch clamped {
        case ..<0.6:
            // Stay green within the comfort zone
            return color(from: greenComponents)
        case ..<0.85:
            let t = (clamped - 0.6) / 0.25
            return blend(from: greenComponents, to: yellowComponents, fraction: t)
        default:
            let t = (clamped - 0.85) / 0.15
            return blend(from: yellowComponents, to: redComponents, fraction: t)
        }
    }
    
    private static func blend(from start: (CGFloat, CGFloat, CGFloat), to end: (CGFloat, CGFloat, CGFloat), fraction: CGFloat) -> Color {
        let t = min(max(fraction, 0), 1)
        let red = lerp(start.0, end.0, t)
        let green = lerp(start.1, end.1, t)
        let blue = lerp(start.2, end.2, t)
        return color(from: (red, green, blue))
    }
    
    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
    
    private static func color(from components: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(red: Double(components.0), green: Double(components.1), blue: Double(components.2))
    }
}

// MARK: - Preview

#Preview("Battery Mode") {
    VStack(spacing: 20) {
        ForEach([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], id: \.self) { value in
            HStack {
                Text("\(Int(value * 100))%")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundColor(.white)
                ColorCodedProgressBar.battery(value: value, width: 200)
            }
        }
    }
    .padding()
    .background(Color.black)
}

#Preview("Volume Mode (Reversed)") {
    VStack(spacing: 20) {
        ForEach([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0], id: \.self) { value in
            HStack {
                Text("\(Int(value * 100))%")
                    .frame(width: 50, alignment: .trailing)
                    .foregroundColor(.white)
                ColorCodedProgressBar.volume(value: value, width: 200)
            }
        }
    }
    .padding()
    .background(Color.black)
}
