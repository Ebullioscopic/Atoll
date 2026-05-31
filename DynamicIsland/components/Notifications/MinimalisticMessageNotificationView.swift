//
//  MinimalisticMessageNotificationView.swift
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

struct MinimalisticMessageNotificationView: View {
    @ObservedObject var notificationManager = NotificationManager.shared

    var body: some View {
        if let notification = notificationManager.currentNotification {
            HStack(spacing: 8) {
                if Defaults[.showProfilePictures], let pic = notification.profilePicture {
                    Image(nsImage: pic)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                } else if let icon = notification.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(Circle())
                }

                Text(notification.sender)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()

                MarqueeText(.constant(notification.filteredContent), font: .caption, nsFont: .body)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: 60)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
