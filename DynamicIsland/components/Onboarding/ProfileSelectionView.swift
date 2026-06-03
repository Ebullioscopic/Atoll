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

struct UserProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let gradient: [Color]
}

struct ProfileSelectionView: View {
    @State private var selectedProfiles: Set<String> = []
    let onContinue: (Set<String>) -> Void
    
    let profiles: [UserProfile] = [
        UserProfile(
            id: "developer",
            name: String(localized: "Developer"),
            icon: "terminal.fill",
            description: String(localized: "Code and debug with color picker, stats monitoring, and screen assistant."),
            gradient: [Color.blue, Color.purple]
        ),
        UserProfile(
            id: "designer",
            name: String(localized: "Designer"),
            icon: "paintbrush.fill",
            description: String(localized: "Create and design with color picker, mirror, and visual effects."),
            gradient: [Color.pink, Color.orange]
        ),
        UserProfile(
            id: "lightuse",
            name: String(localized: "Light Use"),
            icon: "sparkles",
            description: String(localized: "Simple and minimal interface with just the essentials for everyday tasks."),
            gradient: [Color.green, Color.mint]
        ),
        UserProfile(
            id: "student",
            name: String(localized: "Student"),
            icon: "book.fill",
            description: String(localized: "Stay organized with calendar, timer, and battery monitoring."),
            gradient: [Color.indigo, Color.cyan]
        )
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .padding(.bottom, 8)
                
                Text("Choose Your Profile")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Select one or more profiles to customize your experience")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 20)
            
            // Profile Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        isSelected: selectedProfiles.contains(profile.id),
                        onTap: {
                            toggleProfile(profile.id)
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue Button
            Button(action: {
                if !selectedProfiles.isEmpty {
                    onContinue(selectedProfiles)
                }
            }) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedProfiles.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
    
    private func toggleProfile(_ profileId: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedProfiles.contains(profileId) {
                selectedProfiles.remove(profileId)
            } else {
                selectedProfiles.insert(profileId)
            }
        }
    }
}

struct ProfileCard: View {
    let profile: UserProfile
    let isSelected: Bool
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: profile.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(.linearGradient(colors: profile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.linearGradient(colors: profile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                Text(profile.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(profile.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(height: 160)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ?
                          LinearGradient(colors: profile.gradient.map { $0.opacity(0.15) }, startPoint: .topLeading, endPoint: .bottomTrailing) :
                          LinearGradient(colors: [Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ?
                        LinearGradient(colors: profile.gradient, startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isSelected ? 2 : 0
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .shadow(color: isSelected ? profile.gradient[0].opacity(0.3) : .clear, radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Profile Settings Configuration

func applyProfileSettings(_ profiles: Set<String>) {
    // Clipboard is ALWAYS enabled (per user request)
    Defaults[.enableClipboardManager] = true
    
    // Developer Profile Settings
    let isDeveloper = profiles.contains("developer")
    if isDeveloper {
        Defaults[.enableColorPickerFeature] = true
        Defaults[.enableStatsFeature] = true
        Defaults[.enableTerminalFeature] = true
        Defaults[.enableTimerFeature] = true
        Defaults[.enableScreenAssistant] = true
        Defaults[.showMirror] = false
        Defaults[.enableMinimalisticUI] = false
    }
    
    // Designer Profile Settings
    let isDesigner = profiles.contains("designer")
    if isDesigner {
        Defaults[.enableColorPickerFeature] = true
        Defaults[.showMirror] = true
        Defaults[.lightingEffect] = true
        Defaults[.inlineHUD] = true
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = false
        Defaults[.enableMinimalisticUI] = false
        Defaults[.enableScreenAssistant] = false
    }
    
    // Light Use Profile Settings
    let isLightUse = profiles.contains("lightuse")
    if isLightUse {
        Defaults[.enableMinimalisticUI] = true
        Defaults[.enableColorPickerFeature] = false
        Defaults[.showMirror] = false
        Defaults[.enableStatsFeature] = false
        Defaults[.enableTimerFeature] = true
        Defaults[.inlineHUD] = true
        Defaults[.enableScreenAssistant] = false
        Defaults[.enableLyrics] = false
    }
    
    // Student Profile Settings
    let isStudent = profiles.contains("student")
    if isStudent {
        Defaults[.enableTimerFeature] = true
        Defaults[.enableColorPickerFeature] = false
        Defaults[.showMirror] = false
        Defaults[.enableStatsFeature] = false
        Defaults[.enableMinimalisticUI] = false
        Defaults[.enableScreenAssistant] = false
    }
    
    // If Light Use is NOT selected but others are, ensure minimalistic is OFF
    if !isLightUse && !profiles.isEmpty {
        Defaults[.enableMinimalisticUI] = false
    }
    
    // Common settings for all profiles
    Defaults[.menubarIcon] = true
    Defaults[.enableHaptics] = true
    
    // Lyrics disabled by default for all profiles
    Defaults[.enableLyrics] = false
    
    // Weather widget defaults to inline style
    Defaults[.lockScreenWeatherWidgetStyle] = .inline
    
    // Auto-detect notch: Dynamic Island for non-notch Macs, standard notch otherwise
    if mainScreenHasNotch() {
        Defaults[.externalDisplayStyle] = .notch
    } else {
        Defaults[.externalDisplayStyle] = .dynamicIsland
    }
    
    // Lock screen glass: custom liquid glass v11 on macOS 26+
    if #available(macOS 26.0, *) {
        Defaults[.lockScreenGlassStyle] = .liquid
        Defaults[.lockScreenGlassCustomizationMode] = .customLiquid
        Defaults[.lockScreenMusicLiquidGlassVariant] = .v11
    }
    
    print("✅ Applied profile settings for: \(profiles.joined(separator: ", "))")
}

/// Returns `true` when the main screen has a physical notch (safe area insets > 0).
private func mainScreenHasNotch() -> Bool {
    guard let screen = NSScreen.main else { return false }
    return screen.safeAreaInsets.top > 0
}

#Preview {
    ProfileSelectionView(onContinue: { profiles in
        print("Selected profiles: \(profiles)")
    })
}
