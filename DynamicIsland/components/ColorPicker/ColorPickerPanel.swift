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
import Cocoa
import Defaults

private func applyColorPickerCornerMask(_ view: NSView, radius: CGFloat) {
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    view.layer?.cornerRadius = radius
    view.layer?.backgroundColor = NSColor.clear.cgColor
    if #available(macOS 13.0, *) {
        view.layer?.cornerCurve = .continuous
    }
}

class ColorPickerPanelManager: ObservableObject {
    static let shared = ColorPickerPanelManager()
    
    private var panel: ColorPickerPanel?
    
    private init() {}
    
    func showColorPickerPanel() {
        hideColorPickerPanel() // Close any existing panel
        
        let newPanel = ColorPickerPanel()
        self.panel = newPanel
        
        // Position the panel
        newPanel.positionPanel()
        
        // Make the panel visible and focused
        newPanel.makeKeyAndOrderFront(nil)
        newPanel.orderFrontRegardless()
        
        // Activate the app to ensure proper focus handling
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the panel becomes the key window for input
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            newPanel.makeKey()
        }
        
        print("ColorPicker: Panel shown and positioned")
    }
    
    func hideColorPickerPanel() {
        panel?.close()
        panel = nil
        print("ColorPicker: Panel hidden")
    }
    
    func toggleColorPickerPanel() {
        if let panel = panel, panel.isVisible {
            hideColorPickerPanel()
        } else {
            showColorPickerPanel()
        }
    }
    
    var isPanelVisible: Bool {
        return panel?.isVisible ?? false
    }
}

class ColorPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        
        setupPanel()
    }
    
    private func setupPanel() {
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        
        // Allow dragging from any part of the window
        styleMask.insert(.fullSizeContentView)
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary  // Float above full-screen apps
        ]
        
        ScreenCaptureVisibilityManager.shared.register(self, scope: .panelsOnly)
        
        // Accept mouse moved events for proper hover behavior
        acceptsMouseMovedEvents = true
        
        let panelView = ColorPickerPanelView {
            ColorPickerPanelManager.shared.hideColorPickerPanel()
        }
        
        let hostingView = NSHostingView(rootView: panelView)
        applyColorPickerCornerMask(hostingView, radius: 12)
        contentView = hostingView
        
        // Set initial size
        let preferredSize = CGSize(width: 450, height: 600)
        hostingView.setFrameSize(preferredSize)
        setContentSize(preferredSize)
    }
    
    func positionPanel() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = frame
        
        // Check if we have a saved position
        if let savedPosition = getSavedPosition() {
            // Validate saved position is still on screen
            let savedFrame = NSRect(origin: savedPosition, size: panelFrame.size)
            if screenFrame.intersects(savedFrame) {
                setFrameOrigin(savedPosition)
                return
            }
        }
        
        // Default to center of screen (not top center)
        let xPosition = (screenFrame.width - panelFrame.width) / 2 + screenFrame.minX
        let yPosition = (screenFrame.height - panelFrame.height) / 2 + screenFrame.minY
        
        setFrameOrigin(NSPoint(x: xPosition, y: yPosition))
    }
    
    private func getSavedPosition() -> NSPoint? {
        let defaults = UserDefaults.standard
        let x = defaults.double(forKey: "colorPickerPanelPositionX")
        let y = defaults.double(forKey: "colorPickerPanelPositionY")
        
        // Check if we have valid saved coordinates (not default 0.0)
        if x != 0.0 || y != 0.0 {
            return NSPoint(x: x, y: y)
        }
        return nil
    }
    
    private func saveCurrentPosition() {
        let currentOrigin = frame.origin
        let defaults = UserDefaults.standard
        defaults.set(currentOrigin.x, forKey: "colorPickerPanelPositionX")
        defaults.set(currentOrigin.y, forKey: "colorPickerPanelPositionY")
    }
    
    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
        // Save position whenever it changes (user dragging)
        saveCurrentPosition()
    }
    
    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }
}

struct ColorPickerPanelView: View {
    let onClose: () -> Void
    @ObservedObject var colorPickerManager = ColorPickerManager.shared
    @State private var searchText = ""
    @State private var selectedColor: PickedColor?
    @State private var showingDeleteAlert = false
    @State private var colorToDelete: PickedColor?
    
