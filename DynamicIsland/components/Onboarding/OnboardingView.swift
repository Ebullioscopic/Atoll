/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AVFoundation
import Defaults

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case musicPermission
    case profileSelection
    case finished
}

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var showFocusMonitoringChoice = false
    @State private var didPresentFocusMonitoringChoice = false
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: String(localized: "Enable Camera Access"),
                    description: String(localized: "Atoll includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app."),
                    privacyNote: String(localized: "Your camera is never used without your consent, and nothing is recorded or stored."),
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: String(localized: "Enable Calendar Access"),
                    description: String(localized: "Atoll can show all your upcoming events in one place. Access to your calendar is needed to display your schedule."),
                    privacyNote: String(localized: "Your calendar data is only used to show your events and is never shared."),
                    onAllow: {
                        Task {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .profileSelection
                        }
                    }
                )
                .transition(.opacity)
                
            case .profileSelection:
                ProfileSelectionView(
                    onContinue: { profiles in
                        applyProfileSettings(profiles)
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            guard !didPresentFocusMonitoringChoice else { return }
            didPresentFocusMonitoringChoice = true
            showFocusMonitoringChoice = true
        }
        .confirmationDialog(
            "Focus detection mode",
            isPresented: $showFocusMonitoringChoice,
            titleVisibility: .visible
        ) {
            Button("Use DevTools") {
                Defaults[.focusMonitoringMode] = .useDevTools
            }

            Button("Use without DevTools") {
                Defaults[.focusMonitoringMode] = .withoutDevTools
            }

            Button("Later", role: .cancel) {}
        } message: {
            Text("This is optional. You can change it any time from the menu bar.")
        }
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

}
