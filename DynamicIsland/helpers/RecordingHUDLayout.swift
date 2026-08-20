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

import CoreGraphics

enum RecordingHUDPresentation: String, CaseIterable {
    case compact
    case inline
    case expanded

    var extraWidth: CGFloat {
        switch self {
        case .compact:
            return 132
        case .inline:
            return 176
        case .expanded:
            return 140
        }
    }

    var extraHeight: CGFloat {
        self == .expanded ? 70 : 0
    }
}

struct RecordingHUDLayout {
    let isVisible: Bool
    let stopControlsEnabled: Bool
    let hoverStyle: RecordingHoverStyle
    let expanded: Bool

    var presentation: RecordingHUDPresentation {
        guard isVisible else { return .compact }
        guard stopControlsEnabled && expanded else { return .compact }

        switch hoverStyle {
        case .default:
            return .expanded
        case .inline:
            return .inline
        }
    }

    var showsDefaultExpansion: Bool {
        isVisible && presentation == .expanded
    }

    var showsInlineExpansion: Bool {
        isVisible && presentation == .inline
    }

    var extraWidth: CGFloat {
        isVisible ? presentation.extraWidth : 0
    }

    var extraHeight: CGFloat {
        isVisible ? presentation.extraHeight : 0
    }

    func size(closedNotchSize: CGSize, effectiveClosedNotchHeight: CGFloat) -> CGSize? {
        guard isVisible else { return nil }

        return CGSize(
            width: closedNotchSize.width + extraWidth,
            height: effectiveClosedNotchHeight + extraHeight
        )
    }
}

func makeRecordingHUDLayout(
    notchState: NotchState,
    screenRecordingDetectionEnabled: Bool,
    showRecordingIndicator: Bool,
    hideOnClosed: Bool,
    isRecording: Bool,
    closedMusicPairingEligible: Bool,
    recordingControlMode: RecordingControlMode,
    canStopFromHUD: Bool,
    enableMinimalisticUI: Bool,
    recordingHoverStyle: RecordingHoverStyle,
    expanded: Bool
) -> RecordingHUDLayout {
    let isVisible = notchState == .closed
        && screenRecordingDetectionEnabled
        && showRecordingIndicator
        && !hideOnClosed
        && isRecording
        && !closedMusicPairingEligible

    let stopControlsEnabled = recordingControlMode == .withStopButton
        && canStopFromHUD

    return RecordingHUDLayout(
        isVisible: isVisible,
        stopControlsEnabled: stopControlsEnabled,
        hoverStyle: enableMinimalisticUI ? recordingHoverStyle : .inline,
        expanded: expanded
    )
}
