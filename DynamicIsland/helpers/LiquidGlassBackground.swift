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
import AppKit
import Defaults

private final class LiquidGlassContainerView: NSView {
    weak var glassView: NSView?
    var hostingView: NSHostingView<AnyView>?

    private var observedBackdropLayers: [CALayer] = []
    private var hasScheduledBackdropSetup = false
    private let windowServerAwareKeyPath = "windowServerAware"
    private let scaleKeyPath = "scale"

    deinit {
        removeBackdropObservers()
    }

    override func removeFromSuperview() {
        removeBackdropObservers()
        super.removeFromSuperview()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleBackdropSetup()
    }

    override func layout() {
        super.layout()
        scheduleBackdropSetup()
    }

    func scheduleBackdropSetup() {
        guard !hasScheduledBackdropSetup else { return }
        hasScheduledBackdropSetup = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.hasScheduledBackdropSetup = false
            self.configureBackdropLayers()
        }
    }

    private func configureBackdropLayers() {
        guard let glassView else { return }
        guard let rootLayer = glassView.layer else {
            scheduleBackdropSetup()
            return
        }

        setBackdropProperties(in: rootLayer)
        let newBackdropLayers = collectBackdropLayers(in: rootLayer)

        removeBackdropObservers()
        observedBackdropLayers = newBackdropLayers
        for backdrop in observedBackdropLayers {
            backdrop.addObserver(self, forKeyPath: windowServerAwareKeyPath, options: [.old, .new], context: nil)
            backdrop.addObserver(self, forKeyPath: scaleKeyPath, options: [.old, .new], context: nil)
        }
    }

    private func setBackdropProperties(in layer: CALayer) {
        if NSStringFromClass(type(of: layer)).contains("CABackdropLayer") {
            layer.setValue(true, forKey: windowServerAwareKeyPath)
            // Don't override scale — NSGlassEffectView sets variant-specific
            // scale values on its backdrop layers to control blur intensity.
            // Forcing 1.0 here causes lower variants (< v11) to appear overly
            // frosted/opaque because it overrides their intended transparency.
        }
        layer.sublayers?.forEach { setBackdropProperties(in: $0) }
    }

    private func collectBackdropLayers(in layer: CALayer) -> [CALayer] {
        var results: [CALayer] = []
        if NSStringFromClass(type(of: layer)).contains("CABackdropLayer") {
            results.append(layer)
        }
        layer.sublayers?.forEach { results.append(contentsOf: collectBackdropLayers(in: $0)) }
        return results
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if keyPath == windowServerAwareKeyPath {
            if change?[.newKey] as? Bool == false {
                configureBackdropLayers()
            }
        } else if keyPath == scaleKeyPath {
            // Observe scale changes but don't fight them — NSGlassEffectView
            // sets variant-appropriate scale values. Only re-assert windowServerAware
            // if the backdrop was fully zeroed (layer became invisible).
            guard let layer = object as? CALayer else { return }
            if let newScale = (change?[.newKey] as? NSNumber)?.doubleValue, newScale == 0.0 {
                layer.setValue(true, forKey: windowServerAwareKeyPath)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    private func removeBackdropObservers() {
        for layer in observedBackdropLayers {
            layer.removeObserver(self, forKeyPath: windowServerAwareKeyPath)
            layer.removeObserver(self, forKeyPath: scaleKeyPath)
        }
        observedBackdropLayers.removeAll()
    }
}

/// All 20 available liquid‑glass variants.
/// Apple does not publicly describe how each value looks so experiment and pick the one you like!
public enum LiquidGlassVariant: Int, CaseIterable, Identifiable, Defaults.Serializable, Sendable {
    case v0  = 0,  v1  = 1,  v2  = 2,  v3  = 3,  v4  = 4
    case v5  = 5,  v6  = 6,  v7  = 7,  v8  = 8,  v9  = 9
    case v10 = 10, v11 = 11, v12 = 12, v13 = 13, v14 = 14
    case v15 = 15, v16 = 16, v17 = 17, v18 = 18, v19 = 19

    public var id: Int { rawValue }

    public static let supportedRange = 0...19

    public static var defaultVariant: LiquidGlassVariant { .v11 }

    public static func clamped(_ rawValue: Int) -> LiquidGlassVariant {
        let clamped = min(max(rawValue, supportedRange.lowerBound), supportedRange.upperBound)
        return LiquidGlassVariant(rawValue: clamped) ?? .defaultVariant
    }
}

/// A SwiftUI view that embeds its content inside Apple’s private liquid‑glass material.
///
/// ```swift
/// GlassBackground(variant: .v11, cornerRadius: 12) {
///     VStack(spacing: 12) {
///         Image(systemName: "sparkles")
///             .font(.largeTitle)
///         Text("Hello, glass!")
///             .font(.title2)
///     }
///     .padding()
/// }
/// ```
public struct LiquidGlassBackground<Content: View>: NSViewRepresentable {
    private let content: Content
    private let cornerRadius: CGFloat
    private let variant: LiquidGlassVariant
    /// Creates a new liquid‑glass container.
    /// - Parameters:
    ///   - variant: Any ``LiquidGlassVariant`` (0–19). Defaults to `.v11`, which is visually super pleasing
    ///   - cornerRadius: Corner radius in points. Defaults to `10`.
    ///   - content: Your SwiftUI hierarchy.
    public init(
        variant: LiquidGlassVariant = .defaultVariant,
        cornerRadius: CGFloat = 10,
        @ViewBuilder content: () -> Content
    ) {
        self.variant      = variant
        self.cornerRadius = cornerRadius
        self.content      = content()
    }


    @inline(__always)
    private func setterSelector(for key: String, privateVariant: Bool = true) -> Selector? {
        guard !key.isEmpty else { return nil }
        let name: String
        if privateVariant {
            let cleaned = key.hasPrefix("_") ? key : "_" + key
            name = "set" + cleaned
        } else {
            let first = String(key.prefix(1)).uppercased()
            let rest  = String(key.dropFirst())
            name = "set" + first + rest
        }
        return NSSelectorFromString(name + ":")
    }

    private typealias VariantSetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void

    private func callPrivateVariantSetter(on object: AnyObject, value: Int) {
        guard
            let sel   = setterSelector(for: "variant", privateVariant: true),
            let m     = class_getInstanceMethod(object_getClass(object), sel)
        else {
            #if DEBUG
            print("✗ LiquidGlassBackground: selector set_variant: not found. falling back to default")
            #endif
            return
        }
        let imp = method_getImplementation(m)
        let f   = unsafeBitCast(imp, to: VariantSetterIMP.self)
        f(object, sel, value)
    }



    public func makeNSView(context: Context) -> NSView {
        // `NSGlassEffectView` is private. Look it up dynamically to avoid compile‑time coupling.
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let container = LiquidGlassContainerView(frame: .zero)
            container.translatesAutoresizingMaskIntoConstraints = false

            let glass = glassType.init(frame: .zero)
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            callPrivateVariantSetter(on: glass, value: variant.rawValue)

            let hosting = NSHostingView(rootView: AnyView(content))
            hosting.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(hosting, forKey: "contentView")

            container.addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                glass.topAnchor.constraint(equalTo: container.topAnchor),
                glass.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])

            container.glassView = glass
            container.hostingView = hosting
            container.scheduleBackdropSetup()
            return container
        }

        // Fallback for earlier macOS – use an ordinary blur.
        let fallback = NSVisualEffectView()
        fallback.material = .underWindowBackground

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: fallback.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: fallback.bottomAnchor)
        ])
        return fallback
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let container = nsView as? LiquidGlassContainerView,
           let glass = container.glassView {
            container.hostingView?.rootView = AnyView(content)
            glass.setValue(cornerRadius, forKey: "cornerRadius")
            callPrivateVariantSetter(on: glass, value: variant.rawValue)
            container.scheduleBackdropSetup()
            return
        }

        if let hosting = nsView.subviews.first as? NSHostingView<Content> {
            hosting.rootView = content
        }
    }
}
