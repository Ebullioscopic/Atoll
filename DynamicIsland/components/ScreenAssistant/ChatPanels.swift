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

import AppKit
import SwiftUI
import Defaults
import UniformTypeIdentifiers
import QuickLookUI

// One native window keeps the conversation, images and draft together.
class ChatInputPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 660, height: 740),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = String(localized: "Atoll Assistant")
        titlebarAppearsTransparent = true
        backgroundColor = .windowBackgroundColor
        isReleasedWhenClosed = false
        level = .normal
        isFloatingPanel = false
        hidesOnDeactivate = true
        hasShadow = true
        minSize = NSSize(width: 480, height: 480)
        collectionBehavior = [.managed]
        contentView = NSHostingView(rootView: ChatWorkspaceView())
        setFrameAutosaveName("AtollAssistantWorkspace")
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { ScreenAssistantManager.shared.closePanels() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command || (modifiers == [.command, .shift] && event.charactersIgnoringModifiers == "+") {
            switch event.charactersIgnoringModifiers {
            case "=", "+": Defaults[.chatTextScale] = ChatPresentation.zoom(Defaults[.chatTextScale], steps: 1)
            case "-": Defaults[.chatTextScale] = ChatPresentation.zoom(Defaults[.chatTextScale], steps: -1)
            case "0": Defaults[.chatTextScale] = 1
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    func positionInCenter() {
        if !setFrameUsingName("AtollAssistantWorkspace") {
            if let visible = NSScreen.main?.visibleFrame {
                setContentSize(NSSize(width: min(660, visible.width - 60), height: min(740, visible.height - 80)))
            }
            center()
        }
    }
    deinit { ScreenCaptureVisibilityManager.shared.unregister(self) }
}

private let chatAccent = Color(red: 0.16, green: 0.48, blue: 0.45)

struct ChatWorkspaceView: View {
    @ObservedObject var manager = ScreenAssistantManager.shared
    @State private var isDragging = false
    @Default(.chatTextScale) private var textScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(chatAccent)
                Text("Conversation").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 9) {
                    Button { textScale = ChatPresentation.zoom(textScale, steps: -1) } label: { Image(systemName: "textformat.size.smaller") }
                        .help("Decrease text size (⌘−)").accessibilityLabel("Decrease text size")
                        .disabled(textScale <= ChatPresentation.minimumScale)
                    Button { textScale = 1 } label: { Text("\(Int((ChatPresentation.clamp(textScale) * 100).rounded()))%") .monospacedDigit() }
                        .help("Reset text size (⌘0)").accessibilityLabel("Reset text size")
                    Button { textScale = ChatPresentation.zoom(textScale, steps: 1) } label: { Image(systemName: "textformat.size.larger") }
                        .help("Increase text size (⌘+)").accessibilityLabel("Increase text size")
                        .disabled(textScale >= ChatPresentation.maximumScale)
                }.font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
                Button { manager.toggleWindowZoom() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.plain).help("Resize window").accessibilityLabel("Resize window")
                Button { manager.resetConversationContext() } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(manager.isControlling || manager.controlError != nil || manager.pendingAttachments > 0)
                .help("Clear the current conversation and start again")
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider().opacity(0.5)
            ChatMessagesView()
            ChatInputView()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(chatAccent)
        .environment(\.chatTextScale, ChatPresentation.clamp(textScale))
        .overlay {
            if isDragging {
                RoundedRectangle(cornerRadius: 14)
                    .fill(chatAccent.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(chatAccent, style: StrokeStyle(lineWidth: 2, dash: [8, 5])))
                    .overlay {
                        Label(manager.imagesOnly ? String(localized: "Drop images to attach") : String(localized: "Drop images or files to attach"), systemImage: "photo.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(8).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDragging) { manager.acceptDrop($0) }
    }
}

struct ChatMessagesView: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @State private var followLatest = true
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if screenAssistantManager.chatMessages.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(chatAccent)
                                .frame(width: 64, height: 64)
                                .background(chatAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                            Text("A little help, right here.")
                                .font(.system(size: 25, weight: .semibold, design: .rounded))
                            Text("Ask a question, drop an image, or capture part of your screen.")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                            HStack(spacing: 18) {
                                Label("Drop images", systemImage: "photo")
                                Label("Paste screenshots", systemImage: "command")
                            }
                            .font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 66)
                    }
                    ForEach(screenAssistantManager.chatMessages) { message in
                        StreamingChatMessageBubble(message: message).id(message.id)
                    }
                    if screenAssistantManager.isLoading {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text(screenAssistantManager.responseStatus).font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(.leading, 4)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(.horizontal, 26).padding(.vertical, 24)
            }
            .overlay(alignment: .topTrailing) {
                if !screenAssistantManager.chatMessages.isEmpty {
                    Toggle("Follow latest reply", isOn: $followLatest)
                        .toggleStyle(.button).font(.system(size: 11))
                        .padding(6).background(.regularMaterial, in: Capsule()).padding(8)
                }
            }
            .onChange(of: screenAssistantManager.chatMessages.last?.content) { _, _ in
                if followLatest { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: followLatest) { _, enabled in
                if enabled { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
            }
            .onChange(of: screenAssistantManager.chatMessages.count) { _, _ in
                if followLatest { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
            }
            .onChange(of: screenAssistantManager.isLoading) { _, _ in
                if followLatest { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChatInputView: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @Default(.selectedAIProvider) private var currentProvider
    @Default(.selectedAIModel) private var currentModel
    @Default(.enableThinkingMode) private var thinkingEnabled
    @Default(.chatToolsEnabled) private var toolsEnabled
    @Default(.localModelEndpoint) private var localEndpoint
    @Default(.deepseekEndpoint) private var deepseekEndpoint
    @Environment(\.chatTextScale) private var textScale
    @State private var editorHeight: CGFloat = 90
    @State private var showingApiKeyAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if screenAssistantManager.isControlling {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Stopping backend task…") }.font(.system(size: 12))
            }
            if let error = screenAssistantManager.controlError {
                HStack { Text(error); Spacer(); Button("Retry stop") { screenAssistantManager.retryBackendControl() } }
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
            if screenAssistantManager.canRetry {
                Button { screenAssistantManager.retryLastMessage() } label: { Label("Retry last message", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless).font(.system(size: 12))
            }
            if let error = screenAssistantManager.attachmentError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).frame(maxWidth: .infinity, alignment: .leading)
                    Button { screenAssistantManager.attachmentError = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Dismiss attachment error")
                }.font(.system(size: 12)).foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 0) {
                if !screenAssistantManager.attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(screenAssistantManager.attachedFiles) { file in
                                ChatAttachmentCard(file: file, compact: true) { screenAssistantManager.removeFile(file) }
                            }
                        }.padding(12)
                    }
                }
                ZStack(alignment: .topLeading) {
                    if screenAssistantManager.draftMessage.isEmpty {
                        Text("Ask anything, or drop an image…")
                            .font(.system(size: 14 * textScale)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 17).padding(.top, 15)
                            .allowsHitTesting(false)
                    }
                    ChatTextEditor(text: $screenAssistantManager.draftMessage, height: $editorHeight, fontSize: 14 * textScale, onSend: sendMessage)
                        .frame(height: editorHeight).padding(.horizontal, 10).padding(.top, 8)
                }
                HStack(spacing: 16) {
                    AddFilesButton()
                    ScreenshotButton()
                    if !screenAssistantManager.imagesOnly { RecordingButton() }
                    if screenAssistantManager.pendingAttachments > 0 {
                        ProgressView().controlSize(.mini)
                        Text("Importing…").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if screenAssistantManager.isRecording {
                        Text(screenAssistantManager.recordingDuration.formatted(.number.precision(.fractionLength(0))) + "s")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.red)
                    }
                    Button(action: { if screenAssistantManager.isLoading { screenAssistantManager.stopResponse() } else { sendMessage() } }) {
                        Image(systemName: screenAssistantManager.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle((canSend || screenAssistantManager.isLoading) ? .white : Color.secondary.opacity(0.5))
                            .frame(width: 32, height: 32)
                            .background((canSend || screenAssistantManager.isLoading) ? chatAccent : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).disabled(!canSend && !screenAssistantManager.isLoading)
                    .help(screenAssistantManager.isLoading ? String(localized: "Stop reply") : String(localized: "Send message (Return)"))
                    .accessibilityLabel(screenAssistantManager.isLoading ? String(localized: "Stop reply") : String(localized: "Send message"))
                }.padding(.horizontal, 14).padding(.bottom, 12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.09)))
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
            HStack(spacing: 6) {
                Button(action: openModelSelection) {
                    HStack(spacing: 6) {
                        Circle().fill(chatAccent).frame(width: 5, height: 5)
                        Text(screenAssistantManager.actualModelName ?? currentModel?.name ?? currentProvider.displayName).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                }.buttonStyle(.plain).help("Choose AI model").disabled(screenAssistantManager.isLoading || screenAssistantManager.isControlling || screenAssistantManager.isRecording || screenAssistantManager.pendingAttachments > 0)
                if screenAssistantManager.isBridge { Text("pi").foregroundStyle(chatAccent) }
                Spacer(minLength: 4)
                Text("⇧ Return for a new line").foregroundStyle(.tertiary)
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4)
            if screenAssistantManager.isBridge || (currentProvider == .deepseek && ChatRequestBuilder.isOfficial(deepseekEndpoint)) {
                HStack(spacing: 12) {
                    Toggle("Thinking mode", isOn: $thinkingEnabled).toggleStyle(.checkbox)
                    if screenAssistantManager.isBridge { Toggle("Read-only tools", isOn: $toolsEnabled).toggleStyle(.checkbox) }
                    Spacer()
                    Text("Applies to the next message").foregroundStyle(.tertiary)
                }.font(.system(size: 11)).disabled(screenAssistantManager.isLoading || screenAssistantManager.isControlling)
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        .onAppear { screenAssistantManager.refreshModelStatus() }
        .onChange(of: currentProvider) { _, _ in screenAssistantManager.refreshModelStatus() }
        .onChange(of: currentModel?.id) { _, _ in screenAssistantManager.refreshModelStatus() }
        .onChange(of: localEndpoint) { _, _ in screenAssistantManager.refreshModelStatus() }
        .alert("API Key Required", isPresented: $showingApiKeyAlert) {
            Button("Open Model Settings", action: openModelSelection)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Please configure your API key for the selected AI provider in model settings.") }
    }

    private var canSend: Bool {
        !screenAssistantManager.isLoading && !screenAssistantManager.isControlling && screenAssistantManager.controlError == nil && screenAssistantManager.pendingAttachments == 0 && !screenAssistantManager.isRecording &&
        (!screenAssistantManager.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !screenAssistantManager.attachedFiles.isEmpty)
    }
    private func sendMessage() {
        guard canSend else { return }
        let key: String
        switch currentProvider {
        case .gemini: key = AICredentialStore.shared.key(for: .gemini)
        case .openai: key = AICredentialStore.shared.key(for: .openai)
        case .claude: key = AICredentialStore.shared.key(for: .claude)
        case .groq: key = AICredentialStore.shared.key(for: .groq)
        case .local, .deepseek: key = "configured-by-request-builder"
        }
        guard !key.isEmpty else { showingApiKeyAlert = true; return }
        if screenAssistantManager.sendMessage(screenAssistantManager.draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)) {
            screenAssistantManager.draftMessage = ""
        }
    }
    private func openModelSelection() {
        screenAssistantManager.showModelSelection()
    }
}

struct StreamingChatMessageBubble: View {
    @Environment(\.chatTextScale) private var textScale
    let message: ChatMessage
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(message.isFromUser ? String(localized: "YOU") : "ATOLL")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.3)
                    .foregroundStyle(message.isFromUser ? Color.secondary : chatAccent)
                Text(message.timestamp, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("Copy message")
                .accessibilityLabel("Copy message")
            }
            if let files = message.attachedFiles, !files.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(files) { file in ChatAttachmentCard(file: file, compact: false, onRemove: nil) }
                    }
                }
            }
            if !message.tools.isEmpty {
                Label(String(localized: "Tools used:") + " " + message.tools.map(ScreenAssistantManager.toolDisplayName).joined(separator: ", "), systemImage: "wrench.and.screwdriver")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !message.reasoning.isEmpty {
                DisclosureGroup("Model reasoning") {
                    Text(message.reasoning).font(.system(size: 12 * textScale)).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.system(size: 12))
            }
            if let notice = message.notice {
                Label(notice, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.orange)
            }
            if !message.content.isEmpty {
                MarkdownText(content: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(message.isFromUser ? 14 : 0)
                    .background(message.isFromUser ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ChatAttachmentCard: View {
    let file: ScreenAssistantFile
    let compact: Bool
    let onRemove: (() -> Void)?
    @State private var thumbnail: NSImage?
    @State private var showingPreview = false
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: file.type.iconName).foregroundStyle(chatAccent)
                }
            }
            .frame(width: compact ? 44 : 96, height: compact ? 44 : 76)
            .background(Color.primary.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(file.type.displayName).font(.system(size: 10)).foregroundStyle(.secondary)
            }.frame(width: compact ? 108 : 120, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help(String(format: String(localized: "Remove %@"), file.name))
            }
        }
        .padding(6).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .help(file.type == .image ? String(localized: "Click to preview image") : file.name)
        .onTapGesture { if file.type == .image { showingPreview = true } }
        .accessibilityAction(named: Text("Preview image")) { if file.type == .image { showingPreview = true } }
        .sheet(isPresented: $showingPreview) {
            VStack(spacing: 0) {
                HStack { Text(file.name).lineLimit(1); Spacer(); Button("Done") { showingPreview = false }.keyboardShortcut(.cancelAction) }.padding(16)
                if let path = file.fileURL, let url = URL(string: path) { ChatImagePreview(url: url) }
            }.frame(minWidth: 460, idealWidth: 760, minHeight: 360, idealHeight: 620)
        }
        .task(id: file.fileURL) {
            guard file.type == .image, let path = file.fileURL, let url = URL(string: path) else { return }
            // Decode only a small thumbnail, not a full-resolution screenshot.
            let result = await Task.detached(priority: .utility) { ChatAttachmentImport.thumbnailData(url) }.value
            thumbnail = result.flatMap { NSImage(data: $0) }
        }
    }
}

// MARK: - Screenshot Button Component
struct ScreenshotButton: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @StateObject private var screenshotTool = ScreenshotSnippingTool.shared
    @State private var showingScreenshotOptions = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Main screenshot button
            Button(action: startQuickScreenshot) {
                Image(systemName: getIconName())
                    .foregroundColor(getIconColor())
                    .font(.system(size: 16))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Take area screenshot")
            .disabled(screenshotTool.isSnipping)
            .scaleEffect(screenshotTool.isSnipping ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: screenshotTool.isSnipping)
            
            // Options dropdown button
            Button(action: { showingScreenshotOptions.toggle() }) {
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Screenshot options")
            .disabled(screenshotTool.isSnipping)
            .popover(isPresented: $showingScreenshotOptions) {
                ScreenshotOptionsPopover { type in
                    startScreenshot(type: type)
                    showingScreenshotOptions = false
                }
            }
        }
    }
    
    private func getIconName() -> String {
        if screenshotTool.isSnipping {
            return "camera.viewfinder"
        } else {
            return "camera.aperture"
        }
    }
    
    private func getIconColor() -> Color {
        if screenshotTool.isSnipping {
            return .red
        } else {
            return .secondary
        }
    }
    
    private func startQuickScreenshot() {
        // Default to area screenshot for quick action
        startScreenshot(type: .area)
    }
    
    private func startScreenshot(type: ScreenshotSnippingTool.ScreenshotType) {
        // Start snipping with direct callback (ScreenshotApp-based approach)
        screenshotTool.startSnipping(type: type) { [weak screenAssistantManager] screenshotURL in
            guard let manager = screenAssistantManager else {
                print("❌ ScreenshotTool: ScreenAssistantManager deallocated during callback")
                return
            }
            
            print("📁 ScreenshotTool: Adding \(type.displayName.lowercased()) screenshot to chat: \(screenshotURL.lastPathComponent)")
            manager.addFiles([screenshotURL])
            print("📸 \(type.displayName) screenshot captured and added to chat successfully")
        }
    }
}

// MARK: - Visual Effect View for Chat Panels (to avoid conflicts)
struct ChatPanelsVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Screenshot Options Popover (Hidden from Screen Recording)
struct ScreenshotOptionsPopover: View {
    let onOptionSelected: (ScreenshotSnippingTool.ScreenshotType) -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Screenshot Type")
                .font(.headline)
                .padding(.top, 8)
            
            VStack(spacing: 4) {
                ScreenshotOptionButton(
                    type: .area,
                    description: "Select an area",
                    onTap: onOptionSelected
                )
                
                ScreenshotOptionButton(
                    type: .window,
                    description: "Select a window",
                    onTap: onOptionSelected
                )
                
                ScreenshotOptionButton(
                    type: .full,
                    description: "Capture full screen",
                    onTap: onOptionSelected
                )
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .frame(width: 200)
        .background(
            ScreenshotPopoverBackground()
        )
    }
}

// MARK: - Screenshot Option Button
struct ScreenshotOptionButton: View {
    let type: ScreenshotSnippingTool.ScreenshotType
    let description: String
    let onTap: (ScreenshotSnippingTool.ScreenshotType) -> Void
    
    var body: some View {
        Button(action: { onTap(type) }) {
            HStack(spacing: 12) {
                Image(systemName: type.iconName)
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
                    .frame(width: 20, alignment: .center)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .opacity(0.5)
        )
        .onHover { isHovered in
            // Add subtle hover effect if needed
        }
    }
}

// MARK: - Screenshot Popover Background (Hidden from Screen Recording)
struct ScreenshotPopoverBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if let window = nsView.window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

private struct ChatImagePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}
