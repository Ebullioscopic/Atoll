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
