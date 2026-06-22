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

// MARK: - Layout (original WhatsApp notification dimensions)

enum WhatsAppNotificationLayout {
    static let width: CGFloat = 420

    static func contentHeight(
        isReplying: Bool,
        hasFilePreview: Bool,
        messages: [WhatsAppIncomingMessage]
    ) -> CGFloat {
        let messagesHeight = messages.reduce(CGFloat.zero) { total, message in
            total + messageHeight(message) + (total > 0 ? 3 : 0)
        }
        let headerContentHeight = max(38, 17 + (messagesHeight > 0 ? 3 + messagesHeight : 0))
        let headerHeight = 12 + headerContentHeight
        let replyHeight: CGFloat = isReplying ? 44 : 0
        let filePreviewHeight: CGFloat = hasFilePreview ? 40 : 0
        return max(isReplying ? 96 : 56, headerHeight + replyHeight + filePreviewHeight)
    }

    private static func messageHeight(_ message: WhatsAppIncomingMessage) -> CGFloat {
        var height: CGFloat = 0
        let text = cleanedText(message.text)
        if shouldMeasureText(text, for: message) || cleanedText(message.groupSender ?? "").isEmpty == false {
            let explicitLines = max(1, text.components(separatedBy: .newlines).count)
            let estimatedWrappedLines = max(1, Int(ceil(Double(text.count) / 48.0)))
            height += CGFloat(max(explicitLines, estimatedWrappedLines)) * (isEmojiOnly(text) ? 19 : 16)
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
            height += (height > 0 ? 6 : 0) + 16 + CGFloat(min(message.pollOptions.count, 4)) * 39 + 8
        }
        return max(17, height)
    }

    private static func shouldMeasureText(_ text: String, for message: WhatsAppIncomingMessage) -> Bool {
        guard !text.isEmpty else { return false }
        if let document = message.documentPreview {
            let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedFileName = document.fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedText == normalizedFileName || normalizedText.hasPrefix(normalizedFileName) {
                return false
            }
        }
        if message.mediaDataUrl != nil || message.mediaKind != nil {
            let lowered = text.lowercased()
            let mediaOnlyLabels: Set<String> = ["sticker", "adesivo", "immagine", "image", "photo", "foto", "📨 nuovo messaggio"]
            return !mediaOnlyLabels.contains(lowered)
        }
        return true
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

    static func totalSize(
        isReplying: Bool,
        hasFilePreview: Bool,
        messages: [WhatsAppIncomingMessage],
        isDynamicIslandMode: Bool,
        closedNotchHeight: CGFloat
    ) -> CGSize {
        let height = contentHeight(
            isReplying: isReplying,
            hasFilePreview: hasFilePreview,
            messages: messages
        )
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
        messages: [WhatsAppIncomingMessage],
        isDynamicIslandMode: Bool
    ) -> WhatsAppHUDMetrics {
        let topOffset = WhatsAppNotificationLayout.topOffset(
            isDynamicIslandMode: isDynamicIslandMode,
            closedNotchHeight: closedNotchHeight
        )
        return WhatsAppHUDMetrics(
            width: WhatsAppNotificationLayout.width,
            height: WhatsAppNotificationLayout.contentHeight(
                isReplying: isReplying,
                hasFilePreview: hasFilePreview,
                messages: messages
            ) + topOffset,
            topOffset: topOffset,
            bottomRadius: WhatsAppNotificationLayout.bottomCornerRadius(isReplying: isReplying)
        )
    }
}

// MARK: - Shell (battery-style expanding view)

struct WhatsAppTemporaryActivityView: View {
    let senderName: String
    let messages: [WhatsAppIncomingMessage]
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
            messages: messages,
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
            messages: messages,
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
    let messages: [WhatsAppIncomingMessage]
    let chatId: String
    let avatarUrl: String?

    @Binding var isReplying: Bool

    @Default(.isWhatsAppAnimEnabled) var isWhatsAppAnimEnabled

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var sendSuccess: Bool = false
    @State private var sendErrorText: String?
    @State private var selectedPollOptionsByMessage: [String: Set<String>] = [:]
    @State private var pollOptionSendingKey: String?
    @State private var documentDownloadKey: String?
    @FocusState private var isInputFocused: Bool

    private var isPreview: Bool { chatId == WhatsAppManager.previewChatId }
    private var visibleMessages: [WhatsAppIncomingMessage] {
        messages.isEmpty ? [WhatsAppIncomingMessage(text: "📨 Nuovo messaggio")] : messages
    }

