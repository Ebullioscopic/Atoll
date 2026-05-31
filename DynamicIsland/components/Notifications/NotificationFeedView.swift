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

import Defaults
import SwiftUI

struct NotificationFeedView: View {
    @ObservedObject var feedManager = NotificationFeedManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Activity Feed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !feedManager.feedItems.isEmpty {
                    Button("Clear") {
                        feedManager.clearFeed()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            if feedManager.feedItems.isEmpty {
                Text("No recent activity")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(feedManager.feedItems) { item in
                            FeedItemRow(item: item)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(.bottom, 6)
    }
}

struct FeedItemRow: View {
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(item.category == .hermesSession ? Color.purple : Color.blue)
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.relativeTime)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}
