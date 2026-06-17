/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import Foundation
import WebKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Auth State

public enum WAAuthState: Equatable {
    case idle
    case loading
    case qrRequired
    case authenticated
    case error(String)
}

// MARK: - Weak Script Message Handler

private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WhatsAppWebEngine?
    init(_ target: WhatsAppWebEngine) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(message)
    }
}

// MARK: - Engine

@MainActor
public final class WhatsAppWebEngine: NSObject, ObservableObject {
    public static let shared = WhatsAppWebEngine()

    @Published public var authState: WAAuthState = .idle

    private var offscreenWindow: NSWindow?
    private var authTimer: Timer?
    private var authenticationTime: Date?
    private var isMonitorInjectedForCurrentDocument = false
    private var pendingMonitorInjectionTask: Task<Void, Never>?
    private var crashRecoveryTask: Task<Void, Never>?
    private var webProcessCrashCount = 0
    private var lastWebProcessCrashAt: Date?

    // Track in-flight send operations so we can cancel them on crash
    private var activeSendTask: Task<Void, Never>?

    public private(set) lazy var webView: WKWebView = buildWebView()

    private override init() { super.init() }

    // MARK: - Public API

    public func start() {
        guard authState == .idle else { return }
        authState = .loading
        isMonitorInjectedForCurrentDocument = false
        pendingMonitorInjectionTask?.cancel()
        pendingMonitorInjectionTask = nil
        crashRecoveryTask?.cancel()
        crashRecoveryTask = nil
        activeSendTask?.cancel()
        activeSendTask = nil
        webProcessCrashCount = 0
        lastWebProcessCrashAt = nil
        attachToOffscreenWindow()
        let request = URLRequest(url: URL(string: "https://web.whatsapp.com")!)
        webView.load(request)
        startAuthPolling()
        print("WhatsAppWebEngine: started ✅")
    }

    public func stop() {
        authTimer?.invalidate(); authTimer = nil
        pendingMonitorInjectionTask?.cancel()
        pendingMonitorInjectionTask = nil
        crashRecoveryTask?.cancel()
        crashRecoveryTask = nil
        activeSendTask?.cancel()
        activeSendTask = nil
        webView.stopLoading()
        offscreenWindow?.close(); offscreenWindow = nil
        authenticationTime = nil
        isMonitorInjectedForCurrentDocument = false
        webProcessCrashCount = 0
        lastWebProcessCrashAt = nil
        authState = .idle
    }

