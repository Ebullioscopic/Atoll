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

import Defaults
import SwiftUI

/// Renders a script with everything already read dimmed and the current word
/// highlighted.
///
/// Shared by the floating panel and the notch tab so both show the same reading
/// position from the same `confirmedTokenIndex` — there is no second notion of
/// "where we are" to drift out of sync.
struct TeleprompterScriptTextView: View {
    let script: TeleprompterScript
    let confirmedTokenIndex: Int
    var fontSize: Double
    var fontChoice: TeleprompterFontChoice
    var customFontFamily: String
    var isMirrored: Bool
    /// Compact mode drops the section headings and notes, for the notch.
    var isCompact: Bool = false
    /// Sections the reader has covered so far, so a must-cover marker can tick
    /// off live rather than only in the debrief.
    var coveredSectionIndices: Set<Int> = []

    /// Scrolls the current word to the middle of the view.
    private let scrollAnchor = UnitPoint.center

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: isCompact ? 8 : 18) {
                    ForEach(Array(script.sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section, index: index)
                    }
                }
                .padding(.horizontal, isCompact ? 4 : 24)
                .padding(.vertical, isCompact ? 4 : 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scaleEffect(x: isMirrored ? -1 : 1, y: 1, anchor: .center)
            .onChange(of: confirmedTokenIndex) { _, index in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(anchorID(for: index), anchor: scrollAnchor)
                }
            }
            .onAppear {
                proxy.scrollTo(anchorID(for: confirmedTokenIndex), anchor: scrollAnchor)
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func sectionView(_ section: TeleprompterSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 10) {
            if !isCompact, !section.title.isEmpty {
                sectionHeader(section, index: index)
            }
            // Words are laid out as a flowing run so each can be tinted
            // independently while still wrapping like a paragraph.
            wordFlow(for: section)
            if !isCompact {
                ForEach(Array(section.notes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.system(size: fontSize * 0.55, weight: .regular, design: .default))
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionHeader(_ section: TeleprompterSection, index: Int) -> some View {
        HStack(spacing: 6) {
            // Number keys 1-9 jump to the first nine sections.
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: fontSize * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: fontSize * 0.6)
            }
            let isCovered = coveredSectionIndices.contains(index)
            Text(section.title)
                .font(.system(size: fontSize * 0.62, weight: .bold))
                .foregroundStyle(section.mustCover && isCovered ? Color.green : .secondary)
            if section.mustCover {
                Image(systemName: isCovered ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: fontSize * 0.4))
                    .foregroundStyle(isCovered ? .green : .secondary)
                    .help(Text(isCovered
                               ? String(localized: "Covered")
                               : String(localized: "You meant to cover this section")))
                    .animation(.easeOut(duration: 0.25), value: isCovered)
            }
            if let target = section.targetDuration {
                Text(Self.durationText(target))
                    .font(.system(size: fontSize * 0.38, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .id("section-\(index)")
    }

    private func wordFlow(for section: TeleprompterSection) -> some View {
        // A single concatenated `Text` wraps correctly and keeps per-word colour,
        // which a stack of `Text` views would not.
        section.tokenRange.reduce(Text("")) { partial, tokenIndex in
            let token = script.tokens[tokenIndex]
            let styled = Text(token.display + " ")
                .foregroundColor(color(for: tokenIndex))
            return partial + styled
        }
        .font(resolvedFont)
        .lineSpacing(fontSize * 0.35)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One anchor per section keeps the scroll target list small; within a
        // section the flowing text scrolls naturally.
        .id(anchorID(for: section.tokenRange.lowerBound))
    }

    /// Read words recede, the current one leads, the rest wait.
    private func color(for tokenIndex: Int) -> Color {
        if tokenIndex < confirmedTokenIndex { return .secondary.opacity(0.45) }
        if tokenIndex == confirmedTokenIndex { return .accentColor }
        return .primary
    }

    private var resolvedFont: Font {
        switch fontChoice {
        case .system:
            return .system(size: fontSize, weight: .medium)
        case .highLegibility:
            // The accessible default, since Atoll cannot ship OpenDyslexic.
            return .system(size: fontSize, weight: .medium, design: .rounded)
        case .openDyslexic:
            if let family = fontChoice.requiredFamilyName, NSFont(name: family, size: fontSize) != nil {
                return .custom(family, size: fontSize)
            }
            return .system(size: fontSize, weight: .medium, design: .rounded)
        case .custom:
            guard !customFontFamily.isEmpty, NSFont(name: customFontFamily, size: fontSize) != nil else {
                return .system(size: fontSize, weight: .medium)
            }
            return .custom(customFontFamily, size: fontSize)
        }
    }

    /// Scroll anchors are per section, so the id is the section's first token.
    private func anchorID(for tokenIndex: Int) -> String {
        guard script.tokens.indices.contains(tokenIndex) else { return "token-0" }
        let sectionIndex = script.tokens[tokenIndex].sectionIndex
        guard script.sections.indices.contains(sectionIndex) else { return "token-0" }
        return "token-\(script.sections[sectionIndex].tokenRange.lowerBound)"
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return "\(minutes):" + (seconds < 10 ? "0\(seconds)" : "\(seconds)")
    }
}
