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

import SwiftUI
import AppKit
import AtollExtensionKit
import Lottie
import LottieUI
import CryptoKit
import Defaults

// MARK: - Color Conversion

extension AtollColorDescriptor {
    var swiftUIColor: Color {
        if isAccent {
            return .accentColor
        }
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var nsColor: NSColor {
        if isAccent {
            return NSColor.controlAccentColor
        }
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    func resolvedColor(fallback accent: Color) -> Color {
        isAccent ? accent : swiftUIColor
    }
}

// MARK: - Font Conversion

extension AtollFontDescriptor {
    func swiftUIFont() -> Font {
        let design = self.design.swiftUI
        let weight = self.weight.swiftUI
        var font = Font.system(size: size, weight: weight, design: design)
        if isMonospacedDigit {
            font = font.monospacedDigit()
        }
        return font
    }

    func nsFont() -> NSFont {
        let weight = weight.nsFont
        let font: NSFont
        switch design {
        case .serif:
            font = NSFont.userFont(ofSize: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
        case .rounded:
            if let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded) {
                font = NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
            } else {
                font = NSFont.systemFont(ofSize: size, weight: weight)
            }
        case .monospaced:
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .default:
            font = NSFont.systemFont(ofSize: size, weight: weight)
        }
        return font
    }
}

private extension AtollFontWeight {
    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var nsFont: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

private extension AtollFontDesign {
    var swiftUI: Font.Design {
        switch self {
        case .default: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

// MARK: - Icon Rendering

struct ExtensionIconView: View {
    let descriptor: AtollIconDescriptor
    let tint: Color
    let size: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        switch descriptor {
        case let .symbol(name, glyphSize, weight):
            Image(systemName: name)
                .font(.system(size: glyphSize, weight: weight.swiftUI))
                .foregroundStyle(tint)
                .frame(width: size.width, height: size.height)
        case let .image(data, targetSize, radius):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: targetSize.width, height: targetSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                fallbackSymbol
            }
        case let .appIcon(bundleIdentifier, targetSize, radius):
            if let icon = AppIconAsNSImage(for: bundleIdentifier) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: targetSize.width, height: targetSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                fallbackSymbol
            }
        case let .lottie(animationData, targetSize):
            let resolvedSize = CGSize(width: min(targetSize.width, size.width), height: min(targetSize.height, size.height))
            ExtensionLottieView(data: animationData, size: resolvedSize)
                .frame(width: size.width, height: size.height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius(for: descriptor), style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        case .none:
            fallbackSymbol
        }
    }

    private var fallbackSymbol: some View {
        Image(systemName: "app.dashed")
            .font(.system(size: size.width * 0.6, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius(for: descriptor), style: .continuous)
                    .fill(tint.opacity(0.15))
            )
    }

    private func cornerRadius(for descriptor: AtollIconDescriptor) -> CGFloat {
        switch descriptor {
        case .image(_, _, let radius): return radius
        case .appIcon(_, _, let radius): return radius
        default: return cornerRadius
        }
    }
}

struct ExtensionCompositeIconView: View {
    let leading: AtollIconDescriptor
    let badge: AtollIconDescriptor?
    let accent: Color
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ExtensionIconView(
                descriptor: leading,
                tint: accent,
                size: CGSize(width: size, height: size),
                cornerRadius: size * 0.18
            )
            if let badge {
                ExtensionIconView(
                    descriptor: badge,
                    tint: .white,
                    size: CGSize(width: max(size * 0.35, 12), height: max(size * 0.35, 12)),
                    cornerRadius: size * 0.12
                )
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.7))
                        .frame(width: size * 0.4, height: size * 0.4)
                )
            }
        }
        .frame(width: size, height: size)
    }
}

struct ExtensionBadgeIconView: View {
    let descriptor: AtollIconDescriptor
    let accent: Color
    let size: CGFloat

    private var symbolSize: CGFloat { size * 0.5 }
    private var imageSize: CGFloat { size * 0.62 }
    private var imageCornerRadius: CGFloat { size * 0.18 }

    var body: some View {
        Group {
            switch descriptor {
            case let .symbol(name, _, weight):
                Image(systemName: name)
                    .font(.system(size: symbolSize, weight: weight.swiftUI))
                    .foregroundStyle(accent)
            case let .image(data, _, _):
                if let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
                } else {
                    fallbackSymbol
                }
            case let .appIcon(bundleIdentifier, _, _):
                if let icon = AppIconAsNSImage(for: bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous))
                } else {
                    fallbackSymbol
                }
            case let .lottie(animationData, _):
                ExtensionLottieView(data: animationData, size: CGSize(width: imageSize, height: imageSize))
            case .none:
                fallbackSymbol
            }
        }
        .frame(width: size, height: size)
    }

    private var fallbackSymbol: some View {
        Image(systemName: "app.dashed")
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(accent)
            .frame(width: imageSize, height: imageSize)
            .background(
                RoundedRectangle(cornerRadius: imageCornerRadius, style: .continuous)
                    .fill(accent.opacity(0.15))
            )
    }
}

