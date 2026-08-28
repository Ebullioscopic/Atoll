//
//  SmartReplyManager.swift
//  DynamicIsland
//
//  Suggested replies for notch messages, generated on device by Apple
//  Intelligence.
//

import Foundation
import Combine

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Why suggestions are not on offer right now.
///
/// Worth distinguishing rather than collapsing to a bool: "your Mac is too
/// old" and "the model is still downloading" want different words in the
/// settings pane, and only one of them is worth waiting for.
enum SmartReplyAvailability: Equatable {
    case ready
    /// Built for a system without the framework at all.
    case unsupportedOS
    /// Apple Intelligence is off in System Settings.
    case notEnabled
    /// On, but the model has not finished downloading.
    case modelNotReady
    /// Available in principle, refused for this device or region.
    case unavailable(String)

    var isReady: Bool { self == .ready }
}

@MainActor
final class SmartReplyManager: ObservableObject {
    static let shared = SmartReplyManager()

    /// Re-read rather than cached: Apple Intelligence can finish downloading,
    /// or be switched off, while Atoll is running, and a settings pane that
    /// answered once at launch would keep saying the wrong thing.
    @Published private(set) var availability: SmartReplyAvailability = .unsupportedOS

    private init() {
        refreshAvailability()
    }

    func refreshAvailability() {
        availability = Self.currentAvailability()
    }

    private static func currentAvailability() -> SmartReplyAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *) else { return .unsupportedOS }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable(let other):
            return .unavailable(String(describing: other))
        @unknown default:
            return .unavailable("unknown")
        }
        #else
        return .unsupportedOS
        #endif
    }

    /// Three short replies to `message`, or an empty array if the model is not
    /// available or declines. Never throws at the call site: a notch that
    /// cannot suggest anything should simply not offer suggestions.
    func suggestions(for message: String, from sender: String?) async -> [String] {
        #if canImport(FoundationModels)
        guard #available(macOS 26, *), availability.isReady else { return [] }
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let who = sender.map { "from \($0)" } ?? "from a contact"
        let session = LanguageModelSession(instructions: """
            You suggest short replies to chat messages. Each reply is something \
            the user could send as-is: one sentence at most, casual, no \
            greeting, no sign-off, no quotation marks. Offer three that differ \
            in intent rather than in wording -- for a question, that usually \
            means yes, no, and a deferral.
            """)

        do {
            let reply = try await session.respond(
                to: "Suggest replies to this message \(who): \(message)",
                generating: SmartReplySuggestions.self
            )
            return reply.content.replies
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } catch {
            // A refusal (guardrails, a message the model won't touch) is a
            // normal outcome here, not a fault to surface.
            return []
        }
        #else
        return []
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct SmartReplySuggestions {
    @Guide(description: "Three replies the user could send as-is, each at most one sentence.", .count(3))
    var replies: [String]
}
#endif
