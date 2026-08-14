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

import Foundation

/// How much Atoll trusts a context-window size.
///
/// Surfaced in the UI: an `assumed` window is not shown as a percentage, because
/// a confident-looking ring built on a guess is worse than an honest number.
enum ContextWindowConfidence: String, Codable, Sendable {
    /// Derived from tokens actually observed in the transcript. Cannot be wrong
    /// in the direction that matters — the window is at least this big.
    case observed
    /// Recognised model identifier.
    case table
    /// Fell back to the agent's default.
    case assumed
}

struct ContextWindow: Equatable, Sendable {
    let tokens: Int
    let confidence: ContextWindowConfidence
}

/// Works out how large an agent session's context window is.
///
/// ## Why the model identifier is not enough
/// Measured on a real Claude Code transcript: model `claude-opus-5`, context
/// `2 + 558 + 511_471 = 512_031` tokens. The identifier carries **no** `[1m]`
/// marker even though the session plainly has a 1M window, so any rule that
/// reads only the model string reports 512k/200k — a 256% "full" ring.
///
/// So observation wins: if a session has demonstrably held more tokens than a
/// tier allows, the window is promoted to the next tier. That is self-correcting
/// and can only err on the side of showing a session as *emptier* than it is,
/// never fuller.
///
/// Pure and total; the unit-tested seam for the context ring.
enum ContextWindowResolver {
    /// Known window sizes, ascending. A session is assigned the smallest tier
    /// that can contain what has been observed.
    static let tiers = [200_000, 400_000, 1_000_000]

    /// Fraction at which the ring turns amber, then red. The red threshold sits
    /// just below where Claude Code starts auto-compacting, which is the point a
    /// user actually wants to know about.
    static let amberThreshold = 0.70
    static let redThreshold = 0.90

    /// - Parameters:
    ///   - model: model identifier from the transcript, if any.
    ///   - observedTokens: the largest context this session has been seen to
    ///     hold, not just its current size. Context collapses after a compaction,
    ///     so the running maximum is what identifies the window.
    ///   - kind: used only for the final fallback.
    static func resolve(model: String?, observedTokens: Int, kind: AgentKind) -> ContextWindow {
        // An explicit long-context marker is definitive.
        if let model, hasLongContextMarker(model) {
            return ContextWindow(tokens: 1_000_000, confidence: .table)
        }

        let tabled = tabledWindow(for: model) ?? kind.defaultContextWindow
        let confidence: ContextWindowConfidence = tabledWindow(for: model) == nil ? .assumed : .table

        // Observation beats every guess.
        guard observedTokens > tabled else {
            return ContextWindow(tokens: tabled, confidence: confidence)
        }
        if let promoted = tiers.first(where: { $0 >= observedTokens }) {
            return ContextWindow(tokens: promoted, confidence: .observed)
        }
        // Past the largest known tier: round the observation up to a whole
        // million so the ring stays meaningful rather than pinned at 100%.
        let millions = (observedTokens + 999_999) / 1_000_000
        return ContextWindow(tokens: millions * 1_000_000, confidence: .observed)
    }

    /// `claude-opus-5[1m]`, `...-1m`, `...:1m`.
    static func hasLongContextMarker(_ model: String) -> Bool {
        let lowered = model.lowercased()
        return lowered.contains("[1m]") || lowered.hasSuffix("-1m") || lowered.hasSuffix(":1m")
            || lowered.contains("-1m-") || lowered.contains("[1m")
    }

    /// Windows for identifiers Atoll recognises. Deliberately conservative: a
    /// wrong small number is corrected by observation on the next refresh, while a
    /// wrong large one would understate a nearly-full session.
    static func tabledWindow(for model: String?) -> Int? {
        guard let model, !model.isEmpty else { return nil }
        let lowered = model.lowercased()
        if lowered.hasPrefix("claude-") { return 200_000 }
        if lowered.contains("gpt-5") || lowered.hasPrefix("o3") || lowered.hasPrefix("o4") { return 272_000 }
        if lowered.contains("gemini") { return 1_000_000 }
        if lowered.contains("qwen") { return 1_000_000 }
        return nil
    }

    /// Whether a percentage should be shown at all. An assumed window with a
    /// small reading has not yet had a chance to be corrected by observation, so
    /// the raw count is the honest thing to display.
    static func shouldShowFraction(_ window: ContextWindow, usedTokens: Int) -> Bool {
        guard window.confidence == .assumed else { return true }
        return usedTokens >= 150_000
    }
}