// MARK: - Lottie Rendering

struct ExtensionLottieView: View {
    let data: Data
    let size: CGSize
    var loopMode: LottieLoopMode = .loop
    @State private var cachedURL: URL?

    var body: some View {
        Group {
            if let cachedURL {
                LottieView(
                    state: LUStateData(
                        type: .loadedFrom(cachedURL),
                        speed: 1.0,
                        loopMode: loopMode
                    )
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.7))
            }
        }
        .frame(width: size.width, height: size.height)
        .task {
            if cachedURL == nil {
                cachedURL = ExtensionLottieCache.shared.url(for: data)
            }
        }
    }
}

private final class ExtensionLottieCache {
    static let shared = ExtensionLottieCache()
    private let queue = DispatchQueue(label: "com.atoll.extension-lottie-cache")
    private var cache: [String: URL] = [:]

    func url(for data: Data) -> URL? {
        queue.sync {
            let key = Self.hash(data: data)
            if let existing = cache[key], FileManager.default.fileExists(atPath: existing.path) {
                return existing
            }

            let url = FileManager.default.temporaryDirectory.appendingPathComponent("extension-lottie-\(key).json", conformingTo: .json)
            do {
                try data.write(to: url, options: .atomic)
                cache[key] = url
                return url
            } catch {
                cache.removeValue(forKey: key)
                return nil
            }
        }
    }

    private static func hash(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Progress Rendering

struct ExtensionProgressIndicatorView: View {
    let indicator: AtollProgressIndicator
    let progress: Double
    let accent: Color
    let estimatedDuration: TimeInterval?
    let maxVisualHeight: CGFloat?

    init(
        indicator: AtollProgressIndicator,
        progress: Double,
        accent: Color,
        estimatedDuration: TimeInterval?,
        maxVisualHeight: CGFloat? = nil
    ) {
        self.indicator = indicator
        self.progress = progress
        self.accent = accent
        self.estimatedDuration = estimatedDuration
        self.maxVisualHeight = maxVisualHeight
    }

    var body: some View {
        switch indicator {
        case let .ring(diameter, strokeWidth, color):
            let ringColor = color?.resolvedColor(fallback: accent) ?? accent
            let resolvedDiameter = resolvedRingDiameter(requested: diameter)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: strokeWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(progress, 1))))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: progress)
            }
            .frame(width: resolvedDiameter, height: resolvedDiameter)
        case let .bar(width, height, cornerRadius, color):
            let barColor = color?.resolvedColor(fallback: accent) ?? accent
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: width ?? 80, height: height)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(barColor)
                        .frame(width: (width ?? 80) * CGFloat(max(0, min(progress, 1))), height: height)
                        .animation(.smooth(duration: 0.25), value: progress)
                }
        case let .percentage(font, color):
            let textColor = color?.resolvedColor(fallback: accent) ?? accent
            Text("\(Int(progress * 100))%")
                .font(font.swiftUIFont())
                .foregroundStyle(textColor)
                .monospacedDigit()
        case let .countdown(font, color):
            let textColor = color?.resolvedColor(fallback: accent) ?? accent
            let text = countdownText
            Text(text)
                .font(font.swiftUIFont())
                .foregroundStyle(textColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: text)
        case .lottie:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
        case .none:
            EmptyView()
        }
    }

    private var countdownText: String {
        guard let estimatedDuration else { return formatPercent }
        let remaining = max(estimatedDuration * (1 - progress), 0)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formatPercent: String {
        "\(Int(progress * 100))%"
    }

    private func resolvedRingDiameter(requested: CGFloat) -> CGFloat {
        guard let maxVisualHeight else { return requested }
        let target = max(min(maxVisualHeight - 12, 24), 16)
        return min(requested, target)
    }
}

// MARK: - Edge Content Rendering

struct ExtensionEdgeContentView: View {
    let content: AtollTrailingContent
    let accent: Color
    let availableWidth: CGFloat
    let alignment: Alignment

    var body: some View {
        switch content {
        case let .text(value, font: font, color: color):
            Text(value)
                .font(font.swiftUIFont())
                .foregroundStyle(resolvedColor(color))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
        case let .marquee(value, font: font, minDuration: duration, color: color):
            MarqueeText(
                .constant(value),
                font: font.swiftUIFont(),
                nsFont: .body,
                textColor: resolvedColor(color),
                minDuration: duration,
                frameWidth: max(24, availableWidth - 12)
            )
        case let .countdownText(targetDate, font: font, color: color):
            ExtensionCountdownTextView(targetDate: targetDate, font: font, accent: accent, customColor: color?.resolvedColor(fallback: accent))
                .frame(maxWidth: .infinity, alignment: alignment)
        case let .icon(descriptor):
            ExtensionIconView(
                descriptor: descriptor,
                tint: accent,
                size: CGSize(width: 26, height: 26),
                cornerRadius: 6
            )
        case let .spectrum(color: colorDescriptor):
            Rectangle()
                .fill((colorDescriptor.isAccent ? accent : colorDescriptor.swiftUIColor).spectrogramGradient())
                .frame(width: CGFloat(Defaults[.visualizerBarCount]) * 4, height: 14)
                .mask {
                    AudioVisualizerView(isPlaying: .constant(true))
                        .frame(width: CGFloat(Defaults[.visualizerBarCount]) * 4, height: 12)
                }
        case let .animation(data, size):
            let resolvedWidth = min(size.width, availableWidth)
            ExtensionLottieView(data: data, size: CGSize(width: resolvedWidth, height: size.height))
        case .none:
            EmptyView()
        }
    }