    var filteredColors: [PickedColor] {
        if searchText.isEmpty {
            return colorPickerManager.colorHistory
        } else {
            return colorPickerManager.colorHistory.filter { color in
                color.hexString.localizedCaseInsensitiveContains(searchText) ||
                color.rgbString.localizedCaseInsensitiveContains(searchText) ||
                color.hslString.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            contentSection
        }
        .background(ColorPickerVisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .alert("Delete Color", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let color = colorToDelete {
                    colorPickerManager.removeColor(color)
                }
            }
        } message: {
            Text("Are you sure you want to delete this color from your history?")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Title and controls
            HStack {
                // Close button
                NativeStyleCloseButton(action: onClose)
                
                HStack(spacing: 8) {
                    Image(systemName: "eyedropper.halffull")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Text("Color Picker")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                // Controls
                HStack(spacing: 8) {
                    // Pick Color Button
                    Button(action: {
                        colorPickerManager.startColorPicking()
                        onClose() // Close panel when starting to pick
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Pick Color")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Clear History Button
                    Button(action: {
                        colorPickerManager.clearHistory()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(colorPickerManager.colorHistory.isEmpty)
                }
            }
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                
                TextField("Search colors...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(16)
    }
    
    private var contentSection: some View {
        HSplitView {
            // Left side - Color list
            colorListSection
                .frame(minWidth: 200)
            
            // Right side - Color details
            colorDetailsSection
                .frame(minWidth: 220)
        }
        .frame(maxHeight: .infinity)
    }
    
    private var colorListSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Colors")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(filteredColors.count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Color list
            if filteredColors.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredColors) { color in
                            ColorListRow(
                                color: color,
                                isSelected: selectedColor?.id == color.id,
                                onSelect: { selectedColor = color },
                                onDelete: {
                                    colorToDelete = color
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    
    private var colorDetailsSection: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Color Details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            
            Divider()
                .background(Color.gray.opacity(0.3))
            
            // Details content
            if let color = selectedColor {
                ColorDetailsView(color: color)
            } else {
                noSelectionView
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "eyedropper")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Colors Found")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                if searchText.isEmpty {
                    Text("Start picking colors to build your history")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("No colors match '\(searchText)'")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            
            Text("Select a color to view details")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ColorListRow: View {
    let color: PickedColor
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Color preview
            Circle()
                .fill(color.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.2), lineWidth: 1)
                )
            
            // Color info
            VStack(alignment: .leading, spacing: 2) {
                Text(color.hexString)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                
                Text(timeAgoString(from: color.timestamp))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions (shown on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(color.hexString, forType: .string)
                        
                        if Defaults[.enableHaptics] {
                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(isSelected ? Color.blue.opacity(0.2) : (isHovered ? Color.gray.opacity(0.1) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onSelect()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return String(localized: "Just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(localized: "\(minutes)m ago")
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(localized: "\(hours)h ago")
        } else {
            let days = Int(interval / 86400)
            return String(localized: "\(days)d ago")
        }
    }
}

struct ColorDetailsView: View {
    let color: PickedColor
    @Default(.showColorFormats) var showColorFormats
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Large color preview
                VStack(spacing: 12) {
                    Rectangle()
                        .fill(color.color)
                        .frame(height: 80)
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                        )
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.2), radius: 4)
                    
                    Text("Picked \(timeAgoString(from: color.timestamp))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                // Color formats
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color Formats")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    
                    ForEach(color.allFormats) { format in
                        ColorFormatDetailRow(format: format, color: color)
                    }
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return String(localized: "just now")
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return String(localized: "\(minutes) minute\(minutes == 1 ? "" : "s") ago")
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(localized: "\(hours) hour\(hours == 1 ? "" : "s") ago")
        } else {
            let days = Int(interval / 86400)
            return String(localized: "\(days) day\(days == 1 ? "" : "s") ago")
        }
    }
}

struct ColorFormatDetailRow: View {
    let format: ColorFormat
    let color: PickedColor
    @State private var isHovered = false
    @State private var justCopied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(format.name)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(format.value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: copyFormat) {
                Image(systemName: justCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundColor(justCopied ? .green : .blue)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(isHovered || justCopied ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            copyFormat()
        }
    }
    
    private func copyFormat() {
        ColorPickerManager.shared.copyColorToClipboard(color, format: format)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            justCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                justCopied = false
            }
        }
    }
}

// Helper view for visual effects
struct ColorPickerVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Native Style Close Button Component
struct NativeStyleCloseButton: View {
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 13, height: 13)
                .background(isHovered ? Color.red.opacity(0.8) : Color.red)
                .clipShape(Circle())
                .scaleEffect(isHovered ? 1.1 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ColorPickerPanelView {
        print("Close panel")
    }
    .frame(width: 450, height: 600)
    .onAppear {
        ColorPickerManager.shared.colorHistory = PickedColor.sampleColors
    }
}
