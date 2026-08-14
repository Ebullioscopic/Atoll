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
import Foundation

/// One of the AI coding agent CLIs Agent Tower can observe.
///
/// The raw value is the `agent=` query parameter the generated hook shim passes
/// back to Atoll, so it is part of the on-disk hook contract: renaming a case
/// silently orphans every hook already installed in a user's config.
enum AgentKind: String, CaseIterable, Codable, Defaults.Serializable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case geminiCLI
    case qwenCode
    case opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .geminiCLI: return "Gemini CLI"
        case .qwenCode: return "Qwen Code"
        case .opencode: return "opencode"
        }
    }

    var iconSymbolName: String {
        switch self {
        case .claudeCode: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .geminiCLI: return "diamond"
        case .qwenCode: return "cube"
        case .opencode: return "shippingbox"
        }
    }

    /// Default context window, in tokens, when the transcript does not name a model.
    var defaultContextWindow: Int {
        switch self {
        case .claudeCode: return 200_000
        case .codex: return 272_000
        case .cursor: return 200_000
        case .geminiCLI, .qwenCode: return 1_000_000
        case .opencode: return 200_000
        }
    }

    /// Agents Atoll can install hooks into. `opencode` drives customisation through
    /// JavaScript plugins rather than a hook config, so there is nothing to merge.
    var supportsHookInstallation: Bool {
        self != .opencode
    }
}