    private func resolvedColor(_ descriptorColor: AtollColorDescriptor?) -> Color {
        descriptorColor?.resolvedColor(fallback: accent) ?? accent
    }
}

struct ExtensionCountdownTextView: View {
    let targetDate: Date
    let font: AtollFontDescriptor
    let accent: Color
    let customColor: Color?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remainingText = formattedRemaining(since: context.date)
            Text(remainingText)
                .font(font.swiftUIFont())
                .foregroundStyle(customColor ?? accent)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: remainingText)
        }
    }

    private func formattedRemaining(since date: Date) -> String {
        let remaining = max(Int(targetDate.timeIntervalSince(date)), 0)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        let seconds = remaining % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Layout Metrics

enum ExtensionLayoutMetrics {
    static func trailingWidth(for payload: ExtensionLiveActivityPayload, baseWidth: CGFloat, maxWidth: CGFloat? = nil) -> CGFloat {
        let renderable = resolvedExtensionTrailingRenderable(for: payload.descriptor)
        var width: CGFloat
        switch renderable {
        case let .content(content):
            width = edgeWidth(for: content, baseWidth: baseWidth, maxWidth: maxWidth)
        case let .indicator(indicator):
            width = edgeWidth(for: .none, baseWidth: baseWidth, maxWidth: maxWidth)
            width = max(width, widthForProgress(indicator))
        }
        if let maxWidth {
            width = min(width, maxWidth)
        }
        return width
    }

    static func edgeWidth(for content: AtollTrailingContent, baseWidth: CGFloat, maxWidth: CGFloat? = nil) -> CGFloat {
        var width = widthForContent(content, baseWidth: baseWidth)
        if let maxWidth {
            width = min(width, maxWidth)
        }
        return width
    }

    private static func widthForContent(_ content: AtollTrailingContent, baseWidth: CGFloat) -> CGFloat {
        switch content {
        case let .text(text, font: font, color: _):
            let measured = ExtensionTextMeasurer.width(for: text, font: font.nsFont())
            return max(baseWidth, measured + 32)
        case let .marquee(text, font: font, minDuration: _, color: _):
            let measured = ExtensionTextMeasurer.width(for: text, font: font.nsFont())
            return max(baseWidth, min(measured + 40, baseWidth * 2))
        case let .countdownText(targetDate, font: font, color: _):
            let sample = targetDate.timeIntervalSinceNow >= 3600 ? "00:00:00" : "00:00"
            let measured = ExtensionTextMeasurer.width(for: sample, font: font.nsFont())
            return max(baseWidth, measured + 24)
        case .icon:
            return max(baseWidth, 52)
        case .spectrum:
            return max(baseWidth, 56)
        case let .animation(data: _, size: size):
            return max(baseWidth, size.width + 16)
        case .none:
            return baseWidth
        }
    }

    private static func widthForProgress(_ indicator: AtollProgressIndicator) -> CGFloat {
        switch indicator {
        case let .ring(diameter, _, _):
            return diameter + 20
        case let .bar(width, _, _, _):
            return (width ?? 72) + 12
        case .percentage(_, _):
            return 60
        case .countdown(_, _):
            return 74
        case let .lottie(_, size):
            return size.width + 16
        case .none:
            return 0
        }
    }
}

enum ExtensionTextMeasurer {
    static func width(for text: String, font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return max(1, text.size(withAttributes: attributes).width)
    }
}

enum ExtensionTrailingRenderable {
    case content(AtollTrailingContent)
    case indicator(AtollProgressIndicator)
}

func resolvedExtensionLeadingContent(for descriptor: AtollLiveActivityDescriptor) -> AtollTrailingContent {
    guard let override = descriptor.leadingContent else {
        return .icon(descriptor.leadingIcon)
    }

    switch override {
    case .icon, .animation:
        return override
    default:
        return .icon(descriptor.leadingIcon)
    }
}

func resolvedExtensionTrailingRenderable(for descriptor: AtollLiveActivityDescriptor) -> ExtensionTrailingRenderable {
    if let indicator = descriptor.progressIndicator,
       indicator.isRenderable,
       descriptor.trailingContent == .none {
        return .indicator(indicator)
    }
    return .content(descriptor.trailingContent)
}

private extension AtollProgressIndicator {
    var isRenderable: Bool {
        switch self {
        case .none:
            return false
        default:
            return true
        }
    }
}