    public func disconnect(completion: @escaping () -> Void) {
        webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.stop()
                self?.start()
                completion()
            }
        }
    }

    public func sendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        prepareDesktopViewportForReply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.executeSendReply(chatId: chatId, text: text, completion: completion)
        }
    }

    public func sendDocument(chatId: String, fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        loadAndSendDocument(chatId: chatId, fileURL: fileURL, caption: "") { result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    public func sendDocumentWithText(
        chatId: String,
        fileURL: URL,
        caption: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        loadAndSendDocument(chatId: chatId, fileURL: fileURL, caption: trimmedCaption) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let status) where !trimmedCaption.isEmpty && status == "document-sent-without-caption":
                self.sendCaptionFallback(chatId: chatId, fileURL: fileURL, caption: trimmedCaption, completion: completion)
            case .success:
                completion(.success(()))
            case .failure where !trimmedCaption.isEmpty:
                self.sendCaptionFallback(chatId: chatId, fileURL: fileURL, caption: trimmedCaption, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func sendCaptionFallback(
        chatId: String,
        fileURL: URL,
        caption: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        loadAndSendDocument(chatId: chatId, fileURL: fileURL, caption: "") { [weak self] docResult in
            guard let self else { return }
            switch docResult {
            case .success:
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                    self.sendReply(chatId: chatId, text: caption, completion: completion)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func loadAndSendDocument(
        chatId: String,
        fileURL: URL,
        caption: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        prepareDesktopViewportForReply()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let accessGranted = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessGranted { fileURL.stopAccessingSecurityScopedResource() }
            }
            do {
                let fileData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let maxAllowedBytes = 24 * 1024 * 1024
                guard fileData.count <= maxAllowedBytes else {
                    throw NSError(
                        domain: "WhatsAppWebEngine",
                        code: 9010,
                        userInfo: [NSLocalizedDescriptionKey: "Documento troppo grande (\(fileData.count / (1024 * 1024)) MB)."]
                    )
                }

                let base64 = fileData.base64EncodedString()
                let fileName = fileURL.lastPathComponent
                let mimeType = Self.mimeType(for: fileURL)

                // FIX: invece di un delay fisso, aspettiamo che il webView sia stabile
                // usando waitForMainAndExecute sul main thread
                DispatchQueue.main.async {
                    self.waitForWebViewReadyThenSend(
                        chatId: chatId,
                        fileName: fileName,
                        mimeType: mimeType,
                        base64Data: base64,
                        caption: caption,
                        maxWaitSeconds: 12.0,
                        completion: completion
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.restoreMonitoringViewport()
                    completion(.failure(error))
                }
            }
        }
    }

    /// Aspetta che il webView abbia un processo web stabile e poi esegue l'invio.
    /// Questo risolve il crash "main-not-found" causato dal web process che crasha
    /// proprio mentre facciamo il resize del viewport.
    private func waitForWebViewReadyThenSend(
        chatId: String,
        fileName: String,
        mimeType: String,
        base64Data: String,
        caption: String,
        maxWaitSeconds: Double,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let startTime = Date()
        let pollInterval: TimeInterval = 0.4

        func checkReady() {
            // Controlla se il processo web è vivo verificando che il webView
            // risponda a una valutazione JS semplice
            webView.evaluateJavaScript("document.readyState") { [weak self] result, error in
                guard let self else { return }

                if error != nil || result == nil {
                    // Processo web non disponibile
                    if Date().timeIntervalSince(startTime) >= maxWaitSeconds {
                        self.restoreMonitoringViewport()
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9013,
                            userInfo: [NSLocalizedDescriptionKey: "WebView non disponibile dopo \(Int(maxWaitSeconds))s (web process crash loop)"]
                        )))
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { checkReady() }
                    return
                }

                let readyState = result as? String ?? ""
                if readyState == "complete" || readyState == "interactive" {
                    // WebView pronto: piccolo delay per lasciar caricare WhatsApp Web
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        guard let self else { return }
                        self.executeSendDocument(
                            chatId: chatId,
                            fileName: fileName,
                            mimeType: mimeType,
                            base64Data: base64Data,
                            caption: caption,
                            completion: completion
                        )
                    }
                } else {
                    // DOM non ancora pronto
                    if Date().timeIntervalSince(startTime) >= maxWaitSeconds {
                        self.restoreMonitoringViewport()
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9014,
                            userInfo: [NSLocalizedDescriptionKey: "DOM non pronto dopo \(Int(maxWaitSeconds))s"]
                        )))
                        return
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + pollInterval) { checkReady() }
                }
            }
        }

        checkReady()
    }

    private func executeSendDocument(
        chatId: String,
        fileName: String,
        mimeType: String,
        base64Data: String,
        caption: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let script = """
        if (typeof window.atollSendDocument !== 'function') {
            throw new Error('send-document-function-not-injected');
        }
        return await window.atollSendDocument(chatId, fileName, mimeType, base64Data, caption);
        """

        if #available(macOS 12.0, *) {
            webView.callAsyncJavaScript(
                script,
                arguments: [
                    "chatId": chatId,
                    "fileName": fileName,
                    "mimeType": mimeType,
                    "base64Data": base64Data,
                    "caption": caption
                ],
                in: nil,
                in: .page
            ) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let value):
                        self.restoreMonitoringViewport()
                        let status = (value as? String) ?? String(describing: value)
                        print("WhatsAppWebEngine: sendDocument completed -> \(status)")
                        completion(.success(status))
                    case .failure(let error):
                        self.restoreMonitoringViewport()
                        let nsError = error as NSError
                        let jsReason = (nsError.userInfo["WKJavaScriptExceptionMessage"] as? String)
                            ?? (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
                            ?? nsError.localizedDescription
                        print("WhatsAppWebEngine: sendDocument failed -> \(jsReason)")
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9011,
                            userInfo: [NSLocalizedDescriptionKey: jsReason]
                        )))
                    }
                }
            }
        } else {
            restoreMonitoringViewport()
            completion(.failure(NSError(
                domain: "WhatsAppWebEngine",
                code: 9012,
                userInfo: [NSLocalizedDescriptionKey: "Async JavaScript bridge unavailable on this macOS version"]
            )))
        }
    }

    private func executeSendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let script = """
        if (typeof window.atollSendMessage !== 'function') {
            throw new Error('send-function-not-injected');
        }
        return await window.atollSendMessage(chatId, text);
        """

        if #available(macOS 12.0, *) {
            webView.callAsyncJavaScript(
                script,
                arguments: ["chatId": chatId, "text": text],
                in: nil,
                in: .page
            ) { result in
                Task { @MainActor in
                    switch result {
                    case .success:
                        self.restoreMonitoringViewport()
                        completion(.success(()))
                    case .failure(let error):
                        self.restoreMonitoringViewport()
                        let nsError = error as NSError
                        let jsReason = (nsError.userInfo["WKJavaScriptExceptionMessage"] as? String)
                            ?? (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
                            ?? nsError.localizedDescription
                        print("WhatsAppWebEngine: sendReply failed -> \(jsReason)")
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9003,
                            userInfo: [NSLocalizedDescriptionKey: jsReason]
                        )))
                    }
                }
            }
        } else {
            restoreMonitoringViewport()
            completion(.failure(NSError(
                domain: "WhatsAppWebEngine",
                code: 9004,
                userInfo: [NSLocalizedDescriptionKey: "Async JavaScript bridge unavailable on this macOS version"]
            )))
        }
    }

    // MARK: - Private Setup

    private func buildWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        if #available(macOS 14.0, *) {
            let id = UUID(uuidString: "7E74F27C-351F-4D46-8F55-358C44D47651")!
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.default()
        }

        let handler = WeakScriptHandler(self)
        config.userContentController.add(handler, name: "atollWA")

        let authScript = WKUserScript(
            source: JS.authCheck,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(authScript)

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 600), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        wv.navigationDelegate = self
        wv.uiDelegate = self

        if #available(macOS 12.0, *) {
            wv.setValue(false, forKey: "drawsBackground")
        }

        return wv
    }

    private func attachToOffscreenWindow() {
        guard offscreenWindow == nil else { return }

        let win = NSWindow(
            contentRect: NSRect(x: -9999, y: -9999, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = webView
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isOpaque = false
        win.backgroundColor = .clear
        win.alphaValue = 0.0
        win.orderFront(nil)
        offscreenWindow = win
    }

    private func prepareDesktopViewportForReply() {
        guard let offscreenWindow else { return }
        let frame = NSRect(x: -9999, y: -9999, width: 1280, height: 900)
        offscreenWindow.setFrame(frame, display: true)
        webView.frame = NSRect(origin: .zero, size: frame.size)
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()
    }

    private func restoreMonitoringViewport() {
        guard let offscreenWindow else { return }
        let frame = NSRect(x: -9999, y: -9999, width: 1, height: 1)
        offscreenWindow.setFrame(frame, display: true)
        webView.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        webView.needsLayout = true
    }

    // MARK: - Auth Polling

    private func startAuthPolling() {
        authTimer?.invalidate()
        authTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollAuthState()
            }
        }
    }

    private func pollAuthState() {
        let webView = self.webView
        webView.evaluateJavaScript(JS.detectAuth) { [weak self] result, _ in
            guard let state = result as? String else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case "qr":
                    if self.authState != .qrRequired { self.authState = .qrRequired }
                case "auth":
                    if self.authState != .authenticated {
                        self.authState = .authenticated
                        self.authenticationTime = Date()
                        self.authTimer?.invalidate()
                        self.authTimer = nil
                        print("WhatsAppWebEngine: ✅ authenticated, injecting monitor")
                        self.scheduleMonitorInjectionIfNeeded(delayNanoseconds: 1_500_000_000)
                    }
                default: break
                }
            }
        }
    }

    private func scheduleMonitorInjectionIfNeeded(delayNanoseconds: UInt64 = 0) {
        guard authState == .authenticated else { return }
        guard !isMonitorInjectedForCurrentDocument else { return }
        guard pendingMonitorInjectionTask == nil else { return }

        pendingMonitorInjectionTask = Task { @MainActor [weak self] in
            defer { self?.pendingMonitorInjectionTask = nil }
            guard let self else { return }
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard self.authState == .authenticated else { return }
            guard !self.isMonitorInjectedForCurrentDocument else { return }
            self.injectMessageMonitor()
        }
    }

    private func injectMessageMonitor() {
        webView.evaluateJavaScript(JS.messageMonitor) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard self != nil else { return }
                if let e = error {
                    print("WhatsAppWebEngine: monitor injection failed: \(e)")
                } else {
                    self?.isMonitorInjectedForCurrentDocument = true
                    print("WhatsAppWebEngine: message monitor active ✅")
                }
            }
        }
    }

    // MARK: - Script Message Handler

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "atollWA",
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "sendDebug":
            let msg = dict["message"] as? String ?? ""
            print("WhatsAppWebEngine: sendDebug -> \(msg)")

        case "authState":
            let s = dict["state"] as? String ?? ""
            if s == "qr", authState != .qrRequired { authState = .qrRequired }
            if s == "auth", authState != .authenticated {
                authState = .authenticated
                authenticationTime = Date()
                scheduleMonitorInjectionIfNeeded(delayNanoseconds: 1_500_000_000)
            } else if s == "auth", authState == .authenticated {
                scheduleMonitorInjectionIfNeeded()
            }

        case "newMessage":
            guard let chatId = dict["chatId"] as? String,
                  let sender = dict["sender"] as? String,
                  let body = dict["body"] as? String,
                  !body.isEmpty else { return }

            let coordinator = DynamicIslandViewCoordinator.shared
            if coordinator.expandingView.show,
               case .whatsApp = coordinator.expandingView.type {
                print("WhatsAppWebEngine: ⏭ keep active WhatsApp conversation pinned -> \(sender)")
                return
            }

            if shouldIgnoreInformationalMessage(sender: sender, body: body) {
                print("WhatsAppWebEngine: ⏭ skip informational message from \(sender)")
                return
            }

            if let authTime = authenticationTime,
               Date().timeIntervalSince(authTime) < 6.0 {
                print("WhatsAppWebEngine: ⏭ skip startup: \(sender)")
                return
            }

            let avatar = dict["avatarUrl"] as? String
            let providedGroupSender = dict["groupSender"] as? String
            let resolvedGroupSender = resolveGroupSender(
                providedGroupSender: providedGroupSender,
                messageBody: body
            )
            let finalBody = normalizedIncomingMessageBody(
                formatMessageBody(body, withGroupSender: resolvedGroupSender)
            )

            print("WhatsAppWebEngine: 📩 \(sender): \(finalBody)")
            coordinator.cancelExpandingViewHide()
            coordinator.toggleExpandingView(
                status: true,
                type: .whatsApp(senderName: sender, messageText: finalBody, chatId: chatId, avatarUrl: avatar),
                autoHideDuration: 15
            )
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)

        default: break
        }
    }

    private func resolveGroupSender(providedGroupSender: String?, messageBody: String) -> String? {
        let trimmedProvided = providedGroupSender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isValidGroupSenderCandidate(trimmedProvided) { return trimmedProvided }
        guard let colonIndex = messageBody.firstIndex(of: ":") else { return nil }
        let candidate = messageBody[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidGroupSenderCandidate(candidate) ? candidate : nil
    }

    private func isValidGroupSenderCandidate(_ candidate: String) -> Bool {
        guard !candidate.isEmpty else { return false }
        guard candidate.count <= 40 else { return false }
        let lowered = candidate.lowercased()
        let blockedWords: Set<String> = ["bozza", "draft", "tu", "you", "whatsapp", "meta ai"]
        if blockedWords.contains(lowered) { return false }
        if lowered.hasPrefix("http") || lowered.hasPrefix("www.") { return false }
        if candidate.range(of: #"^\d{1,2}$"#, options: .regularExpression) != nil { return false }
        if candidate.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil { return false }
        return true
    }

    private func formatMessageBody(_ body: String, withGroupSender groupSender: String?) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupSender, !groupSender.isEmpty else { return trimmedBody }
        let prefix = "\(groupSender):"
        if trimmedBody.hasPrefix(prefix) { return trimmedBody }
        return "\(groupSender): \(trimmedBody)"
    }

    private func normalizedIncomingMessageBody(_ body: String) -> String {
        let cleaned = body
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "📨 Nuovo messaggio" : cleaned
    }

    private func shouldIgnoreInformationalMessage(sender: String, body: String) -> Bool {
        guard sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "whatsapp" else { return false }
        let normalizedBody = body.lowercased()
        let knownTips = [
            "silence unknown callers",
            "privacy checkup",
            "you control who can reach you",
            "in settings, go to privacy",
            "keep your contacts up-to-date with about",
            "keep your contacts up-to-date",
            "about directly from your chats",
            "share your availability",
            "control who can see it"
        ]
        return knownTips.contains { normalizedBody.contains($0) }
    }

    nonisolated private static func mimeType(for fileURL: URL) -> String {
        guard let utType = UTType(filenameExtension: fileURL.pathExtension) else { return "application/octet-stream" }
        return utType.preferredMIMEType ?? "application/octet-stream"
    }
}

