//
//  InPlayerNotificationBanner.swift
//  DynamicIsland
//
//  This file is part of Atoll.
//  Copyright (C) 2024 Atoll contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI

struct InPlayerNotificationBanner: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    @State private var isVisible = false

    var body: some View {
        if isVisible, let notification = notificationManager.currentNotification {
            HStack(spacing: 6) {
                if let icon = notification.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .clipShape(Circle())
                }

                Text(notification.sender)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Text(notification.filteredContent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    func show() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isVisible = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isVisible = false
                }
            }
        }
    }
}
