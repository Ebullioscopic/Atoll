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

final class LockScreenLiveActivityOverlayModel: ObservableObject {
	@Published var scale: CGFloat = 0.6
	@Published var opacity: Double = 0
}

struct LockScreenLiveActivityOverlay: View {
	@ObservedObject var model: LockScreenLiveActivityOverlayModel
	@ObservedObject var animator: LockIconAnimator
	let notchSize: CGSize
	var isDynamicIslandMode: Bool = false

	private var indicatorSize: CGFloat {
		max(0, notchSize.height - 12)
	}

	private var horizontalPadding: CGFloat {
		isDynamicIslandMode ? 8 : cornerRadiusInsets.closed.bottom
	}

	private var totalWidth: CGFloat {
		notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)
	}

	private var collapsedScale: CGFloat {
		Self.collapsedScale(for: notchSize)
	}

	private var topOffset: CGFloat {
		isDynamicIslandMode ? dynamicIslandTopOffset : 0
	}

    @State private var isHovering: Bool = false

	var body: some View {
		HStack(spacing: 0) {
			Color.clear
				.overlay(alignment: .leading) {
					LockIconProgressView(progress: animator.progress)
						.frame(width: indicatorSize, height: indicatorSize)
				}
				.frame(width: indicatorSize, height: notchSize.height)

			Rectangle()
				.fill(.black)
				.frame(width: notchSize.width, height: notchSize.height)

			Color.clear
				.frame(width: indicatorSize, height: notchSize.height)
		}
		.frame(width: notchSize.width + (indicatorSize * 2), height: notchSize.height)
		.padding(.horizontal, horizontalPadding)
		.background(Color.black)
		.clipShape(
			isDynamicIslandMode
				? AnyShape(DynamicIslandPillShape(
					cornerRadius: max(notchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
				  ))
				: AnyShape(NotchShape(
					topCornerRadius: cornerRadiusInsets.closed.top,
					bottomCornerRadius: cornerRadiusInsets.closed.bottom
				  ))
		)
		.padding(.top, topOffset)
		.frame(width: totalWidth, height: notchSize.height + topOffset)
		.scaleEffect(x: max(model.scale, collapsedScale) * (isHovering ? 1.03 : 1.0), 
                     y: 1 * (isHovering ? 1.03 : 1.0), 
                     anchor: .center)
		.opacity(model.opacity)
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.2)) {
                isHovering = hovering
            }
            if hovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            }
        }
	}
}

extension LockScreenLiveActivityOverlay {
	static func collapsedScale(for notchSize: CGSize, isDynamicIslandMode: Bool = false) -> CGFloat {
		let indicatorSize = max(0, notchSize.height - 12)
		let horizontalPadding = isDynamicIslandMode ? 8.0 : cornerRadiusInsets.closed.bottom
		let totalWidth = notchSize.width + (indicatorSize * 2) + (horizontalPadding * 2)
		guard totalWidth > 0 else { return 1 }
		return notchSize.width / totalWidth
	}
}