// MARK: - WKNavigationDelegate

extension WhatsAppWebEngine: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isMonitorInjectedForCurrentDocument = false
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isMonitorInjectedForCurrentDocument = false
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isMonitorInjectedForCurrentDocument = false
        webProcessCrashCount = 0
        lastWebProcessCrashAt = nil
        pollAuthState()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let e = error as NSError
        if e.code != NSURLErrorCancelled { authState = .error(error.localizedDescription) }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isMonitorInjectedForCurrentDocument = false
        pendingMonitorInjectionTask?.cancel()
        pendingMonitorInjectionTask = nil

        // FIX: ripristina il viewport al crash, così il processo che si riavvia
        // non si trova con un layout 1280x900 e non va in crash loop
        restoreMonitoringViewport()

        let now = Date()
        if let last = lastWebProcessCrashAt, now.timeIntervalSince(last) > 30 { webProcessCrashCount = 0 }
        lastWebProcessCrashAt = now
        webProcessCrashCount += 1

        let delaySeconds = min(8.0, pow(2.0, Double(max(0, webProcessCrashCount - 1))))
        print("[Atoll] WhatsApp WKWebView web process terminated (crash #\(webProcessCrashCount)). Reload in \(delaySeconds)s…")

        crashRecoveryTask?.cancel()
        crashRecoveryTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard let webView else { return }
            webView.reloadFromOrigin()
            self.crashRecoveryTask = nil
        }
    }
}

