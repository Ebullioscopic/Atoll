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
import LottieUI
import Defaults

struct AnimationEditorView: View {
    @Environment(\.dismiss) var dismiss
    
    let sourceURL: URL
    let isRemoteURL: Bool
    @Binding var animation: CustomIdleAnimation?
    let existingAnimation: CustomIdleAnimation?
    
    @State private var name: String
    @State private var speed: CGFloat = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var cropWidth: CGFloat = 30
    @State private var cropHeight: CGFloat = 20
    @State private var rotation: CGFloat = 0
    @State private var opacity: CGFloat = 1.0
    @State private var paddingBottom: CGFloat = 0
    @State private var expandWithAnimation: Bool = false
    @State private var loopMode: AnimationLoopMode = .loop
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isImporting = false
    
    // Preview state
    @State private var previewScale: CGFloat = 10.0
    
    init(sourceURL: URL, isRemoteURL: Bool, animation: Binding<CustomIdleAnimation?>, existingAnimation: CustomIdleAnimation? = nil) {
        self.sourceURL = sourceURL
        self.isRemoteURL = isRemoteURL
        self._animation = animation
        self.existingAnimation = existingAnimation
        
        // Initialize from existing animation if editing, otherwise from URL
        if let existing = existingAnimation {
            _name = State(initialValue: existing.name)
            _speed = State(initialValue: existing.speed)
            
            // Load from overrides if they exist
            let config = Defaults[.animationTransformOverrides][existing.id.uuidString] ?? .default
            _scale = State(initialValue: config.scale)
            _offsetX = State(initialValue: config.offsetX)
            _offsetY = State(initialValue: config.offsetY)
            _cropWidth = State(initialValue: config.cropWidth)
            _cropHeight = State(initialValue: config.cropHeight)
            _rotation = State(initialValue: config.rotation)
            _opacity = State(initialValue: config.opacity)
            _paddingBottom = State(initialValue: config.paddingBottom)
            _expandWithAnimation = State(initialValue: config.expandWithAnimation)
            _loopMode = State(initialValue: config.loopMode)
        } else {
            let fileName = sourceURL.deletingPathExtension().lastPathComponent
            _name = State(initialValue: fileName)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                previewPanel
                    .frame(minWidth: 320, maxWidth: 360)
                Divider()
                controlsPanel
            }
            Divider()
            footer
        }
        .frame(idealWidth: 980, idealHeight: 640)
        .frame(minWidth: 860, minHeight: 620)
        .fixedSize()
        .alert("Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Layout Sections
    
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(existingAnimation != nil ? "Edit Animation" : "Customize Animation")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }
    
    private var footer: some View {
        HStack {
            Label("Blue outline matches the notch canvas", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(existingAnimation != nil ? "Save Changes" : "Import") {
                importAnimation()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(name.isEmpty || isImporting)
        }
        .padding()
    }
    
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Preview")
                    .font(.headline)
                Text("Dash outline equals the exact notch bounds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            previewCanvas
            previewZoomControls
            previewStats
            Spacer(minLength: 0)
        }
        .padding(20)
    }
    
    @ViewBuilder
    private var previewCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)
            
            Rectangle()
                .strokeBorder(Color.blue.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                .frame(width: 30 * previewScale, height: 20 * previewScale)
            
            Group {
                LottieView(state: LUStateData(
                    type: .loadedFrom(sourceURL),
                    speed: speed,
                    loopMode: loopMode.lottieLoopMode
                ))
            }
            .frame(width: cropWidth * scale * previewScale, height: cropHeight * scale * previewScale)
            .offset(x: offsetX * previewScale, y: offsetY * previewScale)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .padding(.bottom, paddingBottom * previewScale)
            .clipped()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
    }
    
