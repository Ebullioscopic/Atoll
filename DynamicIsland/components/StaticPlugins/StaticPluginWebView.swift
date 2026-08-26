/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import WebKit

struct StaticPluginWebView: View {
    static let networkBlockingRules = """
    [
      {"trigger":{"url-filter":"^https?://.*"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"^wss?://.*"},"action":{"type":"block"}}
    ]
    """

    /// 当前需要展示的已校验插件。
    let plugin: InstalledStaticPlugin
    @State private var loadingError: String?

    var body: some View {
        ZStack {
            StaticPluginWebRepresentable(plugin: plugin, loadingError: $loadingError)
            if let loadingError {
                ContentUnavailableView(
                    "Plugin Could Not Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadingError)
                )
            }
        }
    }
}

struct StaticPluginWebRepresentable: NSViewRepresentable {
    /// 当前需要展示的已校验插件。
    let plugin: InstalledStaticPlugin
    /// WebKit 配置或加载失败时显示的错误。
    @Binding var loadingError: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            plugin: plugin,
            loadingError: $loadingError,
            externalOpener: WorkspaceStaticPluginExternalOpener()
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.loadPlugin(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(plugin: plugin, loadingError: $loadingError)
        context.coordinator.loadPluginIfNeeded(in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var plugin: InstalledStaticPlugin
        private var loadingError: Binding<String?>
        private let externalOpener: StaticPluginExternalOpening
        private var configuredPlugin: InstalledStaticPlugin?
        private var configurationInProgress = false

        init(
            plugin: InstalledStaticPlugin,
            loadingError: Binding<String?>,
            externalOpener: StaticPluginExternalOpening
        ) {
            self.plugin = plugin
            self.loadingError = loadingError
            self.externalOpener = externalOpener
        }

        /// 同步 SwiftUI 传入的新插件和错误绑定。
        func update(plugin: InstalledStaticPlugin, loadingError: Binding<String?>) {
            if self.plugin != plugin {
                configuredPlugin = nil
            }
            self.plugin = plugin
            self.loadingError = loadingError
        }

        /// 首次展示时先安装网络拦截规则，再读取本地入口。
        func loadPlugin(in webView: WKWebView) {
            guard !configurationInProgress else { return }
            configurationInProgress = true
            loadingError.wrappedValue = nil
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "AtollStaticPluginNetworkBlocker",
                encodedContentRuleList: StaticPluginWebView.networkBlockingRules
            ) { [weak self, weak webView] ruleList, error in
                Task { @MainActor in
                    guard let self, let webView else { return }
                    self.configurationInProgress = false
                    guard let ruleList else {
                        self.loadingError.wrappedValue = error?.localizedDescription
                            ?? "Atoll could not install the offline-content rules."
                        return
                    }
                    webView.configuration.userContentController.add(ruleList)
                    self.configuredPlugin = self.plugin
                    webView.loadFileURL(
                        self.plugin.entrypointURL,
                        allowingReadAccessTo: self.plugin.rootURL
                    )
                }
            }
        }

        /// 插件被 Replace 后在清单或入口变化时重新配置加载。
        func loadPluginIfNeeded(in webView: WKWebView) {
            guard configuredPlugin != plugin else { return }
            loadPlugin(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let policy = StaticPluginNavigationPolicy(
                pluginRoot: plugin.rootURL,
                allowedExternalURLs: plugin.allowedExternalURLs,
                allowedExternalURLPrefixes: plugin.allowedExternalURLPrefixes
            )
            switch policy.decision(
                for: url,
                userActivated: navigationAction.navigationType == .linkActivated,
                mainFrame: navigationAction.targetFrame?.isMainFrame
            ) {
            case .allow:
                decisionHandler(.allow)
            case .cancel:
                decisionHandler(.cancel)
            case .openExternally(let url):
                externalOpener.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            loadingError.wrappedValue = error.localizedDescription
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            loadingError.wrappedValue = error.localizedDescription
        }

        /// 后续导航成功时移除先前失败留下的错误遮罩。
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadingError.wrappedValue = nil
        }
    }
}
