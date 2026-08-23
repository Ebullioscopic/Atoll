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
import PDFKit

// MARK: - Layout

enum ChatNotificationLayout {
    static let width: CGFloat = 420
    private static let textMeasurementWidth: CGFloat = 332
    /// The card is a notification, not a reader: past this many lines a
    /// message is truncated rather than allowed to push the card past the
    /// height measured for it. The measurement clamps to the same number, so
    /// what is drawn is always what was reserved.
    static let maxTextLines: Int = 6
    private static let textLineHeight: CGFloat = 15
    private static let notificationTopPadding: CGFloat = 14
    private static let notificationBottomPadding: CGFloat = 10

    static func contentHeight(
        isReplying: Bool,
        hasFilePreview: Bool,
        messages: [ChatIncomingMessage]
    ) -> CGFloat {
        let messagesHeight = messages.reduce(CGFloat.zero) { total, message in
            total + messageHeight(message) + (total > 0 ? 4 : 0)
        }
        // 17 for the name row, then the 5pt gap the VStack actually uses --
        // measuring a smaller gap than is drawn is how the card ended up
        // shorter than its own contents.
        let headerContentHeight = max(38, 17 + (messagesHeight > 0 ? 5 + messagesHeight : 0))
        let headerHeight = 12 + headerContentHeight
        let replyHeight: CGFloat = isReplying ? 44 : 0
        let filePreviewHeight: CGFloat = hasFilePreview ? 40 : 0
        return max(isReplying ? 96 : 56, headerHeight + replyHeight + filePreviewHeight)
    }

    private static func messageHeight(_ message: ChatIncomingMessage) -> CGFloat {
        var height: CGFloat = 0
        let text = cleanedText(message.text)
        if shouldMeasureText(text, for: message) || cleanedText(message.groupSender ?? "").isEmpty == false {
            let measuredText = measuredMessageText(message)
            height += measuredTextHeight(measuredText, isEmojiOnly: isEmojiOnly(text))
        }
        if let linkPreview = message.linkPreview {
            height += (height > 0 ? 5 : 0) + (linkPreview.appleMapsUrl == nil ? 56 : 76)
        }
        if message.documentPreview != nil {
            height += (height > 0 ? 5 : 0) + 58
        }
        if message.mediaDataUrl != nil || message.mediaKind != nil {
            height += (height > 0 ? 5 : 0) + (message.mediaKind == .sticker ? 58 : 66)
        }
        if !message.pollOptions.isEmpty {
            height += (height > 0 ? 6 : 0) + 18 + CGFloat(message.pollOptions.count) * 39 + 8
        }
        return max(17, height)
    }

    private static func shouldMeasureText(_ text: String, for message: ChatIncomingMessage) -> Bool {
        guard !text.isEmpty else { return false }
        if isLikelyInlineMediaPayload(text) {
            return false
        }
        if let document = message.documentPreview {
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedFileName = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedText == normalizedFileName || normalizedText.hasPrefix(normalizedFileName) {
                return false
            }
        }
        if message.mediaDataUrl != nil || message.mediaKind != nil {
            let lowered = text.lowercased()
            let mediaOnlyLabels: Set<String> = ["sticker", "adesivo", "immagine", "image", "photo", "foto", "video", "gif", "📨 nuovo messaggio"]
            return !mediaOnlyLabels.contains(lowered)
        }
        return true
    }