    private var previewZoomControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Preview Zoom", systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(previewScale))x")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewScale = max(1, previewScale - 1)
                    }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Slider(value: $previewScale, in: 1...10)
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewScale = min(10, previewScale + 1)
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                
                Button("Reset") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        previewScale = 10
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }
    
    private var previewStats: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Transform")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                PreviewStatChip(title: "Scale", value: String(format: "%.2fx", scale))
                PreviewStatChip(title: "Output", value: "\(Int(cropWidth * scale))x\(Int(cropHeight * scale)) px")
                PreviewStatChip(title: "Offset", value: String(format: "%.1f / %.1f", offsetX, offsetY))
            }
        }
    }
    
    private var controlsPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorSectionCard(title: "Animation Details", subtitle: "Give it a friendly name and control playback speed.") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Animation Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        ParameterSliderRow(
                            title: "Playback Speed",
                            value: $speed,
                            range: 0.1...3.0,
                            formatter: { String(format: "%.2fx", $0) },
                            resetLabel: "1x",
                            resetValue: 1.0,
                            step: 0.05
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Loop Mode")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Picker("Loop Mode", selection: $loopMode) {
                                ForEach(AnimationLoopMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                
                EditorSectionCard(title: "Size & Crop", subtitle: "Match the notch footprint or intentionally exceed it.") {
                    VStack(spacing: 12) {
                        ParameterSliderRow(
                            title: "Scale",
                            value: $scale,
                            range: 0.1...5.0,
                            formatter: { String(format: "%.2fx", $0) },
                            resetLabel: "Reset",
                            resetValue: 1.0
                        )
                        ParameterSliderRow(
                            title: "Visible Width",
                            value: $cropWidth,
                            range: 5...100,
                            formatter: { "\(Int($0)) px" },
                            resetLabel: "30",
                            resetValue: 30
                        )
                        ParameterSliderRow(
                            title: "Visible Height",
                            value: $cropHeight,
                            range: 5...100,
                            formatter: { "\(Int($0)) px" },
                            resetLabel: "20",
                            resetValue: 20
                        )
                    }
                }
                
                EditorSectionCard(title: "Position & Padding", subtitle: "Nudge the animation inside the notch.") {
                    VStack(spacing: 12) {
                        ParameterSliderRow(
                            title: "Horizontal Offset",
                            value: $offsetX,
                            range: -50...50,
                            formatter: { String(format: "%.1f px", $0) },
                            resetLabel: "Center",
                            resetValue: 0
                        )
                        ParameterSliderRow(
                            title: "Vertical Offset",
                            value: $offsetY,
                            range: -50...50,
                            formatter: { String(format: "%.1f px", $0) },
                            resetLabel: "Center",
                            resetValue: 0
                        )
                        ParameterSliderRow(
                            title: "Bottom Padding",
                            value: $paddingBottom,
                            range: -20...20,
                            formatter: { String(format: "%.1f px", $0) },
                            resetLabel: "Reset",
                            resetValue: 0
                        )
                    }
                }
                
                EditorSectionCard(title: "Transform & Display", subtitle: "Dial in the final polish.") {
                    VStack(spacing: 12) {
                        ParameterSliderRow(
                            title: "Rotation",
                            value: $rotation,
                            range: -180...180,
                            formatter: { String(format: "%.0f°", $0) },
                            resetLabel: "Reset",
                            resetValue: 0,
                            step: 1
                        )
                        ParameterSliderRow(
                            title: "Opacity",
                            value: $opacity,
                            range: 0...1,
                            formatter: { "\(Int($0 * 100))%" },
                            resetLabel: "100%",
                            resetValue: 1,
                            step: 0.01
                        )
                        Toggle(isOn: $expandWithAnimation) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Expand notch to follow animation width")
                                    .fontWeight(.medium)
                                Text("Enable when scaling beyond 30x20px so the Atoll opens gracefully.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                EditorSectionCard(title: "Quick Presets", subtitle: "Start from a popular layout and tweak from there.") {
                    let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        Button("Fit to Notch") {
                            withAnimation {
                                scale = 1.0
                                cropWidth = 30
                                cropHeight = 20
                                offsetX = 0
                                offsetY = 0
                                rotation = 0
                                paddingBottom = 0
                                expandWithAnimation = false
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Fill Notch") {
                            withAnimation {
                                scale = 1.5
                                cropWidth = 30
                                cropHeight = 20
                                offsetX = 0
                                offsetY = 0
                                paddingBottom = 0
                                expandWithAnimation = false
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Scale Up 2x") {
                            withAnimation {
                                scale = 2.0
                                expandWithAnimation = true
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Scale Down") {
                            withAnimation {
                                scale = 0.75
                            }
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Reset All") {
                            withAnimation {
                                scale = 1.0
                                cropWidth = 30
                                cropHeight = 20
                                offsetX = 0
                                offsetY = 0
                                rotation = 0
                                opacity = 1.0
                                speed = 1.0
                                paddingBottom = 0
                                expandWithAnimation = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sourceDescription: String {
        if let existing = existingAnimation {
            return existing.name
        }
        if isRemoteURL {
            return sourceURL.absoluteString
        }
        return sourceURL.deletingPathExtension().lastPathComponent
    }
    
    // MARK: - Import Logic
    
    private func importAnimation() {
        guard !name.isEmpty else { return }
        
        isImporting = true
        
        // Create animation config with transform settings
        let config = AnimationTransformConfig(
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY,
            cropWidth: cropWidth,
            cropHeight: cropHeight,
            rotation: rotation,
            opacity: opacity,
            paddingBottom: paddingBottom,
            expandWithAnimation: expandWithAnimation,
            loopMode: loopMode
        )
        
        // If editing existing animation, save transform config to overrides
        if let existing = existingAnimation {
            // Store only the transform config override
            var overrides = Defaults[.animationTransformOverrides]
            overrides[existing.id.uuidString] = config
            Defaults[.animationTransformOverrides] = overrides
            
            print("✅ [AnimationEditor] Saved transform override for: \(existing.name)")
            print("✅ [AnimationEditor] Override: \(config)")
            
            // Force view refresh by updating selectedIdleAnimation if this is the selected one
            if Defaults[.selectedIdleAnimation]?.id == existing.id {
                // Trigger refresh by re-setting the same animation
                let current = Defaults[.selectedIdleAnimation]
                Defaults[.selectedIdleAnimation] = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    Defaults[.selectedIdleAnimation] = current
                }
            }
            
            dismiss()
            return
        }
        
        // Import with config (new animation)
        let result = IdleAnimationManager.shared.importLottieFile(
            from: sourceURL,
            name: name,
            speed: speed
        )
        
        switch result {
        case .success(let importedAnimation):
            animation = importedAnimation
            dismiss()
            
        case .failure(let error):
            errorMessage = error.localizedDescription
            showingError = true
            isImporting = false
        }
    }
}

// MARK: - Supporting Views

private struct EditorSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ParameterSliderRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let formatter: (CGFloat) -> String
    var resetLabel: String?
    var resetValue: CGFloat?
    var step: CGFloat?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .fontWeight(.medium)
                Spacer()
                Text(formatter(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                slider
                if let resetLabel, let resetValue {
                    Button(resetLabel) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            value = resetValue
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }
    
    @ViewBuilder
    private var slider: some View {
        let binding = Binding<Double>(
            get: { Double(value) },
            set: { value = CGFloat($0) }
        )
        let bounds = Double(range.lowerBound)...Double(range.upperBound)
        if let step {
            Slider(value: binding, in: bounds, step: Double(step))
        } else {
            Slider(value: binding, in: bounds)
        }
    }
}

private struct PreviewStatChip: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}

// MARK: - Preview
#Preview {
    AnimationEditorView(
        sourceURL: URL(string: "https://assets9.lottiefiles.com/packages/lf20_mniampqn.json")!,
        isRemoteURL: true,
        animation: .constant(nil)
    )
}
