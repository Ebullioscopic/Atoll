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
        // Check if API key is configured for the selected provider
        let provider = Defaults[.selectedAIProvider]
        var apiKey = ""
        
        switch provider {
        case .gemini:
            apiKey = Defaults[.geminiApiKey]
        case .openai:
            apiKey = Defaults[.openaiApiKey]
        case .claude:
            apiKey = Defaults[.claudeApiKey]
        case .local:
            // Local models don't need API keys
            apiKey = "local"
        case .groq:
            apiKey = Defaults[.groqApiKey]
        }
        
        if apiKey.isEmpty {
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
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
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