    fileprivate static func isLikelyInlineMediaPayload(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 180 else { return false }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("data:image/") || lowercased.hasPrefix("data:video/") {
            return true
        }
        if trimmed.hasPrefix("/9j/") || trimmed.hasPrefix("iVBOR") || trimmed.hasPrefix("R0lGOD") || trimmed.hasPrefix("UklGR") {
            return true
        }
        let sample = trimmed.prefix(240)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=\r\n")
        return sample.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func measuredMessageText(_ message: ChatIncomingMessage) -> String {
        let text = cleanedText(message.text)
        let groupSender = cleanedText(message.groupSender ?? "")
        guard !groupSender.isEmpty else { return text }
        return text.isEmpty ? "\(groupSender):" : "\(groupSender): \(text)"
    }

    private static func measuredTextHeight(_ text: String, isEmojiOnly: Bool) -> CGFloat {
        let cleaned = cleanedText(text)
        guard !cleaned.isEmpty else { return isEmojiOnly ? 19 : 17 }
        if isEmojiOnly { return 19 }

        let font = NSFont.systemFont(ofSize: 12.5)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph
        ]
        let boundingRect = (cleaned as NSString).boundingRect(
            with: CGSize(width: textMeasurementWidth, height: CGFloat(maxTextLines) * textLineHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        return max(17, min(ceil(boundingRect.height), CGFloat(maxTextLines) * textLineHeight) + 1)
    }

    static func isEmojiOnly(_ text: String) -> Bool {
        let trimmed = cleanedText(text)
        guard !trimmed.isEmpty, trimmed.count <= 6 else { return false }
        let nonEmojiScalars = trimmed.unicodeScalars.filter { scalar in
            !scalar.properties.isEmojiPresentation
                && !scalar.properties.isEmoji
                && scalar.value != 0xFE0F
                && scalar.value != 0x200D
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return nonEmojiScalars.isEmpty
    }

    static func cleanedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func topOffset(isDynamicIslandMode: Bool, closedNotchHeight: CGFloat) -> CGFloat {
        isDynamicIslandMode ? 0 : closedNotchHeight
    }

    static func topContentPadding(isDynamicIslandMode: Bool) -> CGFloat {
        notificationTopPadding
    }

    static func bottomContentPadding(isDynamicIslandMode: Bool) -> CGFloat {
        notificationBottomPadding
    }

    static func totalSize(
        isReplying: Bool,
        hasFilePreview: Bool,
        messages: [ChatIncomingMessage],
        isDynamicIslandMode: Bool,
        closedNotchHeight: CGFloat
    ) -> CGSize {
        let height = contentHeight(
            isReplying: isReplying,
            hasFilePreview: hasFilePreview,
            messages: messages
        )
            + topOffset(isDynamicIslandMode: isDynamicIslandMode, closedNotchHeight: closedNotchHeight)
            + topContentPadding(isDynamicIslandMode: isDynamicIslandMode)
            + bottomContentPadding(isDynamicIslandMode: isDynamicIslandMode)
        return CGSize(width: width, height: height)
    }

    static func bottomCornerRadius(isReplying: Bool) -> CGFloat {
        isReplying ? 36 : 24
    }
}

private struct ChatHUDMetrics {
    let width: CGFloat
    let height: CGFloat
    let topOffset: CGFloat
    let topContentPadding: CGFloat
    let bottomContentPadding: CGFloat
    let bottomRadius: CGFloat
}

private enum ChatHUDMetricsFactory {
    static func make(
        closedNotchHeight: CGFloat,
        isReplying: Bool,
        hasFilePreview: Bool,
        messages: [ChatIncomingMessage],
        isDynamicIslandMode: Bool
    ) -> ChatHUDMetrics {
        let topOffset = ChatNotificationLayout.topOffset(
            isDynamicIslandMode: isDynamicIslandMode,
            closedNotchHeight: closedNotchHeight
        )
        return ChatHUDMetrics(
            width: ChatNotificationLayout.width,
            height: ChatNotificationLayout.contentHeight(
                isReplying: isReplying,
                hasFilePreview: hasFilePreview,
                messages: messages
            )
                + topOffset
                + ChatNotificationLayout.topContentPadding(isDynamicIslandMode: isDynamicIslandMode)
                + ChatNotificationLayout.bottomContentPadding(isDynamicIslandMode: isDynamicIslandMode),
            topOffset: topOffset,
            topContentPadding: ChatNotificationLayout.topContentPadding(isDynamicIslandMode: isDynamicIslandMode),
            bottomContentPadding: ChatNotificationLayout.bottomContentPadding(isDynamicIslandMode: isDynamicIslandMode),
            bottomRadius: ChatNotificationLayout.bottomCornerRadius(isReplying: isReplying)
        )
    }
}

// MARK: - Shell (battery-style expanding view)

struct ChatTemporaryActivityView: View {
    let service: ChatService
    let senderName: String
    let messages: [ChatIncomingMessage]
    let chatId: String
    let avatarUrl: String?
    @Binding var isReplying: Bool
    let closedNotchHeight: CGFloat
    let isDynamicIslandMode: Bool

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    private var metrics: ChatHUDMetrics {
        ChatHUDMetricsFactory.make(
            closedNotchHeight: closedNotchHeight,
            isReplying: isReplying,
            hasFilePreview: coordinator.isChatFilePreviewVisible,
            messages: messages,
            isDynamicIslandMode: isDynamicIslandMode
        )
    }

    var body: some View {
        ChatNotificationView(
            service: service,
            senderName: senderName,
            messages: messages,
            chatId: chatId,
            avatarUrl: avatarUrl,
            isReplying: $isReplying
        )
        .padding(.top, metrics.topOffset + metrics.topContentPadding)
        .padding(.bottom, metrics.bottomContentPadding)
        .frame(width: metrics.width, height: metrics.height, alignment: .top)
    }
}

// MARK: - Content

struct ChatNotificationView: View {
    let service: ChatService
    let senderName: String
    let messages: [ChatIncomingMessage]
    let chatId: String
    let avatarUrl: String?

    @Binding var isReplying: Bool

    @Default(.isWhatsAppAnimEnabled) var isWhatsAppAnimEnabled

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var sendSuccess: Bool = false
    @State private var sendErrorText: String?
    @State private var pollOptionSendingKey: String?
    @State private var documentDownloadKey: String?
    @State private var reactionMessageId: String?
    @State private var reactionSendingKey: String?
    @State private var reactionsByMessageId: [String: String] = [:]
    @State private var reactionPulseMessageId: String?
    @State private var reactionPaletteDismissTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var isPreview: Bool { chatId == service.previewChatId }
    private let quickReactionEmojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    private var visibleMessages: [ChatIncomingMessage] {
        messages.isEmpty ? [ChatIncomingMessage(text: "📨 New message")] : messages
    }

    private func sanitizedText(_ text: String) -> String {
        let cleaned = ChatNotificationLayout.cleanedText(text)
        if cleaned.isEmpty {
            return "📨 New message"
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onDisappear {
            reactionPaletteDismissTask?.cancel()
            reactionPaletteDismissTask = nil
            if reactionMessageId != nil || reactionSendingKey != nil {
                endChatInteraction()
            }
        }
    }

    /// The time against the newest message on the card, as the service wrote
    /// it. A message that came in without one is one that just arrived.
    private var timestampLabel: String {
        let stamp = visibleMessages.last?.timeLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stamp.isEmpty ? "now" : stamp
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView
                .offset(y: -8)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(senderName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    // The time never wraps or shrinks: a long name gives way
                    // to it instead, since half a name still reads as the name
                    // and half a time reads as nothing.
                    Text(timestampLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(isReplying ? 0 : 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleMessages) { message in
                        messageRow(message)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 5)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatIncomingMessage) -> some View {
        let text = sanitizedText(message.text)
        let showBodyText = shouldShowText(text, for: message)
        VStack(alignment: .leading, spacing: 5) {
            if groupSenderName(for: message) != nil || showBodyText {
                messageTextView(
                    text: showBodyText ? text : "",
                    groupSender: groupSenderName(for: message)
                )
            }

            if let linkPreview = message.linkPreview {
                if linkPreview.appleMapsUrl == nil {
                    linkPreviewView(linkPreview)
                } else {
                    mapPreviewView(linkPreview)
                }
            }

            if message.linkPreview == nil, let documentPreview = message.documentPreview {
                documentPreviewView(documentPreview, for: message)
            }

            if message.linkPreview == nil, message.documentPreview == nil, message.mediaKind != nil || message.mediaDataUrl != nil {
                messageMediaView(for: message)
            }

            if !message.pollOptions.isEmpty {
                pollOptionsView(for: message)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45) {
            showReactionPalette(for: message)
        }
        .overlay(alignment: .topTrailing) {
            if reactionMessageId == message.id {
                reactionPalette(for: message)
                    .offset(x: -2, y: -6)
                    .transition(.scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let reaction = reactionsByMessageId[message.id] {
                reactionBadge(reaction, isSending: reactionSendingKey?.hasPrefix("\(message.id)|") == true)
                    .offset(x: 4, y: -8)
                    .scaleEffect(reactionPulseMessageId == message.id ? 1.24 : 1.0)
                    .transition(.scale(scale: 0.2, anchor: .center).combined(with: .opacity))
                    .zIndex(10)
            }
        }
    }

    @ViewBuilder
    private func messageTextView(text: String, groupSender: String?) -> some View {
        let isEmojiOnly = ChatNotificationLayout.isEmojiOnly(text)
        Text(linkifiedMessageText(sender: groupSender, text: text, isEmojiOnly: isEmojiOnly))
            .lineLimit(isEmojiOnly ? 1 : ChatNotificationLayout.maxTextLines)
            .truncationMode(.tail)
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func linkifiedMessageText(sender: String?, text: String, isEmojiOnly: Bool) -> AttributedString {
        let baseColor = Color.white.opacity(0.62)
        let linkColor = service.accent.opacity(0.92)
        let bodyFont = Font.system(size: isEmojiOnly ? 18 : 12.5)
        let groupBodyFont = Font.system(size: isEmojiOnly ? 16 : 12.5)
        var output = AttributedString()

        if let sender {
            var senderText = AttributedString("\(sender):")
            senderText.font = .system(size: 12.5, weight: .semibold)
            senderText.foregroundColor = baseColor
            output += senderText

            guard !text.isEmpty else { return output }

            var spacer = AttributedString(" ")
            spacer.font = groupBodyFont
            spacer.foregroundColor = baseColor
            output += spacer
        }

        var body = AttributedString(text)
        body.font = sender == nil ? bodyFont : groupBodyFont
        body.foregroundColor = baseColor

        for match in ChatMessageLinkDetector.matches(in: text) {
            guard let lower = AttributedString.Index(match.range.lowerBound, within: body),
                  let upper = AttributedString.Index(match.range.upperBound, within: body) else {
                continue
            }
            body[lower..<upper].link = match.url
            body[lower..<upper].foregroundColor = linkColor
        }

        output += body
        return output
    }

    private func groupSenderName(for message: ChatIncomingMessage) -> String? {
        let trimmed = ChatNotificationLayout.cleanedText(message.groupSender ?? "")
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldShowText(_ text: String, for message: ChatIncomingMessage) -> Bool {
        if ChatNotificationLayout.isLikelyInlineMediaPayload(text) {
            return false
        }
        if let linkPreview = message.linkPreview {
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let previewTexts = [
                linkPreview.url,
                linkPreview.title,
                linkPreview.domain,
                linkPreview.url.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
            ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            if normalizedText.hasPrefix("http://")
                || normalizedText.hasPrefix("https://")
                || normalizedText.hasPrefix("www.")
                || previewTexts.contains(normalizedText) {
                return false
            }
        }
        if let document = message.documentPreview {
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedFileName = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedText == normalizedFileName || normalizedText.hasPrefix(normalizedFileName) {
                return false
            }
        }
        guard message.mediaDataUrl != nil || message.mediaKind != nil else { return true }
        let lowered = text.lowercased()
        let mediaOnlyLabels: Set<String> = ["sticker", "adesivo", "immagine", "image", "photo", "foto", "video", "gif", "📨 nuovo messaggio"]
        return !mediaOnlyLabels.contains(lowered)
    }

    @ViewBuilder
    private func linkPreviewView(_ preview: ChatIncomingLinkPreview) -> some View {
        HStack(spacing: 9) {
            Group {
                if let dataUrl = preview.imageDataUrl,
                   let image = imageFromDataUrl(dataUrl) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay {
                            Image(systemName: "link")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(preview.domain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: 300, minHeight: 56, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay {
            SecondaryClickCapture {
                openLinkPreview(preview)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openLinkPreview(preview)
        }
    }

    @ViewBuilder
    private func mapPreviewView(_ preview: ChatIncomingLinkPreview) -> some View {
        HStack(spacing: 9) {
            Group {
                if let dataUrl = preview.imageDataUrl,
                   let image = imageFromDataUrl(dataUrl) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    DefaultMapPreviewThumbnail()
                }
            }
            .frame(width: 70, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(preview.domain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                openAppleMaps(preview)
            } label: {
                Image(systemName: "map.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.86))
                    .frame(width: 30, height: 30)
                    .background(service.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Apri in Mappe")
        }
        .padding(6)
        .frame(maxWidth: 322, minHeight: 66, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay {
            SecondaryClickCapture {
                openAppleMaps(preview)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openAppleMaps(preview)
        }
    }

    @ViewBuilder
    private func messageMediaView(for message: ChatIncomingMessage) -> some View {
        let kind = message.mediaKind
        if kind == .sticker,
           let dataUrl = message.mediaDataUrl,
           let payload = dataPayload(from: dataUrl),
           payload.mimeType.lowercased() == "application/x-atoll-lottie+json" {
            ExtensionLottieView(data: payload.data, size: CGSize(width: 76, height: 58))
                .overlay {
                    SecondaryClickCapture {
                        downloadMedia(for: message)
                    }
                }
                .contentShape(Rectangle())
                .help("Tasto destro: scarica")
        } else if let dataUrl = message.mediaDataUrl, let image = imageFromDataUrl(dataUrl) {
            mediaThumbnail(image: image, kind: kind)
                .overlay {
                    SecondaryClickCapture {
                        downloadMedia(for: message)
                    }
                }
                .contentShape(Rectangle())
                .help("Tasto destro: scarica")
        } else {
            HStack(spacing: 6) {
                Image(systemName: mediaPlaceholderIcon(for: kind))
                Text(mediaPlaceholderLabel(for: kind))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.56))
        }
    }

    @ViewBuilder
    private func mediaThumbnail(image: NSImage, kind: ChatIncomingMediaKind?) -> some View {
        let isSticker = kind == .sticker
        let isMotion = kind == .video || kind == .gif
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()

            if isMotion {
                Group {
                    if kind == .gif {
                        Text("GIF")
                            .font(.system(size: 9, weight: .bold))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.58))
                .clipShape(Circle())
            }
        }
        .frame(maxWidth: isSticker ? 76 : 96, maxHeight: isSticker ? 58 : 66, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: isSticker ? 0 : 10, style: .continuous))
    }

    private func mediaPlaceholderIcon(for kind: ChatIncomingMediaKind?) -> String {
        switch kind {
        case .sticker:
            return "face.smiling.inverse"
        case .video, .gif:
            return "play.rectangle"
        case .image, .none:
            return "photo"
        }
    }

    private func mediaPlaceholderLabel(for kind: ChatIncomingMediaKind?) -> String {
        switch kind {
        case .sticker:
            return "Sticker"
        case .video:
            return "Video"
        case .gif:
            return "GIF"
        case .image, .none:
            return "Immagine"
        }
    }

    @ViewBuilder
    private func documentPreviewView(_ document: ChatIncomingDocumentPreview, for message: ChatIncomingMessage) -> some View {
        HStack(spacing: 9) {
            Group {
                if let dataUrl = document.thumbnailDataUrl,
                   let image = imageFromDataUrl(dataUrl) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    DocumentThumbnail(label: documentBadgeLabel(for: document))
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(document.fileName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    Text(document.detail)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)

                    if documentDownloadKey == message.id {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.55)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(maxWidth: 300, minHeight: 56, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .overlay {
            SecondaryClickCapture {
                downloadDocument(document, for: message)
            }
        }
        .contentShape(Rectangle())
        .help("Tasto destro: scarica")
    }

    private func pollOptionsView(for message: ChatIncomingMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(message.pollAllowsMultipleSelection ? "Select one or more options" : "Select an option")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.45))

            ForEach(Array(message.pollOptions.enumerated()), id: \.offset) { _, option in
                Button {
                    selectPollOption(option, for: message)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            pollSelectionIndicator(
                                isSelected: isPollOptionSelected(option, for: message),
                                allowsMultipleSelection: message.pollAllowsMultipleSelection
                            )

                            Text(option.text)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.84))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            if pollOptionSendingKey == "\(message.id)|\(option.id)" {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.55)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentShape(Rectangle())
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .disabled(isPreview || pollOptionSendingKey != nil)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(2)
    }

    @ViewBuilder
    private func pollSelectionIndicator(isSelected: Bool, allowsMultipleSelection: Bool) -> some View {
        let activeColor = service.accent
        ZStack {
            if allowsMultipleSelection {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isSelected ? activeColor : Color.white.opacity(0.46), lineWidth: 1.35)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(activeColor)
                }
            } else {
                Circle()
                    .strokeBorder(isSelected ? activeColor : Color.white.opacity(0.46), lineWidth: 1.35)
                if isSelected {
                    Circle()
                        .fill(activeColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(width: 16, height: 16)
    }

    private func imageFromDataUrl(_ dataUrl: String) -> NSImage? {
        guard let payload = dataPayload(from: dataUrl) else { return nil }
        let metadata = payload.mimeType.lowercased()
        let data = payload.data
        if metadata.contains("application/pdf") {
            return pdfThumbnail(from: data)
        }
        return NSImage(data: data)
    }

    private func dataPayload(from dataUrl: String) -> (mimeType: String, data: Data)? {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else { return nil }
        let metadata = String(dataUrl[..<commaIndex]).lowercased()
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        let mimeType = metadata
            .replacingOccurrences(of: "data:", with: "")
            .components(separatedBy: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (mimeType?.isEmpty == false ? mimeType! : "application/octet-stream", data)
    }

    private func documentBadgeLabel(for document: ChatIncomingDocumentPreview) -> String {
        let extensionLabel = URL(fileURLWithPath: document.fileName).pathExtension.uppercased()
        if !extensionLabel.isEmpty {
            switch extensionLabel {
            case "NUMBERS":
                return "NUM"
            default:
                return String(extensionLabel.prefix(5))
            }
        }
        if let mimeType = document.mimeType,
           let preferredExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension?.uppercased(),
           !preferredExtension.isEmpty {
            return String(preferredExtension.prefix(5))
        }
        return "FILE"
    }

    private func pdfThumbnail(from data: Data) -> NSImage? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else { return nil }
        return page.thumbnail(
            of: CGSize(width: 180, height: 180),
            for: .mediaBox
        )
    }

    private func openLinkPreview(_ preview: ChatIncomingLinkPreview) {
        guard let url = normalizedOpenURL(preview.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAppleMaps(_ preview: ChatIncomingLinkPreview) {
        guard let url = normalizedOpenURL(preview.appleMapsUrl ?? preview.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func normalizedOpenURL(_ rawURL: String) -> URL? {
        var value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("www.") {
            value = "https://" + value
        }
        guard value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") else {
            return nil
        }
        return URL(string: value)
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

            Image(service.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .offset(x: 2, y: 2)
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: service.badgeGradient,
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.gray)
                        Text("Sending...")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                    }
                } else if sendSuccess {
                    HStack(spacing: 8) {
                        if isWhatsAppAnimEnabled {
                            AnimatedDoubleCheckmark()
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.gray)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.gray)
                                        .offset(x: 5, y: 0)
                                )
                                .padding(.trailing, 5)
                        }
                        Text("Sent")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.gray)
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
                                    syncChatAutoDismissSuppression()
                                }

                            Button(action: sendMessage) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        canSendMessage
                                            ? service.accent
                                            : Color.white.opacity(0.28)
                                    )
                                    .frame(width: 32, height: 32)
                                    .background(
                                        canSendMessage
                                            ? service.accent.opacity(0.18)
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
            .padding(.top, 6)
            .padding(.bottom, 6)
            .onAppear {
                DispatchQueue.main.async {
                    guard isReplying else { return }
                    isInputFocused = true
                }
            }
            .onChange(of: isSending) { _, _ in
                syncChatAutoDismissSuppression()
            }
            .onDisappear {
                coordinator.suppressChatAutoDismiss = false
            }
        }
    }

    private func dismissNotification() {
        isReplying = false
        coordinator.suppressChatAutoDismiss = false
        DynamicIslandViewCoordinator.shared.toggleExpandingView(
            status: false,
            type: .chat(
                service: service,
                senderName: senderName,
                messages: messages,
                chatId: chatId,
                avatarUrl: avatarUrl
            )
        )
    }

    private var canSendMessage: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDraftReply: Bool {
        !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncChatAutoDismissSuppression() {
        coordinator.suppressChatAutoDismiss = hasDraftReply || isSending
    }

    private func beginChatInteraction() {
        coordinator.suppressChatAutoDismiss = true
    }

    private func endChatInteraction() {
        coordinator.suppressChatAutoDismiss = false
    }

    private func pollSelectionKey(for message: ChatIncomingMessage) -> String {
        "\(chatId)|\(message.id)"
    }

    private func selectedPollOptions(for message: ChatIncomingMessage) -> Set<String> {
        coordinator.chatSelectedPollOptionsByMessage[pollSelectionKey(for: message)]
            ?? Set(message.pollOptions.filter(\.isSelected).map(\.text))
    }

    private func isPollOptionSelected(_ option: ChatIncomingPollOption, for message: ChatIncomingMessage) -> Bool {
        selectedPollOptions(for: message).contains(option.text)
    }

    private func showReactionPalette(for message: ChatIncomingMessage) {
        // Offering a reaction the service cannot deliver is worse than not
        // offering one: the palette opens, the emoji is chosen, and the only
        // thing that happens is an error.
        guard service.supportsReactions else { return }
        guard reactionSendingKey == nil else { return }
        reactionPaletteDismissTask?.cancel()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            reactionMessageId = reactionMessageId == message.id ? nil : message.id
        }
        if reactionMessageId != nil {
            beginChatInteraction()
            reactionPaletteDismissTask = Task {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard reactionSendingKey == nil else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        reactionMessageId = nil
                    }
                    endChatInteraction()
                    reactionPaletteDismissTask = nil
                }
            }
        } else {
            endChatInteraction()
            reactionPaletteDismissTask = nil
        }
    }

    private func reactionKey(for message: ChatIncomingMessage, reaction: String) -> String {
        "\(message.id)|\(reaction)"
    }

    @ViewBuilder
    private func reactionBadge(_ reaction: String, isSending: Bool) -> some View {
        HStack(spacing: 4) {
            Text(reaction)
                .font(.system(size: 13))

            if isSending {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.42)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.9))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private func reactionPalette(for message: ChatIncomingMessage) -> some View {
        HStack(spacing: 2) {
            ForEach(quickReactionEmojis, id: \.self) { emoji in
                Button {
                    sendReaction(emoji, for: message)
                } label: {
                    ZStack {
                        Text(emoji)
                            .font(.system(size: 15))
                            .frame(width: 26, height: 26)
                            .opacity(reactionSendingKey == reactionKey(for: message, reaction: emoji) ? 0 : 1)

                        if reactionSendingKey == reactionKey(for: message, reaction: emoji) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.45)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(reactionSendingKey != nil)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.88))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
    }

    private func sendReaction(_ reaction: String, for message: ChatIncomingMessage) {
        guard reactionSendingKey == nil else { return }
        guard !isPreview else {
            reactionPaletteDismissTask?.cancel()
            reactionPaletteDismissTask = nil
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                reactionMessageId = nil
                reactionsByMessageId[message.id] = reaction
                reactionPulseMessageId = message.id
            }
            clearReactionPulse(for: message)
            endChatInteraction()
            return
        }

        let key = reactionKey(for: message, reaction: reaction)
        reactionPaletteDismissTask?.cancel()
        reactionPaletteDismissTask = nil
        reactionSendingKey = key
        sendErrorText = nil
        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
            reactionMessageId = nil
            reactionsByMessageId[message.id] = reaction
            reactionPulseMessageId = message.id
        }
        clearReactionPulse(for: message)
        beginChatInteraction()

        service.provider.reactToMessage(
            chatId: chatId,
            messageId: message.id,
            messageText: message.text,
            reaction: reaction
        ) { result in
            DispatchQueue.main.async {
                reactionSendingKey = nil
                endChatInteraction()
                switch result {
                case .success:
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                        reactionMessageId = nil
                    }
                case .failure(let error):
                    print("Error sending \(service.displayName) reaction: \(error.localizedDescription)")
                    withAnimation(.easeOut(duration: 0.16)) {
                        if reactionsByMessageId[message.id] == reaction {
                            reactionsByMessageId.removeValue(forKey: message.id)
                        }
                    }
                    sendErrorText = error.localizedDescription
                }
            }
        }
    }

    private func clearReactionPulse(for message: ChatIncomingMessage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard reactionPulseMessageId == message.id else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                reactionPulseMessageId = nil
            }
        }
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
        beginChatInteraction()

        isSending = true
        let replyToSend = replyText
        
        service.provider.sendReply(chatId: chatId, text: replyToSend) { result in
            DispatchQueue.main.async {
                endChatInteraction()
                isSending = false
                switch result {
                case .success:
                    replyText = ""
                    sendSuccess = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismissNotification()
                    }
                case .failure(let error):
                    print("Error sending \(service.displayName) reply: \(error.localizedDescription)")
                    sendSuccess = false
                    // The reason, not just "it failed": these engines drive
                    // somebody else's web app, so what went wrong is usually
                    // specific and worth putting in front of the user.
                    sendErrorText = error.localizedDescription
                }
            }
        }
    }

    private func selectPollOption(_ option: ChatIncomingPollOption, for message: ChatIncomingMessage) {
        guard !isPreview else { return }
        guard pollOptionSendingKey == nil else { return }
        let sendingKey = "\(message.id)|\(option.id)"
        let selectionKey = pollSelectionKey(for: message)
        let previousSelection = coordinator.chatSelectedPollOptionsByMessage[selectionKey]
        pollOptionSendingKey = sendingKey
        beginChatInteraction()
        var selectedOptions = selectedPollOptions(for: message)
        let wasSelected = selectedOptions.contains(option.text)
        if message.pollAllowsMultipleSelection {
            if wasSelected {
                selectedOptions.remove(option.text)
            } else {
                selectedOptions.insert(option.text)
            }
        } else {
            selectedOptions = wasSelected ? [] : [option.text]
        }
        coordinator.chatSelectedPollOptionsByMessage[selectionKey] = selectedOptions

        service.provider.selectPollOption(
            chatId: chatId,
            messageId: message.id,
            questionText: message.text,
            selectedOptionTexts: Array(selectedOptions),
            optionText: option.text
        ) { result in
            DispatchQueue.main.async {
                endChatInteraction()
                pollOptionSendingKey = nil
                switch result {
                case .success:
                    coordinator.chatSelectedPollOptionsByMessage[selectionKey] = selectedOptions
                case .failure(let error):
                    if let previousSelection {
                        coordinator.chatSelectedPollOptionsByMessage[selectionKey] = previousSelection
                    } else {
                        coordinator.chatSelectedPollOptionsByMessage.removeValue(forKey: selectionKey)
                    }
                    print("Error selecting \(service.displayName) poll option: \(error.localizedDescription)")
                    sendErrorText = error.localizedDescription
                }
            }
        }
    }

    private func downloadDocument(_ document: ChatIncomingDocumentPreview, for message: ChatIncomingMessage) {
        guard !isPreview else { return }
        guard documentDownloadKey == nil else { return }
        documentDownloadKey = message.id
        beginChatInteraction()
        sendErrorText = nil

        service.provider.downloadDocument(
            chatId: chatId,
            messageId: message.id,
            fileName: document.fileName
        ) { result in
            DispatchQueue.main.async {
                endChatInteraction()
                documentDownloadKey = nil
                switch result {
                case .success:
                    break
                case .failure(let error):
                    print("Error downloading \(service.displayName) document: \(error.localizedDescription)")
                    sendErrorText = error.localizedDescription
                }
            }
        }
    }

    private func downloadMedia(for message: ChatIncomingMessage) {
        guard !isPreview else { return }
        guard let dataUrl = message.mediaDataUrl,
              let payload = dataPayload(from: dataUrl) else {
            sendErrorText = "Download failed"
            return
        }

        do {
            let fileName = mediaDownloadFileName(for: message, mimeType: payload.mimeType)
            _ = try saveDataToDownloads(payload.data, fileName: fileName)
        } catch {
            print("Error downloading \(service.displayName) media: \(error.localizedDescription)")
            sendErrorText = error.localizedDescription
        }
    }

    private func mediaDownloadFileName(for message: ChatIncomingMessage, mimeType: String) -> String {
        let kind: String
        switch message.mediaKind {
        case .sticker:
            kind = "Sticker"
        case .video:
            kind = "Video Thumbnail"
        case .gif:
            kind = "GIF Thumbnail"
        case .image, .none:
            kind = "Image"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let extensionLabel = mediaFileExtension(for: mimeType, kind: message.mediaKind)
        return "\(service.displayName) \(kind) \(formatter.string(from: Date())).\(extensionLabel)"
    }

    private func mediaFileExtension(for mimeType: String, kind: ChatIncomingMediaKind?) -> String {
        let lowercasedMime = mimeType.lowercased()
        if lowercasedMime.contains("webp") { return "webp" }
        if lowercasedMime.contains("jpeg") || lowercasedMime.contains("jpg") { return "jpg" }
        if lowercasedMime.contains("png") { return "png" }
        if lowercasedMime.contains("gif") { return "gif" }
        if let preferredExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension {
            return preferredExtension
        }
        return kind == .sticker ? "webp" : "png"
    }

    private func saveDataToDownloads(_ data: Data, fileName: String) throws -> URL {
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let destination = uniqueDownloadURL(in: downloadsURL, fileName: sanitizedDownloadFileName(fileName))
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private func sanitizedDownloadFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        let cleaned = fileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
        return cleaned.isEmpty ? "\(service.displayName) File" : cleaned
    }

    private func uniqueDownloadURL(in directory: URL, fileName: String) -> URL {
        let baseURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let fileExtension = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for index in 1...999 {
            let candidateName = fileExtension.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(fileExtension)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return directory.appendingPathComponent(UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)"))
    }
}

private struct DocumentThumbnail: View {
    let label: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))

            VStack(spacing: 3) {
                Image(systemName: "doc.richtext.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))

                Text(label)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.38, blue: 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct DefaultMapPreviewThumbnail: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.78, green: 0.86, blue: 0.72),
                        Color(red: 0.56, green: 0.75, blue: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                mapBlock(
                    x: size.width * 0.02,
                    y: size.height * 0.04,
                    width: size.width * 0.34,
                    height: size.height * 0.42,
                    color: Color(red: 0.62, green: 0.78, blue: 0.50)
                )
                mapBlock(
                    x: size.width * 0.56,
                    y: size.height * 0.04,
                    width: size.width * 0.40,
                    height: size.height * 0.34,
                    color: Color(red: 0.72, green: 0.82, blue: 0.58)
                )
                mapBlock(
                    x: size.width * 0.08,
                    y: size.height * 0.62,
                    width: size.width * 0.32,
                    height: size.height * 0.30,
                    color: Color(red: 0.67, green: 0.80, blue: 0.54)
                )

                roadPath(size: size)
                    .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                roadPath(size: size)
                    .stroke(Color(red: 0.88, green: 0.78, blue: 0.48), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                routePath(size: size)
                    .stroke(Color(red: 0.08, green: 0.44, blue: 0.95), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(.white)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(red: 0.08, green: 0.44, blue: 0.95), lineWidth: 2)
                    )
                    .position(x: size.width * 0.22, y: size.height * 0.72)

                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.94, green: 0.12, blue: 0.16), .white)
                    .position(x: size.width * 0.76, y: size.height * 0.25)
            }
        }
    }

    private func mapBlock(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color.opacity(0.78))
            .frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
    }

    private func roadPath(size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.02, y: size.height * 0.50))
            path.addCurve(
                to: CGPoint(x: size.width * 0.98, y: size.height * 0.42),
                control1: CGPoint(x: size.width * 0.30, y: size.height * 0.22),
                control2: CGPoint(x: size.width * 0.62, y: size.height * 0.72)
            )
            path.move(to: CGPoint(x: size.width * 0.48, y: size.height * 0.02))
            path.addCurve(
                to: CGPoint(x: size.width * 0.40, y: size.height * 0.98),
                control1: CGPoint(x: size.width * 0.42, y: size.height * 0.30),
                control2: CGPoint(x: size.width * 0.58, y: size.height * 0.64)
            )
        }
    }

    private func routePath(size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.72))
            path.addCurve(
                to: CGPoint(x: size.width * 0.76, y: size.height * 0.28),
                control1: CGPoint(x: size.width * 0.36, y: size.height * 0.70),
                control2: CGPoint(x: size.width * 0.50, y: size.height * 0.30)
            )
        }
    }
}

private enum ChatMessageLinkDetector {
    struct Match {
        let range: Range<String.Index>
        let url: URL
    }

    private static let expression = try? NSRegularExpression(
        pattern: #"(?i)\b((?:https?://|www\.)[^\s<>"']+|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}(?::\d+)?(?:/[^\s<>"']*)?)"#,
        options: []
    )

    static func matches(in text: String) -> [Match] {
        guard let expression else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, options: [], range: nsRange).compactMap { result in
            guard let rawRange = Range(result.range(at: 1), in: text) else { return nil }
            let range = trimmedRange(rawRange, in: text)
            guard range.isEmpty == false,
                  !isEmailDomainMatch(range, in: text),
                  let url = normalizedURL(String(text[range])) else {
                return nil
            }
            return Match(range: range, url: url)
        }
    }

    private static func trimmedRange(_ range: Range<String.Index>, in text: String) -> Range<String.Index> {
        var upper = range.upperBound
        let trailingCharacters = CharacterSet(charactersIn: ".,;:!?)]}\"'")
        while range.lowerBound < upper {
            let previous = text.index(before: upper)
            guard let scalar = text[previous].unicodeScalars.first,
                  trailingCharacters.contains(scalar) else {
                break
            }
            upper = previous
        }
        return range.lowerBound..<upper
    }

    private static func isEmailDomainMatch(_ range: Range<String.Index>, in text: String) -> Bool {
        guard range.lowerBound > text.startIndex else { return false }
        let previous = text.index(before: range.lowerBound)
        return text[previous] == "@"
    }

    private static func normalizedURL(_ rawURL: String) -> URL? {
        var value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return nil }
        let lowercased = value.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            value = "https://" + value
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

private struct SecondaryClickCapture: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> SecondaryClickCaptureView {
        SecondaryClickCaptureView(action: action)
    }

    func updateNSView(_ nsView: SecondaryClickCaptureView, context: Context) {
        nsView.action = action
    }
}

private final class SecondaryClickCaptureView: NSView {
    var action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        action = {}
        super.init(coder: coder)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent else { return nil }
        return event.type == .rightMouseDown ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        action()
    }
}

// MARK: - Animated Double Checkmark

struct AnimatedDoubleCheckmark: View {
    @State private var showSecond = false
    @State private var color: Color = .gray

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)

            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .offset(x: 5, y: 0)
                .opacity(showSecond ? 1 : 0)
                .scaleEffect(showSecond ? 1 : 0.5, anchor: .leading)
        }
        .padding(.trailing, 5)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                color = .blue
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.15)) {
                showSecond = true
                color = .pink
            }
        }
    }
}
