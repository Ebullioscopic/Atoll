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
import Defaults

struct LocalSendLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @StateObject private var localSend = LocalSendService.shared
    
    @State private var isHovering: Bool = false
    @State private var isExpanded: Bool = false
    
    private var tint: Color {
        switch localSend.transferState {
        case .completed:
            return .green
        case .failed, .rejected:
            return .red
        default:
            return .accentColor
        }
    }
    
    private var isActive: Bool {
        localSend.isSending || localSend.transferState == .completed ||
        isFailedOrRejected
    }
    
    private var isFailedOrRejected: Bool {
        if case .failed = localSend.transferState { return true }
        if case .rejected = localSend.transferState { return true }
        return false
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: upload icon capsule
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tint.opacity(0.14))
                                
                                Image(systemName: leftIcon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            .frame(
                                width: vm.effectiveClosedNotchHeight - 12,
                                height: vm.effectiveClosedNotchHeight - 12
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(
                    width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)) : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )
            
            // Center: closed notch body (slightly wider during transfers)
            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width
                        + (isHovering ? 8 : 0)
                        + (isActive ? 40 : 0)
                )
            
            // Right side: progress ring or status icon
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            rightContent
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(
                    width: isExpanded ? max(60, vm.effectiveClosedNotchHeight) : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = newValue
            }
        }
    }
    
    private var leftIcon: String {
        // Always show document upload icon on left side
        return "document.badge.arrow.up.fill"
    }
    
    @ViewBuilder
    private var rightContent: some View {
        switch localSend.transferState {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .semibold))
                .padding(.trailing, 6)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 16, weight: .semibold))
                .padding(.trailing, 6)
        case .rejected:
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16, weight: .semibold))
                .padding(.trailing, 6)
        case .sending, .idle:
            LocalSendProgressRing(progress: localSend.sendProgress)
                .padding(.trailing, 6)
        }
    }
}

// MARK: - Progress Ring

private struct LocalSendProgressRing: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)
            
            if progress > 0.99 {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 20, height: 20)
    }
}
