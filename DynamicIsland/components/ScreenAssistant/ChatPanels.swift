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

private func applyChatPanelCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

// MARK: - Chat Messages Panel (Left Side)
class ChatMessagesPanel: NSPanel {
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    override var canBecomeKey: Bool {
        return false  // Don't steal focus from input panel
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    private func setupWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = false  // Fixed position
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]
        
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let contentView = ChatMessagesView()
        let hostingView = NSHostingView(rootView: contentView)
        applyChatPanelCornerMask(hostingView, radius: 16)
        self.contentView = hostingView
        
        // Set size for chat messages panel (wider and taller)
        let preferredSize = CGSize(width: 600, height: 500)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionOnLeftSide() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Position on the left side of the screen
        let xPosition = screenFrame.minX + 50 // 50pt from left edge
        let yPosition = screenFrame.maxY - panelFrame.height - 100 // 100pt from top
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

// MARK: - Chat Input Panel (Center)
class ChatInputPanel: NSPanel {
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    override var canBecomeKey: Bool {
        return true  // Can receive focus for text input
    }
    
    override var canBecomeMain: Bool {
        return true
    }
    
    // Handle ESC key globally for the panel
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            ScreenAssistantManager.shared.closePanels()
        } else {
            super.keyDown(with: event)
        }
    }
    
    private func setupWindow() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true  // Enable dragging
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        
        styleMask.insert(.fullSizeContentView)
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]
        
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let contentView = ChatInputView()
        let hostingView = NSHostingView(rootView: contentView)
        applyChatPanelCornerMask(hostingView, radius: 16)
        self.contentView = hostingView
        
        // Set compact size for single-line input panel
        let preferredSize = CGSize(width: 500, height: 60)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionInCenter() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Position in the center-bottom of the screen (like a search bar)
        let xPosition = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let yPosition = screenFrame.minY + 100 // 100pt from bottom
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