// MARK: - WKUIDelegate

extension WhatsAppWebEngine: WKUIDelegate {
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }
}

// MARK: - JavaScript
// (invariato rispetto all'originale - tutto il JS rimane identico)


private enum JS {
    static let authCheck = """
    (function() {
        function check() {
            var qr = document.querySelector('[data-testid="qr-container"]')
                   || document.querySelector('canvas[aria-label]')
                   || document.querySelector('[data-ref]');
            var sidebar = document.querySelector('#side')
                       || document.querySelector('[data-testid="chatlist-header"]');
            var state = qr ? 'qr' : (sidebar ? 'auth' : 'loading');
            window.webkit.messageHandlers.atollWA.postMessage({ type: 'authState', state: state });
        }
        check();
        setInterval(check, 3000);
    })();
    """

    static let detectAuth = """
    (function() {
        var qr = document.querySelector('[data-testid="qr-container"]')
               || document.querySelector('canvas[aria-label]')
               || document.querySelector('[data-ref]');
        var sidebar = document.querySelector('#side')
                   || document.querySelector('[data-testid="chatlist-header"]');
        return qr ? 'qr' : (sidebar ? 'auth' : 'loading');
    })()
    """

    static let messageMonitor = """
    (function() {
        if (window.__atollMonitorV3) return;
        window.__atollMonitorV3 = true;

        console.log('[Atoll] Inizializzazione monitor v3...');

        // Snapshot dei sender già non letti all'avvio → da ignorare
        var ignoredSenders = new Set();
        // Mappa sender → ultimo body visto → per rilevare CAMBIAMENTI
        var lastBodyBySender = {};
        // Set di chiavi già notificate
        var notified = new Set();
        var chatRowSelector = '[data-testid="cell-frame-container"], #pane-side [role="listitem"]';

        function extractSender(row) {
            var titleEl = row.querySelector('[data-testid="cell-frame-title"]');
            if (titleEl) {
                var spans = titleEl.querySelectorAll('span[title]');
                for (var i = 0; i < spans.length; i++) {
                    var t = (spans[i].getAttribute('title') || '').trim();
                    if (t && !/^\\d+$/.test(t) && !/non letto/i.test(t) && !/unread/i.test(t)) {
                        return t;
                    }
                }
                spans = titleEl.querySelectorAll('span');
                for (var j = 0; j < spans.length; j++) {
                    var txt = spans[j].textContent.trim();
                    if (txt && !/^\\d+$/.test(txt) && !/non letto/i.test(txt) && !/unread/i.test(txt)) {
                        return txt;
                    }
                }
            }
            var autoSpans = row.querySelectorAll('span[dir="auto"][title]');
            for (var k = 0; k < autoSpans.length; k++) {
                var n = (autoSpans[k].getAttribute('title') || '').trim();
                if (n && !/^\\d+$/.test(n)) return n;
            }
            return null;
        }

        function extractBodyAndGroupSender(row) {
            var body = '📨 Nuovo messaggio';
            var groupSender = '';
            try {
                // 1. Logica originale ed estremamente affidabile per estrarre il corpo
                var sel = [
                    '[data-testid="last-msg-status"] ~ span span',
                    '[data-testid="cell-frame-secondary-detail"] span span',
                    'span[dir="ltr"]'
                ];
                for (var i = 0; i < sel.length; i++) {
                    var el = row.querySelector(sel[i]);
                    if (el && el.textContent.trim()) {
                        body = el.textContent.trim();
                        break;
                    }
                }
                
                // Se non trovato, proviamo il testo interno del dettaglio secondario
                if (!body || body === '📨 Nuovo messaggio') {
                    var sec = row.querySelector('[data-testid="cell-frame-secondary-detail"]');
                    if (sec && sec.textContent.trim()) {
                        body = sec.textContent.trim();
                    }
                }

                // 2. Trova il mittente del gruppo se presente
                var secondary = row.querySelector('[data-testid="cell-frame-secondary-detail"]');
                if (secondary) {
                    var fullText = secondary.textContent || '';
                    var colonIdx = fullText.indexOf(': ');
                    if (colonIdx > 0 && colonIdx < 30) {
                        var possibleMember = fullText.substring(0, colonIdx).trim();
                        // Escludi orari o parole riservate
                        if (possibleMember !== 'Bozza' && possibleMember !== 'Draft' && !/^\\d{1,2}$/.test(possibleMember) && !/^\\d{1,2}:\\d{2}$/.test(possibleMember)) {
                            groupSender = possibleMember;
                        }
                    }
                }
            } catch (e) {
                console.log('[Atoll] Errore in extractBodyAndGroupSender: ' + e);
            }
            
            // Pulisci eventuali checkmark di lettura
            if (body && (body.startsWith('✓') || body.startsWith('✔'))) {
                body = body.replace(/^[✓✔\\s\\u200B-\\u200D\\uFEFF]+/, '');
            }
            
            return { body: body || '📨 Nuovo messaggio', member: groupSender || '' };
        }

        function extractAvatar(row) {
            var avatarContainer = row.querySelector('[data-testid="avatar"]');
            var img = avatarContainer ? avatarContainer.querySelector('img') : null;
            if (!img) {
                var imgs = row.querySelectorAll('img');
                for (var i = 0; i < imgs.length; i++) {
                    var src = imgs[i].src || '';
                    if (src && !src.includes('emoji') && !src.includes('data:image')) {
                        img = imgs[i];
                        break;
                    }
                }
            }
            if (img && img.src && !img.src.includes('emoji') && !img.src.includes('data:image')) {
                return img.src;
            }
            return null;
        }

        var lastUnreadBySender = {};

        // Costruisci snapshot iniziale di tutti i badge non letti
        function buildSnapshot() {
            var rows = document.querySelectorAll(chatRowSelector);
            rows.forEach(function(row) {
                var unreadEl = row.querySelector('[data-testid="icon-unread-count"]');
                if (!unreadEl) return;
                var sender = extractSender(row);
                if (!sender) return;
                var result = extractBodyAndGroupSender(row);
                var unreadCount = parseInt(unreadEl.textContent) || 1;
                
                ignoredSenders.add(sender);
                lastBodyBySender[sender] = result.body || '';
                lastUnreadBySender[sender] = unreadCount;
                console.log('[Atoll] snapshot: ' + sender + ' → ' + (result.body || '(no body)') + ' (unread: ' + unreadCount + ')');
            });
            console.log('[Atoll] snapshot completo: ' + ignoredSenders.size + ' chat');
        }

        buildSnapshot();

        // Funzione principale: controlla se c'è qualcosa di NUOVO
        function checkForNew() {
            var rows = document.querySelectorAll(chatRowSelector);
            rows.forEach(function(row) {
                var unreadEl = row.querySelector('[data-testid="icon-unread-count"]');
                if (!unreadEl) return;

                var sender = extractSender(row);
                if (!sender) return;

                var result = extractBodyAndGroupSender(row);
                var body = result.body || '📨 Nuovo messaggio';
                var groupSender = result.member;
                var unreadCount = parseInt(unreadEl.textContent) || 1;

                var prevBody = lastBodyBySender[sender] || '';
                var prevCount = lastUnreadBySender[sender] || 0;

                if (ignoredSenders.has(sender)) {
                    // Ignora se corpo e count non sono cambiati (nessuna novità)
                    if (body === prevBody && unreadCount <= prevCount) return;
                } else {
                    ignoredSenders.add(sender);
                }

                // Aggiorna stato
                lastBodyBySender[sender] = body;
                lastUnreadBySender[sender] = unreadCount;

                var dedupKey = sender + '||' + body + '||' + unreadCount;
                if (notified.has(dedupKey)) return;
                notified.add(dedupKey);

                // Non puliamo più notified in automatico, contiamo su unreadCount e body per capire se è cambiato
                
                var avatar = extractAvatar(row);
                console.log('[Atoll] 🔔 NUOVO: ' + sender + ' → ' + body + ' | avatar: ' + avatar + ' | count: ' + unreadCount);
                window.webkit.messageHandlers.atollWA.postMessage({
                    type: 'newMessage',
                    chatId: sender + '@c.us',
                    sender: sender,
                    body: body,
                    avatarUrl: avatar,
                    groupSender: groupSender
                });
            });
        }

        function attachObserver() {
            var pane = document.querySelector('#pane-side');
            if (!pane) {
                console.log('[Atoll] pane-side non trovato, riprovo...');
                setTimeout(attachObserver, 500);
                return;
            }
            console.log('[Atoll] MutationObserver attaccato a #pane-side');
            var debounceTimer = null;
            new MutationObserver(function() {
                if (debounceTimer) clearTimeout(debounceTimer);
                debounceTimer = setTimeout(checkForNew, 200);
            }).observe(pane, {
                childList: true,
                subtree: true,
                characterData: true
            });
            
            // Affidabilità al 100%: poll aggiuntivo a bassa latenza
            setInterval(checkForNew, 2000);
        }
        attachObserver();

        // Send reply (apre la chat corretta e conferma che il composer cambi stato)
        window.atollSendMessage = function(chatId, text) {
            var targetSender = chatId.replace(/@(c|g)\\.us$/, '').trim();
            function debug(message) {
                try {
                    window.webkit.messageHandlers.atollWA.postMessage({
                        type: 'sendDebug',
                        message: message
                    });
                } catch (e) {}
            }

            debug('start target="' + targetSender + '" viewport=' + window.innerWidth + 'x' + window.innerHeight);

            function normalize(value) {
                return (value || '').trim().toLowerCase();
            }

            var rows = document.querySelectorAll(chatRowSelector);
            var targetRow = null;
            var targetRowName = '';
            for (var i = 0; i < rows.length; i++) {
                var s = extractSender(rows[i]);
                if (s && normalize(s) === normalize(targetSender)) {
                    targetRow = rows[i];
                    targetRowName = s;
                    break;
                }
            }

            function fireMouseSequence(element) {
                if (!element) return false;
                try { element.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {}
                try { element.focus({ preventScroll: true }); } catch (e) {}

                var rect = element.getBoundingClientRect();
                var x = Math.max(1, Math.floor(rect.left + Math.min(rect.width / 2, rect.width - 2)));
                var y = Math.max(1, Math.floor(rect.top + Math.min(rect.height / 2, rect.height - 2)));
                var target = document.elementFromPoint(x, y) || element;
                var eventOptions = {
                    bubbles: true,
                    cancelable: true,
                    composed: true,
                    view: window,
                    clientX: x,
                    clientY: y,
                    screenX: x,
                    screenY: y
                };

                if (typeof PointerEvent === 'function') {
                    target.dispatchEvent(new PointerEvent('pointerover', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, eventOptions)));
                    target.dispatchEvent(new PointerEvent('pointerenter', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, eventOptions)));
                    target.dispatchEvent(new PointerEvent('pointerdown', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 1, button: 0 }, eventOptions)));
                    target.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 0, button: 0 }, eventOptions)));
                }

                target.dispatchEvent(new MouseEvent('mouseover', eventOptions));
                target.dispatchEvent(new MouseEvent('mouseenter', eventOptions));
                target.dispatchEvent(new MouseEvent('mousedown', Object.assign({ buttons: 1, button: 0 }, eventOptions)));
                target.dispatchEvent(new MouseEvent('mouseup', Object.assign({ buttons: 0, button: 0 }, eventOptions)));
                target.dispatchEvent(new MouseEvent('click', Object.assign({ buttons: 0, button: 0 }, eventOptions)));
                try { target.click(); } catch (e) {}

                element.dispatchEvent(new KeyboardEvent('keydown', {
                    bubbles: true,
                    cancelable: true,
                    key: 'Enter',
                    code: 'Enter',
                    keyCode: 13,
                    which: 13
                }));
                element.dispatchEvent(new KeyboardEvent('keyup', {
                    bubbles: true,
                    cancelable: true,
                    key: 'Enter',
                    code: 'Enter',
                    keyCode: 13,
                    which: 13
                }));
                return true;
            }

            function openTargetRow(reason) {
                if (!targetRow) {
                    debug('chat row not found; trying current chat');
                    return false;
                }

                var clickable = targetRow.querySelector('[role="button"]')
                    || targetRow.querySelector('[role="gridcell"]')
                    || targetRow.querySelector('[tabindex="0"]')
                    || targetRow.querySelector('[tabindex="-1"]')
                    || targetRow;

                debug('open row (' + reason + ') name="' + targetRowName + '" clickable=' + (clickable.getAttribute('role') || clickable.tagName));
                return fireMouseSequence(clickable);
            }

            function composerText(input) {
                if (!input) return '';
                return ((input.innerText || input.textContent || '').replace(/\\u200B/g, '').trim());
            }

            function findComposerInput(main) {
                var footer = main.querySelector('footer')
                    || document.querySelector('[data-testid="conversation-panel-wrapper"] footer')
                    || document.querySelector('footer');
                if (!footer) footer = main;
                return footer.querySelector('[data-testid="conversation-compose-box-input"]')
                    || footer.querySelector('div[data-lexical-editor="true"][contenteditable="true"]')
                    || footer.querySelector('div[contenteditable="true"][role="textbox"][aria-label]')
                    || footer.querySelector('div[contenteditable="true"][role="textbox"][aria-placeholder]')
                    || footer.querySelector('div[contenteditable="true"][data-tab]')
                    || footer.querySelector('div[contenteditable="true"]');
            }

            function findSendButton(main) {
                var selectors = [
                    '[data-testid="send"]',
                    'button[aria-label="Invia"]',
                    'button[aria-label="Send"]',
                    'button span[data-icon="send"]'
                ];
                for (var i = 0; i < selectors.length; i++) {
                    var match = main.querySelector(selectors[i]);
                    if (!match) continue;
                    return match.closest('button') || match;
                }
                return null;
            }

            function setComposerText(input, value) {
                input.focus();
                input.textContent = '';

                var selection = window.getSelection();
                var range = document.createRange();
                range.selectNodeContents(input);
                range.collapse(false);
                selection.removeAllRanges();
                selection.addRange(range);

                var insertedWithCommand = false;
                if (typeof document.execCommand === 'function') {
                    try {
                        insertedWithCommand = document.execCommand('insertText', false, value);
                    } catch (e) {
                        insertedWithCommand = false;
                    }
                }

                if (!insertedWithCommand || composerText(input).length === 0) {
                    input.textContent = '';
                    var lines = String(value).split('\\n');
                    for (var i = 0; i < lines.length; i++) {
                        if (i > 0) {
                            input.appendChild(document.createElement('br'));
                        }
                        input.appendChild(document.createTextNode(lines[i]));
                    }
                    input.dispatchEvent(new Event('input', { bubbles: true }));
                }

                input.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function waitForComposer(attempt) {
                if (attempt === 1 || attempt === 8 || attempt === 18 || attempt === 32) {
                    openTargetRow('attempt ' + attempt);
                }
                var main = document.querySelector('#main');
                if (!main) return null;
                var input = findComposerInput(main);
                if (!input && (attempt === 20 || attempt === 45 || attempt === 70)) {
                    var mainText = ((main.innerText || main.textContent || '').trim()).slice(0, 160).replace(/\\s+/g, ' ');
                    debug('composer missing: attempt=' + attempt + ' main=' + !!main + ' footer=' + !!main.querySelector('footer') + ' editableCount=' + main.querySelectorAll('div[contenteditable="true"]').length + ' mainText="' + mainText + '"');
                }
                if (input || attempt >= 75) {
                    return { main: main, input: input };
                }
                return null;
            }

            return new Promise(function(resolve, reject) {
                var attempts = 0;
                var poll = setInterval(function() {
                    attempts += 1;
                    var composer = waitForComposer(attempts);
                    if (!composer) return;
                    clearInterval(poll);

                    var main = composer.main;
                    var input = composer.input;
                    if (!main || !input) {
                        return reject('compose-input-not-found');
                    }

                    debug('composer found');

                    setComposerText(input, text);

                    setTimeout(function() {
                        var btn = findSendButton(main);
                        debug('send button=' + !!btn + ' composerTextLength=' + composerText(input).length);
                        if (btn && !btn.disabled && btn.getAttribute('aria-disabled') !== 'true') {
                            btn.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, view: window }));
                            btn.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true, view: window }));
                            btn.click();
                        } else {
                            input.focus();
                            input.dispatchEvent(new KeyboardEvent('keydown', {
                                bubbles: true,
                                cancelable: true,
                                key: 'Enter',
                                code: 'Enter',
                                keyCode: 13,
                                which: 13
                            }));
                            input.dispatchEvent(new KeyboardEvent('keyup', {
                                bubbles: true,
                                cancelable: true,
                                key: 'Enter',
                                code: 'Enter',
                                keyCode: 13,
                                which: 13
                            }));
                        }

                        var verifyAttempts = 0;
                        var verify = setInterval(function() {
                            verifyAttempts += 1;
                            var remainingText = composerText(input);
                            var sendStillVisible = !!findSendButton(main);
                            if (remainingText.length === 0 || !sendStillVisible) {
                                clearInterval(verify);
                                resolve('sent-confirmed');
                                return;
                            }
                            if (verifyAttempts >= 20) {
                                clearInterval(verify);
                                reject('send-not-confirmed input="' + remainingText + '" sendButton=' + sendStillVisible);
                            }
                        }, 120);
                    }, 180);
                }, 120);
            });
        };

        console.log('[Atoll] Monitor v3 attivo ✅');
    })();
    """
}