    private func sanitizedText(_ text: String) -> String {
        let cleaned = WhatsAppNotificationLayout.cleanedText(text)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
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

                    Spacer(minLength: 4)

                    Text("now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
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
    private func messageRow(_ message: WhatsAppIncomingMessage) -> some View {
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
    }

    @ViewBuilder
    private func messageTextView(text: String, groupSender: String?) -> some View {
        let isEmojiOnly = WhatsAppNotificationLayout.isEmojiOnly(text)
        Group {
            if let groupSender {
                groupMessageText(sender: groupSender, text: text)
                    .lineLimit(isEmojiOnly ? 1 : nil)
            } else {
                Text(text)
                    .font(.system(size: isEmojiOnly ? 18 : 12.5))
                    .lineLimit(isEmojiOnly ? 1 : nil)
            }
        }
        .foregroundStyle(.white.opacity(0.62))
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func groupMessageText(sender: String, text: String) -> Text {
        Text("\(sender):")
            .font(.system(size: 12.5, weight: .semibold))
        + Text(text.isEmpty ? "" : " \(text)")
            .font(.system(size: WhatsAppNotificationLayout.isEmojiOnly(text) ? 16 : 12.5))
    }

    private func groupSenderName(for message: WhatsAppIncomingMessage) -> String? {
        let trimmed = WhatsAppNotificationLayout.cleanedText(message.groupSender ?? "")
        return trimmed.isEmpty ? nil : trimmed
    }

    private func shouldShowText(_ text: String, for message: WhatsAppIncomingMessage) -> Bool {
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
        let mediaOnlyLabels: Set<String> = ["sticker", "adesivo", "immagine", "image", "photo", "foto", "📨 nuovo messaggio"]
        return !mediaOnlyLabels.contains(lowered)
    }

    @ViewBuilder
    private func linkPreviewView(_ preview: WhatsAppIncomingLinkPreview) -> some View {
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
    }

    @ViewBuilder
    private func mapPreviewView(_ preview: WhatsAppIncomingLinkPreview) -> some View {
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
                    .background(Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255))
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
    }

    @ViewBuilder
    private func messageMediaView(for message: WhatsAppIncomingMessage) -> some View {
        let kind = message.mediaKind
        if let dataUrl = message.mediaDataUrl, let image = imageFromDataUrl(dataUrl) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: kind == .sticker ? 76 : 96, maxHeight: kind == .sticker ? 58 : 66, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: kind == .sticker ? 0 : 10, style: .continuous))
                .overlay {
                    SecondaryClickCapture {
                        downloadMedia(for: message)
                    }
                }
                .contentShape(Rectangle())
                .help("Tasto destro: scarica")
        } else {
            HStack(spacing: 6) {
                Image(systemName: kind == .sticker ? "face.smiling.inverse" : "photo")
                Text(kind == .sticker ? "Sticker" : "Immagine")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.56))
        }
    }

    @ViewBuilder
    private func documentPreviewView(_ document: WhatsAppIncomingDocumentPreview, for message: WhatsAppIncomingMessage) -> some View {
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

    private func pollOptionsView(for message: WhatsAppIncomingMessage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text(message.pollAllowsMultipleSelection ? "Seleziona una o più opzioni" : "Seleziona un'opzione")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.45))

            ForEach(message.pollOptions.prefix(4)) { option in
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

                            Text("\(option.voteCount)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.76))

                            if pollOptionSendingKey == "\(message.id)|\(option.id)" {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.55)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                        .contentShape(Rectangle())

                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(isPollOptionSelected(option, for: message) ? 0.34 : 0.18))
                                        .frame(width: proxy.size.width * pollShare(for: option, in: message))
                                }
                        }
                        .frame(height: 4)
                        .padding(.leading, 24)
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .disabled(isPreview || pollOptionSendingKey != nil)
            }
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    @ViewBuilder
    private func pollSelectionIndicator(isSelected: Bool, allowsMultipleSelection: Bool) -> some View {
        let activeColor = Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)
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

    private func documentBadgeLabel(for document: WhatsAppIncomingDocumentPreview) -> String {
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

    private func openLinkPreview(_ preview: WhatsAppIncomingLinkPreview) {
        guard let url = normalizedOpenURL(preview.url) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openAppleMaps(_ preview: WhatsAppIncomingLinkPreview) {
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

            Image("WhatsApp")
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
                                    syncWhatsAppAutoDismissSuppression()
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
            .padding(.top, 6)
            .padding(.bottom, 6)
            .onAppear {
                DispatchQueue.main.async {
                    guard isReplying else { return }
                    isInputFocused = true
                }
            }
            .onChange(of: isSending) { _, _ in
                syncWhatsAppAutoDismissSuppression()
            }
            .onDisappear {
                coordinator.suppressWhatsAppAutoDismiss = false
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

    private func syncWhatsAppAutoDismissSuppression() {
        coordinator.suppressWhatsAppAutoDismiss = hasDraftReply || isSending
    }

    private func beginWhatsAppInteraction() {
        coordinator.suppressWhatsAppAutoDismiss = true
    }

    private func endWhatsAppInteraction() {
        coordinator.suppressWhatsAppAutoDismiss = false
    }

    private func isPollOptionSelected(_ option: WhatsAppIncomingPollOption, for message: WhatsAppIncomingMessage) -> Bool {
        selectedPollOptionsByMessage[message.id]?.contains(option.text) == true || option.isSelected
    }

    private func pollShare(for option: WhatsAppIncomingPollOption, in message: WhatsAppIncomingMessage) -> CGFloat {
        let totalVotes = max(message.pollOptions.map(\.voteCount).reduce(0, +), 1)
        return CGFloat(option.voteCount) / CGFloat(totalVotes)
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

    private func selectPollOption(_ option: WhatsAppIncomingPollOption, for message: WhatsAppIncomingMessage) {
        guard !isPreview else { return }
        guard pollOptionSendingKey == nil else { return }
        let sendingKey = "\(message.id)|\(option.id)"
        pollOptionSendingKey = sendingKey
        beginWhatsAppInteraction()
        var selectedOptions = selectedPollOptionsByMessage[message.id]
            ?? Set(message.pollOptions.filter(\.isSelected).map(\.text))
        if message.pollAllowsMultipleSelection {
            if selectedOptions.contains(option.text) {
                selectedOptions.remove(option.text)
            } else {
                selectedOptions.insert(option.text)
            }
        } else {
            selectedOptions = [option.text]
        }

        WhatsAppManager.shared.selectPollOption(
            chatId: chatId,
            messageId: message.id,
            questionText: message.text,
            selectedOptionTexts: Array(selectedOptions),
            optionText: option.text
        ) { result in
            DispatchQueue.main.async {
                endWhatsAppInteraction()
                pollOptionSendingKey = nil
                switch result {
                case .success:
                    selectedPollOptionsByMessage[message.id] = selectedOptions
                case .failure(let error):
                    print("Error selecting WhatsApp poll option: \(error.localizedDescription)")
                    sendErrorText = "Sondaggio non selezionato"
                }
            }
        }
    }

    private func downloadDocument(_ document: WhatsAppIncomingDocumentPreview, for message: WhatsAppIncomingMessage) {
        guard !isPreview else { return }
        guard documentDownloadKey == nil else { return }
        documentDownloadKey = message.id
        beginWhatsAppInteraction()
        sendErrorText = nil

        WhatsAppManager.shared.downloadDocument(
            chatId: chatId,
            messageId: message.id,
            fileName: document.fileName
        ) { result in
            DispatchQueue.main.async {
                endWhatsAppInteraction()
                documentDownloadKey = nil
                switch result {
                case .success:
                    break
                case .failure(let error):
                    print("Error downloading WhatsApp document: \(error.localizedDescription)")
                    sendErrorText = "Download fallito"
                }
            }
        }
    }

    private func downloadMedia(for message: WhatsAppIncomingMessage) {
        guard !isPreview else { return }
        guard let dataUrl = message.mediaDataUrl,
              let payload = dataPayload(from: dataUrl) else {
            sendErrorText = "Download fallito"
            return
        }

        do {
            let fileName = mediaDownloadFileName(for: message, mimeType: payload.mimeType)
            _ = try saveDataToDownloads(payload.data, fileName: fileName)
        } catch {
            print("Error downloading WhatsApp media: \(error.localizedDescription)")
            sendErrorText = "Download fallito"
        }
    }

    private func mediaDownloadFileName(for message: WhatsAppIncomingMessage, mimeType: String) -> String {
        let kind = message.mediaKind == .sticker ? "Sticker" : "Image"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let extensionLabel = mediaFileExtension(for: mimeType, kind: message.mediaKind)
        return "WhatsApp \(kind) \(formatter.string(from: Date())).\(extensionLabel)"
    }

    private func mediaFileExtension(for mimeType: String, kind: WhatsAppIncomingMediaKind?) -> String {
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
        return cleaned.isEmpty ? "WhatsApp File" : cleaned
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
