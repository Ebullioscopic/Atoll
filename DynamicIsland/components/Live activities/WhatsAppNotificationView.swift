/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import Defaults
import AppKit
import UniformTypeIdentifiers

// MARK: - Layout (original WhatsApp notification dimensions)

enum WhatsAppNotificationLayout {
    static let width: CGFloat = 420

    static func contentHeight(isReplying: Bool, hasFilePreview: Bool) -> CGFloat {
        guard isReplying else { return 98 }
        return hasFilePreview ? 188 : 148
    }

    static func topOffset(isDynamicIslandMode: Bool, closedNotchHeight: CGFloat) -> CGFloat {
        isDynamicIslandMode ? 0 : closedNotchHeight
    }

    static func totalSize(
        isReplying: Bool,
        hasFilePreview: Bool,
        isDynamicIslandMode: Bool,
        closedNotchHeight: CGFloat
    ) -> CGSize {
        let height = contentHeight(isReplying: isReplying, hasFilePreview: hasFilePreview)
            + topOffset(isDynamicIslandMode: isDynamicIslandMode, closedNotchHeight: closedNotchHeight)
        return CGSize(width: width, height: height)
    }

    static func bottomCornerRadius(isReplying: Bool) -> CGFloat {
        isReplying ? 36 : 24
    }
}

private struct WhatsAppHUDMetrics {
    let width: CGFloat
    let height: CGFloat
    let topOffset: CGFloat
    let bottomRadius: CGFloat
}

private enum WhatsAppHUDMetricsFactory {
    static func make(
        closedNotchHeight: CGFloat,
        isReplying: Bool,
        hasFilePreview: Bool,
        isDynamicIslandMode: Bool
    ) -> WhatsAppHUDMetrics {
        let topOffset = WhatsAppNotificationLayout.topOffset(
            isDynamicIslandMode: isDynamicIslandMode,
            closedNotchHeight: closedNotchHeight
        )
        return WhatsAppHUDMetrics(
            width: WhatsAppNotificationLayout.width,
            height: WhatsAppNotificationLayout.contentHeight(isReplying: isReplying, hasFilePreview: hasFilePreview) + topOffset,
            topOffset: topOffset,
            bottomRadius: WhatsAppNotificationLayout.bottomCornerRadius(isReplying: isReplying)
        )
    }
}

// MARK: - Shell (battery-style expanding view)

struct WhatsAppTemporaryActivityView: View {
    let senderName: String
    let messageText: String
    let chatId: String
    let avatarUrl: String?
    @Binding var isReplying: Bool
    let closedNotchHeight: CGFloat
    let isDynamicIslandMode: Bool
    let topCornerRadius: CGFloat

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    private var metrics: WhatsAppHUDMetrics {
        WhatsAppHUDMetricsFactory.make(
            closedNotchHeight: closedNotchHeight,
            isReplying: isReplying,
            hasFilePreview: coordinator.isWhatsAppFilePreviewVisible,
            isDynamicIslandMode: isDynamicIslandMode
        )
    }

    private var surfaceShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(DynamicIslandPillShape(cornerRadius: dynamicIslandPillCornerRadiusInsets.opened))
        }
        return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: metrics.bottomRadius))
    }

    var body: some View {
        WhatsAppNotificationView(
            senderName: senderName,
            messageText: messageText,
            chatId: chatId,
            avatarUrl: avatarUrl,
            isReplying: $isReplying
        )
        .padding(.top, metrics.topOffset)
        .frame(width: metrics.width, height: metrics.height, alignment: .top)
        .clipShape(surfaceShape)
    }
}

// MARK: - Content

struct WhatsAppNotificationView: View {
    let senderName: String
    let messageText: String
    let chatId: String
    let avatarUrl: String?

    @Binding var isReplying: Bool

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var sendSuccess: Bool = false
    @State private var sendErrorText: String?
    @FocusState private var isInputFocused: Bool

    private var isPreview: Bool { chatId == WhatsAppManager.previewChatId }
    private var sanitizedMessageText: String {
        let cleaned = messageText
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return "📨 Nuovo messaggio"
        }
        return cleaned
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            if isReplying {
                replySection
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .offset(y: -8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(senderName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text("now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .opacity(isReplying ? 0 : 1)
                }

                Text(sanitizedMessageText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )

            Circle()
                .fill(Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "message.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(3.5)
                )
                .offset(x: 2, y: 2)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.55, blue: 0.34),
                        Color(red: 0.05, green: 0.38, blue: 0.24)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(senderName.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    @ViewBuilder
    private var replySection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)

            Group {
                if isSending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Sending...")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                } else if sendSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255))
                            .font(.system(size: 14))
                        Text("Sent")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255))
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if let sendErrorText {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.system(size: 11))
                                Text(sendErrorText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Add message...", text: $replyText)
                                .textFieldStyle(.plain)
                                .focused($isInputFocused)
                                .onSubmit { sendMessage() }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                                )
                                .onChange(of: replyText) { _, _ in
                                    if sendErrorText != nil {
                                        sendErrorText = nil
                                    }
                                }

                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        canSendMessage
                                            ? Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)
                                            : Color.white.opacity(0.28)
                                    )
                                    .frame(width: 32, height: 32)
                                    .background(
                                        canSendMessage
                                            ? Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255).opacity(0.18)
                                            : Color.clear
                                    )
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSendMessage)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .onAppear {
                // Defer focus to the next run loop so the first reply expansion
                // keeps a stable top anchor instead of re-laying out mid-frame.
                DispatchQueue.main.async {
                    guard isReplying else { return }
                    isInputFocused = true
                }
            }
        }
    }

    private func dismissNotification() {
        isReplying = false
        coordinator.suppressWhatsAppAutoDismiss = false
        DynamicIslandViewCoordinator.shared.toggleExpandingView(
            status: false,
            type: .whatsApp(
                senderName: senderName,
                messageText: messageText,
                chatId: chatId,
                avatarUrl: avatarUrl
            )
        )
    }

    private var canSendMessage: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginWhatsAppInteraction() {
        coordinator.suppressWhatsAppAutoDismiss = true
        coordinator.cancelExpandingViewHide()
    }

    private func endWhatsAppInteraction() {
        coordinator.suppressWhatsAppAutoDismiss = false
    }

    private func sendMessage() {
        guard !isSending else { return }
        guard canSendMessage else { return }
        guard !isPreview else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                sendSuccess = true
                replyText = ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    dismissNotification()
                }
            }
            return
        }

        sendErrorText = nil
        sendSuccess = false
        beginWhatsAppInteraction()

        isSending = true
        let replyToSend = replyText
        
        WhatsAppManager.shared.sendReply(chatId: chatId, text: replyToSend) { result in
            DispatchQueue.main.async {
                endWhatsAppInteraction()
                isSending = false
                switch result {
                case .success:
                    replyText = ""
                    sendSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismissNotification()
                    }
                case .failure(let error):
                    print("Error sending WhatsApp reply: \(error.localizedDescription)")
                    sendSuccess = false
                    sendErrorText = "Invio fallito, riprova"
                }
            }
        }
    }
}
