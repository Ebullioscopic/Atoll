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
import Defaults


struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController
    
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedMediaController: MediaControllerType = Defaults[.mediaController]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose a Music Source")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 24)

            Text("Select the music source you want to use. You can change this later in the app settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(availableMediaControllers) { controller in
                        ControllerOptionView(
                            controller: controller,
                            isSelected: self.selectedMediaController == controller
                        )
                        .onTapGesture {
                            self.selectedMediaController = controller
                        }
                    }
                }
                .padding()
            }

            Spacer()

            Button("Continue", action: {
                self.mediaController = self.selectedMediaController
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
                onContinue()
            })
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(controller.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if controller == .youtubeMusic, let url = URL(string: "https://github.com/th-ch/youtube-music") {
                    Link("View on GitHub: th-ch/youtube-music", destination: url)
                        .font(.subheadline)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return String(localized: "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version.")
        case .spotify:
            return String(localized: "Connects directly to the Spotify app.")
        case .appleMusic:
            return String(localized: "Connects directly to the Apple Music app.")
        case .youtubeMusic:
            return String(localized: "Requires a third-party client with API plugin enabled.")
        case .amazonMusic:
            return String(localized: "Uses macOS Now Playing when the Amazon Music app is the active media source. Playback controls follow the system Now Playing target. Scrubbing the timeline may not work if the Amazon Music app does not support remote seek.")
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
