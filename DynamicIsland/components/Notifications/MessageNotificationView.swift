//
//  MessageNotificationView.swift
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

import Defaults
import SwiftUI

struct MessageNotificationView: View {
    @ObservedObject var notificationManager = NotificationManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notificationManager.notifications.indices, id: \.self) { index in
                    let notification = notificationManager.notifications[index]
                    notificationRow(notification)
                    if index < notificationManager.notifications.count - 1 {
                        Divider().opacity(0.3)
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 300)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func notificationRow(_ notification: MessageNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if Defaults[.showProfilePictures], let pic = notification.profilePicture {
                Image(nsImage: pic)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            } else if let icon = notification.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.sender)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(notification.filteredContent)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(notification.timestamp, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
