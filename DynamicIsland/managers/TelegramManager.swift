/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Bridges the Telegram settings toggle to `TelegramWebEngine`, and is what the
/// notification card talks to when it has a reply to send.
///
/// The engine does the work; this owns the lifecycle and answers for the things
/// Telegram's web client will not let a reply do from here, so the card gets a
/// clear refusal rather than a silent failure.
@MainActor
public final class TelegramManager: ObservableObject, ChatMessagingProvider {
    public static let shared = TelegramManager()

    static let previewChatId = "__atoll_telegram_preview__"

    /// Mirrors the engine's state so Settings can bind to it.
    @Published public var authState: TelegramAuthState = .idle

    private var cancellables = Set<AnyCancellable>()

    private init() {
        TelegramWebEngine.shared.$authState
            .receive(on: RunLoop.main)
            .assign(to: &$authState)

        Defaults.publisher(.telegramEnabled, options: [.initial])
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] change in
                self?.handleEnabledChange(change.newValue)
            }
            .store(in: &cancellables)
    }

    // MARK: - ChatMessagingProvider

    public func sendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        TelegramWebEngine.shared.sendReply(chatId: chatId, text: text, completion: completion)
    }

    public func reactToMessage(
        chatId: String,
        messageId: String,
        messageText: String,
        reaction: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.failure(ChatProviderError.unsupported(.telegram, "react to a message")))
    }

    public func selectPollOption(
        chatId: String,
        messageId: String,
        questionText: String,
        selectedOptionTexts: [String],
        optionText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.failure(ChatProviderError.unsupported(.telegram, "vote in a poll")))
    }

    public func downloadDocument(
        chatId: String,
        messageId: String,
        fileName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        completion(.failure(ChatProviderError.unsupported(.telegram, "download an attachment")))
    }

    public func sendDocumentWithText(
        chatId: String,
        fileURL: URL,
        messageText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        completion(.failure(ChatProviderError.unsupported(.telegram, "send a file")))
    }

    // MARK: - Connection

    public func connect() {
        TelegramSignInWindowManager.shared.show()
    }

    public func disconnect() {
        TelegramWebEngine.shared.disconnect {}
    }

    /// Puts a sample card in the notch, so the layout and the animation can be
    /// looked at without waiting for somebody to write.
    public func showPreviewNotification() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let previewType: SneakContentType = .chat(
            service: .telegram,
            senderName: "Atoll Preview",
            messages: [ChatIncomingMessage(text: "Test notification: click to reply, or wait for it to close.")],
            chatId: Self.previewChatId,
            avatarUrl: nil
        )

        coordinator.cancelExpandingViewHide()

        // Already showing this same preview: take it down first, so the card
        // plays its arrival again rather than silently swapping its contents.
        if coordinator.expandingView.show,
           case .chat(_, _, _, let chatId, _) = coordinator.expandingView.type,
           chatId == Self.previewChatId {
            coordinator.toggleExpandingView(status: false, type: previewType)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.showPreviewNotification()
            }
            return
        }

        coordinator.toggleExpandingView(status: true, type: previewType, autoHideDuration: 15)
    }

    // MARK: - Private

    private func handleEnabledChange(_ enabled: Bool) {
        if enabled {
            TelegramWebEngine.shared.start()
        } else {
            TelegramWebEngine.shared.stop()
        }
    }
}
