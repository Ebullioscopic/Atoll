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

// MARK: - Privacy Indicator Type
enum PrivacyIndicatorType {
    case camera
    case microphone
    
    var icon: String {
        switch self {
        case .camera:
            return "video.fill"
        case .microphone:
            return "mic.fill"
        }
    }
    
    var label: String {
        switch self {
        case .camera:
            return String(localized: "Camera Active")
        case .microphone:
            return String(localized: "Microphone Active")
        }
    }
    
    var accessibilityLabel: String {
        switch self {
        case .camera:
            return String(localized: "Camera is being used by an application")
        case .microphone:
            return String(localized: "Microphone is being used by an application")
        }
    }
}

// MARK: - Privacy Indicator Icon View
struct PrivacyIndicatorIcon: View {
    // MARK: - Properties
    let type: PrivacyIndicatorType
    let showLabel: Bool
    
    @State private var isAnimating: Bool = false
    
    // MARK: - Initialization
    init(type: PrivacyIndicatorType, showLabel: Bool = false) {
        self.type = type
        self.showLabel = showLabel
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: 4) {
            // Icon with glow effect
            ZStack {
                // Background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.4),
                                Color.orange.opacity(0.2),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 12
                        )
                    )
                    .frame(width: 24, height: 24)
                    .opacity(isAnimating ? 0.8 : 0.5)
                
                // Icon background circle
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 18, height: 18)
                
                // Icon
                Image(systemName: type.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .frame(width: 24, height: 24)
            
            // Optional label
            if showLabel {
                Text(type.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
            }
        }
        .accessibilityLabel(type.accessibilityLabel)
        .onAppear {
            startPulseAnimation()
        }
    }
    
    // MARK: - Animation
    private func startPulseAnimation() {
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            isAnimating = true
        }
    }
}

// MARK: - Privacy Indicator Container
/// Container view that shows both camera and microphone indicators based on layout
struct PrivacyIndicatorContainer: View {
    // MARK: - Environment
    @EnvironmentObject var privacyManager: PrivacyIndicatorManager
    
    // MARK: - Properties
    let showLabels: Bool
    let spacing: CGFloat
    
    // MARK: - Initialization
    init(showLabels: Bool = false, spacing: CGFloat = 8) {
        self.showLabels = showLabels
        self.spacing = spacing
    }
    
    // MARK: - Body
    var body: some View {
        HStack(spacing: spacing) {
            // Microphone indicator (on the left when both are shown)
            if privacyManager.indicatorLayout.showsMicrophoneIndicator {
                PrivacyIndicatorIcon(type: .microphone, showLabel: showLabels)
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Camera indicator (on the right when both are shown)
            if privacyManager.indicatorLayout.showsCameraIndicator {
                PrivacyIndicatorIcon(type: .camera, showLabel: showLabels)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: privacyManager.indicatorLayout)
    }
}

// MARK: - Privacy Indicator Detail View
/// Detailed view showing privacy indicator status (for settings/tips)
struct PrivacyIndicatorDetailView: View {
    @EnvironmentObject var privacyManager: PrivacyIndicatorManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Privacy Indicators")
                .font(.headline)
            
            // Camera status
            HStack(spacing: 12) {
                PrivacyIndicatorIcon(type: .camera)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera")
                        .font(.subheadline.weight(.medium))
                    
                    Text(privacyManager.cameraActive ? "Currently active" : "Not active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(privacyManager.cameraActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(10)
            
            // Microphone status
            HStack(spacing: 12) {
                PrivacyIndicatorIcon(type: .microphone)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone")
                        .font(.subheadline.weight(.medium))
                    
                    Text(privacyManager.microphoneActive ? "Currently active" : "Not active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(privacyManager.microphoneActive ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(10)
            
            // Info text
            Text("These indicators appear in the notch when apps are using your camera or microphone, matching macOS's native privacy indicators.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Preview
#Preview("Single Indicators") {
    VStack(spacing: 20) {
        PrivacyIndicatorIcon(type: .camera)
        PrivacyIndicatorIcon(type: .microphone)
        PrivacyIndicatorIcon(type: .camera, showLabel: true)
        PrivacyIndicatorIcon(type: .microphone, showLabel: true)
    }
    .padding()
    .background(Color.black)
}

#Preview("Container") {
    let manager = PrivacyIndicatorManager.shared
    
    VStack(spacing: 20) {
        Text("Both Active")
        PrivacyIndicatorContainer()
            .onAppear {
                manager.cameraActive = true
                manager.microphoneActive = true
            }
        
        Text("Camera Only")
        PrivacyIndicatorContainer()
            .onAppear {
                manager.cameraActive = true
                manager.microphoneActive = false
            }
        
        Text("Microphone Only")
        PrivacyIndicatorContainer()
            .onAppear {
                manager.cameraActive = false
                manager.microphoneActive = true
            }
    }
    .padding()
    .background(Color.black)
    .environmentObject(manager)
}

#Preview("Detail View") {
    let manager = PrivacyIndicatorManager.shared
    
    PrivacyIndicatorDetailView()
        .padding()
        .environmentObject(manager)
        .onAppear {
            manager.cameraActive = true
            manager.microphoneActive = false
        }
}
