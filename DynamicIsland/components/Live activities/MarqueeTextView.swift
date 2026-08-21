/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct MeasureSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: SizePreferenceKey.self, value: geometry.size)
        })
    }
}

enum MusicLyricsLayoutMetrics {
    static let standardFontSize: CGFloat = 12
    static let standardMinimumFontSize: CGFloat = 4
    static let standardWeight: Font.Weight = .regular
    static let standardNSWeight: NSFont.Weight = .regular
    static let standardTopPadding: CGFloat = 2

    static let minimalisticOpenFontSize: CGFloat = 12
    static let minimalisticOpenMinimumFontSize: CGFloat = 4
    static let minimalisticOpenWeight: Font.Weight = .semibold
    static let minimalisticOpenNSWeight: NSFont.Weight = .semibold
    static let minimalisticOpenTopPadding: CGFloat = 10

    static let compactFontSize: CGFloat = 11
    static let compactMinimumFontSize: CGFloat = 4
    static let compactWeight: Font.Weight = .semibold
    static let compactNSWeight: NSFont.Weight = .semibold
    static let compactBottomAreaPadding: CGFloat = 4

    static var standardReservedTextHeight: CGFloat {
        TwoLineFittingText.reservedHeight(fontSize: standardFontSize, weight: standardNSWeight)
    }

    static var standardReservedAreaHeight: CGFloat {
        standardTopPadding + standardReservedTextHeight
    }

    static var minimalisticOpenReservedTextHeight: CGFloat {
        TwoLineFittingText.reservedHeight(fontSize: minimalisticOpenFontSize, weight: minimalisticOpenNSWeight)
    }

    static var minimalisticOpenReservedAreaHeight: CGFloat {
        minimalisticOpenTopPadding + minimalisticOpenReservedTextHeight
    }

    static var compactReservedTextHeight: CGFloat {
        TwoLineFittingText.reservedHeight(fontSize: compactFontSize, weight: compactNSWeight)
    }

    static var compactReservedAreaHeight: CGFloat {
        compactBottomAreaPadding + compactReservedTextHeight
    }
}

struct TwoLineFittingText: View {
    let text: String
    let fontSize: CGFloat
    let minimumFontSize: CGFloat
    let weight: Font.Weight
    let nsWeight: NSFont.Weight
    let textColor: Color
    let alignment: Alignment
    let multilineTextAlignment: TextAlignment

    init(
        text: String,
        fontSize: CGFloat,
        minimumFontSize: CGFloat,
        weight: Font.Weight = .regular,
        nsWeight: NSFont.Weight = .regular,
        textColor: Color = .primary,
        alignment: Alignment = .topLeading,
        multilineTextAlignment: TextAlignment = .leading
    ) {
        self.text = text
        self.fontSize = fontSize
        self.minimumFontSize = minimumFontSize
        self.weight = weight
        self.nsWeight = nsWeight
        self.textColor = textColor
        self.alignment = alignment
        self.multilineTextAlignment = multilineTextAlignment
    }

    var body: some View {
        Text(Self.normalizedDisplayText(text))
            .font(.system(size: fontSize, weight: weight))
            .foregroundColor(textColor)
            .lineLimit(2)
            .multilineTextAlignment(multilineTextAlignment)
            .allowsTightening(true)
            .minimumScaleFactor(max(0.1, minimumFontSize / max(fontSize, 1)))
            .frame(maxWidth: .infinity, alignment: alignment)
            // Pass the caller's alignment through — .frame(height:) defaults to .center,
            // which floated a one-line lyric half a line below the top-aligned note icon.
            .frame(height: Self.reservedHeight(fontSize: fontSize, weight: nsWeight), alignment: alignment)
    }

    static func reservedHeight(fontSize: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return ceil(font.ascender - font.descender + font.leading) * 2
    }

    private static func normalizedDisplayText(_ text: String) -> String {
        let normalizedLines = text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }

        guard !normalizedLines.isEmpty else { return "" }

        // Plain-lyrics fallbacks can contain the full song body. Keep the preview to
        // the first two logical lines so the UI stays readable.
        if normalizedLines.count > 1 {
            return normalizedLines.prefix(2).joined(separator: "\n")
        }

        return normalizedLines[0]
    }

}

struct MarqueeText: View {
    @Binding var text: String
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    
    @State private var textSize: CGSize = .zero
    @State private var offset: CGFloat = 0
    @State private var isAnimating: Bool = false
    
    init(_ text: Binding<String>, font: Font = .body, nsFont: NSFont.TextStyle = .body, textColor: Color = .primary, backgroundColor: Color = .clear, minDuration: Double = 3.0, frameWidth: CGFloat = 200) {
        _text = text
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
    }

    static func reservedHeight(forTextStyle textStyle: NSFont.TextStyle) -> CGFloat {
        ceil(NSFont.preferredFont(forTextStyle: textStyle).pointSize * 1.3)
    }
    
