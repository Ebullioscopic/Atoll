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
import AtollExtensionKit
import WebKit
import AppKit

struct ExtensionLockScreenWidgetView: View {
    let payload: ExtensionLockScreenWidgetPayload

    private var descriptor: AtollLockScreenWidgetDescriptor { payload.descriptor }
    private var accentColor: Color { descriptor.accentColor.swiftUIColor }
    private var appearance: AtollWidgetAppearanceOptions? { descriptor.appearance }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: descriptor.cornerRadius, style: .continuous)
        ZStack {
            backgroundLayer(shape: shape)
            contentView
                .padding(resolvedContentInsets)
        }
        .frame(width: descriptor.size.width, height: descriptor.size.height)
        .clipShape(shape)
        .overlay(borderOverlay(shape: shape))
        .shadow(color: shadowColor, radius: shadowRadius, x: shadowOffset.width, y: shadowOffset.height)
        .onAppear {
            logWidgetDiagnostics("Rendering extension lock screen widget \(payload.descriptor.id) for \(payload.bundleIdentifier)")
        }
        .onDisappear {
            logWidgetDiagnostics("Lock screen widget \(payload.descriptor.id) removed")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch descriptor.layoutStyle {
        case .inline, .card, .custom:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(descriptor.content.enumerated()), id: \.offset) { index, element in
                    view(for: element)
                        .frame(maxWidth: .infinity, alignment: alignment(for: element))
                        .accessibilityIdentifier("extension-widget-element-\(payload.id)-\(index)")
                }
            }
        case .circular:
            ZStack {
                ForEach(Array(descriptor.content.enumerated()), id: \.offset) { index, element in
                    view(for: element)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .accessibilityIdentifier("extension-widget-element-\(payload.id)-\(index)")
                }
            }
        }
    }

    private func view(for element: AtollWidgetContentElement) -> some View {
        ExtensionWidgetElementView(
            element: element,
            accent: accentColor,
            allowWebInteraction: false
        )
    }

    private func alignment(for element: AtollWidgetContentElement) -> Alignment {
        switch element {
        case let .text(_, _, _, alignment):
            return alignment.swiftUI
        default:
            return .leading
        }
    }

    private var resolvedContentInsets: EdgeInsets {
        if let custom = appearance?.contentInsets {
            return EdgeInsets(top: custom.top, leading: custom.leading, bottom: custom.bottom, trailing: custom.trailing)
        }
        switch descriptor.layoutStyle {
        case .circular:
            return EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        default:
            return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        }
    }

    @ViewBuilder
    private func backgroundLayer(shape: RoundedRectangle) -> some View {
        if descriptor.material == .liquid {
            liquidGlassBackground(shape: shape)
        } else if shouldUseGlassHighlight {
            if #available(macOS 26.0, *) {
                ZStack {
                    shape
                        .fill(Color.clear)
                        .glassEffect(
                            .clear.interactive(),
                            in: .rect(cornerRadius: descriptor.cornerRadius)
                        )
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    tintOverlay(shape: shape)
                }
            } else {
                ZStack {
                    shape.fill(AnyShapeStyle(.regularMaterial))
                    tintOverlay(shape: shape)
                }
            }
        } else {
            ZStack {
                shape.fill(baseMaterialStyle)
                tintOverlay(shape: shape)
            }
        }
    }

    @ViewBuilder
    private func liquidGlassBackground(shape: RoundedRectangle) -> some View {
        LiquidGlassBackground(variant: requestedLiquidGlassVariant, cornerRadius: descriptor.cornerRadius) {
            Color.black.opacity(0.08)
        }
        .overlay {
            tintOverlay(shape: shape)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var baseMaterialStyle: AnyShapeStyle {
        switch descriptor.material {
        case .frosted:
            return AnyShapeStyle(.ultraThinMaterial)
        case .liquid:
            return AnyShapeStyle(.regularMaterial)
        case .solid:
            return AnyShapeStyle(resolvedSolidFillColor.opacity(0.95))
        case .semiTransparent:
            return AnyShapeStyle(resolvedSolidFillColor.opacity(0.35))
        case .clear:
            return AnyShapeStyle(Color.clear)
        }
    }

    private var resolvedSolidFillColor: Color {
        if let tint = appearance?.tintColor?.swiftUIColor {
            return tint
        }
        return accentColor
    }

    @ViewBuilder
    private func tintOverlay(shape: RoundedRectangle) -> some View {
        Group {
            if shouldApplyTintOverlay, let overlay = tintedOverlayColor {
                shape
                    .fill(overlay)
                    .allowsHitTesting(false)
            }
        }
    }

    private var tintedOverlayColor: Color? {
        guard let descriptor = appearance, let tint = descriptor.tintColor, descriptor.tintOpacity > 0 else {
            return nil
        }
        return tint.swiftUIColor.opacity(descriptor.tintOpacity)
    }

    private var shouldApplyTintOverlay: Bool {
        guard appearance?.tintColor != nil else { return false }
        switch descriptor.material {
        case .solid, .semiTransparent:
            return false
        default:
            return true
        }
    }

    private var shouldUseGlassHighlight: Bool {
        (appearance?.enableGlassHighlight ?? false) && descriptor.material != .liquid
    }

    private var requestedLiquidGlassVariant: LiquidGlassVariant {
        guard let requested = appearance?.liquidGlassVariant?.rawValue else {
            return LiquidGlassVariant.defaultVariant
        }
        return LiquidGlassVariant.clamped(requested)
    }

    @ViewBuilder
    private func borderOverlay(shape: RoundedRectangle) -> some View {
        if let border = appearance?.border {
            shape
                .stroke(border.color.swiftUIColor.opacity(border.opacity), lineWidth: border.width)
        } else {
            shape
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        }
    }

    private var shadowColor: Color {
        guard let shadow = appearance?.shadow else { return .clear }
        return shadow.color.swiftUIColor.opacity(shadow.opacity)
    }

    private var shadowRadius: CGFloat {
        appearance?.shadow?.radius ?? 0
    }

    private var shadowOffset: CGSize {
        appearance?.shadow?.offset ?? .zero
    }
}

private func logWidgetDiagnostics(_ message: String) {
    guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
    Logger.log(message, category: .extensions)
}

struct ExtensionWidgetElementView: View {
    let element: AtollWidgetContentElement
    let accent: Color
    let allowWebInteraction: Bool
    let actionURL: URL?
    let onOpenURL: (() -> Void)?

    init(
        element: AtollWidgetContentElement,
        accent: Color,
        allowWebInteraction: Bool,
        actionURL: URL? = nil,
        onOpenURL: (() -> Void)? = nil
    ) {
        self.element = element
        self.accent = accent
        self.allowWebInteraction = allowWebInteraction
        self.actionURL = actionURL
        self.onOpenURL = onOpenURL
    }

    var body: some View {
        switch element {
        case let .text(text, font: font, color: color, alignment: _):
            let label = Text(text)
                .font(font.swiftUIFont())
                .foregroundStyle((color?.swiftUIColor) ?? Color.white.opacity(0.9))
                .lineLimit(2)
            if let actionURL {
                Button {
                    guard CodexThreadActionResolver.isCodexThreadURL(actionURL) else { return }
                    guard NSWorkspace.shared.open(actionURL) else { return }
                    onOpenURL?()
                } label: {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("打开对应的 Codex 对话")
            } else {
                label
            }
        case let .icon(iconDescriptor, tint):
            ExtensionIconView(
                descriptor: iconDescriptor,
                tint: (tint?.swiftUIColor) ?? accent,
                size: CGSize(width: 28, height: 28),
                cornerRadius: 8
            )
        case let .progress(indicator, value, color):
            ExtensionProgressIndicatorView(
                indicator: indicator,
                progress: value,
                accent: (color?.swiftUIColor) ?? accent,
                estimatedDuration: nil
            )
        case let .graph(data, color, size):
            ExtensionGraphView(data: data, color: color.swiftUIColor, size: size)
                .frame(width: size.width, height: size.height)
        case let .gauge(value, minValue, maxValue, style, color):
            ExtensionGaugeView(
                value: value,
                minValue: minValue,
                maxValue: maxValue,
                style: style,
                accent: (color?.swiftUIColor) ?? accent
            )
                .frame(maxWidth: .infinity)
        case let .spacer(height):
            Color.clear
                .frame(height: height)
        case let .divider(color, thickness):
            Rectangle()
                .fill(color.swiftUIColor.opacity(0.4))
                .frame(height: thickness)
        case let .webView(webDescriptor):
            ExtensionWebContentView(descriptor: webDescriptor, allowInteraction: allowWebInteraction)
                .frame(height: webDescriptor.preferredHeight)
                .frame(maxWidth: webDescriptor.maximumContentWidth ?? .infinity)
        }
    }
}

struct ExtensionWebContentView: NSViewRepresentable {
    let descriptor: AtollWidgetWebContentDescriptor
    let allowInteraction: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(descriptor: descriptor)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = ConfigurableWKWebView(frame: .zero, configuration: configuration)
        webView.allowInteraction = allowInteraction
        webView.navigationDelegate = context.coordinator
        webView.wantsLayer = true
        applyConfiguration(descriptor, to: webView)
        context.coordinator.lastHTML = descriptor.html
        webView.loadHTMLString(descriptor.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.descriptor = descriptor
        webView.navigationDelegate = context.coordinator
        applyConfiguration(descriptor, to: webView)
        if let configurableView = webView as? ConfigurableWKWebView {
            configurableView.allowInteraction = allowInteraction
        }
        if context.coordinator.lastHTML != descriptor.html {
            webView.loadHTMLString(descriptor.html, baseURL: nil)
            context.coordinator.lastHTML = descriptor.html
        }
    }

    private func applyConfiguration(_ descriptor: AtollWidgetWebContentDescriptor, to webView: WKWebView) {
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        if descriptor.isTransparent {
            webView.setValue(false, forKey: "drawsBackground")
            webView.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            let fallbackColor = descriptor.backgroundColor?.nsColor ?? NSColor.windowBackgroundColor
            webView.layer?.backgroundColor = fallbackColor.cgColor
        }
    }

    private final class ConfigurableWKWebView: WKWebView {
        var allowInteraction = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard allowInteraction else { return nil }
            return super.hitTest(point)
        }

        override var acceptsFirstResponder: Bool {
            allowInteraction
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var descriptor: AtollWidgetWebContentDescriptor
        var lastHTML: String?

        init(descriptor: AtollWidgetWebContentDescriptor) {
            self.descriptor = descriptor
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if isAllowed(url: url) {
                decisionHandler(.allow)
            } else {
                logWidgetDiagnostics("Blocked external navigation to \(url.absoluteString)")
                decisionHandler(.cancel)
            }
        }

        private func isAllowed(url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "about" || scheme == "data" {
                return true
            }
            if (scheme == "http" || scheme == "https") {
                if allowsRemoteRequests() {
                    return true
                }
                guard descriptor.allowLocalhostRequests else {
                    return false
                }
                let host = url.host?.lowercased()
                return host == "localhost" || host == "127.0.0.1"
            }
            return false
        }

        private func allowsRemoteRequests() -> Bool {
            guard let data = try? JSONEncoder().encode(descriptor),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = json["allowRemoteRequests"] as? Bool else {
                return false
            }
            return value
        }
    }
}

private struct ExtensionGraphView: View {
    let data: [Double]
    let color: Color
    let size: CGSize

    var body: some View {
        GeometryReader { proxy in
            let minValue = data.min() ?? 0
            let maxValue = data.max() ?? 1
            let range = max(maxValue - minValue, 0.0001)
            let step = proxy.size.width / CGFloat(max(data.count - 1, 1))
            Path { path in
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let normalized = (value - minValue) / range
                    let y = proxy.size.height - (CGFloat(normalized) * proxy.size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct ExtensionGaugeView: View {
    let value: Double
    let minValue: Double
    let maxValue: Double
    let style: AtollWidgetContentElement.GaugeStyle
    let accent: Color

    var body: some View {
        switch style {
        case .circular:
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: CGFloat(normalizedValue))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.3), value: normalizedValue)
                Text("\(Int(normalizedValue * 100))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)
        case .linear:
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(accent)
                            .frame(width: proxy.size.width * CGFloat(normalizedValue), height: 8)
                            .animation(.smooth(duration: 0.3), value: normalizedValue)
                    }
            }
            .frame(height: 8)
        }
    }

    private var normalizedValue: Double {
        guard maxValue > minValue else { return 0 }
        return min(max((value - minValue) / (maxValue - minValue), 0), 1)
    }
}

private extension AtollWidgetContentElement.TextAlignment {
    var swiftUI: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}
