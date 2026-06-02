/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * Adapted from SwiftTerm (https://github.com/migueldeicaza/SwiftTerm)
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

import AppKit
import Foundation
import SwiftUI
import SwiftTerm
import Defaults

// MARK: - Stable Container

/// Container NSView that shields its terminal child from zero-sized frames.
///
/// When the notch closes, SwiftUI removes the `NSViewRepresentable` from the
/// hierarchy — but later re-adds the same `containerView` on reopen.  During
/// that insertion, SwiftUI momentarily sets the frame to `.zero`.  Without
/// protection, AppKit's autoresizing mask propagates the zero frame to the
/// terminal child, causing SwiftTerm's `processSizeChange` to resize the
/// emulator to 2 cols × 1 row (the enforced minimum), which destroys the
/// scrollback buffer.
///
/// We bypass `super.resizeSubviews(withOldSize:)` entirely and manually set
/// children to fill the container's bounds.  This avoids the autoresizing
/// calculation which produces corrupt geometry when `oldSize` was `.zero`
/// (recorded during the transient removal) but the child kept its previous
/// large frame.
final class StableTerminalContainerView: NSView {
    /// Identifies the gutter tint view so `resizeSubviews` can keep its ring mask in sync.
    static let gutterTintIdentifier = NSUserInterfaceItemIdentifier("terminalGutterTint")
    /// Identifies the custom scroll knob overlay so `resizeSubviews` leaves its frame
    /// alone (it's positioned from the scroll state, not stretched to fill the bounds).
    static let scrollKnobIdentifier = NSUserInterfaceItemIdentifier("terminalScrollKnob")

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        let size = bounds.size
        // Block degenerate sizes — the terminal would collapse to 2×1
        guard size.width >= 10, size.height >= 10 else { return }
        // Manually fill children to bounds — bypasses autoresizing math
        // that breaks when oldSize was zero but child kept its old frame.
        // The terminal view gets an inner inset so glyphs don't hug the edge;
        // the frosted blur underlay and the gutter tint stay full-bleed to the
        // rounded clip (the tint is masked to the ring so it only fills the inset
        // gutter, matching the terminal background without doubling over it).
        let inset = notchTerminalInnerTextInset
        let terminalFrame = bounds.insetBy(dx: inset, dy: inset)
        for child in subviews {
            if child is LocalProcessTerminalView {
                child.frame = terminalFrame
            } else if child.identifier == Self.scrollKnobIdentifier {
                // Positioned from scroll state in `updateScrollKnob`; don't stretch it.
                continue
            } else {
                child.frame = bounds
                if child.identifier == Self.gutterTintIdentifier {
                    Self.applyGutterMask(to: child, bounds: bounds, hole: terminalFrame)
                }
            }
        }
        MainActor.assumeIsolated {
            TerminalManager.shared.refreshScrollKnobLayout()
        }
    }

    /// Masks `view` to the gutter ring: the full bounds minus the inset `hole`
    /// where the terminal sits, using the even-odd fill rule.
    static func applyGutterMask(to view: NSView, bounds: CGRect, hole: CGRect) {
        let localBounds = CGRect(origin: .zero, size: bounds.size)
        let mask = (view.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        mask.fillRule = .evenOdd
        let path = CGMutablePath()
        path.addRect(localBounds)
        path.addRect(CGRect(x: hole.minX, y: hole.minY, width: hole.width, height: hole.height))
        mask.path = path
        mask.frame = localBounds
        view.layer?.mask = mask
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        // When re-inserted into a window (notch reopened), force a full
        // redraw so SwiftTerm re-renders the terminal buffer contents.
        for child in subviews {
            child.needsDisplay = true
        }
        Task { @MainActor in
            TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
        }
    }
}

// MARK: - Scroll Knob Overlay

/// Layer-backed rounded knob drawn on top of the terminal as a custom scrollbar.
///
/// SwiftTerm's built-in `NSScroller` is layer-backed and renders its knob via CoreUI,
/// which ignores `drawKnob`/`drawKnobSlot` overrides — so we can't restyle it directly.
/// Instead we hide that scroller and render this view ourselves, driven by the
/// scroller's live values (`doubleValue`, `knobProportion`, `isEnabled`) via KVO.
///
/// `hitTest` returns nil so clicks and scroll-wheel events pass straight through to
/// the terminal underneath.
final class TerminalScrollKnobView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Terminal Manager

/// Manages the Guake-style dropdown terminal session lifecycle.
/// The terminal is lazily created when the user first switches to the terminal tab,
/// and the process is kept alive across notch open/close cycles.
///
/// Uses a stable `StableTerminalContainerView` as the host so that SwiftUI's
/// `NSViewRepresentable` lifecycle (make/update/dismantle) never tears down
/// the actual terminal.  The `LocalProcessTerminalView` is added as a subview
/// of the container and survives notch close/open cycles.
@MainActor
class TerminalManager: ObservableObject {
    static let shared = TerminalManager()

    /// Whether a shell process is currently running.
    @Published var isProcessRunning: Bool = false

    /// The current terminal title reported by the shell.
    @Published var terminalTitle: String = "Terminal"

    /// Stable container returned to SwiftUI — never deallocated.
    /// Uses `StableTerminalContainerView` to prevent zero-frame transients
    /// from destroying the scrollback buffer.
    let containerView: StableTerminalContainerView = {
        let v = StableTerminalContainerView(frame: .zero)
        v.autoresizingMask = [.width, .height]
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }()

    /// The actual terminal view (child of `containerView`).
    private(set) var terminalView: LocalProcessTerminalView?

    /// SwiftTerm's built-in scroller (kept as the data source for our custom knob).
    private weak var terminalScroller: NSScroller?

    /// KVO of the scroller's value/proportion/enabled state that drives the knob.
    private var scrollerObservations: [NSKeyValueObservation] = []

    /// Custom rounded scrollbar knob rendered on top of the terminal.
    private lazy var scrollKnobView: TerminalScrollKnobView = {
        let v = TerminalScrollKnobView()
        v.identifier = StableTerminalContainerView.scrollKnobIdentifier
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.45).cgColor
        v.alphaValue = 0
        return v
    }()

    /// Thickness of the custom scroll knob, and its margins inside the terminal.
    private let scrollKnobThickness: CGFloat = 6
    private let scrollKnobEndInset: CGFloat = 3
    private let scrollKnobRightMargin: CGFloat = 2

    /// Frosted blur of desktop/content behind the terminal; always below `terminalView`.
    private lazy var terminalBackgroundEffectView: NSVisualEffectView = {
        let v = NSVisualEffectView()
        // Minimal frosted look with very light blur/vibrancy.
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .active
        v.autoresizingMask = [.width, .height]
        return v
    }()

    /// Tinted ring that fills the inset gutter with the terminal's background color
    /// so the inset text isn't surrounded by a bare-blur "ring".  Sits above the
    /// blur and below `terminalView`; masked to the gutter so it never doubles the
    /// translucent background over the terminal's own cells.
    private lazy var terminalGutterTintView: NSView = {
        let v = NSView()
        v.identifier = StableTerminalContainerView.gutterTintIdentifier
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        v.autoresizingMask = [.width, .height]
        return v
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Ensures the terminal view exists inside the container and returns the container.
    /// Call this from the `NSViewRepresentable` wrapper.
    func ensureTerminalView(delegate: LocalProcessTerminalViewDelegate) {
        if let existing = terminalView, existing.superview === containerView {
            // Already mounted — just re-wire the delegate in case the coordinator changed.
            existing.processDelegate = delegate
            // Re-apply opacity/translucency after hide/show cycles (e.g. shortcut toggle).
            refreshTerminalOpacityAndTranslucency(for: existing)
            return
        }

        // Use the container's current bounds if valid, otherwise a reasonable
        // default.  SwiftTerm's init calls setupOptions() which reads the
        // frame — a zero frame creates a 2×1 terminal that is corrected
        // once the container gets its proper layout size.
        let initialFrame = containerView.bounds.size.width >= 10
            ? containerView.bounds
            : CGRect(x: 0, y: 0, width: 400, height: 300)

        // Replace only the terminal view - keep the blur underlay between restarts.
        terminalView?.removeFromSuperview()

        let view = LocalProcessTerminalView(frame: initialFrame)
        view.autoresizingMask = [.width, .height]

        // Apply all settings from Defaults
        applyAllSettings(to: view)

        view.processDelegate = delegate

        if terminalBackgroundEffectView.superview == nil {
            containerView.addSubview(terminalBackgroundEffectView)
        }
        if terminalGutterTintView.superview == nil {
            containerView.addSubview(
                terminalGutterTintView,
                positioned: .above,
                relativeTo: terminalBackgroundEffectView
            )
        }
        updateGutterTintColor()
        containerView.addSubview(view)
        terminalView = view

        // Keep the custom scroll knob above the terminal (re-add to bring to front).
        scrollKnobView.removeFromSuperview()
        containerView.addSubview(scrollKnobView)
        if let scroller = terminalScroller {
            updateScrollKnob(from: scroller)
        }

        // If the container already has a valid size, snap the children to it.
        // Blur + gutter tint fill the full bounds; the terminal is inset so its
        // glyphs don't hug the edge, and the gutter tint is masked to the ring.
        let containerSize = containerView.bounds.size
        if containerSize.width >= 10, containerSize.height >= 10 {
            let bounds = containerView.bounds
            let terminalFrame = bounds.insetBy(
                dx: notchTerminalInnerTextInset,
                dy: notchTerminalInnerTextInset
            )
            terminalBackgroundEffectView.frame = bounds
            terminalGutterTintView.frame = bounds
            StableTerminalContainerView.applyGutterMask(
                to: terminalGutterTintView,
                bounds: bounds,
                hole: terminalFrame
            )
            view.frame = terminalFrame
        }

        // Apply translucency immediately and again on the next run loop tick.
        // The deferred pass handles AppKit/SwiftUI mount timing where layer
        // changes can otherwise be lost on first open.
        refreshTerminalOpacityAndTranslucency(for: view)
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, self.terminalView === view else { return }
            self.refreshTerminalOpacityAndTranslucency(for: view)
        }
    }

    /// Starts the shell process if not already running.
    func startShellProcess() {
        guard let view = terminalView, !isProcessRunning else { return }

        let shell = Defaults[.terminalShellPath]
        let execName = "-" + (shell as NSString).lastPathComponent  // login shell convention

        view.startProcess(
            executable: shell,
            args: [],
            environment: buildEnvironment(),
            execName: execName
        )
        isProcessRunning = true
    }

    /// Called when the shell process terminates.
    func processDidTerminate(exitCode: Int32?) {
        isProcessRunning = false
    }

    /// Restarts the shell by tearing down the old terminal and creating a fresh one.
    ///
    /// Instead of bumping a generation counter (which forced SwiftUI to destroy
    /// and recreate the `NSViewRepresentable` — recycling the same `containerView`
    /// across identities which broke layout), we simply nil out `terminalView`
    /// and change `@Published` state.  SwiftUI's `updateNSView` will fire,
    /// see the nil terminal, and call `ensureTerminalView` to mount a new one.
    func restartShell() {
        // Terminate the running process gracefully
        terminalView?.terminate()
        // Remove old terminal from container
        terminalView?.removeFromSuperview()
        terminalView = nil
        isProcessRunning = false
        terminalTitle = "Terminal"
    }

    /// Updates the terminal title from the shell escape sequence.
    func updateTitle(_ title: String) {
        terminalTitle = title
    }

    // MARK: - Font Resolution

    /// Resolves the terminal font from the user's chosen family and size.
    ///
    /// - If `family` is empty, returns the system monospaced font.
    /// - Otherwise tries `NSFont(name:size:)` and falls back to system monospaced
    ///   when the name is invalid or the font is not installed.
    private func resolveFont(family: String, size: CGFloat) -> NSFont {
        if !family.isEmpty, let custom = NSFont(name: family, size: size) {
            return custom
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Background color with opacity slider applied to alpha only (glyphs stay fully opaque).
    private func resolvedTerminalBackgroundNSColor(
        baseColor: NSColor? = nil,
        opacitySlider: CGFloat? = nil
    ) -> NSColor {
        let raw = baseColor ?? NSColor(Defaults[.terminalBackgroundColor])
        let rgb = raw.usingColorSpace(.deviceRGB) ?? raw.usingColorSpace(.sRGB) ?? raw
        let opacity = opacitySlider ?? CGFloat(Defaults[.terminalOpacity])
        let alpha = CGFloat(rgb.cgColor.alpha) * opacity
        return rgb.withAlphaComponent(alpha)
    }

    /// Composites the terminal buffer over `terminalBackgroundEffectView` without dimming glyphs.
    /// SwiftTerm’s `TerminalView.isOpaque` is read-only; translucency relies on alpha in `nativeBackgroundColor`.
    private func applyTerminalBackgroundAppearance(to view: LocalProcessTerminalView) {
        view.layer?.opacity = 1
        view.nativeBackgroundColor = resolvedTerminalBackgroundNSColor()
    }

    /// Upstream `TerminalView.setupOptions()` assigns `layer.backgroundColor` from `nativeBackgroundColor`, which
    /// prevents the `NSVisualEffectView` under the terminal from showing through. Re-clear after our color updates.
    /// Default-cell alpha and attribute-cache invalidation on native color changes may still need a SwiftTerm PR
    private func applyTerminalLayerTranslucencyHacks(to view: LocalProcessTerminalView) {
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }

    /// Best-effort redraw. `TerminalView.installColors(_:)` could clear SwiftTerm color caches but needs 16
    /// `SwiftTerm.Color` values; `Terminal.ansiColors` is not public, so we do not duplicate a palette here.
    private func synchronizeTerminalTranslucencyPresentation(to view: LocalProcessTerminalView) {
        applyTerminalLayerTranslucencyHacks(to: view)
        view.setNeedsDisplay(view.bounds)
    }

    /// Re-applies backdrop opacity + translucency hacks after remount/reopen paths.
    private func refreshTerminalOpacityAndTranslucency(for view: LocalProcessTerminalView) {
        applyTerminalBackgroundAppearance(to: view)
        synchronizeTerminalTranslucencyPresentation(to: view)
        updateGutterTintColor()
    }

    /// Keeps the gutter tint ring matching the terminal's resolved (translucent)
    /// background color so the inset gutter blends seamlessly with the cells.
    private func updateGutterTintColor() {
        terminalGutterTintView.layer?.backgroundColor = resolvedTerminalBackgroundNSColor().cgColor
    }

    // MARK: - Settings Application

    /// Applies all persisted settings to a terminal view at creation time.
    private func applyAllSettings(to view: LocalProcessTerminalView) {
        // Font
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: fontSize)

        // Colors (background opacity is separate from terminal opacity slider — see `applyTerminalBackgroundAppearance`)
        applyTerminalBackgroundAppearance(to: view)
        view.nativeForegroundColor = NSColor(Defaults[.terminalForegroundColor])
        view.caretColor = NSColor(Defaults[.terminalCursorColor])

        // Cursor style
        let cursorStyle = TerminalCursorStyleOption(rawValue: Defaults[.terminalCursorStyle])
            ?? .blinkBlock
        view.getTerminal().setCursorStyle(cursorStyle.swiftTermStyle)

        // Keep drawing the selected cursor style when TerminalView.hasFocus is false; SwiftTerm
        // otherwise uses an unfocused/outline caret while tracksFocus is true.
        view.caretViewTracksFocus = false

        // Scrollback
        let scrollback = Defaults[.terminalScrollbackLines]
        view.getTerminal().buffer.changeHistorySize(scrollback)
        view.getTerminal().options.scrollback = scrollback

        // Input behavior
        view.optionAsMetaKey = Defaults[.terminalOptionAsMeta]
        view.allowMouseReporting = Defaults[.terminalMouseReporting]

        // Rendering
        view.useBrightColors = Defaults[.terminalBoldAsBright]

        refreshTerminalOpacityAndTranslucency(for: view)
        styleTerminalScroller(for: view)
    }

    /// Hides SwiftTerm's built-in scroller and wires KVO so its live scroll state
    /// drives our custom `scrollKnobView` (see `TerminalScrollKnobView`).
    private func styleTerminalScroller(for view: LocalProcessTerminalView) {
        guard let scroller = view.subviews.compactMap({ $0 as? NSScroller }).first else { return }
        terminalScroller = scroller
        // Hide SwiftTerm's own scroller drawing; it stays alive as our data source.
        scroller.alphaValue = 0

        scrollerObservations.forEach { $0.invalidate() }
        scrollerObservations = []
        let onChange: (NSScroller) -> Void = { scroller in
            MainActor.assumeIsolated {
                TerminalManager.shared.updateScrollKnob(from: scroller)
            }
        }
        scrollerObservations = [
            scroller.observe(\.doubleValue, options: [.new]) { s, _ in onChange(s) },
            scroller.observe(\.knobProportion, options: [.new]) { s, _ in onChange(s) },
            scroller.observe(\.isEnabled, options: [.new]) { s, _ in onChange(s) }
        ]
        updateScrollKnob(from: scroller)
    }

    /// Re-runs the knob layout using the current scroller state (e.g. after a resize).
    func refreshScrollKnobLayout() {
        guard let scroller = terminalScroller else { return }
        updateScrollKnob(from: scroller)
    }

    /// Positions and shows/hides the custom scroll knob from the scroller's state.
    private func updateScrollKnob(from scroller: NSScroller) {
        guard scrollKnobView.superview === containerView else { return }

        guard scroller.isEnabled else {
            scrollKnobView.animator().alphaValue = 0
            return
        }

        let bounds = containerView.bounds
        guard bounds.width >= 10, bounds.height >= 10 else { return }

        // Track lives inside the inset terminal area, along its right edge.
        let terminalFrame = bounds.insetBy(
            dx: notchTerminalInnerTextInset,
            dy: notchTerminalInnerTextInset
        )
        let thickness = scrollKnobThickness
        let trackTopY = terminalFrame.maxY - scrollKnobEndInset      // visual top (non-flipped)
        let trackBottomY = terminalFrame.minY + scrollKnobEndInset
        let trackHeight = max(0, trackTopY - trackBottomY)
        guard trackHeight > thickness else {
            scrollKnobView.animator().alphaValue = 0
            return
        }

        let proportion = max(0.04, min(1.0, CGFloat(scroller.knobProportion)))
        let knobHeight = max(thickness * 2, proportion * trackHeight)
        let travel = max(0, trackHeight - knobHeight)
        // doubleValue: 0 = top of scrollback, 1 = bottom (current); y grows upward.
        let value = max(0, min(1, CGFloat(scroller.doubleValue)))
        let knobMinY = trackBottomY + (1 - value) * travel
        let x = terminalFrame.maxX - thickness - scrollKnobRightMargin

        scrollKnobView.frame = NSRect(x: x, y: knobMinY, width: thickness, height: knobHeight)
        scrollKnobView.layer?.cornerRadius = thickness / 2
        scrollKnobView.animator().alphaValue = 1
    }

    /// Updates font size on the live terminal view.
    func applyFontSize(_ size: Double) {
        guard let view = terminalView else { return }
        let fontFamily = Defaults[.terminalFontFamily]
        view.font = resolveFont(family: fontFamily, size: CGFloat(size))
    }

    /// Updates font family on the live terminal view.
    func applyFontFamily(_ family: String) {
        guard let view = terminalView else { return }
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        view.font = resolveFont(family: family, size: fontSize)
    }

    /// Updates background opacity on the live terminal view (glyphs stay fully opaque).
    func applyOpacity(_ opacity: Double) {
        guard let view = terminalView else { return }
        view.layer?.opacity = 1
        view.nativeBackgroundColor = resolvedTerminalBackgroundNSColor(opacitySlider: CGFloat(opacity))
        refreshTerminalOpacityAndTranslucency(for: view)
    }

    /// Updates cursor style on the live terminal view.
    func applyCursorStyle(_ style: TerminalCursorStyleOption) {
        guard let view = terminalView else { return }
        view.getTerminal().setCursorStyle(style.swiftTermStyle)
        view.setNeedsDisplay(view.bounds)
    }

    /// Updates scrollback buffer size on the live terminal view.
    func applyScrollback(_ lines: Int) {
        guard let view = terminalView else { return }
        view.getTerminal().buffer.changeHistorySize(lines)
        view.getTerminal().options.scrollback = lines
    }

    /// Updates option-as-meta on the live terminal view.
    func applyOptionAsMeta(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.optionAsMetaKey = enabled
    }

    /// Updates mouse reporting on the live terminal view.
    func applyMouseReporting(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.allowMouseReporting = enabled
    }

    /// Updates bold-as-bright on the live terminal view.
    func applyBoldAsBright(_ enabled: Bool) {
        guard let view = terminalView else { return }
        view.useBrightColors = enabled
    }

    /// Updates background color on the live terminal view.
    func applyBackgroundColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.layer?.opacity = 1
        view.nativeBackgroundColor = resolvedTerminalBackgroundNSColor(baseColor: NSColor(color))
        refreshTerminalOpacityAndTranslucency(for: view)
    }

    /// Updates foreground color on the live terminal view.
    func applyForegroundColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.nativeForegroundColor = NSColor(color)
        synchronizeTerminalTranslucencyPresentation(to: view)
    }

    /// Called by UI lifecycle hooks after tab re-appearance to keep opacity stable.
    func refreshTerminalAppearanceIfNeeded() {
        guard let view = terminalView else { return }
        refreshTerminalOpacityAndTranslucency(for: view)
    }

    /// Makes terminal view first responder when terminal tab opens.
    /// Retries a few times to cover mount/animation timing so typing works immediately.
    func focusTerminalIfPossible() {
        focusTerminalIfPossible(attemptsRemaining: 3)
    }

    private func focusTerminalIfPossible(attemptsRemaining: Int) {
        guard let view = terminalView else { return }
        guard let window = containerView.window ?? view.window else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusTerminalIfPossible(attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }

        guard window.firstResponder !== view else { return }
        if !window.makeFirstResponder(view), attemptsRemaining > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusTerminalIfPossible(attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }

    /// Resigns terminal focus before closing notch to avoid stale responder state.
    func resignTerminalFirstResponderIfNeeded() {
        guard let view = terminalView else { return }
        guard let window = containerView.window ?? view.window else { return }
        guard window.firstResponder === view else { return }
        _ = window.makeFirstResponder(nil)
    }

    /// True when the terminal view is currently first responder.
    func isTerminalFirstResponder() -> Bool {
        guard let view = terminalView else { return false }
        guard let window = containerView.window ?? view.window else { return false }
        return window.firstResponder === view
    }

    /// Updates cursor color on the live terminal view.
    func applyCursorColor(_ color: SwiftUI.Color) {
        guard let view = terminalView else { return }
        view.caretColor = NSColor(color)
    }

    // MARK: - Environment

    /// Builds the environment for the child shell process.
    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        // Remove TERM_PROGRAM if set by a parent terminal
        env.removeValue(forKey: "TERM_PROGRAM")
        return env.map { "\($0.key)=\($0.value)" }
    }
}

// MARK: - Cursor Style Bridge

/// Codable-friendly cursor style enum that bridges to SwiftTerm's `CursorStyle`.
enum TerminalCursorStyleOption: String, CaseIterable, Defaults.Serializable {
    case blinkBlock = "blinkBlock"
    case steadyBlock = "steadyBlock"
    case blinkUnderline = "blinkUnderline"
    case steadyUnderline = "steadyUnderline"
    case blinkBar = "blinkBar"
    case steadyBar = "steadyBar"

    var swiftTermStyle: CursorStyle {
        switch self {
        case .blinkBlock: return .blinkBlock
        case .steadyBlock: return .steadyBlock
        case .blinkUnderline: return .blinkUnderline
        case .steadyUnderline: return .steadyUnderline
        case .blinkBar: return .blinkBar
        case .steadyBar: return .steadyBar
        }
    }

    var displayName: String {
        switch self {
        case .blinkBlock: return "Block (blinking)"
        case .steadyBlock: return "Block (steady)"
        case .blinkUnderline: return "Underline (blinking)"
        case .steadyUnderline: return "Underline (steady)"
        case .blinkBar: return "Bar (blinking)"
        case .steadyBar: return "Bar (steady)"
        }
    }
}