// MARK: - Chat Messages View (Redesigned for standalone panel)
struct ChatMessagesView: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("AI Assistant")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()

                Button(action: {
                    screenAssistantManager.resetConversationContext()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                        Text("Reset Context")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                }
                .disabled(screenAssistantManager.isLoading)
                .buttonStyle(PlainButtonStyle())
                .help("Clear conversation and attachments")
                
                Button(action: {
                    screenAssistantManager.closePanels()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close assistant")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            
            Divider()
            
            // Chat content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if screenAssistantManager.chatMessages.isEmpty {
                            VStack(spacing: 20) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 60))
                                    .foregroundColor(.blue.opacity(0.6))
                                
                                VStack(spacing: 8) {
                                    Text("AI Assistant")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Start a conversation to see your chat history here")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 80)
                        } else {
                            ForEach(screenAssistantManager.chatMessages) { message in
                                StreamingChatMessageBubble(message: message)
                                    .id(message.id)
                            }
                            
                            if screenAssistantManager.isLoading {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("AI is thinking...")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .onChange(of: screenAssistantManager.chatMessages.count) { _, _ in
                    if let lastMessage = screenAssistantManager.chatMessages.last {
                        withAnimation(.easeOut(duration: 0.5)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: screenAssistantManager.isLoading) { _, _ in
                    if screenAssistantManager.isLoading {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                if let lastMessage = screenAssistantManager.chatMessages.last {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(ChatPanelsVisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
    }
}

// MARK: - Chat Input View (Single Line Panel)
struct ChatInputView: View {
    @ObservedObject var screenAssistantManager = ScreenAssistantManager.shared
    @State private var messageText = ""
    @State private var isDraggingFiles = false
    @State private var showingApiKeyAlert = false
    @FocusState private var isTextFieldFocused: Bool
    
    // Current model information
    private var currentProvider: AIModelProvider {
        Defaults[.selectedAIProvider]
    }
    
    private var currentModel: AIModel? {
        Defaults[.selectedAIModel]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Current model indicator
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: iconForProvider(currentProvider))
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text(currentModel?.name ?? currentProvider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if currentModel?.supportsThinking == true && Defaults[.enableThinkingMode] {
                        Text("• Thinking")
                            .font(.caption2)
                            .foregroundColor(.purple)
                    }
                }
                
                Spacer()
                
                Button("Change", action: openModelSelection)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.05))
            
            // File attachments row (if any)
            if !screenAssistantManager.attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(screenAssistantManager.attachedFiles) { file in
                            AttachedFileChip(file: file) {
                                screenAssistantManager.removeFile(file)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.05))
                
                Divider()
            }
            
            // Single line input row
            HStack(spacing: 12) {
                // Add files button
                AddFilesButton()
                
                // Screenshot snipping button
                ScreenshotButton()
                
                // Text input - SINGLE LINE
                TextField("Ask me anything...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .onSubmit {
                        sendMessage()
                    }
                
                // Model selection button
                Button(action: openModelSelection) {
                    Image(systemName: "brain.head.profile.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Choose AI model")
                
                // Recording button
                RecordingButton()
                
                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12))
                        .padding(8)
                        .background(canSend ? Color.blue : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSend)
            }
            .padding(12)
        }
        .background(ChatPanelsVisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingFiles) { providers in
            handleFilesDrop(providers)
        }
        .alert("API Key Required", isPresented: $showingApiKeyAlert) {
            Button("Open Model Settings") {
                openModelSelection()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please configure your API key for the selected AI provider in model settings.")
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
    }
    
    private func iconForProvider(_ provider: AIModelProvider) -> String {
        switch provider {
        case .gemini: return "sparkles"
        case .openai: return "brain.head.profile"
        case .claude: return "doc.text"
        case .local: return "server.rack"
        case .groq: return "bolt.fill"
        }
    }
    
    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !screenAssistantManager.attachedFiles.isEmpty
    }
    
    private func sendMessage() {
        // Check if API key is configured for the selected provider.
        // A provider with no key account (local models) needs none.
        let provider = Defaults[.selectedAIProvider]
        if let account = provider.keyAccount, !KeychainAIKeyStore.shared.hasKey(account) {
            showingApiKeyAlert = true
            return
        }
        
        // Prepare the message
        let userMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        if userMessage.isEmpty && screenAssistantManager.attachedFiles.isEmpty {
            return
        }
        
        // Send message through manager
        screenAssistantManager.sendMessage(userMessage)
        messageText = ""
    }
    
    private func openModelSelection() {
        let panel = ModelSelectionPanel()
        panel.positionInCenter()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        
        // Activate the app to ensure proper focus handling
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func handleFilesDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        screenAssistantManager.addFiles([url])
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Enhanced Chat Message Bubble (No Auto-Streaming)
struct StreamingChatMessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isFromUser {
                Spacer()
            }
            
            // Avatar
            if !message.isFromUser {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())
            }
            
            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 8) {
                // Header with name and timestamp
                HStack {
                    Text(message.isFromUser ? "You" : "AI Assistant")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(message.isFromUser ? .blue : .green)
                    
                    Spacer()
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // File attachments (if any)
                if let files = message.attachedFiles, !files.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(files.prefix(3)) { file in
                            HStack(spacing: 4) {
                                Image(systemName: file.type.iconName)
                                    .font(.caption2)
                                Text(file.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        if files.count > 3 {
                            Text("+\(files.count - 3) more")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Message content - NO AUTO STREAMING
                MarkdownText(content: message.content)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.isFromUser ? Color.blue : Color.gray.opacity(0.15))
                    )
                    .foregroundColor(message.isFromUser ? .white : .primary)
            }
            .frame(maxWidth: 400, alignment: message.isFromUser ? .trailing : .leading)
            
            // User avatar
            if message.isFromUser {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 32, height: 32)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Note: Shared Components (MarkdownText, AttachedFileChip, AddFilesButton, RecordingButton, ApiKeyAlertView) 
// are defined in ScreenAssistantPanel.swift to avoid redeclaration conflicts.

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
                    .font(.system(size: 20))
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
            return .green
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
