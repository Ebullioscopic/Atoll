/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import Foundation
import SwiftUI

/// A messaging service the notch can show and answer messages for.
///
/// The card, its reply box, its reactions and the whole expanding-view shell
/// are the same piece of work whichever service delivered the message, so they
/// take one of these rather than each service growing a copy of the UI. What
/// differs is the branding, what the service can actually do, and which engine
/// carries an action back to the web app.
enum ChatService: String, CaseIterable, Identifiable, Defaults.Serializable {
    case whatsApp
    case telegram

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whatsApp: return "WhatsApp"
        case .telegram: return "Telegram"
        }
    }

    /// The asset catalog image used as the service badge on the card.
    var assetName: String {
        switch self {
        case .whatsApp: return "WhatsApp"
        case .telegram: return "Telegram"
        }
    }

    /// The service's own colour, used for links, the send button and the
    /// reaction highlight.
    var accent: Color {
        switch self {
        case .whatsApp: return Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)
        case .telegram: return Color(red: 42 / 255, green: 171 / 255, blue: 238 / 255)
        }
    }

    /// The badge's fill, dark enough for the white glyph to hold up on it.
    var badgeGradient: [Color] {
        switch self {
        case .whatsApp:
            return [
                Color(red: 0.12, green: 0.55, blue: 0.34),
                Color(red: 0.05, green: 0.38, blue: 0.24)
            ]
        case .telegram:
            return [
                Color(red: 0.16, green: 0.63, blue: 0.88),
                Color(red: 0.07, green: 0.43, blue: 0.69)
            ]
        }
    }

    /// The chat id the settings preview card is shown under, which is never a
    /// real chat -- the card checks for it to keep its buttons inert.
    var previewChatId: String {
        switch self {
        case .whatsApp: return WhatsAppManager.previewChatId
        case .telegram: return TelegramManager.previewChatId
        }
    }

    /// The engine that carries a reply, a reaction or a download back to the
    /// service.
    @MainActor
    var provider: ChatMessagingProvider {
        switch self {
        case .whatsApp: return WhatsAppManager.shared
        case .telegram: return TelegramManager.shared
        }
    }

    /// Whether a message can be reacted to from the card.
    ///
    /// Telegram's web client puts reactions behind a hover menu on the message
    /// itself, which means opening the conversation and finding the bubble --
    /// a great deal of driving somebody else's UI for one emoji, and it breaks
    /// the moment they move a button. The card leaves reactions to Telegram.
    var supportsReactions: Bool {
        switch self {
        case .whatsApp: return true
        case .telegram: return false
        }
    }

    /// Polls are a WhatsApp feature. Telegram has them too, but its web client
    /// votes through a different surface than the one this reads, so the card
    /// shows the options without offering to vote.
    var supportsPollVoting: Bool {
        switch self {
        case .whatsApp: return true
        case .telegram: return false
        }
    }

    /// Whether a file can be attached to a reply.
    var supportsSendingDocuments: Bool {
        switch self {
        case .whatsApp: return true
        case .telegram: return false
        }
    }
}

/// What the card needs of a service to answer a message.
///
/// Every action is optional in effect: a service that cannot do one reports
/// failure rather than pretending, and `ChatService` says up front which
/// affordances to draw at all.
@MainActor
protocol ChatMessagingProvider {
    func sendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void)

    func reactToMessage(
        chatId: String,
        messageId: String,
        messageText: String,
        reaction: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func selectPollOption(
        chatId: String,
        messageId: String,
        questionText: String,
        selectedOptionTexts: [String],
        optionText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )

    func downloadDocument(
        chatId: String,
        messageId: String,
        fileName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    )

    func sendDocumentWithText(
        chatId: String,
        fileURL: URL,
        messageText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

/// The failure a provider reports when the card offers something the service
/// does not do. Reaching this is a bug in what the card chose to draw, not a
/// state the user should ever be shown.
enum ChatProviderError: LocalizedError {
    case unsupported(ChatService, String)

    var errorDescription: String? {
        switch self {
        case let .unsupported(service, action):
            return "\(service.displayName) cannot \(action) from here."
        }
    }
}