    private var needsScrolling: Bool {
        textSize.width > frameWidth
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 20) {
                Text(text)
                Text(text)
                    .opacity(needsScrolling ? 1 : 0)
            }
            .id(text)
            .font(font)
            .foregroundColor(textColor)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: offset)
            .background(backgroundColor)
            .modifier(MeasureSizeModifier())
            .onPreferenceChange(SizePreferenceKey.self) { size in
                self.textSize = CGSize(width: size.width / 2, height: NSFont.preferredFont(forTextStyle: nsFont).pointSize)
                resetAndStart()
            }
            .onChange(of: text) { _, _ in
                resetAndStart()
            }
            .onAppear {
                resetAndStart()
            }
            .onDisappear {
                isAnimating = false
            }
        }
        .frame(width: frameWidth, alignment: .leading)
        .clipped()
        .frame(height: Self.reservedHeight(forTextStyle: nsFont))
    }
    
    private func resetAndStart() {
        isAnimating = false
        withAnimation(.none) {
            offset = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if needsScrolling {
                isAnimating = true
                startAnimationLoop()
            }
        }
    }
    
    private func startAnimationLoop() {
        guard isAnimating && needsScrolling else { return }
        
        // Duration based on speed (approx 30 pts per second)
        let duration = Double(textSize.width / 30)
        
        // 1. Initial/Restart Pause
        DispatchQueue.main.asyncAfter(deadline: .now() + minDuration) {
            guard isAnimating else { return }
            
            // 2. Linear Move
            withAnimation(.linear(duration: duration)) {
                offset = -(textSize.width + 20) // Text width + spacing
            }
            
            // 3. Wait for move to finish
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard isAnimating else { return }
                
                // 4. Snap back instantly
                withAnimation(.none) {
                    offset = 0
                }
                
                // 5. Repeat
                startAnimationLoop()
            }
        }
    }
}

struct MusicExplicitBadge: View {
    var label: String = "E"
    var fontSize: CGFloat = 9
    var height: CGFloat = 14
    var horizontalPadding: CGFloat = 4
    var minWidth: CGFloat? = nil
    var foregroundColor: Color = .white.opacity(0.92)
    var backgroundColor: Color = .white.opacity(0.18)
    var cornerRadius: CGFloat? = nil
    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, max(horizontalPadding, height * 0.2))
            .frame(minWidth: minWidth, minHeight: height)
            .background(
                RoundedRectangle(
                    cornerRadius: cornerRadius ?? max(4, height * 0.28),
                    style: .continuous
                )
                .fill(backgroundColor)
            )
            .fixedSize()
    }
}

struct MusicTitleMarqueeView: View {
    let text: String
    let isExplicit: Bool
    let font: Font
    let nsFont: NSFont.TextStyle
    let textColor: Color
    let backgroundColor: Color
    let minDuration: Double
    let frameWidth: CGFloat
    let alignment: Alignment
    let badgeSpacing: CGFloat
    let badgeLabel: String
    let badgeFontSize: CGFloat?
    let badgeHeight: CGFloat?
    let badgeForegroundColor: Color
    let badgeBackgroundColor: Color
    let badgeHorizontalPadding: CGFloat
    let badgeMinWidth: CGFloat?
    let badgeCornerRadius: CGFloat?

    init(
        text: String,
        isExplicit: Bool,
        font: Font = .body,
        nsFont: NSFont.TextStyle = .body,
        textColor: Color = .primary,
        backgroundColor: Color = .clear,
        minDuration: Double = 3.0,
        frameWidth: CGFloat = 200,
        alignment: Alignment = .leading,
        badgeSpacing: CGFloat = 6,
        badgeLabel: String = "E",
        badgeFontSize: CGFloat? = nil,
        badgeHeight: CGFloat? = nil,
        badgeForegroundColor: Color = .white.opacity(0.92),
        badgeBackgroundColor: Color = .white.opacity(0.18),
        badgeHorizontalPadding: CGFloat = 4,
        badgeMinWidth: CGFloat? = nil,
        badgeCornerRadius: CGFloat? = nil
    ) {
        self.text = text
        self.isExplicit = isExplicit
        self.font = font
        self.nsFont = nsFont
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.minDuration = minDuration
        self.frameWidth = frameWidth
        self.alignment = alignment
        self.badgeSpacing = badgeSpacing
        self.badgeLabel = badgeLabel
        self.badgeFontSize = badgeFontSize
        self.badgeHeight = badgeHeight
        self.badgeForegroundColor = badgeForegroundColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeHorizontalPadding = badgeHorizontalPadding
        self.badgeMinWidth = badgeMinWidth
        self.badgeCornerRadius = badgeCornerRadius
    }

    private var resolvedBadgeHeight: CGFloat {
        badgeHeight ?? max(12, NSFont.preferredFont(forTextStyle: nsFont).pointSize * 1.12)
    }

    private var resolvedBadgeFontSize: CGFloat {
        badgeFontSize ?? max(8, resolvedBadgeHeight * 0.6)
    }

    private var reservedBadgeWidth: CGFloat {
        guard isExplicit else { return 0 }
        return resolvedBadgeHeight + (resolvedBadgeHeight * 0.7) + badgeSpacing
    }

    private var titleFrameWidth: CGFloat {
        max(0, frameWidth - reservedBadgeWidth)
    }

    private var measurementFont: NSFont {
        NSFont.preferredFont(forTextStyle: nsFont)
    }

    private var measuredTextWidth: CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: measurementFont]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private var needsScrolling: Bool {
        frameWidth > 0 && measuredTextWidth > titleFrameWidth
    }

    var body: some View {
        HStack(spacing: badgeSpacing) {
            if needsScrolling {
                MarqueeText(
                    .constant(text),
                    font: font,
                    nsFont: nsFont,
                    textColor: textColor,
                    backgroundColor: backgroundColor,
                    minDuration: minDuration,
                    frameWidth: titleFrameWidth
                )
            } else {
                Text(text)
                    .font(font)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if isExplicit {
                MusicExplicitBadge(
                    label: badgeLabel,
                    fontSize: resolvedBadgeFontSize,
                    height: resolvedBadgeHeight,
                    horizontalPadding: badgeHorizontalPadding,
                    minWidth: badgeMinWidth,
                    foregroundColor: badgeForegroundColor,
                    backgroundColor: badgeBackgroundColor,
                    cornerRadius: badgeCornerRadius
                )
            }
        }
        .frame(width: frameWidth, alignment: alignment)
        .frame(height: MarqueeText.reservedHeight(forTextStyle: nsFont))
    }
}
