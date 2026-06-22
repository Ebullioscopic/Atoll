/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import AppKit
import Defaults
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Thin coordinator that bridges the WhatsApp settings toggle with
/// `WhatsAppWebEngine`. All message interception and reply-sending
/// is handled by the engine; this class only manages lifecycle.
@MainActor
public final class WhatsAppManager: ObservableObject {
    public static let shared = WhatsAppManager()

    static let previewChatId = "__atoll_whatsapp_preview__"

    /// Mirrors the engine's auth state so the Settings UI can bind to it.
    @Published public var authState: WAAuthState = .idle

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Mirror engine state
        WhatsAppWebEngine.shared.$authState
            .receive(on: RunLoop.main)
            .assign(to: &$authState)

        // React to enable/disable toggle
        Defaults.publisher(.whatsAppEnabled, options: [.initial])
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] change in
                self?.handleEnabledChange(change.newValue)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public

    public func sendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        WhatsAppWebEngine.shared.sendReply(chatId: chatId, text: text, completion: completion)
    }

    public func selectPollOption(
        chatId: String,
        messageId: String,
        questionText: String,
        selectedOptionTexts: [String],
        optionText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        WhatsAppWebEngine.shared.selectPollOption(
            chatId: chatId,
            messageId: messageId,
            questionText: questionText,
            selectedOptionTexts: selectedOptionTexts,
            optionText: optionText,
            completion: completion
        )
    }

    public func sendDocument(chatId: String, fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        WhatsAppWebEngine.shared.sendDocument(chatId: chatId, fileURL: fileURL, completion: completion)
    }

    public func downloadDocument(
        chatId: String,
        messageId: String,
        fileName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        WhatsAppWebEngine.shared.downloadDocument(
            chatId: chatId,
            messageId: messageId,
            fileName: fileName,
            completion: completion
        )
    }

    /// Invia un documento con didascalia opzionale (un solo messaggio in chat).
    public func sendDocumentWithText(
        chatId: String,
        fileURL: URL,
        messageText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let maxBytes = 24 * 1024 * 1024
        if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxBytes {
            completion(.failure(NSError(
                domain: "WhatsAppManager",
                code: 9010,
                userInfo: [NSLocalizedDescriptionKey:
                    "Il file è troppo grande (\(size / (1024 * 1024)) MB). Max 24 MB."]
            )))
            return
        }

        WhatsAppWebEngine.shared.sendDocumentWithText(
            chatId: chatId,
            fileURL: fileURL,
            caption: messageText,
            completion: completion
        )
    }

    /// Apre il file picker nativo di macOS (NSOpenPanel) e restituisce il file selezionato.
    /// `runModal()` è più affidabile di `begin` in una UI borderless/offscreen.
    public func pickDocumentURL(completion: @escaping (Result<URL, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Scegli un documento da inviare"
        panel.prompt = "Invia"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        panel.treatsFilePackagesAsDirectories = false

        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            completion(.failure(NSError(
                domain: "WhatsAppManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Selezione annullata"]
            )))
            return
        }

        let maxBytes = 24 * 1024 * 1024
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           size > maxBytes {
            completion(.failure(NSError(
                domain: "WhatsAppManager",
                code: 9010,
                userInfo: [NSLocalizedDescriptionKey:
                    "Il file è troppo grande (\(size / (1024 * 1024)) MB). Max 24 MB."]
            )))
            return
        }

        completion(.success(url))
    }

    /// Apre il file picker nativo di macOS (NSOpenPanel) e, una volta scelto un file,
    /// lo invia al chat indicato passando attraverso `WhatsAppWebEngine`.
    public func pickAndSendDocument(
        chatId: String,
        completion: ((Result<URL, Error>) -> Void)? = nil
    ) {
        pickDocumentURL { result in
            switch result {
            case .success(let url):
                WhatsAppWebEngine.shared.sendDocument(chatId: chatId, fileURL: url) { result in
                    switch result {
                    case .success:
                        completion?(.success(url))
                    case .failure(let error):
                        completion?(.failure(error))
                    }
                }
            case .failure(let error):
                completion?(.failure(error))
            }
        }
    }

    public func connectWhatsApp() {
        WhatsAppQRWindowManager.shared.show()
    }

    public func disconnect() {
        WhatsAppWebEngine.shared.disconnect {}
    }

    /// Shows a sample WhatsApp notification in the Dynamic Island for animation and layout testing.
    public func showPreviewNotification() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let previewType: SneakContentType = .whatsApp(
            senderName: "Atoll Preview",
            messages: [
                WhatsAppIncomingMessage(text: "Notifica di prova: tocca per rispondere e attendi per chiudere.")
            ],
            chatId: Self.previewChatId,
            avatarUrl: nil
        )

        coordinator.cancelExpandingViewHide()

        if coordinator.expandingView.show,
           case .whatsApp(_, _, let chatId, _) = coordinator.expandingView.type,
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
            WhatsAppWebEngine.shared.start()
        } else {
            WhatsAppWebEngine.shared.stop()
        }
    }
}
