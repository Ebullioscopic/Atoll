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

import SwiftUI

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
