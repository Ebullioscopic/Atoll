/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 */

import Foundation
import AppKit
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

    // Queue for incoming messages that arrive while one is already displayed
    private struct PendingMessage {
        let sender: String
        let messages: [WhatsAppIncomingMessage]
        let chatId: String
        let avatarUrl: String?
    }
    private var messageQueue: [PendingMessage] = []
    private var drainTask: Task<Void, Never>?

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
        drainTask?.cancel()
        drainTask = nil
        messageQueue.removeAll()
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

    public func selectPollOption(
        chatId: String,
        messageId: String,
        questionText: String,
        selectedOptionTexts: [String],
        optionText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        prepareDesktopViewportForReply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.executeSelectPollOption(
                chatId: chatId,
                messageId: messageId,
                questionText: questionText,
                selectedOptionTexts: selectedOptionTexts,
                optionText: optionText,
                completion: completion
            )
        }
    }

    public func downloadDocument(
        chatId: String,
        messageId: String,
        fileName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        prepareDesktopViewportForReply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.executeDownloadDocument(
                chatId: chatId,
                messageId: messageId,
                fileName: fileName,
                completion: completion
            )
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

    private func executeSelectPollOption(
        chatId: String,
        messageId: String,
        questionText: String,
        selectedOptionTexts: [String],
        optionText: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let script = """
        if (typeof window.atollSelectPollOption !== 'function') {
            throw new Error('poll-select-function-not-injected');
        }
        return await window.atollSelectPollOption(chatId, messageId, optionText, questionText, selectedOptionTexts);
        """

        if #available(macOS 12.0, *) {
            webView.callAsyncJavaScript(
                script,
                arguments: ["chatId": chatId, "messageId": messageId, "optionText": optionText, "questionText": questionText, "selectedOptionTexts": selectedOptionTexts],
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
                        print("WhatsAppWebEngine: selectPollOption failed -> \(jsReason)")
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9020,
                            userInfo: [NSLocalizedDescriptionKey: jsReason]
                        )))
                    }
                }
            }
        } else {
            restoreMonitoringViewport()
            completion(.failure(NSError(
                domain: "WhatsAppWebEngine",
                code: 9021,
                userInfo: [NSLocalizedDescriptionKey: "Async JavaScript bridge unavailable on this macOS version"]
            )))
        }
    }

    private func executeDownloadDocument(
        chatId: String,
        messageId: String,
        fileName: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let script = """
        if (typeof window.atollDownloadDocument !== 'function') {
            throw new Error('document-download-function-not-injected');
        }
        return await window.atollDownloadDocument(chatId, messageId, fileName);
        """

        if #available(macOS 12.0, *) {
            webView.callAsyncJavaScript(
                script,
                arguments: ["chatId": chatId, "messageId": messageId, "fileName": fileName],
                in: nil,
                in: .page
            ) { result in
                Task { @MainActor in
                    self.restoreMonitoringViewport()
                    switch result {
                    case .success(let value):
                        guard let payload = value as? [String: Any],
                              let dataUrl = payload["dataUrl"] as? String else {
                            completion(.failure(NSError(
                                domain: "WhatsAppWebEngine",
                                code: 9030,
                                userInfo: [NSLocalizedDescriptionKey: "Download documento non disponibile"]
                            )))
                            return
                        }
                        let downloadedFileName = (payload["fileName"] as? String) ?? fileName
                        do {
                            let url = try self.saveDownloadedDocument(dataUrl: dataUrl, fileName: downloadedFileName)
                            print("WhatsAppWebEngine: document downloaded -> \(url.path)")
                            completion(.success(url))
                        } catch {
                            completion(.failure(error))
                        }
                    case .failure(let error):
                        let nsError = error as NSError
                        let jsReason = (nsError.userInfo["WKJavaScriptExceptionMessage"] as? String)
                            ?? (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
                            ?? nsError.localizedDescription
                        print("WhatsAppWebEngine: downloadDocument failed -> \(jsReason)")
                        completion(.failure(NSError(
                            domain: "WhatsAppWebEngine",
                            code: 9031,
                            userInfo: [NSLocalizedDescriptionKey: jsReason]
                        )))
                    }
                }
            }
        } else {
            restoreMonitoringViewport()
            completion(.failure(NSError(
                domain: "WhatsAppWebEngine",
                code: 9032,
                userInfo: [NSLocalizedDescriptionKey: "Async JavaScript bridge unavailable on this macOS version"]
            )))
        }
    }

    private func saveDownloadedDocument(dataUrl: String, fileName: String) throws -> URL {
        guard let commaIndex = dataUrl.firstIndex(of: ",") else {
            throw NSError(
                domain: "WhatsAppWebEngine",
                code: 9033,
                userInfo: [NSLocalizedDescriptionKey: "Formato documento non valido"]
            )
        }
        let base64 = String(dataUrl[dataUrl.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64) else {
            throw NSError(
                domain: "WhatsAppWebEngine",
                code: 9034,
                userInfo: [NSLocalizedDescriptionKey: "Documento non decodificabile"]
            )
        }
        guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "WhatsAppWebEngine",
                code: 9035,
                userInfo: [NSLocalizedDescriptionKey: "Cartella Download non trovata"]
            )
        }
        let destination = uniqueDownloadURL(
            in: downloadsURL,
            fileName: sanitizedDownloadFileName(fileName)
        )
        try data.write(to: destination, options: [.atomic])
        return destination
    }

    private func sanitizedDownloadFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "WhatsApp File" : trimmed
        let invalid = CharacterSet(charactersIn: "/\\:")
        let cleaned = fallback
            .components(separatedBy: invalid)
            .joined(separator: "-")
        return cleaned.isEmpty ? "WhatsApp File" : cleaned
    }

    private func uniqueDownloadURL(in directory: URL, fileName: String) -> URL {
        let baseURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: baseURL.path) else { return baseURL }

        let ext = baseURL.pathExtension
        let stem = baseURL.deletingPathExtension().lastPathComponent
        for index in 1...999 {
            let candidateName = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return directory.appendingPathComponent(UUID().uuidString + (ext.isEmpty ? "" : ".\(ext)"))
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
            contentRect: NSRect(x: -9999, y: -9999, width: 1280, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = webView
        webView.frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        webView.needsLayout = true
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
        let frame = NSRect(x: -9999, y: -9999, width: 1280, height: 900)
        offscreenWindow.setFrame(frame, display: true)
        webView.frame = NSRect(origin: .zero, size: frame.size)
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

        case "pollDebug":
            let msg = dict["message"] as? String ?? ""
            print("WhatsAppWebEngine: pollDebug -> \(msg)")

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
            let finalBody = normalizedIncomingMessageBody(body)
            let incomingMessages = parseIncomingMessages(
                from: dict,
                fallbackBody: finalBody,
                sender: sender,
                chatId: chatId
            )

            let coordinator = DynamicIslandViewCoordinator.shared
            let pending = PendingMessage(sender: sender, messages: incomingMessages, chatId: chatId, avatarUrl: avatar)
            if resolvedGroupSender != nil || incomingMessages.contains(where: { $0.groupSender != nil }) {
                print("WhatsAppWebEngine: group payload -> group=\(sender) member=\(resolvedGroupSender ?? "-") messages=\(incomingMessages.map { "\($0.groupSender ?? "-"): \($0.text)" }.joined(separator: " / "))")
            }

            // If a WhatsApp card is already visible, queue the new message
            if coordinator.expandingView.show,
               case .whatsApp(let visibleSender, let visibleMessages, let visibleChatId, let visibleAvatarUrl) = coordinator.expandingView.type {
                if visibleChatId == chatId || visibleSender == sender {
                    var updatedMessages = visibleMessages
                    let uniqueNewMessages = incomingMessages.filter { incoming in
                        !updatedMessages.contains(where: { existing in
                            stableMessageKey(existing, sender: sender, chatId: chatId) == stableMessageKey(incoming, sender: sender, chatId: chatId)
                        })
                    }
                    guard !uniqueNewMessages.isEmpty else {
                        print("WhatsAppWebEngine: ⏭ duplicate, skip \(sender)")
                        return
                    }
                    updatedMessages.append(contentsOf: uniqueNewMessages)
                    updatedMessages = deduplicatedIncomingMessages(updatedMessages, sender: visibleSender, chatId: visibleChatId)
                    guard updatedMessages.count > visibleMessages.count else {
                        print("WhatsAppWebEngine: ⏭ duplicate after normalization, skip \(sender)")
                        return
                    }
                    coordinator.toggleExpandingView(
                        status: true,
                        type: .whatsApp(
                            senderName: visibleSender,
                            messages: updatedMessages,
                            chatId: visibleChatId,
                            avatarUrl: visibleAvatarUrl ?? avatar
                        ),
                        autoHideDuration: 15
                    )
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    print("WhatsAppWebEngine: ➕ appended from \(sender)")
                    return
                }

                // Avoid duplicate identical messages in the queue
                let alreadyQueued = messageQueue.contains {
                    $0.sender == sender
                        && $0.chatId == chatId
                        && $0.messages.map { stableMessageKey($0, sender: sender, chatId: chatId) }
                            == incomingMessages.map { stableMessageKey($0, sender: sender, chatId: chatId) }
                }
                if !alreadyQueued {
                    print("WhatsAppWebEngine: 📥 queued from \(sender)")
                    messageQueue.append(pending)
                    scheduleQueueDrain(coordinator: coordinator)
                } else {
                    print("WhatsAppWebEngine: ⏭ duplicate, skip \(sender)")
                }
                return
            }

            showMessage(pending, coordinator: coordinator)

        default: break
        }
    }

    // MARK: - Message Queue helpers

    private func showMessage(_ msg: PendingMessage, coordinator: DynamicIslandViewCoordinator) {
        let summary = msg.messages.map { message in
            if message.pollOptions.isEmpty {
                return message.text
            }
            return "\(message.text) [poll: \(message.pollOptions.map(\.text).joined(separator: " | "))]"
        }.joined(separator: " / ")
        print("WhatsAppWebEngine: 📩 \(msg.sender): \(summary)")
        coordinator.cancelExpandingViewHide()
        coordinator.toggleExpandingView(
            status: true,
            type: .whatsApp(senderName: msg.sender, messages: msg.messages, chatId: msg.chatId, avatarUrl: msg.avatarUrl),
            autoHideDuration: 15
        )
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }

    private func scheduleQueueDrain(coordinator: DynamicIslandViewCoordinator) {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            // Wait until the current card is dismissed
            while true {
                try? await Task.sleep(for: .seconds(0.5))
                guard self != nil else { return }
                guard !Task.isCancelled else { return }
                let showing = await MainActor.run { coordinator.expandingView.show }
                if !showing { break }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !self.messageQueue.isEmpty else {
                    self.drainTask = nil
                    return
                }
                let next = self.messageQueue.removeFirst()
                self.drainTask = nil
                self.showMessage(next, coordinator: coordinator)
                // If there are more, schedule again
                if !self.messageQueue.isEmpty {
                    self.scheduleQueueDrain(coordinator: coordinator)
                }
            }
        }
    }

    private func parseIncomingMessages(
        from dict: [String: Any],
        fallbackBody: String,
        sender: String,
        chatId: String
    ) -> [WhatsAppIncomingMessage] {
        let rawMessages = dict["messages"] as? [[String: Any]] ?? []
        let parsedMessages = rawMessages.compactMap { raw -> WhatsAppIncomingMessage? in
            let rawBody = raw["body"] as? String ?? raw["text"] as? String ?? ""
            let providedGroupSender = raw["groupSender"] as? String ?? dict["groupSender"] as? String
            let resolvedGroupSender = resolveGroupSender(
                providedGroupSender: providedGroupSender,
                messageBody: rawBody
            )
            let text = normalizedIncomingMessageBody(
                messageBodyWithoutGroupSender(rawBody, groupSender: resolvedGroupSender)
            )
            let mediaKind = (raw["mediaKind"] as? String).flatMap(WhatsAppIncomingMediaKind.init(rawValue:))
            let mediaDataUrl = nonEmptyString(raw["mediaDataUrl"])
            let linkPreview = parseLinkPreview(raw["linkPreview"]) ?? linkPreviewFromMessageText(text)
            let documentPreview = parseDocumentPreview(raw["documentPreview"]) ?? parseDocumentPreview(raw["document"])
            let pollOptions = parsePollOptions(raw["pollOptions"])
            let pollAllowsMultipleSelection = raw["pollAllowsMultipleSelection"] as? Bool ?? false
            let id = nonEmptyString(raw["id"])
                ?? nonEmptyString(raw["messageId"])
                ?? stableMessageID(sender: sender, chatId: chatId, text: text, groupSender: resolvedGroupSender, mediaKind: mediaKind, linkPreview: linkPreview, documentPreview: documentPreview, pollOptions: pollOptions)

            guard text != "📨 Nuovo messaggio" || mediaKind != nil || mediaDataUrl != nil || linkPreview != nil || documentPreview != nil || !pollOptions.isEmpty else { return nil }
            return WhatsAppIncomingMessage(
                id: id,
                text: text,
                mediaKind: mediaKind,
                mediaDataUrl: mediaDataUrl,
                linkPreview: linkPreview,
                documentPreview: documentPreview,
                groupSender: resolvedGroupSender,
                pollOptions: pollOptions,
                pollAllowsMultipleSelection: pollAllowsMultipleSelection
            )
        }

        let uniqueParsedMessages = deduplicatedIncomingMessages(parsedMessages, sender: sender, chatId: chatId)
        if !uniqueParsedMessages.isEmpty {
            return uniqueParsedMessages
        }

        let mediaKind = (dict["mediaKind"] as? String).flatMap(WhatsAppIncomingMediaKind.init(rawValue:))
        let mediaDataUrl = nonEmptyString(dict["mediaDataUrl"])
        let providedFallbackGroupSender = dict["groupSender"] as? String
        let fallbackGroupSender = resolveGroupSender(
            providedGroupSender: providedFallbackGroupSender,
            messageBody: fallbackBody
        )
        let fallbackText = normalizedIncomingMessageBody(
            messageBodyWithoutGroupSender(fallbackBody, groupSender: fallbackGroupSender)
        )
        let linkPreview = parseLinkPreview(dict["linkPreview"]) ?? linkPreviewFromMessageText(fallbackText)
        let documentPreview = parseDocumentPreview(dict["documentPreview"]) ?? parseDocumentPreview(dict["document"])
        let pollOptions = parsePollOptions(dict["pollOptions"])
        let pollAllowsMultipleSelection = dict["pollAllowsMultipleSelection"] as? Bool ?? false
        let messageID = nonEmptyString(dict["messageId"])
        return [
            WhatsAppIncomingMessage(
                id: messageID ?? stableMessageID(sender: sender, chatId: chatId, text: fallbackText, groupSender: fallbackGroupSender, mediaKind: mediaKind, linkPreview: linkPreview, documentPreview: documentPreview, pollOptions: pollOptions),
                text: fallbackText,
                mediaKind: mediaKind,
                mediaDataUrl: mediaDataUrl,
                linkPreview: linkPreview,
                documentPreview: documentPreview,
                groupSender: fallbackGroupSender,
                pollOptions: pollOptions,
                pollAllowsMultipleSelection: pollAllowsMultipleSelection
            )
        ]
    }

    private func parsePollOptions(_ value: Any?) -> [WhatsAppIncomingPollOption] {
        guard let rawOptions = value as? [[String: Any]] else { return [] }
        return rawOptions.compactMap { raw in
            guard let text = nonEmptyString(raw["text"]) else { return nil }
            let id = nonEmptyString(raw["id"]) ?? text.lowercased()
            let selected = raw["selected"] as? Bool ?? raw["isSelected"] as? Bool ?? false
            let voteCount = raw["voteCount"] as? Int ?? raw["votes"] as? Int ?? 0
            return WhatsAppIncomingPollOption(id: id, text: text, isSelected: selected, voteCount: voteCount)
        }
    }

    private func parseLinkPreview(_ value: Any?) -> WhatsAppIncomingLinkPreview? {
        guard let raw = value as? [String: Any],
              let url = normalizedLinkURL(nonEmptyString(raw["url"])) else { return nil }
        let domain = nonEmptyString(raw["domain"]) ?? displayDomain(for: url)
        let title = sanitizedLinkPreviewTitle(
            nonEmptyString(raw["title"]) ?? nonEmptyString(raw["description"]),
            domain: domain,
            url: url
        )
        return WhatsAppIncomingLinkPreview(
            url: url,
            title: title,
            domain: domain,
            imageDataUrl: nonEmptyString(raw["imageDataUrl"]),
            appleMapsUrl: normalizedLinkURL(nonEmptyString(raw["appleMapsUrl"]))
                ?? appleMapsURL(for: url, title: title)
        )
    }

    private func parseDocumentPreview(_ value: Any?) -> WhatsAppIncomingDocumentPreview? {
        guard let raw = value as? [String: Any],
              let fileName = nonEmptyString(raw["fileName"]) else { return nil }
        return WhatsAppIncomingDocumentPreview(
            fileName: fileName,
            detail: nonEmptyString(raw["detail"]) ?? "FILE",
            mimeType: nonEmptyString(raw["mimeType"]),
            thumbnailDataUrl: nonEmptyString(raw["thumbnailDataUrl"]) ?? nonEmptyString(raw["imageDataUrl"])
        )
    }

    private func linkPreviewFromMessageText(_ text: String) -> WhatsAppIncomingLinkPreview? {
        guard let match = text.range(
            of: #"(https?://[^\s<>"']+|www\.[^\s<>"']+)"#,
            options: .regularExpression
        ) else { return nil }
        guard let url = normalizedLinkURL(String(text[match])) else { return nil }
        let domain = displayDomain(for: url)
        return WhatsAppIncomingLinkPreview(
            url: url,
            title: domain,
            domain: domain,
            imageDataUrl: nil,
            appleMapsUrl: appleMapsURL(for: url, title: domain)
        )
    }

    private func sanitizedLinkPreviewTitle(_ rawTitle: String?, domain: String, url: String) -> String {
        guard let title = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return domain }
        let lowered = title.lowercased()
        if lowered.range(
            of: #"^\d+\s+(messaggi?\s+non\s+lett[oi]|unread\s+messages?)$"#,
            options: .regularExpression
        ) != nil {
            return domain
        }
        if normalizedLinkURL(title) == url {
            return domain
        }
        return title
    }

    private func normalizedLinkURL(_ rawURL: String?) -> String? {
        guard var url = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else { return nil }
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)}"))
        if url.lowercased().hasPrefix("www.") {
            url = "https://" + url
        }
        guard url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") else { return nil }
        return URL(string: url)?.absoluteString ?? url
    }

    private func displayDomain(for rawURL: String) -> String {
        guard let url = URL(string: rawURL),
              let host = url.host,
              !host.isEmpty else {
            return rawURL
                .replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
                .components(separatedBy: "/")
                .first ?? rawURL
        }
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }

    private func appleMapsURL(for rawURL: String, title: String?) -> String? {
        guard let url = URL(string: rawURL),
              let host = url.host?.lowercased() else { return nil }
        let normalizedHost = host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        if normalizedHost == "maps.apple.com" {
            return rawURL
        }

        let path = url.path
        let isGoogleMap = normalizedHost == "maps.google.com"
            || (normalizedHost.contains("google.") && path.contains("/maps"))
            || normalizedHost == "maps.app.goo.gl"
            || normalizedHost == "goo.gl"
        guard isGoogleMap else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let origin = queryValue(named: ["origin", "saddr"], in: queryItems)
        var destination = queryValue(named: ["destination", "daddr"], in: queryItems)
        var query = queryValue(named: ["query", "q"], in: queryItems)

        if destination == nil || query == nil {
            let pathParts = path
                .split(separator: "/")
                .map { String($0).removingPercentEncoding ?? String($0) }
                .filter { !$0.isEmpty && !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
            if let dirIndex = pathParts.firstIndex(of: "dir") {
                let routeParts = Array(pathParts.dropFirst(dirIndex + 1))
                    .filter { !$0.hasPrefix("data") && !$0.hasPrefix("am=") }
                if destination == nil {
                    destination = routeParts.dropFirst().last ?? routeParts.last
                }
            } else if let placeIndex = pathParts.firstIndex(of: "place") ?? pathParts.firstIndex(of: "search"),
                      query == nil {
                query = pathParts.dropFirst(placeIndex + 1).first
            }
        }

        if destination == nil {
            destination = query
        }
        if destination == nil,
           let title,
           !title.isEmpty,
           title.lowercased() != normalizedHost,
           normalizedLinkURL(title) == nil {
            destination = title
        }
        guard let destination, !destination.isEmpty else { return nil }

        var appleComponents = URLComponents(string: "https://maps.apple.com/")!
        var appleItems: [URLQueryItem] = []
        if let origin, !origin.isEmpty {
            appleItems.append(URLQueryItem(name: "saddr", value: origin))
        }
        appleItems.append(URLQueryItem(name: "daddr", value: destination))
        appleItems.append(URLQueryItem(name: "dirflg", value: appleDirectionFlag(from: queryValue(named: ["travelmode", "dirflg"], in: queryItems))))
        appleComponents.queryItems = appleItems
        return appleComponents.url?.absoluteString
    }

    private func queryValue(named names: [String], in items: [URLQueryItem]) -> String? {
        for name in names {
            if let value = items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func appleDirectionFlag(from travelMode: String?) -> String {
        switch travelMode?.lowercased() {
        case "walking", "w":
            return "w"
        case "transit", "r":
            return "r"
        default:
            return "d"
        }
    }

    private func stableMessageID(
        sender: String,
        chatId: String,
        text: String,
        groupSender: String?,
        mediaKind: WhatsAppIncomingMediaKind?,
        linkPreview: WhatsAppIncomingLinkPreview?,
        documentPreview: WhatsAppIncomingDocumentPreview?,
        pollOptions: [WhatsAppIncomingPollOption]
    ) -> String {
        let resolvedGroupSender = resolveGroupSender(providedGroupSender: groupSender, messageBody: text)
        let normalizedText = normalizedStableMessagePart(
            messageBodyWithoutGroupSender(text, groupSender: resolvedGroupSender)
        )
        return [
            normalizedStableMessagePart(sender),
            normalizedStableMessagePart(chatId),
            normalizedStableMessagePart(resolvedGroupSender ?? ""),
            normalizedText,
            mediaKind?.rawValue ?? "text",
            linkPreview?.url.lowercased() ?? "",
            normalizedStableMessagePart(documentPreview?.fileName ?? ""),
            pollOptions.map { normalizedStableMessagePart($0.text) }.joined(separator: "|")
        ].joined(separator: "||")
    }

    private func stableMessageKey(_ message: WhatsAppIncomingMessage, sender: String, chatId: String) -> String {
        stableMessageID(
            sender: sender,
            chatId: chatId,
            text: message.text,
            groupSender: message.groupSender,
            mediaKind: message.mediaKind,
            linkPreview: message.linkPreview,
            documentPreview: message.documentPreview,
            pollOptions: message.pollOptions
        )
    }

    private func deduplicatedIncomingMessages(
        _ messages: [WhatsAppIncomingMessage],
        sender: String,
        chatId: String
    ) -> [WhatsAppIncomingMessage] {
        var seen = Set<String>()
        return messages.filter { message in
            let key = stableMessageKey(message, sender: sender, chatId: chatId)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func normalizedStableMessagePart(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
            .replacingOccurrences(of: "\u{200D}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func messageBodyWithoutGroupSender(_ body: String, groupSender: String?) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let groupSender, !groupSender.isEmpty else { return trimmedBody }
        let prefix = "\(groupSender):"
        guard trimmedBody.hasPrefix(prefix) else { return trimmedBody }
        return trimmedBody
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedIncomingMessageBody(_ body: String) -> String {
        let cleaned = body
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "")
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
        var documentPreviewDataUrlByKey = {};

        function postPollDebug(message) {
            console.log('[Atoll] ' + message);
            try {
                window.webkit.messageHandlers.atollWA.postMessage({
                    type: 'pollDebug',
                    message: message
                });
            } catch (e) {}
        }

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

        function textWithEmoji(root) {
            if (!root) return '';
            var out = '';
            function walk(node) {
                if (!node) return;
                if (node.nodeType === Node.TEXT_NODE) {
                    out += node.nodeValue || '';
                    return;
                }
                if (node.nodeType !== Node.ELEMENT_NODE) return;
                var tag = (node.tagName || '').toLowerCase();
                if (tag === 'img') {
                    var alt = node.getAttribute('alt') || '';
                    if (alt) out += alt;
                    return;
                }
                var dataPlainText = node.getAttribute('data-plain-text') || '';
                if (dataPlainText) {
                    out += dataPlainText;
                    return;
                }
                var ariaLabel = node.getAttribute('aria-label') || '';
                var className = String(node.className || '');
                var testId = node.getAttribute('data-testid') || '';
                if (ariaLabel && /emoji|emoticon/i.test(className + ' ' + testId)) {
                    out += ariaLabel;
                    return;
                }
                node.childNodes.forEach(walk);
            }
            walk(root);
            return out.replace(/\\s+/g, ' ').trim();
        }

        function emojiAltText(root) {
            if (!root) return '';
            var pieces = [];
            root.querySelectorAll('img[alt]').forEach(function(img) {
                if (isAvatarImage(img)) return;
                var alt = img.getAttribute('alt') || '';
                if (alt && alt.length <= 12) pieces.push(alt);
            });
            root.querySelectorAll('[aria-label], [data-plain-text]').forEach(function(el) {
                var label = el.getAttribute('data-plain-text') || el.getAttribute('aria-label') || '';
                label = cleanMessageText(label);
                if (label && label.length <= 12 && !/send|invia|reply|rispondi|message|messaggio/i.test(label)) {
                    pieces.push(label);
                }
            });
            return pieces.join(' ').trim();
        }

        function extractBodyAndGroupSender(row) {
            var body = '📨 Nuovo messaggio';
            var groupSender = '';
            var isOutgoing = false;
            try {
                var secondary = row.querySelector('[data-testid="cell-frame-secondary-detail"]');
                isOutgoing = !!row.querySelector('[data-testid="last-msg-status"], [data-icon="msg-check"], [data-icon="msg-dblcheck"], [data-icon="msg-dblcheck-ack"]');
                var secondaryRichText = textWithEmoji(secondary);
                if (secondaryRichText) {
                    body = secondaryRichText;
                }

                // 1. Logica originale estremamente affidabile come fallback
                var sel = [
                    '[data-testid="last-msg-status"] ~ span span',
                    '[data-testid="cell-frame-secondary-detail"] span span',
                    'span[dir="ltr"]'
                ];
                if (!body || body === '📨 Nuovo messaggio') {
                    for (var i = 0; i < sel.length; i++) {
                        var el = row.querySelector(sel[i]);
                        var text = textWithEmoji(el);
                        if (el && text) {
                            body = text;
                            break;
                        }
                    }
                }

                // Se non trovato, proviamo il testo interno del dettaglio secondario
                if (!body || body === '📨 Nuovo messaggio') {
                    var sec = row.querySelector('[data-testid="cell-frame-secondary-detail"]');
                    var secText = textWithEmoji(sec);
                    if (sec && secText) {
                        body = secText;
                    }
                }

                if (!body || body === '📨 Nuovo messaggio') {
                    var emojiText = emojiAltText(secondary || row);
                    if (emojiText) {
                        body = emojiText;
                    }
                }

                // 2. Trova il mittente del gruppo se presente
                if (secondary) {
                    var fullText = textWithEmoji(secondary) || '';
                    var colonIdx = fullText.indexOf(': ');
                    if (colonIdx > 0 && colonIdx < 30) {
                        var possibleMember = fullText.substring(0, colonIdx).trim();
                        // Escludi orari o parole riservate
                        if (isValidGroupSenderCandidate(possibleMember)) {
                            groupSender = possibleMember;
                            if (body && body.indexOf(possibleMember + ':') === 0) {
                                body = cleanMessageText(body.slice(possibleMember.length + 1));
                            }
                        }
                    }
                    if (!groupSender) {
                        var titledParts = Array.from(secondary.querySelectorAll('span[title], [aria-label]'));
                        for (var t = 0; t < titledParts.length; t++) {
                            var candidate = cleanMessageText(
                                titledParts[t].getAttribute('title')
                                    || titledParts[t].getAttribute('aria-label')
                                    || textWithEmoji(titledParts[t])
                                    || ''
                            ).replace(/:$/, '').trim();
                            if (!isValidGroupSenderCandidate(candidate)) continue;
                            if (looksLikeDocumentFileName(candidate) || /\\b(sticker|adesivo|immagine|image|photo|foto|pagina|pagine|page|pages|kb|mb|gb|pdf|docx?|pptx?|xlsx?|file|documento)\\b/i.test(candidate)) continue;
                            if (body && comparableMessageText(candidate) === comparableMessageText(body)) continue;
                            groupSender = candidate;
                            break;
                        }
                    }
                }
            } catch (e) {
                console.log('[Atoll] Errore in extractBodyAndGroupSender: ' + e);
            }

            // Pulisci eventuali checkmark di lettura
            if (body && (body.startsWith('✓') || body.startsWith('✔'))) {
                isOutgoing = true;
                body = body.replace(/^[✓✔\\s\\u200B-\\u200D\\uFEFF]+/, '');
            }

            return { body: body || '📨 Nuovo messaggio', member: groupSender || '', isOutgoing: isOutgoing };
        }

        function cleanMessageText(value) {
            return (value || '')
                .replace(/^[✓✔\\s\\u200B-\\u200D\\uFEFF]+/, '')
                .replace(/\\s*\\b\\d{1,2}:\\d{2}\\b\\s*$/, '')
                .replace(/\\s+/g, ' ')
                .trim();
        }

        function isValidGroupSenderCandidate(value) {
            var candidate = cleanMessageText(value || '').replace(/:$/, '').trim();
            if (!candidate || candidate.length > 40) return false;
            var lower = candidate.toLowerCase();
            if (['bozza', 'draft', 'tu', 'you', 'whatsapp', 'meta ai'].indexOf(lower) >= 0) return false;
            if (lower.indexOf('http') === 0 || lower.indexOf('www.') === 0) return false;
            if (/^\\d{1,2}$/.test(candidate) || /^\\d{1,2}:\\d{2}$/.test(candidate)) return false;
            if (/^\\d+\\s+(messaggi?\\s+non\\s+lett[oi]|unread\\s+messages?)$/i.test(candidate)) return false;
            return true;
        }

        function groupSenderFromMessageNode(node, fallbackGroupSender) {
            if (!node) return fallbackGroupSender || '';

            var prePlainNodes = [];
            if (node.hasAttribute && node.hasAttribute('data-pre-plain-text')) {
                prePlainNodes.push(node);
            }
            prePlainNodes = prePlainNodes.concat(Array.from(node.querySelectorAll('[data-pre-plain-text]')));
            for (var p = 0; p < prePlainNodes.length; p++) {
                var preText = prePlainNodes[p].getAttribute('data-pre-plain-text') || '';
                var preMatch = preText.match(/\\]\\s*([^\\n]{1,80}?):\\s*$/);
                if (preMatch && isValidGroupSenderCandidate(preMatch[1])) {
                    return cleanMessageText(preMatch[1]);
                }
            }

            var authorSelectors = [
                '[data-testid="msg-author"]',
                '[data-testid="message-author"]',
                '[aria-label*="sender" i]',
                '[aria-label*="mittente" i]'
            ];
            for (var i = 0; i < authorSelectors.length; i++) {
                var author = node.querySelector(authorSelectors[i]);
                var authorText = cleanMessageText(textWithEmoji(author) || (author && author.getAttribute('aria-label')) || '');
                if (isValidGroupSenderCandidate(authorText)) return authorText.replace(/:$/, '').trim();
            }

            var labelCandidates = Array.from(node.querySelectorAll('[title], [aria-label]'));
            for (var c = 0; c < Math.min(labelCandidates.length, 24); c++) {
                var labelText = cleanMessageText(
                    labelCandidates[c].getAttribute('title')
                        || labelCandidates[c].getAttribute('aria-label')
                        || ''
                ).replace(/:$/, '').trim();
                if (!isValidGroupSenderCandidate(labelText)) continue;
                if (looksLikeDocumentFileName(labelText) || /\\b(sticker|adesivo|immagine|image|photo|foto|pagina|pagine|page|pages|kb|mb|gb|pdf|docx?|pptx?|xlsx?|file|documento|download|scarica|apri|open)\\b/i.test(labelText)) continue;
                return labelText;
            }

            var lines = fallbackGroupSender ? textLinesFromRoot(node) : [];
            if (lines.length > 1) {
                var firstLine = cleanMessageText(lines[0]).replace(/:$/, '').trim();
                if (isValidGroupSenderCandidate(firstLine) && !firstUrlFromText(firstLine) && !isPollMarkerText(firstLine)) {
                    return firstLine;
                }
            }
            return fallbackGroupSender || '';
        }

        function looksLikeEmojiLabel(value) {
            var text = cleanMessageText(value)
                .replace(/[\\u200D\\uFE0F]/g, '')
                .replace(/\\s+/g, '');
            return !!text && text.length <= 12 && !/[A-Za-z0-9]/.test(text);
        }

        function mediaKindFromRow(row) {
            var label = ((row.getAttribute('aria-label') || '') + ' ' + textWithEmoji(row)).toLowerCase();
            if (row.querySelector('[data-icon*="sticker"], [aria-label*="sticker" i], [aria-label*="adesivo" i]') || /\\b(sticker|adesivo)\\b/.test(label)) {
                return 'sticker';
            }
            if (row.querySelector('[data-icon*="image"], [data-icon*="photo"], [aria-label*="image" i], [aria-label*="photo" i], [aria-label*="immagine" i]')) {
                return 'image';
            }
            return '';
        }

        function mediaMarkerForElement(element) {
            var parts = [];
            var cursor = element;
            for (var depth = 0; depth < 5 && cursor; depth++) {
                if (cursor.getAttribute) {
                    parts.push(cursor.getAttribute('aria-label') || '');
                    parts.push(cursor.getAttribute('data-testid') || '');
                    parts.push(cursor.getAttribute('data-icon') || '');
                    parts.push(cursor.getAttribute('title') || '');
                }
                parts.push(String(cursor.className || ''));
                cursor = cursor.parentElement;
            }
            return parts.join(' ').toLowerCase();
        }

        function mediaKindFromElement(element, fallbackKind) {
            var marker = mediaMarkerForElement(element);
            if (/\\b(sticker|adesivo)\\b/.test(marker)) return 'sticker';
            if (/\\b(image|photo|picture|immagine|foto)\\b/.test(marker)) return 'image';
            return fallbackKind || '';
        }

        function isAvatarImage(img) {
            return !!(img.closest('[data-testid="avatar"]') || img.closest('[aria-label*="profile" i]'));
        }

        function isEmojiImage(img) {
            var src = img.currentSrc || img.src || '';
            var alt = img.getAttribute('alt') || '';
            var marker = String(img.className || '') + ' ' + (img.getAttribute('data-testid') || '') + ' ' + (img.getAttribute('aria-label') || '');
            if (/sticker|adesivo/i.test(marker + ' ' + alt)) return false;
            var rect = img.getBoundingClientRect();
            if (rect.width < 28 && rect.height < 28 && (src.includes('emoji') || /emoji|emoticon/i.test(marker) || (!!alt && looksLikeEmojiLabel(alt)))) {
                return true;
            }
            if ((rect.width >= 28 && rect.height >= 28) || src.startsWith('blob:') || src.startsWith('data:image')) {
                return false;
            }
            return src.includes('emoji')
                || /emoji|emoticon/i.test(marker)
                || (!!alt && looksLikeEmojiLabel(alt) && !src.startsWith('blob:') && !src.startsWith('data:image'));
        }

        function urlToDataUrl(url) {
            return new Promise(function(resolve) {
                try {
                    if (!url) {
                        resolve(null);
                        return;
                    }
                    if (url.startsWith('data:image')) {
                        resolve(url);
                        return;
                    }
                    fetch(url)
                        .then(function(response) { return response.blob(); })
                        .then(function(blob) {
                            var reader = new FileReader();
                            reader.onloadend = function() {
                                resolve(typeof reader.result === 'string' ? reader.result : null);
                            };
                            reader.onerror = function() { resolve(null); };
                            reader.readAsDataURL(blob);
                        })
                        .catch(function() { resolve(null); });
                } catch (e) {
                    resolve(null);
                }
            });
        }

        function blobToDataUrl(blob) {
            return new Promise(function(resolve) {
                try {
                    if (!blob) {
                        resolve(null);
                        return;
                    }
                    var reader = new FileReader();
                    reader.onloadend = function() {
                        resolve(typeof reader.result === 'string' ? reader.result : null);
                    };
                    reader.onerror = function() { resolve(null); };
                    reader.readAsDataURL(blob);
                } catch (e) {
                    resolve(null);
                }
            });
        }

        async function imageDataUrlFromUnknownValue(value, mimeType, maxEdge) {
            if (!value) return '';
            try {
                var dataUrl = '';
                if (typeof Blob !== 'undefined' && value instanceof Blob) {
                    dataUrl = await blobToDataUrl(value);
                } else if (value instanceof ArrayBuffer || (ArrayBuffer.isView && ArrayBuffer.isView(value))) {
                    var imageBuffer = value instanceof ArrayBuffer
                        ? value
                        : value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
                    dataUrl = 'data:' + (mimeType || 'image/png') + ';base64,' + base64FromArrayBuffer(imageBuffer);
                } else if (typeof value === 'string') {
                    var raw = value.trim();
                    if (raw.indexOf('data:image') === 0) {
                        dataUrl = raw;
                    } else if (raw.indexOf('blob:') === 0 || raw.indexOf('http://') === 0 || raw.indexOf('https://') === 0) {
                        dataUrl = await urlToDataUrl(raw);
                    } else if (/^[A-Za-z0-9+/=\\s]+$/.test(raw) && raw.length > 80) {
                        dataUrl = 'data:' + (mimeType || 'image/png') + ';base64,' + raw.replace(/\\s+/g, '');
                    }
                }
                return dataUrl ? await rasterizeImageDataUrl(dataUrl, maxEdge || 320) : '';
            } catch (e) {
                return '';
            }
        }

        async function dataUrlFromUnknownFileValue(value, mimeType) {
            if (!value) return '';
            try {
                if (typeof Blob !== 'undefined' && value instanceof Blob) {
                    return await blobToDataUrl(value) || '';
                }
                if (value instanceof ArrayBuffer || (ArrayBuffer.isView && ArrayBuffer.isView(value))) {
                    var fileBuffer = value instanceof ArrayBuffer
                        ? value
                        : value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
                    return 'data:' + (mimeType || 'application/octet-stream') + ';base64,' + base64FromArrayBuffer(fileBuffer);
                }
                if (typeof value === 'string') {
                    var raw = value.trim();
                    if (raw.indexOf('data:') === 0) return raw;
                    if (raw.indexOf('blob:') === 0 || raw.indexOf('http://') === 0 || raw.indexOf('https://') === 0) {
                        return await urlToDataUrl(raw) || '';
                    }
                    if (/^[A-Za-z0-9+/=\\s]+$/.test(raw) && raw.length > 120) {
                        return 'data:' + (mimeType || 'application/octet-stream') + ';base64,' + raw.replace(/\\s+/g, '');
                    }
                }
            } catch (e) {}
            return '';
        }

        async function storeImageFallbackDataUrl(msg, maxEdge) {
            if (!msg) return '';
            var mimeType = msg.mimetype || (msg.type === 'sticker' ? 'image/webp' : 'image/png');
            var mediaData = msg.mediaData || {};
            var candidates = [
                msg.jpegThumbnail,
                msg.thumbnail,
                msg.thumbnailUrl,
                msg.previewImage,
                msg.body && msg.type === 'sticker' ? msg.body : null,
                mediaData.jpegThumbnail,
                mediaData.thumbnail,
                mediaData.thumbnailUrl,
                mediaData.preview,
                mediaData.previewImage,
                mediaData.mediaBlob,
                mediaData._mediaBlob,
                mediaData.blob,
                mediaData.file,
                msg.stickerData && msg.stickerData.url,
                msg.stickerData && msg.stickerData.thumbnail,
                msg.stickerData && msg.stickerData.mediaBlob
            ];
            for (var i = 0; i < candidates.length; i++) {
                var dataUrl = await imageDataUrlFromUnknownValue(candidates[i], mimeType, maxEdge || 320);
                if (dataUrl) return dataUrl;
            }
            return '';
        }

        function imageElementToDataUrl(img) {
            return new Promise(function(resolve) {
                try {
                    var src = img.currentSrc || img.src || '';
                    if (src.startsWith('data:image')) {
                        rasterizeImageDataUrl(src, 320).then(resolve);
                        return;
                    }
                    if (src.startsWith('blob:')) {
                        urlToDataUrl(src).then(function(dataUrl) {
                            if (dataUrl) {
                                rasterizeImageDataUrl(dataUrl, 320).then(resolve);
                            } else {
                                resolve(null);
                            }
                        });
                        return;
                    }
                    var finish = function() {
                        try {
                            var width = img.naturalWidth || img.width || 96;
                            var height = img.naturalHeight || img.height || 96;
                            if (width < 12 || height < 12) {
                                resolve(null);
                                return;
                            }
                            var maxEdge = 320;
                            var scale = Math.min(1, maxEdge / Math.max(width, height));
                            var canvas = document.createElement('canvas');
                            canvas.width = Math.max(1, Math.round(width * scale));
                            canvas.height = Math.max(1, Math.round(height * scale));
                            var ctx = canvas.getContext('2d');
                            ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                            resolve(canvas.toDataURL('image/png'));
                        } catch (e) {
                            urlToDataUrl(src).then(function(dataUrl) {
                                if (dataUrl) {
                                    rasterizeImageDataUrl(dataUrl, 320).then(resolve);
                                } else {
                                    resolve(null);
                                }
                            });
                        }
                    };
                    if (img.complete) {
                        finish();
                    } else {
                        img.addEventListener('load', finish, { once: true });
                        img.addEventListener('error', function() { resolve(null); }, { once: true });
                        setTimeout(function() { resolve(null); }, 900);
                    }
                } catch (e) {
                    resolve(null);
                }
            });
        }

        async function backgroundImageToDataUrl(element) {
            try {
                var style = window.getComputedStyle(element);
                var background = style.backgroundImage || '';
                var match = background.match(/url\\(["']?([^"')]+)["']?\\)/);
                if (!match || !match[1]) return null;
                var dataUrl = await urlToDataUrl(match[1]);
                return dataUrl ? await rasterizeImageDataUrl(dataUrl, 320) : null;
            } catch (e) {
                return null;
            }
        }

        async function videoElementToDataUrl(video) {
            try {
                var poster = video.getAttribute('poster') || video.poster || '';
                if (poster) {
                    var posterDataUrl = await urlToDataUrl(poster);
                    if (posterDataUrl) return await rasterizeImageDataUrl(posterDataUrl, 320);
                }
                var width = video.videoWidth || video.clientWidth || 96;
                var height = video.videoHeight || video.clientHeight || 96;
                if (width < 12 || height < 12) return '';
                var scale = Math.min(1, 320 / Math.max(width, height));
                var canvas = document.createElement('canvas');
                canvas.width = Math.max(1, Math.round(width * scale));
                canvas.height = Math.max(1, Math.round(height * scale));
                var ctx = canvas.getContext('2d');
                ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                return canvas.toDataURL('image/png');
            } catch (e) {
                return '';
            }
        }

        async function extractMedia(row) {
            var kind = mediaKindFromRow(row);
            var imgs = Array.from(row.querySelectorAll('img')).filter(function(img) {
                if (isAvatarImage(img) || isEmojiImage(img)) return false;
                var rect = img.getBoundingClientRect();
                return rect.width >= 12 && rect.height >= 12;
            }).sort(function(a, b) {
                var ar = a.getBoundingClientRect();
                var br = b.getBoundingClientRect();
                var aKind = mediaKindFromElement(a, kind);
                var bKind = mediaKindFromElement(b, kind);
                var aScore = ar.width * ar.height + (aKind === 'sticker' ? 100000 : 0);
                var bScore = br.width * br.height + (bKind === 'sticker' ? 100000 : 0);
                return bScore - aScore;
            });
            for (var i = 0; i < imgs.length; i++) {
                var img = imgs[i];
                var imageKind = mediaKindFromElement(img, kind);
                var dataUrl = await imageElementToDataUrl(img);
                if (dataUrl) {
                    return { kind: imageKind || kind || 'image', dataUrl: dataUrl };
                }
            }

            var videos = Array.from(row.querySelectorAll('video')).filter(function(video) {
                var rect = video.getBoundingClientRect();
                return rect.width >= 12 && rect.height >= 12;
            });
            for (var v = 0; v < videos.length; v++) {
                var videoDataUrl = await videoElementToDataUrl(videos[v]);
                if (videoDataUrl) {
                    return { kind: mediaKindFromElement(videos[v], kind) || kind || 'sticker', dataUrl: videoDataUrl };
                }
            }

            var backgroundNodes = row.querySelectorAll('[style*="background-image"]');
            for (var b = 0; b < backgroundNodes.length; b++) {
                var bgDataUrl = await backgroundImageToDataUrl(backgroundNodes[b]);
                if (bgDataUrl) {
                    return { kind: mediaKindFromElement(backgroundNodes[b], kind) || kind || 'image', dataUrl: bgDataUrl };
                }
            }

            if (kind === 'sticker') {
                var visualNodes = Array.from(row.querySelectorAll('div, span')).filter(function(el) {
                    var rect = el.getBoundingClientRect();
                    return rect.width >= 24 && rect.height >= 24 && rect.width <= 260 && rect.height <= 260;
                }).sort(function(a, b) {
                    var ar = a.getBoundingClientRect();
                    var br = b.getBoundingClientRect();
                    return (br.width * br.height) - (ar.width * ar.height);
                });
                for (var c = 0; c < Math.min(visualNodes.length, 24); c++) {
                    var computedDataUrl = await backgroundImageToDataUrl(visualNodes[c]);
                    if (computedDataUrl) {
                        return { kind: 'sticker', dataUrl: computedDataUrl };
                    }
                }
            }

            var canvas = row.querySelector('canvas');
            if (canvas) {
                try {
                    return { kind: mediaKindFromElement(canvas, kind) || kind || 'image', dataUrl: canvas.toDataURL('image/png') };
                } catch (e) {}
            }

            return { kind: kind, dataUrl: '' };
        }

        function firstUrlFromText(value) {
            var tokens = String(value || '').split(/\\s+/);
            for (var i = 0; i < tokens.length; i++) {
                var token = trimPreviewToken(tokens[i]);
                var lower = token.toLowerCase();
                if (lower.indexOf('http://') === 0 || lower.indexOf('https://') === 0 || lower.indexOf('www.') === 0) {
                    var url = normalizePreviewUrl(token);
                    if (url) return url;
                }
            }
            return '';
        }

        function isPreviewLeadingCode(code) {
            return code === 60 || code === 40 || code === 34 || code === 39 || code === 91 || code === 123;
        }

        function isPreviewTrailingCode(code) {
            return code === 62 || code === 41 || code === 34 || code === 39 || code === 93 || code === 125 || code === 46 || code === 44 || code === 59 || code === 58 || code === 33 || code === 63;
        }

        function trimPreviewToken(value) {
            var token = cleanMessageText(value || '');
            while (token.length && isPreviewLeadingCode(token.charCodeAt(0))) {
                token = token.slice(1);
            }
            while (token.length && isPreviewTrailingCode(token.charCodeAt(token.length - 1))) {
                token = token.slice(0, -1);
            }
            return token;
        }

        function normalizePreviewUrl(value) {
            var url = trimPreviewToken(value || '');
            if (!url) return '';
            var lower = url.toLowerCase();
            if (lower.indexOf('www.') === 0) url = 'https://' + url;
            lower = url.toLowerCase();
            if (lower.indexOf('http://') !== 0 && lower.indexOf('https://') !== 0) return '';
            try {
                return new URL(url).href;
            } catch (e) {
                return url;
            }
        }

        function previewDomain(url) {
            try {
                return new URL(url).hostname.replace(/^www\\./i, '');
            } catch (e) {
                var cleaned = cleanMessageText(url);
                var lower = cleaned.toLowerCase();
                if (lower.indexOf('https://') === 0) cleaned = cleaned.slice(8);
                if (lower.indexOf('http://') === 0) cleaned = cleaned.slice(7);
                if (cleaned.toLowerCase().indexOf('www.') === 0) cleaned = cleaned.slice(4);
                return cleaned.split('/')[0] || url;
            }
        }

        function isUnreadCountText(value) {
            return /^\\d+\\s+(messaggi?\\s+non\\s+lett[oi]|unread\\s+messages?)$/i.test(cleanMessageText(value || ''));
        }

        function isBadPreviewTitle(value, url, domain) {
            var title = cleanMessageText(value || '');
            if (!title || isUnreadCountText(title)) return true;
            var titleUrl = firstUrlFromText(title);
            if (titleUrl && titleUrl === url) return true;
            var lower = title.toLowerCase();
            var lowerDomain = (domain || '').toLowerCase();
            if (lower === lowerDomain || lower === ('www.' + lowerDomain)) return true;
            return /^(open link|apri link|link)$/i.test(title);
        }

        function queryParam(searchParams, names) {
            for (var i = 0; i < names.length; i++) {
                var value = searchParams.get(names[i]);
                if (value) return value;
            }
            return '';
        }

        function appleDirectionFlag(mode) {
            mode = String(mode || '').toLowerCase();
            if (mode === 'walking' || mode === 'w') return 'w';
            if (mode === 'transit' || mode === 'r') return 'r';
            return 'd';
        }

        function appleMapsUrlFromPreview(url, title) {
            try {
                var parsed = new URL(url);
                var host = parsed.hostname.toLowerCase().replace(/^www\\./, '');
                if (host === 'maps.apple.com') return url;
                var isGoogleMap = host === 'maps.google.com'
                    || (host.indexOf('google.') >= 0 && parsed.pathname.indexOf('/maps') >= 0)
                    || host === 'maps.app.goo.gl'
                    || host === 'goo.gl';
                if (!isGoogleMap) return '';

                var params = parsed.searchParams;
                var origin = queryParam(params, ['origin', 'saddr']);
                var destination = queryParam(params, ['destination', 'daddr']);
                var query = queryParam(params, ['query', 'q']);
                var domain = previewDomain(url);
                var parts = parsed.pathname.split('/').map(function(part) {
                    try { return decodeURIComponent(part); } catch (e) { return part; }
                }).filter(function(part) {
                    return !!part && part.charAt(0) !== '@' && part.indexOf('data=') !== 0;
                });

                if (!destination) {
                    var dirIndex = parts.indexOf('dir');
                    if (dirIndex >= 0) {
                        var routeParts = parts.slice(dirIndex + 1).filter(function(part) {
                            return part.indexOf('data') !== 0 && part.indexOf('am=') !== 0;
                        });
                        destination = routeParts.length > 1 ? routeParts[routeParts.length - 1] : (routeParts[0] || '');
                    }
                }
                if (!destination && !query) {
                    var placeIndex = parts.indexOf('place');
                    if (placeIndex < 0) placeIndex = parts.indexOf('search');
                    if (placeIndex >= 0) query = parts[placeIndex + 1] || '';
                }
                if (!destination) destination = query;
                if (!destination && title && !isBadPreviewTitle(title, url, domain)) {
                    destination = title;
                }
                if (!destination) return '';

                var appleParams = new URLSearchParams();
                if (origin) appleParams.set('saddr', origin);
                appleParams.set('daddr', destination);
                appleParams.set('dirflg', appleDirectionFlag(queryParam(params, ['travelmode', 'dirflg'])));
                return 'https://maps.apple.com/?' + appleParams.toString();
            } catch (e) {
                return '';
            }
        }

        function storeThumbnailDataUrl(msg) {
            var mediaData = (msg && msg.mediaData) || {};
            var thumb = msg && (
                msg.jpegThumbnail
                    || msg.thumbnail
                    || msg.thumbnailUrl
                    || msg.previewImage
                    || mediaData.jpegThumbnail
                    || mediaData.thumbnail
                    || mediaData.thumbnailUrl
                    || mediaData.preview
                    || mediaData.previewImage
            );
            if (!thumb || typeof thumb !== 'string') return '';
            if (thumb.indexOf('data:image') === 0) return thumb;
            if (/^[A-Za-z0-9+/=\\s]+$/.test(thumb) && thumb.length > 80) {
                return 'data:image/jpeg;base64,' + thumb.replace(/\\s+/g, '');
            }
            return '';
        }

        function documentFileSizeFromStoreMessage(msg) {
            var mediaData = (msg && msg.mediaData) || {};
            return Number(
                (msg && (msg.size || msg.fileSize || msg.mediaSize || msg.fileLength))
                    || mediaData.size
                    || mediaData.fileSize
                    || mediaData.mediaSize
                    || mediaData.fileLength
                    || 0
            ) || 0;
        }

        function shouldUsePdfDataAsThumbnail(msg, fileName, mimeType) {
            var isPdf = /pdf/i.test(mimeType || '') || /\\.pdf$/i.test(fileName || '');
            if (!isPdf) return false;
            var size = documentFileSizeFromStoreMessage(msg);
            return !size || size <= 8 * 1024 * 1024;
        }

        function linkPreviewFromStoreMessage(msg) {
            if (!msg) return null;
            var url = normalizePreviewUrl(
                msg.canonicalUrl || msg.matchedText || msg.url || msg.link || firstUrlFromText(msg.body || msg.caption || '')
            );
            if (!url) return null;
            var domain = previewDomain(url);
            var title = cleanMessageText(msg.title || msg.description || msg.body || domain);
            if (isBadPreviewTitle(title, url, domain)) title = domain;
            return {
                url: url,
                title: title,
                domain: domain,
                imageDataUrl: storeThumbnailDataUrl(msg),
                appleMapsUrl: appleMapsUrlFromPreview(url, title)
            };
        }

        function looksLikePreviewIconElement(element) {
            if (!element) return false;
            var marker = '';
            try {
                marker = [
                    element.getAttribute('data-icon') || '',
                    element.getAttribute('data-testid') || '',
                    element.getAttribute('aria-label') || '',
                    element.getAttribute('title') || '',
                    String(element.className || '')
                ].join(' ').toLowerCase();
            } catch (e) {}
            return /\\b(document|file|pdf|download|scarica|icon)\\b/.test(marker);
        }

        async function previewImageDataUrlFromRoot(root) {
            var allImgs = Array.from(root.querySelectorAll('img')).filter(function(img) {
                if (isAvatarImage(img) || isEmojiImage(img)) return false;
                var rect = img.getBoundingClientRect();
                if (rect.width < 24 || rect.height < 24) return false;
                return true;
            }).sort(function(a, b) {
                var ar = a.getBoundingClientRect();
                var br = b.getBoundingClientRect();
                return (br.width * br.height) - (ar.width * ar.height);
            });
            var imgs = allImgs.filter(function(img) {
                var rect = img.getBoundingClientRect();
                if (looksLikePreviewIconElement(img) && rect.width < 72 && rect.height < 72) return false;
                return true;
            });
            for (var i = 0; i < imgs.length; i++) {
                var imageDataUrl = await imageElementToDataUrl(imgs[i]);
                if (imageDataUrl) return imageDataUrl;
            }
            for (var smallImageIndex = 0; smallImageIndex < allImgs.length; smallImageIndex++) {
                if (imgs.indexOf(allImgs[smallImageIndex]) >= 0) continue;
                var fallbackImageDataUrl = await imageElementToDataUrl(allImgs[smallImageIndex]);
                if (fallbackImageDataUrl) return fallbackImageDataUrl;
            }

            var allBackgroundNodes = Array.from(root.querySelectorAll('[style*="background-image"]')).filter(function(el) {
                var rect = el.getBoundingClientRect();
                if (rect.width < 32 || rect.height < 32) return false;
                return true;
            }).sort(function(a, b) {
                var ar = a.getBoundingClientRect();
                var br = b.getBoundingClientRect();
                return (br.width * br.height) - (ar.width * ar.height);
            });
            var backgroundNodes = allBackgroundNodes.filter(function(el) {
                var rect = el.getBoundingClientRect();
                if (looksLikePreviewIconElement(el) && rect.width < 72 && rect.height < 72) return false;
                return true;
            });
            for (var b = 0; b < backgroundNodes.length; b++) {
                var backgroundDataUrl = await backgroundImageToDataUrl(backgroundNodes[b]);
                if (backgroundDataUrl) return backgroundDataUrl;
            }
            for (var smallBackgroundIndex = 0; smallBackgroundIndex < allBackgroundNodes.length; smallBackgroundIndex++) {
                if (backgroundNodes.indexOf(allBackgroundNodes[smallBackgroundIndex]) >= 0) continue;
                var fallbackBackgroundDataUrl = await backgroundImageToDataUrl(allBackgroundNodes[smallBackgroundIndex]);
                if (fallbackBackgroundDataUrl) return fallbackBackgroundDataUrl;
            }

            var canvases = Array.from(root.querySelectorAll('canvas')).filter(function(canvas) {
                var rect = canvas.getBoundingClientRect();
                return rect.width >= 24 && rect.height >= 24;
            }).sort(function(a, b) {
                var ar = a.getBoundingClientRect();
                var br = b.getBoundingClientRect();
                return (br.width * br.height) - (ar.width * ar.height);
            });
            for (var canvasIndex = 0; canvasIndex < canvases.length; canvasIndex++) {
                try {
                    var canvasDataUrl = canvases[canvasIndex].toDataURL('image/png');
                    if (canvasDataUrl) return canvasDataUrl;
                } catch (e) {}
            }
            return '';
        }

        async function extractLinkPreview(root, messageText) {
            if (!root) return null;
            var anchors = Array.from(root.querySelectorAll('a[href]')).filter(function(anchor) {
                var href = normalizePreviewUrl(anchor.getAttribute('href') || anchor.href || '');
                return !!href;
            });
            var anchor = anchors[0] || null;
            var url = normalizePreviewUrl(anchor ? (anchor.getAttribute('href') || anchor.href || '') : '')
                || firstUrlFromText(textWithEmoji(root) || root.innerText || root.textContent || '')
                || firstUrlFromText(messageText || '');
            if (!url) return null;

            var domain = previewDomain(url);
            var title = cleanMessageText(
                (anchor && (anchor.getAttribute('title') || anchor.getAttribute('aria-label') || textWithEmoji(anchor))) || ''
            );
            if (isBadPreviewTitle(title, url, domain)) {
                var message = cleanMessageText(messageText || '');
                var lines = textLinesFromRoot(root).filter(function(line) {
                    if (!line || pollLineIsTime(line) || isPollMarkerText(line)) return false;
                    if (isBadPreviewTitle(line, url, domain)) return false;
                    if (firstUrlFromText(line)) return false;
                    if (line === domain || normalizePreviewUrl(line) === url) return false;
                    if (message && line === message && !firstUrlFromText(message)) return false;
                    return !/^(open link|apri link|link)$/i.test(line);
                });
                title = lines[0] || domain;
            }

            var imageDataUrl = await previewImageDataUrlFromRoot(root);

            return {
                url: url,
                title: title,
                domain: domain,
                imageDataUrl: imageDataUrl || '',
                appleMapsUrl: appleMapsUrlFromPreview(url, title)
            };
        }

        function linkPreviewFromTextOnly(messageText) {
            var url = firstUrlFromText(messageText || '');
            if (!url) return null;
            var domain = previewDomain(url);
            return {
                url: url,
                title: domain,
                domain: domain,
                imageDataUrl: '',
                appleMapsUrl: appleMapsUrlFromPreview(url, domain)
            };
        }

        function mergeLinkPreviews(basePreview, candidatePreview) {
            if (!basePreview) return candidatePreview || null;
            if (!candidatePreview) return basePreview;
            if (basePreview.url && candidatePreview.url && basePreview.url !== candidatePreview.url) return basePreview;
            var url = candidatePreview.url || basePreview.url;
            var domain = candidatePreview.domain || basePreview.domain || previewDomain(url);
            var candidateTitle = cleanMessageText(candidatePreview.title || '');
            var baseTitle = cleanMessageText(basePreview.title || '');
            var title = !isBadPreviewTitle(candidateTitle, url, domain) ? candidateTitle : baseTitle;
            if (isBadPreviewTitle(title, url, domain)) title = domain;
            return {
                url: url,
                title: title,
                domain: domain,
                imageDataUrl: candidatePreview.imageDataUrl || basePreview.imageDataUrl || '',
                appleMapsUrl: candidatePreview.appleMapsUrl || basePreview.appleMapsUrl || appleMapsUrlFromPreview(url, title)
            };
        }

        function documentFileNameFromStoreMessage(msg) {
            if (!msg) return '';
            var mediaData = msg.mediaData || {};
            return cleanMessageText(
                msg.filename
                    || msg.fileName
                    || msg.mediaName
                    || mediaData.filename
                    || mediaData.fileName
                    || mediaData.name
                    || ''
            );
        }

        function documentExtensionFromFileName(fileName) {
            var match = cleanMessageText(fileName || '').match(/\\.([A-Za-z0-9]{1,8})(?:\\s|$)/);
            return match && match[1] ? match[1].toLowerCase() : '';
        }

        function documentNameRegex() {
            return /([^\\n•]+?\\.(pdf|doc|docx|ppt|pptx|xls|xlsx|csv|txt|rtf|zip|rar|7z|pages|numbers|key|odt|ods|odp|json|xml|html|htm|ics|vcf|md|yaml|yml|log|sql|db|sqlite|dmg|pkg|apk|ipa|exe|msi|deb|iso|epub|mobi|azw3|sketch|fig|psd|ai|eps|svg|png|jpg|jpeg|heic|webp|gif|mp4|mov|avi|mkv|mp3|wav|m4a|aac))\\b/i;
        }

        function documentTypeLabel(fileName, mimeType) {
            var extension = documentExtensionFromFileName(fileName).toUpperCase();
            var mime = String(mimeType || '').toLowerCase();
            if (mime.indexOf('pdf') >= 0 || extension === 'PDF') return 'PDF';
            if (mime.indexOf('presentation') >= 0 && !extension) return 'PPTX';
            if (mime.indexOf('word') >= 0 && !extension) return 'DOCX';
            if (mime.indexOf('spreadsheet') >= 0 && !extension) return 'XLSX';
            if (mime.indexOf('text/') === 0 && !extension) return 'TXT';
            return extension || 'FILE';
        }

        function mimeTypeForDocumentFileName(fileName) {
            switch (documentExtensionFromFileName(fileName)) {
            case 'pdf': return 'application/pdf';
            case 'doc': return 'application/msword';
            case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
            case 'ppt': return 'application/vnd.ms-powerpoint';
            case 'pptx': return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
            case 'xls': return 'application/vnd.ms-excel';
            case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
            case 'csv': return 'text/csv';
            case 'txt': return 'text/plain';
            case 'rtf': return 'application/rtf';
            case 'zip': return 'application/zip';
            case 'rar': return 'application/vnd.rar';
            case '7z': return 'application/x-7z-compressed';
            case 'json': return 'application/json';
            case 'xml': return 'application/xml';
            case 'html':
            case 'htm': return 'text/html';
            case 'ics': return 'text/calendar';
            case 'vcf': return 'text/vcard';
            case 'md': return 'text/markdown';
            case 'yaml':
            case 'yml': return 'application/yaml';
            case 'png': return 'image/png';
            case 'jpg':
            case 'jpeg': return 'image/jpeg';
            case 'heic': return 'image/heic';
            case 'webp': return 'image/webp';
            case 'gif': return 'image/gif';
            case 'mp4': return 'video/mp4';
            case 'mov': return 'video/quicktime';
            case 'mp3': return 'audio/mpeg';
            case 'wav': return 'audio/wav';
            case 'm4a': return 'audio/mp4';
            default: return 'application/octet-stream';
            }
        }

        function looksLikeDocumentFileName(value) {
            return documentNameRegex().test(cleanMessageText(value || ''));
        }

        function storeMessageLooksLikeDocument(msg, fileName, mimeType) {
            var mime = String(mimeType || (msg && msg.mimetype) || '').toLowerCase();
            var type = String((msg && msg.type) || '').toLowerCase();
            return type === 'document'
                || looksLikeDocumentFileName(fileName)
                || (mime && mime.indexOf('image/') !== 0 && mime.indexOf('video/') !== 0 && mime.indexOf('audio/') !== 0 && mime !== 'image/webp');
        }

        function formatBytes(bytes) {
            var size = Number(bytes || 0);
            if (!size || !isFinite(size)) return '';
            if (size < 1024 * 1024) return Math.max(1, Math.round(size / 1024)) + ' KB';
            return (size / (1024 * 1024)).toFixed(size < 10 * 1024 * 1024 ? 1 : 0).replace(/\\.0$/, '') + ' MB';
        }

        function documentDetailFromStoreMessage(msg) {
            if (!msg) return 'FILE';
            var mimeType = msg.mimetype || '';
            var fileName = documentFileNameFromStoreMessage(msg);
            var typeLabel = documentTypeLabel(fileName, mimeType);
            var pages = Number(msg.pageCount || (msg.mediaData && msg.mediaData.pageCount) || 0);
            var pieces = [typeLabel];
            if (pages > 0) pieces.push(pages + (pages === 1 ? ' pagina' : ' pagine'));
            var size = formatBytes(msg.size || msg.fileSize || (msg.mediaData && msg.mediaData.size));
            if (size) pieces.push(size);
            return pieces.join(' • ');
        }

        function documentPreviewFromText(value) {
            var fullText = cleanMessageText(value || '');
            if (!fullText) return null;
            var colonIdx = fullText.indexOf(': ');
            if (colonIdx > 0 && colonIdx < 40 && isValidGroupSenderCandidate(fullText.substring(0, colonIdx))) {
                fullText = cleanMessageText(fullText.slice(colonIdx + 1));
            }
            var match = fullText.match(documentNameRegex());
            if (!match || !match[1]) return null;
            var fileName = cleanMessageText(match[1]);
            if (!fileName) return null;
            var detail = cleanMessageText(
                fullText
                    .replace(match[1], '')
                    .replace(/^[\\s•\\-–—]+/, '')
                    .replace(/[\\s•\\-–—]+$/, '')
            );
            return {
                fileName: fileName,
                detail: detail || documentTypeLabel(fileName, ''),
                mimeType: mimeTypeForDocumentFileName(fileName),
                thumbnailDataUrl: ''
            };
        }

        async function documentPreviewFromStoreMessage(msg) {
            if (!msg) return null;
            var fileName = documentFileNameFromStoreMessage(msg);
            var mimeType = msg.mimetype || '';
            var isDocument = storeMessageLooksLikeDocument(msg, fileName, mimeType);
            if (!isDocument || !fileName) return null;
            var cacheKey = serializedId(msg.id) || fileName;
            var thumbnailDataUrl = documentPreviewDataUrlByKey[cacheKey] || storeThumbnailDataUrl(msg) || await storeImageFallbackDataUrl(msg, 180);
            if (!thumbnailDataUrl && shouldUsePdfDataAsThumbnail(msg, fileName, mimeType)) {
                thumbnailDataUrl = await fileDataUrlFromStoreMessage(msg);
            }
            if (thumbnailDataUrl && cacheKey) {
                documentPreviewDataUrlByKey[cacheKey] = thumbnailDataUrl;
            }
            return {
                fileName: fileName,
                detail: documentDetailFromStoreMessage(msg),
                mimeType: mimeType || mimeTypeForDocumentFileName(fileName),
                thumbnailDataUrl: thumbnailDataUrl || ''
            };
        }

        function contactNameFromRecord(contact) {
            if (!contact) return '';
            var contactId = serializedId(contact.id || contact);
            if (/@g\\.us$/i.test(contactId)) return '';
            var fields = [
                contact.formattedName,
                contact.displayName,
                contact.name,
                contact.pushname,
                contact.shortName,
                contact.verifiedName,
                contact.notifyName,
                contact.phoneUser
            ];
            for (var i = 0; i < fields.length; i++) {
                var name = cleanMessageText(fields[i] || '').replace(/:$/, '').trim();
                if (isValidGroupSenderCandidate(name)) return name;
            }
            return '';
        }

        function storeContactById(id) {
            if (!id || /@g\\.us$/i.test(id)) return null;
            try {
                var collections = waRequire('WAWebCollections');
                var contactStore = collections && (collections.Contact || collections.Contacts);
                if (!contactStore) return null;
                if (typeof contactStore.get === 'function') {
                    return contactStore.get(id)
                        || contactStore.get(id.replace(/@lid$/i, '@c.us'))
                        || contactStore.get(id.replace(/@c\\.us$/i, '@lid'))
                        || null;
                }
                if (Array.isArray(contactStore.models)) {
                    return contactStore.models.find(function(contact) {
                        return serializedId(contact && contact.id) === id;
                    }) || null;
                }
            } catch (e) {}
            return null;
        }

        function displayNameFromWid(value) {
            var id = serializedId(value);
            if (!id || /@g\\.us$/i.test(id)) return '';
            var directName = contactNameFromRecord(value);
            if (directName) return directName;
            var contact = storeContactById(id);
            return contactNameFromRecord(contact);
        }

        function groupSenderFromStoreMessage(msg, fallbackGroupSender) {
            if (!msg) return fallbackGroupSender || '';
            function modelValue(key) {
                try {
                    if (typeof msg.get === 'function') return msg.get(key);
                } catch (e) {}
                try {
                    var internalKey = '__x_' + key;
                    if (Object.prototype.hasOwnProperty.call(msg, internalKey)) return msg[internalKey];
                } catch (e) {}
                try {
                    if (msg.attributes && Object.prototype.hasOwnProperty.call(msg.attributes, key)) return msg.attributes[key];
                } catch (e) {}
                try {
                    if (msg._data && Object.prototype.hasOwnProperty.call(msg._data, key)) return msg._data[key];
                } catch (e) {}
                return msg[key];
            }
            var widCandidates = [
                modelValue('author'),
                modelValue('participant'),
                modelValue('sender'),
                modelValue('from'),
                modelValue('authorObj'),
                modelValue('senderObj'),
                modelValue('participantObj'),
                msg.id && msg.id.participant,
                msg.id && msg.id.author
            ];
            for (var w = 0; w < widCandidates.length; w++) {
                var widName = displayNameFromWid(widCandidates[w]);
                if (isValidGroupSenderCandidate(widName)) return widName;
            }
            var candidates = [
                modelValue('senderName'),
                modelValue('senderPushName'),
                modelValue('notifyName'),
                modelValue('pushname'),
                modelValue('authorName'),
                modelValue('participantName'),
                modelValue('senderObj') && (modelValue('senderObj').formattedName || modelValue('senderObj').name || modelValue('senderObj').pushname || modelValue('senderObj').shortName),
                modelValue('authorObj') && (modelValue('authorObj').formattedName || modelValue('authorObj').name || modelValue('authorObj').pushname || modelValue('authorObj').shortName)
            ];
            for (var i = 0; i < candidates.length; i++) {
                var candidate = cleanMessageText(candidates[i] || '').replace(/:$/, '').trim();
                if (isValidGroupSenderCandidate(candidate)) return candidate;
            }
            return fallbackGroupSender || '';
        }

        async function documentPreviewFromNode(node) {
            if (!node) return null;
            var lines = textLinesFromRoot(node);
            var fullText = cleanMessageText((node.innerText || node.textContent || textWithEmoji(node) || ''));
            var fileName = '';
            var detail = '';
            var textPreview = documentPreviewFromText(fullText);

            for (var i = 0; i < lines.length; i++) {
                var line = lines[i];
                var documentMatch = line.match(documentNameRegex());
                if (documentMatch) {
                    fileName = cleanMessageText(documentMatch[1]);
                    var rest = cleanMessageText(line.replace(documentMatch[1], '').replace(/^\\s*[•-]\\s*/, ''));
                    if (rest) detail = rest;
                    break;
                }
            }

            if (!fileName && textPreview) {
                fileName = textPreview.fileName;
                detail = textPreview.detail;
            }
            if (!fileName) {
                var textMatch = fullText.match(documentNameRegex());
                if (textMatch) fileName = cleanMessageText(textMatch[1]);
            }
            if (!fileName) return null;
            var typeLabel = documentTypeLabel(fileName, '');

            if (!detail) {
                for (var d = 0; d < lines.length; d++) {
                    if (lines[d] === fileName) continue;
                    if (/pagina|pagine|page|pages|kb|mb|gb|documento|file|download|scarica|pdf|docx?|pptx?|xlsx?/i.test(lines[d]) && !looksLikeDocumentFileName(lines[d])) {
                        detail = lines[d];
                        break;
                    }
                }
            }
            if (!detail) detail = typeLabel;

            var thumbnailDataUrl = await previewImageDataUrlFromRoot(node);
            return {
                fileName: fileName,
                detail: detail,
                mimeType: mimeTypeForDocumentFileName(fileName),
                thumbnailDataUrl: thumbnailDataUrl || ''
            };
        }

        function nodeLikelyHasDocument(node) {
            if (!node) return false;
            var text = cleanMessageText(node.innerText || node.textContent || textWithEmoji(node) || '');
            if (documentPreviewFromText(text)) return true;
            var markers = Array.from(node.querySelectorAll('[data-icon], [data-testid], [aria-label], [title]')).slice(0, 80).map(function(el) {
                return [
                    el.getAttribute('data-icon') || '',
                    el.getAttribute('data-testid') || '',
                    el.getAttribute('aria-label') || '',
                    el.getAttribute('title') || ''
                ].join(' ');
            }).join(' ').toLowerCase();
            return /\\b(document|file|pdf|doc|docx|ppt|pptx|xls|xlsx|download|scarica)\\b/.test(markers);
        }

        function rowLikelyHasDocument(row) {
            if (!row) return false;
            var text = cleanMessageText(textWithEmoji(row) || row.innerText || row.textContent || '');
            if (documentPreviewFromText(text)) return true;
            if (row.querySelector('[data-icon*="document"], [data-icon*="file"], [data-icon*="pdf"], [data-testid*="document"], [data-testid*="pdf"], [data-testid*="attachment"]')) {
                return true;
            }
            var markers = Array.from(row.querySelectorAll('[data-icon], [data-testid], [aria-label], [title]')).slice(0, 80).map(function(el) {
                return [
                    el.getAttribute('data-icon') || '',
                    el.getAttribute('data-testid') || '',
                    el.getAttribute('aria-label') || '',
                    el.getAttribute('title') || ''
                ].join(' ');
            }).join(' ').toLowerCase();
            return /\\b(document|documento|pdf|doc|docx|ppt|pptx|xls|xlsx|file|attachment|allegato)\\b/.test(markers);
        }

        function isGroupSenderLine(line, groupSender) {
            var text = comparableMessageText(cleanMessageText(line || '').replace(/:$/, ''));
            var sender = comparableMessageText(cleanMessageText(groupSender || '').replace(/:$/, ''));
            return !!text && !!sender && text === sender;
        }

        function isDocumentMetaLine(line, documentPreview, groupSender) {
            var text = cleanMessageText(line || '');
            if (!text) return true;
            if (isGroupSenderLine(text, groupSender)) return true;
            if (pollLineIsTime(text)) return true;
            var normalized = comparableMessageText(text);
            var fileName = comparableMessageText((documentPreview && documentPreview.fileName) || '');
            var typeLabel = comparableMessageText(documentTypeLabel((documentPreview && documentPreview.fileName) || '', (documentPreview && documentPreview.mimeType) || ''));
            if (fileName && (normalized === fileName || normalized.indexOf(fileName) >= 0 || fileName.indexOf(normalized) >= 0)) return true;
            if (typeLabel && normalized === typeLabel) return true;
            if (/^(pdf|doc|docx|ppt|pptx|xls|xlsx|csv|txt|rtf|zip|rar|7z|documento|file|download|scarica|apri|open)$/i.test(text)) return true;
            if (/^(pdf|doc|docx|ppt|pptx|xls|xlsx|documento|file)?\\s*[•\\-–—]?\\s*\\d+\\s*(pagina|pagine|page|pages)\\b/i.test(text)) return true;
            if (/\\b(pdf|docx?|pptx?|xlsx?|csv|txt|rtf|zip|pagina|pagine|page|pages|kb|mb|gb)\\b/i.test(text) && !/[a-zà-ÿ]{3,}\\s+[a-zà-ÿ]{3,}/i.test(text.replace(/pdf|docx?|pptx?|xlsx?|csv|txt|rtf|zip|pagina|pagine|page|pages|kb|mb|gb/ig, ''))) return true;
            return false;
        }

        function documentCaptionFromNode(node, documentPreview, groupSender) {
            if (!node || !documentPreview) return '';
            var lines = textLinesFromRoot(node);
            for (var i = lines.length - 1; i >= 0; i--) {
                var line = cleanMessageText(lines[i]);
                if (!line || isDocumentMetaLine(line, documentPreview, groupSender)) continue;
                if (isValidGroupSenderCandidate(line.replace(/:$/, '')) && i === 0) continue;
                return line;
            }
            return '';
        }

        async function extractDocumentPreview(node, storeMessage) {
            var storePreview = await documentPreviewFromStoreMessage(storeMessage);
            var nodePreview = await documentPreviewFromNode(node);
            if (!storePreview) return nodePreview;
            if (!nodePreview) return storePreview;
            return {
                fileName: storePreview.fileName || nodePreview.fileName,
                detail: storePreview.detail || nodePreview.detail,
                mimeType: storePreview.mimeType || nodePreview.mimeType,
                thumbnailDataUrl: storePreview.thumbnailDataUrl || nodePreview.thumbnailDataUrl || ''
            };
        }

        function waRequire(moduleName) {
            try {
                if (typeof window.require === 'function') {
                    return window.require(moduleName);
                }
            } catch (e) {}
            return null;
        }

        function serializedId(value) {
            if (!value) return '';
            if (typeof value === 'string') return value;
            return value._serialized || value.id || value.user || '';
        }

        function messageIdFromNode(node) {
            if (!node) return '';
            return node.getAttribute('data-id')
                || (node.querySelector('[data-id]') ? node.querySelector('[data-id]').getAttribute('data-id') : '')
                || '';
        }

        async function storeMessageById(messageId) {
            if (!messageId) return null;
            try {
                var collections = waRequire('WAWebCollections');
                if (!collections || !collections.Msg) return null;
                return collections.Msg.get(messageId)
                    || ((await collections.Msg.getMessagesById([messageId])) || {}).messages?.[0]
                    || null;
            } catch (e) {
                return null;
            }
        }

        function recentStoreMessages() {
            try {
                var collections = waRequire('WAWebCollections');
                var msgCollection = collections && collections.Msg;
                if (!msgCollection) return [];
                if (Array.isArray(msgCollection.models)) return msgCollection.models.slice(-250);
                if (Array.isArray(msgCollection._models)) return msgCollection._models.slice(-250);
                if (typeof msgCollection.toArray === 'function') return msgCollection.toArray().slice(-250);
                if (typeof msgCollection.getModelsArray === 'function') return msgCollection.getModelsArray().slice(-250);
                if (msgCollection._index) return Object.values(msgCollection._index).slice(-250);
            } catch (e) {}
            return [];
        }

        function storePollMessageByQuestion(questionText) {
            var question = comparableMessageText(questionText || '');
            if (!question) return null;
            var messages = recentStoreMessages();
            for (var i = messages.length - 1; i >= 0; i--) {
                var msg = messages[i];
                if (!msg || !msg.pollOptions) continue;
                var pollName = comparableMessageText(msg.pollName || msg.body || '');
                if (pollName && (pollName === question || pollName.indexOf(question) >= 0 || question.indexOf(pollName) >= 0)) {
                    return msg;
                }
            }
            return null;
        }

        function storeDocumentMessageByFileName(fileName) {
            var target = comparableMessageText(fileName || '');
            if (!target) return null;
            var messages = recentStoreMessages();
            for (var i = messages.length - 1; i >= 0; i--) {
                var msg = messages[i];
                if (!msg) continue;
                var candidate = comparableMessageText(documentFileNameFromStoreMessage(msg) || msg.body || msg.caption || '');
                var isDocument = storeMessageLooksLikeDocument(msg, documentFileNameFromStoreMessage(msg) || candidate, msg.mimetype || '');
                if (!isDocument || !candidate) continue;
                if (candidate === target || candidate.indexOf(target) >= 0 || target.indexOf(candidate) >= 0) {
                    return msg;
                }
            }
            return null;
        }

        function isOutgoingStoreMessage(msg) {
            try {
                return !!(msg && (msg.fromMe || msg.isSentByMe || (msg.id && msg.id.fromMe)));
            } catch (e) {
                return false;
            }
        }

        function storeMediaMessageByKind(kind) {
            var messages = recentStoreMessages();
            for (var i = messages.length - 1; i >= 0; i--) {
                var msg = messages[i];
                if (!msg || isOutgoingStoreMessage(msg)) continue;
                if (kind === 'sticker' && msg.type === 'sticker') return msg;
                if (kind === 'image' && (msg.type === 'image' || msg.type === 'video')) return msg;
            }
            return null;
        }

        function base64FromArrayBuffer(buffer) {
            var bytes = new Uint8Array(buffer);
            var binary = '';
            var chunkSize = 0x8000;
            for (var i = 0; i < bytes.length; i += chunkSize) {
                var chunk = bytes.subarray(i, i + chunkSize);
                binary += String.fromCharCode.apply(null, chunk);
            }
            return btoa(binary);
        }

        function rasterizeImageDataUrl(dataUrl, maxEdge) {
            return new Promise(function(resolve) {
                try {
                    var img = new Image();
                    img.onload = function() {
                        try {
                            var sourceWidth = img.naturalWidth || img.width || 96;
                            var sourceHeight = img.naturalHeight || img.height || 96;
                            var limit = maxEdge || 320;
                            var scale = Math.min(1, limit / Math.max(sourceWidth, sourceHeight));
                            var canvas = document.createElement('canvas');
                            canvas.width = Math.max(1, Math.round(sourceWidth * scale));
                            canvas.height = Math.max(1, Math.round(sourceHeight * scale));
                            var ctx = canvas.getContext('2d');
                            ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
                            resolve(canvas.toDataURL('image/png'));
                        } catch (e) {
                            resolve(dataUrl);
                        }
                    };
                    img.onerror = function() { resolve(dataUrl); };
                    img.src = dataUrl;
                } catch (e) {
                    resolve(dataUrl);
                }
            });
        }

        async function mediaDataUrlFromStoreMessage(msg) {
            if (!msg) return '';
            var fallbackDataUrl = await storeImageFallbackDataUrl(msg, msg.type === 'sticker' ? 240 : 360);
            if (fallbackDataUrl && msg.type === 'sticker') return fallbackDataUrl;
            if (!msg.directPath || !msg.mediaKey) return fallbackDataUrl || '';
            try {
                if (msg.mediaData && msg.mediaData.mediaStage && msg.mediaData.mediaStage !== 'RESOLVED' && typeof msg.downloadMedia === 'function') {
                    var downloaded = await msg.downloadMedia({ downloadEvenIfExpensive: true, rmrReason: 1 });
                    var downloadedImage = await imageDataUrlFromUnknownValue(downloaded, msg.mimetype || (msg.type === 'sticker' ? 'image/webp' : 'image/png'), msg.type === 'sticker' ? 240 : 360);
                    if (downloadedImage) return downloadedImage;
                }

                var downloadManagerModule = waRequire('WAWebDownloadManager');
                var downloadManager = downloadManagerModule && downloadManagerModule.downloadManager;
                if (!downloadManager || typeof downloadManager.downloadAndMaybeDecrypt !== 'function') return fallbackDataUrl || '';

                var decryptedMedia = await downloadManager.downloadAndMaybeDecrypt({
                    directPath: msg.directPath,
                    encFilehash: msg.encFilehash,
                    filehash: msg.filehash,
                    mediaKey: msg.mediaKey,
                    mediaKeyTimestamp: msg.mediaKeyTimestamp,
                    type: msg.type,
                    signal: new AbortController().signal,
                    downloadQpl: {
                        addAnnotations: function() { return this; },
                        addPoint: function() { return this; }
                    }
                });

                var base64 = window.WWebJS && typeof window.WWebJS.arrayBufferToBase64Async === 'function'
                    ? await window.WWebJS.arrayBufferToBase64Async(decryptedMedia)
                    : base64FromArrayBuffer(decryptedMedia);
                var mimetype = msg.mimetype || (msg.type === 'sticker' ? 'image/webp' : 'image/png');
                var dataUrl = 'data:' + mimetype + ';base64,' + base64;
                return await rasterizeImageDataUrl(dataUrl, msg.type === 'sticker' ? 240 : 360);
            } catch (e) {
                return fallbackDataUrl || '';
            }
        }

        async function fileDataUrlFromStoreMessage(msg) {
            if (!msg) return '';
            var mimeType = msg.mimetype || 'application/octet-stream';
            var mediaData = msg.mediaData || {};
            var fallbackCandidates = [
                mediaData.mediaBlob,
                mediaData._mediaBlob,
                mediaData.blob,
                mediaData.file,
                msg.file,
                msg.blob
            ];
            for (var i = 0; i < fallbackCandidates.length; i++) {
                var fallbackDataUrl = await dataUrlFromUnknownFileValue(fallbackCandidates[i], mimeType);
                if (fallbackDataUrl) return fallbackDataUrl;
            }
            if (!msg.directPath || !msg.mediaKey) return '';

            try {
                if (msg.mediaData && msg.mediaData.mediaStage && msg.mediaData.mediaStage !== 'RESOLVED' && typeof msg.downloadMedia === 'function') {
                    var downloaded = await msg.downloadMedia({ downloadEvenIfExpensive: true, rmrReason: 1 });
                    var directDataUrl = await dataUrlFromUnknownFileValue(downloaded, mimeType);
                    if (directDataUrl) return directDataUrl;
                }

                var downloadManagerModule = waRequire('WAWebDownloadManager');
                var downloadManager = downloadManagerModule && downloadManagerModule.downloadManager;
                if (!downloadManager || typeof downloadManager.downloadAndMaybeDecrypt !== 'function') return '';

                var decryptedMedia = await downloadManager.downloadAndMaybeDecrypt({
                    directPath: msg.directPath,
                    encFilehash: msg.encFilehash,
                    filehash: msg.filehash,
                    mediaKey: msg.mediaKey,
                    mediaKeyTimestamp: msg.mediaKeyTimestamp,
                    type: msg.type,
                    signal: new AbortController().signal,
                    downloadQpl: {
                        addAnnotations: function() { return this; },
                        addPoint: function() { return this; }
                    }
                });

                var base64 = window.WWebJS && typeof window.WWebJS.arrayBufferToBase64Async === 'function'
                    ? await window.WWebJS.arrayBufferToBase64Async(decryptedMedia)
                    : base64FromArrayBuffer(decryptedMedia);
                return 'data:' + mimeType + ';base64,' + base64;
            } catch (e) {
                return '';
            }
        }

        function pollOptionsFromStoreMessage(msg) {
            var options = rawPollOptionsFromStoreMessage(msg);
            return options.map(function(option, index) {
                var name = cleanMessageText(option.name || option.text || option.title || option.optionName || option.pollOptionName || '');
                return {
                    id: String(option.localId ?? option.id ?? index),
                    text: name,
                    selected: !!(option.isSelected || option.selected),
                    voteCount: Number(option.voteCount ?? option.votes ?? option.count ?? (option.voters ? option.voters.length : 0) ?? 0) || 0
                };
            }).filter(function(option) {
                return option.text.length > 0;
            });
        }

        function rawPollOptionsFromStoreMessage(msg) {
            var rawOptions = msg && msg.pollOptions;
            if (!rawOptions) return [];
            var options = [];
            if (Array.isArray(rawOptions)) {
                options = rawOptions;
            } else if (typeof rawOptions.forEach === 'function') {
                rawOptions.forEach(function(option) { options.push(option); });
            } else if (Array.isArray(rawOptions.models)) {
                options = rawOptions.models;
            } else if (Array.isArray(rawOptions._models)) {
                options = rawOptions._models;
            } else if (typeof rawOptions.serialize === 'function') {
                options = rawOptions.serialize();
            } else {
                options = Object.values(rawOptions).filter(function(option) {
                    return option && typeof option === 'object';
                });
            }
            return options;
        }

        function pollAllowsMultipleSelectionFromText(text) {
            return /seleziona una o più opzioni|seleziona più opzioni|scegli una o più opzioni|scegli più opzioni|select one or more options|choose one or more options|select multiple|multiple answers/i.test(text || '');
        }

        function pollAllowsMultipleSelectionFromStoreMessage(msg) {
            if (!msg) return false;
            var sources = [
                msg,
                msg.poll,
                msg.pollData,
                msg.pollContent,
                msg.pollCreation,
                msg.pollCreationMessage,
                msg.message
            ].filter(Boolean);
            var booleanFields = [
                'allowMultipleAnswers',
                'allowsMultipleAnswers',
                'allowMultipleSelection',
                'allowsMultipleSelection',
                'pollAllowMultipleAnswers',
                'pollAllowsMultipleAnswers',
                'multipleAnswers',
                'isMultiSelect',
                'isMultipleChoice'
            ];
            for (var b = 0; b < sources.length; b++) {
                for (var f = 0; f < booleanFields.length; f++) {
                    if (sources[b][booleanFields[f]] === true) return true;
                }
            }

            var countFields = [
                'pollSelectableOptionsCount',
                'selectableOptionsCount',
                'pollSelectableOptionCount',
                'pollOptionsSelectableCount',
                'selectableOptionCount',
                'maxSelectedOptions',
                'maxSelectableOptions'
            ];
            for (var s = 0; s < sources.length; s++) {
                for (var c = 0; c < countFields.length; c++) {
                    var raw = sources[s][countFields[c]];
                    if (raw === undefined || raw === null || raw === '') continue;
                    var count = Number(raw);
                    if (!isFinite(count)) continue;
                    if (count === 0 || count > 1) return true;
                    if (count === 1) return false;
                }
            }
            return false;
        }

        async function messageFromStoreModel(msg, fallbackGroupSender) {
            if (!msg) return null;
            var type = msg.type || '';
            var pollOptions = type === 'poll_creation' || msg.pollOptions ? pollOptionsFromStoreMessage(msg) : [];
            var pollAllowsMultipleSelection = pollAllowsMultipleSelectionFromStoreMessage(msg);
            var text = cleanMessageText(
                pollOptions.length ? (msg.pollName || msg.body || '') : (msg.body || msg.caption || msg.pollName || msg.eventName || '')
            );
            var mediaKind = type === 'sticker' ? 'sticker' : ((type === 'image' || type === 'video') ? 'image' : '');
            var mediaDataUrl = '';
            var linkPreview = linkPreviewFromStoreMessage(msg);
            var documentPreview = await documentPreviewFromStoreMessage(msg);
            if (documentPreview && !text) {
                text = documentPreview.fileName;
            }

            if (type === 'sticker' || type === 'image') {
                mediaDataUrl = await mediaDataUrlFromStoreMessage(msg);
            }

            if (!text && !mediaDataUrl && !documentPreview && pollOptions.length === 0) return null;
            return {
                id: serializedId(msg.id) || (text + '|' + type),
                body: text || (mediaKind === 'sticker' ? 'Sticker' : '📨 Nuovo messaggio'),
                mediaKind: mediaKind,
                mediaDataUrl: mediaDataUrl,
                linkPreview: linkPreview,
                documentPreview: documentPreview,
                pollOptions: pollOptions,
                pollAllowsMultipleSelection: pollAllowsMultipleSelection,
                isPoll: type === 'poll_creation' || !!msg.pollOptions || !!msg.pollName,
                groupSender: groupSenderFromStoreMessage(msg, fallbackGroupSender)
            };
        }

        function uniqueOptions(options) {
            var seen = new Set();
            return options.filter(function(option) {
                var key = cleanMessageText(option.text).toLowerCase();
                if (!key || seen.has(key)) return false;
                seen.add(key);
                option.text = cleanMessageText(option.text);
                return option.text.length > 0;
            });
        }

        function pollOptionTextFromElement(el) {
            var text = cleanMessageText(textWithEmoji(el) || el.getAttribute('aria-label') || '');
            text = text
                .replace(/\\b\\d+\\s*(votes?|voti?)\\b/ig, '')
                .replace(/\\b\\d+%\\b/g, '')
                .replace(/\\s+\\d+$/, '')
                .replace(/^[○◉●◯\\s]+/, '')
                .trim();
            return text;
        }

        function pollVoteCountFromElement(el) {
            var text = cleanMessageText(textWithEmoji(el) || el.getAttribute('aria-label') || '');
            var explicitVotes = text.match(/\\b(\\d+)\\s*(votes?|voti?)\\b/i);
            if (explicitVotes) return parseInt(explicitVotes[1], 10) || 0;
            var trailingNumber = text.match(/\\s(\\d+)$/);
            if (trailingNumber) return parseInt(trailingNumber[1], 10) || 0;
            return 0;
        }

        function isPollMarkerText(text) {
            return isExplicitPollMarkerText(text) || /\\bpoll\\b|\\bsondaggio\\b/i.test(text || '');
        }

        function isExplicitPollMarkerText(text) {
            return pollAllowsMultipleSelectionFromText(text)
                || /seleziona un'opzione|seleziona una opzione|scegli un'opzione|scegli una opzione|select one option|select an option|choose one option|visualizza voti|view votes/i.test(text || '');
        }

        function pollLineIsTime(text) {
            return /^\\d{1,2}:\\d{2}$/.test(cleanMessageText(text));
        }

        function textLinesFromRoot(root) {
            if (!root) return [];
            var raw = root.innerText || root.textContent || '';
            if (!raw) raw = textWithEmoji(root);
            return raw
                .split(/\\n+/)
                .map(function(line) { return cleanMessageText(line); })
                .filter(function(line) { return line.length > 0; });
        }

        function pollAllowsMultipleSelectionFromRoot(root) {
            if (!root) return false;
            var text = cleanMessageText((root.innerText || root.textContent || textWithEmoji(root) || ''));
            if (pollAllowsMultipleSelectionFromText(text)) return true;
            if (root.querySelector('[role="checkbox"], [aria-label*="checkbox" i], [aria-label*="casella" i]')) return true;
            var markerText = Array.from(root.querySelectorAll('[aria-label], [title], [data-testid]')).slice(0, 80).map(function(el) {
                return [
                    el.getAttribute('aria-label') || '',
                    el.getAttribute('title') || '',
                    el.getAttribute('data-testid') || ''
                ].join(' ');
            }).join(' ');
            return pollAllowsMultipleSelectionFromText(markerText);
        }

        function pollOptionFromTextLine(line) {
            var text = cleanMessageText(line)
                .replace(/^[○◉●◯✓✔\\s]+/, '')
                .replace(/\\b\\d+%\\b/g, '')
                .trim();
            if (!text || pollLineIsTime(text) || isPollMarkerText(text)) return null;
            if (/^\\d+$/.test(text)) {
                return { countOnly: true, voteCount: parseInt(text, 10) || 0 };
            }
            var trailingCount = text.match(/^(.*?)(?:\\s+)(\\d+)\\s*(?:votes?|voti?)?$/i);
            var voteCount = 0;
            if (trailingCount && trailingCount[1] && trailingCount[1].trim().length > 0) {
                text = cleanMessageText(trailingCount[1]);
                voteCount = parseInt(trailingCount[2], 10) || 0;
            }
            if (!text || /^\\d+$/.test(text) || pollLineIsTime(text) || isPollMarkerText(text)) return null;
            return { text: text, selected: false, voteCount: voteCount };
        }

        function pollFromTextLines(root, fallbackQuestion) {
            var lines = textLinesFromRoot(root);
            if (lines.length < 3) return null;

            var markerIndex = -1;
            var votesIndex = -1;
            var allowsMultipleSelection = pollAllowsMultipleSelectionFromRoot(root);
            for (var i = 0; i < lines.length; i++) {
                if (markerIndex < 0 && isExplicitPollMarkerText(lines[i])) {
                    markerIndex = i;
                }
                if (pollAllowsMultipleSelectionFromText(lines[i])) {
                    allowsMultipleSelection = true;
                }
                if (votesIndex < 0 && /visualizza voti|view votes/i.test(lines[i])) {
                    votesIndex = i;
                }
            }
            if (markerIndex < 0 && votesIndex < 0) return null;

            var question = cleanMessageText(fallbackQuestion || '');
            if (!question) {
                var questionEnd = markerIndex >= 0 ? markerIndex : lines.length;
                for (var q = questionEnd - 1; q >= 0; q--) {
                    if (!isPollMarkerText(lines[q]) && !pollLineIsTime(lines[q]) && !/^\\d+$/.test(lines[q])) {
                        question = lines[q];
                        break;
                    }
                }
            }

            var start = markerIndex >= 0 ? markerIndex + 1 : 0;
            var end = votesIndex >= 0 ? votesIndex : lines.length;
            var options = [];
            for (var lineIndex = start; lineIndex < end; lineIndex++) {
                var option = pollOptionFromTextLine(lines[lineIndex]);
                if (!option) continue;
                if (option.countOnly) {
                    if (options.length > 0) {
                        options[options.length - 1].voteCount = option.voteCount;
                    }
                    continue;
                }
                if (question && normalizePollText(option.text) === normalizePollText(question)) continue;
                option.id = 'poll-text-option-' + options.length;
                options.push(option);
            }

            options = uniqueOptions(options).filter(function(option) {
                return option.text.length <= 80
                    && !/^(send|invia|reply|rispondi)$/i.test(option.text)
                    && !pollLineIsTime(option.text);
            });

            if (options.length < 2) {
                postPollDebug('poll marker found but options missing. lines=' + JSON.stringify(lines.slice(0, 16)));
                return null;
            }

            return { question: question || lines[0] || 'Sondaggio', options: options.slice(0, 8), allowsMultipleSelection: allowsMultipleSelection, selectedStateReliable: false };
        }

        function normalizePollText(value) {
            return cleanMessageText(value).toLowerCase();
        }

        function comparableMessageText(value) {
            return normalizePollText(value)
                .replace(/[\\u200D\\uFE0F]/g, '')
                .replace(/[😀-🙏🌀-🗿🚀-🛿☀-⛿✀-➿]/gu, '')
                .replace(/\\s+/g, ' ')
                .trim();
        }

        function messageMatchesFallback(message, fallbackBody) {
            if (!message) return false;
            var body = comparableMessageText(message.body || '');
            var fallback = comparableMessageText(fallbackBody || '');
            var messageUrl = (message.linkPreview && message.linkPreview.url) || firstUrlFromText(message.body || '');
            var fallbackUrl = firstUrlFromText(fallbackBody || '');
            if (messageUrl && fallbackUrl && messageUrl === fallbackUrl) return true;
            if (message.documentPreview && message.documentPreview.fileName) {
                var documentFile = comparableMessageText(message.documentPreview.fileName);
                if (documentFile && (fallback.indexOf(documentFile) >= 0 || body.indexOf(documentFile) >= 0)) return true;
            }
            var fallbackIsMediaLabel = /^(📨\\s*)?(nuovo messaggio|new message|sticker|adesivo|immagine|image|photo|foto)$/i.test(fallback || '');
            if (fallbackIsMediaLabel && (message.mediaDataUrl || message.mediaKind)) return true;
            if (!fallback) return true;
            if (!body) return false;
            if (body === fallback) return true;
            return body.indexOf(fallback) >= 0 || fallback.indexOf(body) >= 0;
        }

        function isMediaOnlyFallbackText(value) {
            var fallback = comparableMessageText(value || '');
            return /^(📨\\s*)?(nuovo messaggio|new message|sticker|adesivo|immagine|image|photo|foto)$/i.test(fallback || '');
        }

        function fallbackCaptionForDocument(fallbackBody, documentPreview) {
            var caption = cleanMessageText(fallbackBody || '');
            if (!caption || !documentPreview) return '';
            if (isMediaOnlyFallbackText(caption)) return '';
            if (documentPreviewFromText(caption)) return '';
            var normalizedCaption = comparableMessageText(caption);
            var normalizedFileName = comparableMessageText(documentPreview.fileName || '');
            if (!normalizedCaption || normalizedCaption === normalizedFileName) return '';
            if (normalizedFileName && (normalizedCaption.indexOf(normalizedFileName) >= 0 || normalizedFileName.indexOf(normalizedCaption) >= 0)) return '';
            return caption;
        }

        function mergeFallbackCaptionIntoDocument(message, fallbackBody) {
            if (!message || !message.documentPreview) return message;
            var caption = fallbackCaptionForDocument(fallbackBody, message.documentPreview);
            if (!caption) return message;
            var body = cleanMessageText(message.body || '');
            var normalizedBody = comparableMessageText(body);
            var normalizedFileName = comparableMessageText(message.documentPreview.fileName || '');
            var normalizedGroupSender = comparableMessageText(message.groupSender || '');
            if (!body || isMediaOnlyFallbackText(body) || isDocumentMetaLine(body, message.documentPreview, message.groupSender || '') || normalizedBody === normalizedFileName || (normalizedFileName && normalizedBody.indexOf(normalizedFileName) >= 0) || (normalizedGroupSender && normalizedBody === normalizedGroupSender)) {
                message.body = caption;
            }
            return message;
        }

        function isStickerFallbackText(value) {
            return /^(📨\\s*)?(sticker|adesivo)$/i.test(comparableMessageText(value || ''));
        }

        function isDocumentFallbackText(value) {
            return !!documentPreviewFromText(value || '');
        }

        async function hydrateFallbackOrMessage(message, fallbackBody, options) {
            if (!message) return message;
            var hydrated = Object.assign({}, message);
            var fallbackText = cleanMessageText(fallbackBody || hydrated.body || '');
            var allowDocumentCaption = !options || options.allowDocumentCaption !== false;

            if (!hydrated.documentPreview) {
                hydrated.documentPreview = documentPreviewFromText(hydrated.body || '') || (allowDocumentCaption ? documentPreviewFromText(fallbackText) : null);
            }
            if (hydrated.documentPreview) {
                var docMsg = storeDocumentMessageByFileName(hydrated.documentPreview.fileName);
                var storeDocPreview = await documentPreviewFromStoreMessage(docMsg);
                var storeDocGroupSender = groupSenderFromStoreMessage(docMsg, hydrated.groupSender || '');
                if (storeDocGroupSender) {
                    hydrated.groupSender = storeDocGroupSender;
                }
                if (storeDocPreview) {
                    hydrated.documentPreview = {
                        fileName: storeDocPreview.fileName || hydrated.documentPreview.fileName,
                        detail: storeDocPreview.detail || hydrated.documentPreview.detail,
                        mimeType: storeDocPreview.mimeType || hydrated.documentPreview.mimeType,
                        thumbnailDataUrl: storeDocPreview.thumbnailDataUrl || hydrated.documentPreview.thumbnailDataUrl || ''
                    };
                    hydrated.id = hydrated.id || serializedId(docMsg && docMsg.id) || hydrated.documentPreview.fileName;
                }
                hydrated.mediaKind = '';
                hydrated.mediaDataUrl = '';
                if (!hydrated.body || comparableMessageText(hydrated.body) === comparableMessageText(hydrated.documentPreview.fileName)) {
                    hydrated.body = hydrated.documentPreview.fileName;
                }
                if (allowDocumentCaption) {
                    hydrated = mergeFallbackCaptionIntoDocument(hydrated, fallbackText);
                }
            }

            var wantsSticker = hydrated.mediaKind === 'sticker'
                || isStickerFallbackText(hydrated.body)
                || isStickerFallbackText(fallbackText);
            if (wantsSticker && !hydrated.mediaDataUrl) {
                var stickerMsg = storeMediaMessageByKind('sticker');
                var stickerDataUrl = await mediaDataUrlFromStoreMessage(stickerMsg);
                if (stickerDataUrl) {
                    hydrated.id = hydrated.id || serializedId(stickerMsg && stickerMsg.id) || hydrated.body || 'Sticker';
                    hydrated.body = hydrated.body || 'Sticker';
                    hydrated.mediaKind = 'sticker';
                    hydrated.mediaDataUrl = stickerDataUrl;
                }
            }

            return hydrated;
        }

        function extractPoll(node) {
            var fullText = cleanMessageText(textWithEmoji(node));
            var visibleText = cleanMessageText(node.innerText || node.textContent || '');
            var pollRoot = node.querySelector('[data-testid*="poll"], [aria-label*="poll" i], [aria-label*="sondaggio" i], [data-icon*="poll"]');
            var hasPollMarker = !!pollRoot || isPollMarkerText(fullText) || isPollMarkerText(visibleText) || isPollMarkerText(node.getAttribute('aria-label') || '');

            if (!hasPollMarker) return null;

            var searchRoot = pollRoot || node;
            var questionCandidate = cleanMessageText(textWithEmoji(
                node.querySelector('span.selectable-text.copyable-text, [data-testid="msg-text"]')
            ));
            var textLinePoll = pollFromTextLines(node, questionCandidate) || pollFromTextLines(searchRoot, questionCandidate);
            if (textLinePoll) return textLinePoll;

            var candidates = Array.from(searchRoot.querySelectorAll([
                '[data-testid*="poll-option"]',
                '[data-testid*="poll_option"]',
                '[role="radio"]',
                '[role="checkbox"]',
                '[aria-checked]',
                '[aria-label*="option" i]',
                '[aria-label*="opzione" i]',
                'label'
            ].join(',')));
            var options = candidates.map(function(el, index) {
                return {
                    id: el.getAttribute('data-id') || el.getAttribute('id') || ('poll-option-' + index),
                    text: pollOptionTextFromElement(el),
                    selected: el.getAttribute('aria-checked') === 'true' || el.className.toString().indexOf('selected') >= 0,
                    voteCount: pollVoteCountFromElement(el)
                };
            });
            options = uniqueOptions(options).filter(function(option) {
                return option.text.length <= 80
                    && !/^(send|invia|reply|rispondi)$/i.test(option.text)
                    && !/^\\d{1,2}:\\d{2}$/.test(option.text);
            });

            if (options.length < 2) {
                var lineCandidates = [];
                Array.from(searchRoot.querySelectorAll('div[role="button"], div[tabindex], [aria-label], div')).forEach(function(el, index) {
                    var rect = el.getBoundingClientRect();
                    if (rect.width < 80 || rect.height < 16 || rect.height > 78) return;
                    var text = pollOptionTextFromElement(el);
                    if (!text || text.length > 80) return;
                    if (questionCandidate && text === questionCandidate) return;
                    if (isPollMarkerText(text)) return;
                    if (/^(poll|sondaggio|view votes|vedi voti|visualizza voti|vote|vota)$/i.test(text)) return;
                    if (/^\\d+$/.test(text)) return;
                    lineCandidates.push({
                        id: el.getAttribute('data-id') || el.getAttribute('id') || ('poll-line-option-' + index),
                        text: text,
                        selected: el.getAttribute('aria-checked') === 'true',
                        voteCount: pollVoteCountFromElement(el)
                    });
                });
                options = options.concat(lineCandidates);
                options = uniqueOptions(options).filter(function(option) {
                    return option.text.length <= 80
                        && !/^(send|invia|reply|rispondi)$/i.test(option.text)
                        && !/^\\d{1,2}:\\d{2}$/.test(option.text);
                });
            }

            if (options.length < 2) return null;

            var question = questionCandidate;
            if (!question) {
                question = fullText;
                options.forEach(function(option) {
                    question = question.replace(option.text, '').trim();
                });
                question = question
                    .replace(/seleziona una o più opzioni/ig, '')
                    .replace(/select one or more options/ig, '')
                    .replace(/visualizza voti|view votes/ig, '')
                    .replace(/\\s+/g, ' ')
                    .trim();
            }
            return {
                question: question,
                options: options.slice(0, 8),
                allowsMultipleSelection: pollAllowsMultipleSelectionFromRoot(searchRoot) || pollAllowsMultipleSelectionFromRoot(node),
                selectedStateReliable: true
            };
        }

        function sleep(ms) {
            return new Promise(function(resolve) { setTimeout(resolve, ms); });
        }

        function clickElement(element) {
            if (!element) return false;
            try { element.scrollIntoView({ block: 'center', inline: 'nearest' }); } catch (e) {}
            try { element.focus({ preventScroll: true }); } catch (e) {}
            var rect = element.getBoundingClientRect();
            var x = Math.max(1, Math.floor(rect.left + Math.min(rect.width / 2, rect.width - 2)));
            var y = Math.max(1, Math.floor(rect.top + Math.min(rect.height / 2, rect.height - 2)));
            return clickPoint(x, y, element);
        }

        function clickPoint(x, y, fallbackElement) {
            x = Math.max(1, Math.floor(x));
            y = Math.max(1, Math.floor(y));
            var target = document.elementFromPoint(x, y) || fallbackElement;
            if (!target) return false;
            try { target.focus({ preventScroll: true }); } catch (e) {}
            var options = {
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
                target.dispatchEvent(new PointerEvent('pointerdown', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 1, button: 0 }, options)));
                target.dispatchEvent(new PointerEvent('pointerup', Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true, buttons: 0, button: 0 }, options)));
            }
            target.dispatchEvent(new MouseEvent('mousedown', Object.assign({ button: 0, buttons: 1 }, options)));
            target.dispatchEvent(new MouseEvent('mouseup', Object.assign({ button: 0, buttons: 0 }, options)));
            target.dispatchEvent(new MouseEvent('click', Object.assign({ button: 0, buttons: 0 }, options)));
            try { target.click(); } catch (e) {}
            return true;
        }

        function expandedMessageNode(node) {
            if (!node) return node;
            var current = node.closest('.message-in, .message-out') || node.closest('[data-id]') || node;
            var best = current;
            var main = document.querySelector('#main');

            for (var i = 0; i < 7 && current && current.parentElement && current.parentElement !== main; i++) {
                var parent = current.parentElement;
                var messageCount = parent.querySelectorAll('.message-in, .message-out').length;
                if (messageCount > 1) break;

                var rect = parent.getBoundingClientRect();
                var bestRect = best.getBoundingClientRect();
                if (rect.width <= 0 || rect.height <= 0 || rect.height > 650) {
                    current = parent;
                    continue;
                }

                var parentText = parent.innerText || parent.textContent || textWithEmoji(parent) || '';
                var bestText = best.innerText || best.textContent || textWithEmoji(best) || '';
                if (isPollMarkerText(parentText) && parentText.length >= bestText.length && rect.height >= bestRect.height) {
                    best = parent;
                }

                current = parent;
            }

            return best;
        }

        function visibleMessageNodes() {
            var nodes = Array.from(document.querySelectorAll('#main .message-in, #main [data-id]'));
            var seen = new Set();
            var bubbles = nodes.map(function(node) {
                return {
                    source: node,
                    bubble: expandedMessageNode(node.closest('.message-in, .message-out') || node.closest('[data-id]') || node)
                };
            });
            return bubbles.filter(function(entry) {
                var source = entry.source;
                var bubble = entry.bubble;
                if (source.classList && source.classList.contains('message-out')) return false;
                if (source.closest && source.closest('.message-out')) return false;
                var key = bubble.getAttribute('data-id') || bubble.outerHTML.slice(0, 120);
                if (seen.has(key)) return false;
                seen.add(key);
                var rect = bubble.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            }).map(function(entry) {
                return entry.bubble;
            });
        }

        function visiblePollMessageNodes() {
            var main = document.querySelector('#main');
            if (!main) return [];
            var markerNodes = Array.from(main.querySelectorAll('.message-in, .message-out, [data-id], [role="button"], [tabindex], div, span')).filter(function(node) {
                var text = node.innerText || node.textContent || '';
                if (!isExplicitPollMarkerText(text)) return false;
                var rect = node.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });
            var seen = new Set();
            return markerNodes.map(function(node) {
                return expandedMessageNode(node.closest('.message-in, .message-out') || node.closest('[data-id]') || node);
            }).filter(function(node) {
                if (!node) return false;
                var key = node.getAttribute('data-id') || node.outerHTML.slice(0, 160);
                if (seen.has(key)) return false;
                seen.add(key);
                return true;
            });
        }

        function scrollChatToBottom() {
            var main = document.querySelector('#main');
            if (!main) return false;
            var candidates = Array.from(main.querySelectorAll('[data-testid="conversation-panel-messages"], div[role="application"], div')).filter(function(el) {
                return el && el.scrollHeight > el.clientHeight + 20;
            });
            candidates.sort(function(a, b) {
                return (b.scrollHeight - b.clientHeight) - (a.scrollHeight - a.clientHeight);
            });
            var didScroll = false;
            candidates.slice(0, 4).forEach(function(el) {
                try {
                    el.scrollTop = el.scrollHeight;
                    el.dispatchEvent(new WheelEvent('wheel', {
                        bubbles: true,
                        cancelable: true,
                        deltaY: 1200,
                        clientX: Math.max(1, Math.floor(el.getBoundingClientRect().left + 8)),
                        clientY: Math.max(1, Math.floor(el.getBoundingClientRect().bottom - 8))
                    }));
                    didScroll = true;
                } catch (e) {}
            });
            try {
                window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'End', code: 'End', keyCode: 35, which: 35 }));
            } catch (e) {}
            return didScroll;
        }

        function uniqueMessageNodes(nodes) {
            var seen = new Set();
            return nodes.filter(function(node) {
                if (!node) return false;
                var id = messageIdFromNode(node);
                var key = id || cleanMessageText(node.innerText || node.textContent || textWithEmoji(node) || '').slice(0, 180);
                if (!key || seen.has(key)) return false;
                seen.add(key);
                return true;
            }).sort(function(a, b) {
                if (a === b) return 0;
                var position = a.compareDocumentPosition(b);
                if (position & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
                if (position & Node.DOCUMENT_POSITION_PRECEDING) return 1;
                return 0;
            });
        }

        async function messageFromNode(node, fallbackGroupSender) {
            node = expandedMessageNode(node);
            var nodeGroupSender = groupSenderFromMessageNode(node, fallbackGroupSender);
            var storeMessage = await storeMessageById(messageIdFromNode(node));
            var storePayload = await messageFromStoreModel(storeMessage, nodeGroupSender);
            var storePayloadNeedsDomMedia = storePayload && !storePayload.isPoll && storePayload.mediaKind && !storePayload.mediaDataUrl;
            var storePayloadNeedsDomDocument = storePayload && !storePayload.isPoll && (
                (storePayload.documentPreview && !storePayload.documentPreview.thumbnailDataUrl)
                    || (!storePayload.documentPreview && nodeLikelyHasDocument(node))
            );
            if (storePayload && !storePayload.isPoll && !storePayloadNeedsDomMedia && !storePayloadNeedsDomDocument && (storePayload.mediaDataUrl || storePayload.body !== '📨 Nuovo messaggio')) {
                if (storePayload.linkPreview || firstUrlFromText(storePayload.body || '')) {
                    storePayload.linkPreview = mergeLinkPreviews(
                        storePayload.linkPreview || linkPreviewFromTextOnly(storePayload.body || ''),
                        await extractLinkPreview(node, storePayload.body)
                    );
                }
                return storePayload;
            }
            if (storePayload && storePayload.isPoll && storePayload.pollOptions.length > 0) {
                var storePollDom = extractPoll(node);
                if (storePollDom && storePollDom.allowsMultipleSelection) {
                    storePayload.pollAllowsMultipleSelection = true;
                }
                return storePayload;
            }

            var textRoot = node.querySelector('span.selectable-text.copyable-text, [data-testid="msg-text"], span[dir="ltr"], span[dir="auto"]');
            var text = cleanMessageText(textWithEmoji(textRoot || node));
            if (!text) {
                text = cleanMessageText(emojiAltText(node));
            }
            var media = await extractMedia(node);
            var linkPreview = await extractLinkPreview(node, text);
            var documentPreview = await extractDocumentPreview(node, storeMessage);
            var resolvedNodeGroupSender = (storePayload && storePayload.groupSender) || nodeGroupSender || fallbackGroupSender || '';
            var documentCaption = documentCaptionFromNode(node, documentPreview, resolvedNodeGroupSender);
            if (documentPreview && text && isGroupSenderLine(text, resolvedNodeGroupSender)) {
                text = '';
            }
            if (documentPreview && documentCaption && (!text || isDocumentMetaLine(text, documentPreview, resolvedNodeGroupSender))) {
                text = documentCaption;
            }
            if (linkPreview && !linkPreview.imageDataUrl && media.dataUrl) {
                linkPreview.imageDataUrl = media.dataUrl;
            }
            var poll = extractPoll(node);
            if (poll && poll.question) {
                text = (storePayload && storePayload.body && storePayload.body !== '📨 Nuovo messaggio') ? storePayload.body : poll.question;
            }
            if (poll && media.dataUrl) {
                if (!text || comparableMessageText(text) === comparableMessageText(poll.question || '')) {
                    text = '';
                }
                poll = null;
            }
            if (storePayload && !storePayload.isPoll && !poll) {
                var storeBody = cleanMessageText(storePayload.body || '');
                if (!text && storeBody && storeBody !== '📨 Nuovo messaggio') {
                    text = storeBody;
                }
                var mergedLinkPreview = storePayload.linkPreview || linkPreview;
                if ((mergedLinkPreview || firstUrlFromText(storeBody || text || '')) && !mergedLinkPreview) {
                    mergedLinkPreview = linkPreviewFromTextOnly(storeBody || text || '');
                }
                if (mergedLinkPreview) {
                    mergedLinkPreview = mergeLinkPreviews(mergedLinkPreview, linkPreview);
                }
                var mergedMediaKind = storePayload.mediaKind || media.kind || '';
                var mergedMediaDataUrl = storePayload.mediaDataUrl || media.dataUrl || '';
                var mergedDocumentPreview = storePayload.documentPreview || documentPreview;
                var mergedGroupSender = storePayload.groupSender || nodeGroupSender || '';
                if (mergedDocumentPreview && storeBody && isGroupSenderLine(storeBody, mergedGroupSender)) {
                    storeBody = '';
                }
                var mergedDocumentCaption = documentCaption || (storeBody && !isDocumentMetaLine(storeBody, mergedDocumentPreview, mergedGroupSender) ? storeBody : '');
                if (mergedDocumentPreview && text && isGroupSenderLine(text, mergedGroupSender)) {
                    text = '';
                }
                if (mergedDocumentPreview && mergedDocumentCaption && (!text || isDocumentMetaLine(text, mergedDocumentPreview, mergedGroupSender))) {
                    text = mergedDocumentCaption;
                }
                if (storePayload.documentPreview && documentPreview && !storePayload.documentPreview.thumbnailDataUrl && documentPreview.thumbnailDataUrl) {
                    mergedDocumentPreview = {
                        fileName: storePayload.documentPreview.fileName || documentPreview.fileName,
                        detail: storePayload.documentPreview.detail || documentPreview.detail,
                        mimeType: storePayload.documentPreview.mimeType || documentPreview.mimeType,
                        thumbnailDataUrl: documentPreview.thumbnailDataUrl
                    };
                }
                if (mergedDocumentPreview) {
                    mergedMediaKind = '';
                    mergedMediaDataUrl = '';
                }
                if (mergedLinkPreview && !mergedLinkPreview.imageDataUrl && mergedMediaDataUrl) {
                    mergedLinkPreview.imageDataUrl = mergedMediaDataUrl;
                }
                if (!text && mergedMediaKind) {
                    text = mergedMediaKind === 'sticker' ? 'Sticker' : 'Immagine';
                }
                if (text || mergedMediaDataUrl || mergedMediaKind || mergedLinkPreview || mergedDocumentPreview) {
                    return {
                        id: storePayload.id || messageIdFromNode(node) || (text + '|' + (mergedMediaKind || '') + '|' + (mergedMediaDataUrl || '').slice(0, 24)),
                        body: text || (mergedDocumentPreview ? mergedDocumentPreview.fileName : '📨 Nuovo messaggio'),
                        mediaKind: mergedLinkPreview ? '' : mergedMediaKind,
                        mediaDataUrl: mergedLinkPreview ? '' : mergedMediaDataUrl,
                        linkPreview: mergedLinkPreview,
                        documentPreview: mergedDocumentPreview,
                        pollOptions: [],
                        pollAllowsMultipleSelection: false,
                        groupSender: mergedGroupSender
                    };
                }
            }
            if (poll && storePayload && storePayload.isPoll) {
                return {
                    id: storePayload.id || messageIdFromNode(node) || (text + '|' + poll.options.map(function(o) { return o.text; }).join('|')),
                    body: text || storePayload.body || '📨 Nuovo messaggio',
                    mediaKind: storePayload.mediaKind || media.kind || '',
                    mediaDataUrl: storePayload.mediaDataUrl || media.dataUrl || '',
                    linkPreview: storePayload.linkPreview || linkPreview,
                    documentPreview: storePayload.documentPreview || documentPreview,
                    pollOptions: poll.options,
                    pollAllowsMultipleSelection: storePayload.pollAllowsMultipleSelection || !!poll.allowsMultipleSelection,
                    groupSender: storePayload.groupSender || nodeGroupSender || ''
                };
            }
            var id = node.getAttribute('data-id')
                  || (node.querySelector('[data-id]') ? node.querySelector('[data-id]').getAttribute('data-id') : '')
                  || (text + '|' + (media.kind || '') + '|' + (media.dataUrl || '').slice(0, 24) + '|' + (poll ? poll.options.map(function(o) { return o.text; }).join('|') : ''));
            if (!text && media.kind) {
                text = media.kind === 'sticker' ? 'Sticker' : 'Immagine';
            }
            if (!text && documentPreview) {
                text = documentPreview.fileName;
            }
            if (!text && !media.dataUrl && !poll && !linkPreview && !documentPreview) return null;
            return {
                id: id,
                body: text || '📨 Nuovo messaggio',
                mediaKind: linkPreview || documentPreview ? '' : (media.kind || ''),
                mediaDataUrl: linkPreview || documentPreview ? '' : (media.dataUrl || ''),
                linkPreview: linkPreview,
                documentPreview: documentPreview,
                pollOptions: poll ? poll.options : [],
                pollAllowsMultipleSelection: poll ? !!poll.allowsMultipleSelection : false,
                groupSender: nodeGroupSender || ''
            };
        }

        async function extractLatestMessagesFromChat(row, unreadCount, fallbackMessage) {
            var fallbackLinkUrl = (fallbackMessage.linkPreview && fallbackMessage.linkPreview.url) || firstUrlFromText(fallbackMessage.body || '');
            var fallbackDocumentPreview = fallbackMessage.documentPreview || documentPreviewFromText(fallbackMessage.body || '');
            var fallbackDocumentFile = fallbackDocumentPreview && fallbackDocumentPreview.fileName;
            var fallbackExpectsDocument = !!fallbackMessage.expectsDocument || !!fallbackDocumentFile;
            var shouldOpenChat = unreadCount >= 1 || (!!fallbackMessage.mediaKind && !fallbackMessage.mediaDataUrl) || !!fallbackLinkUrl || fallbackExpectsDocument;
            if (!shouldOpenChat) return [fallbackMessage];

            clickElement(row);
            var nodes = [];
            var pollNodes = [];
            var scanNotes = [];
            var scanLimit = (fallbackLinkUrl || fallbackExpectsDocument) ? 8 : 4;
            for (var scanAttempt = 0; scanAttempt < scanLimit; scanAttempt++) {
                await sleep(scanAttempt === 0 ? 650 : 350);
                scrollChatToBottom();
                await sleep(180);
                nodes = visibleMessageNodes();
                pollNodes = visiblePollMessageNodes();
                scanNotes.push('try' + scanAttempt + ':nodes=' + nodes.length + ',poll=' + pollNodes.length);
                if (fallbackLinkUrl) {
                    var previewReady = false;
                    var previewNodes = uniqueMessageNodes(nodes.concat(pollNodes));
                    for (var previewIndex = previewNodes.length - 1; previewIndex >= 0; previewIndex--) {
                        var previewMessage = await messageFromNode(previewNodes[previewIndex], fallbackMessage.groupSender || '');
                        var preview = previewMessage && previewMessage.linkPreview;
                        if (preview && preview.url === fallbackLinkUrl && (preview.imageDataUrl || !isBadPreviewTitle(preview.title, preview.url, preview.domain))) {
                            previewReady = true;
                            break;
                        }
                    }
                    if (previewReady) break;
                }
                if (fallbackDocumentFile) {
                    var documentReady = false;
                    var documentNodes = uniqueMessageNodes(nodes.concat(pollNodes));
                    for (var documentIndex = documentNodes.length - 1; documentIndex >= 0; documentIndex--) {
                        var documentMessage = await messageFromNode(documentNodes[documentIndex], fallbackMessage.groupSender || '');
                        var documentPreview = documentMessage && documentMessage.documentPreview;
                        if (!documentPreview) continue;
                        var documentFile = comparableMessageText(documentPreview.fileName || '');
                        var targetFile = comparableMessageText(fallbackDocumentFile || '');
                        if (documentFile && targetFile && (documentFile.indexOf(targetFile) >= 0 || targetFile.indexOf(documentFile) >= 0)) {
                            if (documentPreview.thumbnailDataUrl || scanAttempt >= 3) {
                                documentReady = true;
                                break;
                            }
                        }
                    }
                    if (documentReady) break;
                }
                if (pollNodes.length > 0 || (scanAttempt >= 2 && nodes.length >= Math.max(1, unreadCount || 1) && !fallbackLinkUrl && !fallbackExpectsDocument)) {
                    break;
                }
            }
            var fallbackBody = cleanMessageText(fallbackMessage.body || '');
            var candidateNodes = uniqueMessageNodes(nodes.concat(pollNodes));
            var candidateMessages = [];
            for (var i = candidateNodes.length - 1; i >= 0; i--) {
                var candidateMessage = await messageFromNode(candidateNodes[i], fallbackMessage.groupSender || '');
                if (!candidateMessage) continue;
                candidateMessages.push(await hydrateFallbackOrMessage(candidateMessage, fallbackBody, { allowDocumentCaption: false }));
            }
            var storePollFallback = await messageFromStoreModel(storePollMessageByQuestion(fallbackBody), fallbackMessage.groupSender || '');
            if (storePollFallback && (storePollFallback.pollOptions || []).length > 0) {
                candidateMessages.unshift(storePollFallback);
            }

            var messages = [];
            for (var pollMatchIndex = 0; pollMatchIndex < candidateMessages.length; pollMatchIndex++) {
                var pollCandidate = candidateMessages[pollMatchIndex];
                if (pollCandidate && (pollCandidate.pollOptions || []).length > 0 && messageMatchesFallback(pollCandidate, fallbackBody)) {
                    messages = [pollCandidate];
                    break;
                }
            }

            var textMatchCandidate = null;
            if (!documentPreviewFromText(fallbackBody)) {
                for (var textMatchIndex = 0; textMatchIndex < candidateMessages.length; textMatchIndex++) {
                    if (!candidateMessages[textMatchIndex].documentPreview && !((candidateMessages[textMatchIndex].pollOptions || []).length > 0) && messageMatchesFallback(candidateMessages[textMatchIndex], fallbackBody)) {
                        textMatchCandidate = candidateMessages[textMatchIndex];
                        break;
                    }
                }
            }

            if (!messages.length && fallbackExpectsDocument) {
                var documentCaptionSearchLimit = Math.min(candidateMessages.length, Math.max(3, (unreadCount || 1) + 1));
                for (var documentCaptionIndex = 0; documentCaptionIndex < documentCaptionSearchLimit; documentCaptionIndex++) {
                    var documentCaptionCandidate = candidateMessages[documentCaptionIndex];
                    if (!documentCaptionCandidate || !documentCaptionCandidate.documentPreview) continue;
                    messages = [mergeFallbackCaptionIntoDocument(documentCaptionCandidate, fallbackBody)];
                    break;
                }
            }

            if (!messages.length && textMatchCandidate) {
                messages = [textMatchCandidate];
            }

            for (var documentMatchIndex = 0; documentMatchIndex < candidateMessages.length; documentMatchIndex++) {
                if (messages.length) break;
                if (!fallbackExpectsDocument) break;
                if (candidateMessages[documentMatchIndex].documentPreview && messageMatchesFallback(candidateMessages[documentMatchIndex], fallbackBody)) {
                    messages = [mergeFallbackCaptionIntoDocument(candidateMessages[documentMatchIndex], fallbackBody)];
                    break;
                }
            }

            if (!messages.length) {
                for (var matchIndex = 0; matchIndex < candidateMessages.length; matchIndex++) {
                    if (candidateMessages[matchIndex].documentPreview && !fallbackExpectsDocument) continue;
                    if (messageMatchesFallback(candidateMessages[matchIndex], fallbackBody)) {
                        messages = [candidateMessages[matchIndex]];
                        break;
                    }
                }
            }

            postPollDebug('chat scan fallback="' + fallbackBody + '" viewport=' + window.innerWidth + 'x' + window.innerHeight + ' ' + scanNotes.join(';') + ' candidates=' + candidateNodes.length + ' messages=' + messages.map(function(message) {
                return cleanMessageText(message.body) + ' options=' + ((message.pollOptions || []).map(function(option) { return option.text; }).join('|') || '0');
            }).join(' / '));

            return messages.length ? messages : [await hydrateFallbackOrMessage(fallbackMessage, fallbackBody)];
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
            rows.forEach(async function(row) {
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
                var media = { kind: mediaKindFromRow(row), dataUrl: '' };
                var linkPreview = linkPreviewFromTextOnly(body);
                var documentPreview = documentPreviewFromText(body);
                var expectsDocument = rowLikelyHasDocument(row) || !!documentPreview;
                if (documentPreview) {
                    media = { kind: '', dataUrl: '' };
                }
                var messageId = sender + '||' + body + '||' + unreadCount + '||' + Date.now();
                var fallbackMessage = {
                    id: messageId,
                    body: body,
                    mediaKind: media.kind || '',
                    mediaDataUrl: media.dataUrl || '',
                    linkPreview: linkPreview,
                    documentPreview: documentPreview,
                    expectsDocument: expectsDocument,
                    pollOptions: [],
                    pollAllowsMultipleSelection: false,
                    groupSender: groupSender || ''
                };
                var messages = [fallbackMessage];
                try {
                    messages = await extractLatestMessagesFromChat(row, unreadCount, fallbackMessage);
                } catch (e) {
                    postPollDebug('message extraction failed for "' + sender + '": ' + e);
                }
                console.log('[Atoll] 🔔 NUOVO: ' + sender + ' → ' + body + ' | avatar: ' + avatar + ' | count: ' + unreadCount + ' | media: ' + (media.kind || 'none'));
                window.webkit.messageHandlers.atollWA.postMessage({
                    type: 'newMessage',
                    chatId: sender + '@c.us',
                    sender: sender,
                    body: body,
                    avatarUrl: avatar,
                    groupSender: groupSender,
                    mediaKind: media.kind || '',
                    mediaDataUrl: media.dataUrl || '',
                    linkPreview: linkPreview,
                    documentPreview: documentPreview,
                    expectsDocument: expectsDocument,
                    pollOptions: fallbackMessage.pollOptions,
                    pollAllowsMultipleSelection: fallbackMessage.pollAllowsMultipleSelection,
                    messageId: messageId,
                    messages: messages
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

        window.atollDownloadDocument = function(chatId, messageId, fileName) {
            var targetSender = chatId.replace(/@(c|g)\\.us$/, '').trim();

            function normalize(value) {
                return (value || '').trim().toLowerCase();
            }

            function openTargetRow() {
                var rows = document.querySelectorAll(chatRowSelector);
                for (var i = 0; i < rows.length; i++) {
                    var s = extractSender(rows[i]);
                    if (s && normalize(s) === normalize(targetSender)) {
                        return clickElement(rows[i].querySelector('[role="button"]') || rows[i]);
                    }
                }
                return false;
            }

            async function payloadFromStoreMessage(msg) {
                if (!msg) return null;
                var documentPreview = await documentPreviewFromStoreMessage(msg);
                var resolvedFileName = (documentPreview && documentPreview.fileName) || documentFileNameFromStoreMessage(msg) || fileName || 'WhatsApp File';
                var dataUrl = await fileDataUrlFromStoreMessage(msg);
                if (!dataUrl) return null;
                return {
                    fileName: resolvedFileName,
                    mimeType: (documentPreview && documentPreview.mimeType) || msg.mimetype || 'application/octet-stream',
                    dataUrl: dataUrl
                };
            }

            return new Promise(async function(resolve, reject) {
                var directPayload = await payloadFromStoreMessage(await storeMessageById(messageId));
                if (directPayload) {
                    resolve(directPayload);
                    return;
                }

                openTargetRow();
                var attempts = 0;
                var isTrying = false;
                var poll = setInterval(async function() {
                    if (isTrying) return;
                    isTrying = true;
                    attempts += 1;

                    scrollChatToBottom();

                    var byNamePayload = await payloadFromStoreMessage(storeDocumentMessageByFileName(fileName));
                    if (byNamePayload) {
                        clearInterval(poll);
                        resolve(byNamePayload);
                        return;
                    }

                    var nodes = uniqueMessageNodes(visibleMessageNodes()).reverse();
                    for (var n = 0; n < nodes.length; n++) {
                        var node = nodes[n];
                        var nodeId = messageIdFromNode(node);
                        var hasSyntheticMessageId = (messageId || '').indexOf('||') >= 0;
                        if (messageId && nodeId && !hasSyntheticMessageId && messageId !== nodeId && messageId.indexOf(nodeId) < 0 && nodeId.indexOf(messageId) < 0) {
                            continue;
                        }
                        var nodeDocument = await extractDocumentPreview(node, await storeMessageById(nodeId));
                        if (!nodeDocument) continue;
                        if (fileName && comparableMessageText(nodeDocument.fileName).indexOf(comparableMessageText(fileName)) < 0 && comparableMessageText(fileName).indexOf(comparableMessageText(nodeDocument.fileName)) < 0) {
                            continue;
                        }
                        var nodePayload = await payloadFromStoreMessage(await storeMessageById(nodeId));
                        if (nodePayload) {
                            clearInterval(poll);
                            resolve(nodePayload);
                            return;
                        }
                    }

                    if (attempts >= 25) {
                        clearInterval(poll);
                        reject('document-download-not-found');
                    }
                    isTrying = false;
                }, 180);
            });
        };

        window.atollSelectPollOption = function(chatId, messageId, optionText, questionText, selectedOptionTexts) {
            var targetSender = chatId.replace(/@(c|g)\\.us$/, '').trim();
            var intendedOptionTexts = Array.isArray(selectedOptionTexts) ? selectedOptionTexts : [optionText];

            function normalize(value) {
                return (value || '').trim().toLowerCase();
            }

            function openTargetRow() {
                var rows = document.querySelectorAll(chatRowSelector);
                for (var i = 0; i < rows.length; i++) {
                    var s = extractSender(rows[i]);
                    if (s && normalize(s) === normalize(targetSender)) {
                        return clickElement(rows[i].querySelector('[role="button"]') || rows[i]);
                    }
                }
                return false;
            }

            function optionCandidates(root) {
                return Array.from(root.querySelectorAll('[role="radio"], [role="checkbox"], [role="button"], [aria-checked], button, label, [tabindex="0"], div[tabindex]'));
            }

            function textMatches(value, expected) {
                var left = comparableMessageText(value || '');
                var right = comparableMessageText(expected || '');
                if (!right) return true;
                return left === right || left.indexOf(right) >= 0 || right.indexOf(left) >= 0;
            }

            function optionTextMatches(value, expected) {
                var left = comparableMessageText(value || '');
                var right = comparableMessageText(expected || '');
                return !!left && !!right && left === right;
            }

            function pollMatchesQuestion(node) {
                if (!questionText) return true;
                var poll = extractPoll(node);
                if (poll && textMatches(poll.question, questionText)) return true;
                var nodeText = cleanMessageText(node.innerText || node.textContent || textWithEmoji(node) || '');
                return textMatches(nodeText, questionText);
            }

            async function sendVoteFromStoreMessage(msg) {
                if (!msg || !msg.pollOptions) return false;
                try {
                    var selectedLocalIds = [];
                    rawPollOptionsFromStoreMessage(msg).forEach(function(option) {
                        var label = option.name || option.text || option.title || option.optionName || option.pollOptionName || '';
                        var shouldSelect = intendedOptionTexts.some(function(text) { return optionTextMatches(label, text); });
                        var localId = option.localId ?? option.id;
                        if (shouldSelect && localId !== undefined && localId !== null) {
                            selectedLocalIds.push(localId);
                        }
                    });
                    if (!selectedLocalIds.length && intendedOptionTexts.length > 0) return false;
                    var voteAction = waRequire('WAWebPollsSendVoteMsgAction');
                    if (!voteAction || typeof voteAction.sendVote !== 'function') return false;
                    await voteAction.sendVote(msg, selectedLocalIds);
                    postPollDebug('vote store option="' + optionText + '" selected="' + intendedOptionTexts.join('|') + '" question="' + (questionText || '') + '" ids=' + selectedLocalIds.join('|'));
                    return true;
                } catch (e) {
                    postPollDebug('vote store failed: ' + e);
                    return false;
                }
            }

            async function sendVoteFromStoreId(id) {
                try {
                    return await sendVoteFromStoreMessage(await storeMessageById(id));
                } catch (e) {
                    return false;
                }
            }

            async function sendVoteFromStoreQuestion() {
                try {
                    return await sendVoteFromStoreMessage(storePollMessageByQuestion(questionText));
                } catch (e) {
                    return false;
                }
            }

            function optionTargetMatches(candidate, expectedText) {
                var label = pollOptionTextFromElement(candidate) || cleanMessageText(textWithEmoji(candidate) || candidate.getAttribute('aria-label') || '');
                return optionTextMatches(label, expectedText || optionText);
            }

            function optionLabelFromElement(candidate) {
                return pollOptionTextFromElement(candidate) || cleanMessageText(textWithEmoji(candidate) || candidate.getAttribute('aria-label') || '');
            }

            function optionClickDescriptorFromLabel(labelNode, expectedText) {
                var labelRect = labelNode.getBoundingClientRect();
                if (labelRect.width <= 0 || labelRect.height <= 0) return null;

                var row = labelNode.closest('[role="radio"], [role="checkbox"], [aria-checked], [role="button"], [tabindex]');
                if (!row) {
                    var cursor = labelNode;
                    for (var depth = 0; depth < 6 && cursor && cursor.parentElement; depth++) {
                        var parent = cursor.parentElement;
                        var rect = parent.getBoundingClientRect();
                        var parentText = optionLabelFromElement(parent);
                        if (rect.width >= labelRect.width && rect.height >= labelRect.height && rect.height <= 90 && optionTargetMatches(parent, expectedText)) {
                            row = parent;
                        }
                        cursor = parent;
                    }
                }
                if (!row) row = labelNode;

                var rowRect = row.getBoundingClientRect();
                var x = Math.max(rowRect.left + 12, labelRect.left - 22);
                var y = labelRect.top + (labelRect.height / 2);
                var checked = row.closest('[aria-checked]') || row.querySelector('[aria-checked]');
                if (checked) {
                    var checkedRect = checked.getBoundingClientRect();
                    if (checkedRect.width > 0 && checkedRect.height > 0) {
                        x = checkedRect.left + (checkedRect.width / 2);
                        y = checkedRect.top + (checkedRect.height / 2);
                        row = checked;
                    }
                }

                return {
                    element: row,
                    x: x,
                    y: y,
                    label: optionLabelFromElement(labelNode),
                    tag: (row.tagName || '').toLowerCase(),
                    role: row.getAttribute('role') || '',
                    ariaChecked: row.getAttribute('aria-checked') || ''
                };
            }

            function findOptionClickTarget(root, expectedText) {
                var textNodes = Array.from(root.querySelectorAll('span, div, [aria-label]')).filter(function(candidate) {
                    var rect = candidate.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0 && optionTargetMatches(candidate, expectedText);
                }).sort(function(a, b) {
                    var al = optionLabelFromElement(a);
                    var bl = optionLabelFromElement(b);
                    var expected = expectedText || optionText;
                    var exactA = comparableMessageText(al) === comparableMessageText(expected) ? 0 : 1;
                    var exactB = comparableMessageText(bl) === comparableMessageText(expected) ? 0 : 1;
                    if (exactA !== exactB) return exactA - exactB;
                    var ar = a.getBoundingClientRect();
                    var br = b.getBoundingClientRect();
                    return (ar.width * ar.height) - (br.width * br.height);
                });
                for (var t = 0; t < textNodes.length; t++) {
                    var descriptor = optionClickDescriptorFromLabel(textNodes[t], expectedText);
                    if (descriptor) return descriptor;
                }

                var candidates = optionCandidates(root).filter(function(candidate) {
                    var rect = candidate.getBoundingClientRect();
                    return rect.width > 0 && rect.height > 0 && optionTargetMatches(candidate, expectedText);
                });
                if (!candidates.length) return null;
                return optionClickDescriptorFromLabel(candidates[0], expectedText);
            }

            function targetLooksSelected(target) {
                if (!target) return false;
                if (target.getAttribute('aria-checked') === 'true') return true;
                var selected = target.querySelector('[aria-checked="true"], [data-icon*="check"], [data-testid*="check"]');
                if (selected) return true;
                return /selected|checked|active/i.test(String(target.className || ''));
            }

            function optionLooksSelectedInRoot(root, expectedText) {
                var poll = extractPoll(root);
                if (!poll || !poll.options) return false;
                return poll.options.some(function(option) {
                    return optionTextMatches(option.text, expectedText || optionText) && !!option.selected;
                });
            }

            async function clickPollOptionInDom(root, expectedText) {
                var target = findOptionClickTarget(root, expectedText);
                if (!target || !target.element) return false;
                clickPoint(target.x, target.y, target.element);
                clickElement(target.element);
                try {
                    target.element.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: ' ', code: 'Space', keyCode: 32, which: 32 }));
                    target.element.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, key: ' ', code: 'Space', keyCode: 32, which: 32 }));
                    target.element.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 }));
                    target.element.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 }));
                } catch (e) {}
                await sleep(450);
                if (!targetLooksSelected(target.element)) {
                    var refreshed = findOptionClickTarget(root, expectedText);
                    if (refreshed && refreshed.element) {
                        clickPoint(refreshed.x, refreshed.y, refreshed.element);
                        clickElement(refreshed.element);
                        target = refreshed;
                    }
                }
                await sleep(900);
                var selected = targetLooksSelected(target.element) || optionLooksSelectedInRoot(root, expectedText);
                postPollDebug('vote dom clicked option="' + (expectedText || optionText) + '" question="' + (questionText || '') + '" selected=' + selected + ' target=' + target.tag + '[role=' + target.role + ',checked=' + target.ariaChecked + '] point=' + Math.round(target.x) + ',' + Math.round(target.y) + ' label="' + target.label + '"');
                return selected;
            }

            async function syncMultiplePollOptionsInDom(root) {
                var poll = extractPoll(root);
                if (!poll || !poll.allowsMultipleSelection) return false;
                if (!poll.selectedStateReliable) {
                    return await clickPollOptionInDom(root, optionText);
                }

                var clickedAny = false;
                for (var p = 0; p < poll.options.length; p++) {
                    var option = poll.options[p];
                    var desired = intendedOptionTexts.some(function(text) { return optionTextMatches(option.text, text); });
                    if (!desired && !option.selected) continue;
                    var target = findOptionClickTarget(root, option.text);
                    var current = !!option.selected || (target && targetLooksSelected(target.element));
                    if (desired === current) continue;
                    if (target && target.element) {
                        await clickPollOptionInDom(root, option.text);
                        clickedAny = true;
                    }
                    await sleep(220);
                }
                return clickedAny;
            }

            return new Promise(async function(resolve, reject) {
                openTargetRow();
                var attempts = 0;
                var isTrying = false;
                var poll = setInterval(async function() {
                    if (isTrying) return;
                    isTrying = true;
                    attempts += 1;
                    var main = document.querySelector('#main');
                    if (!main) {
                        isTrying = false;
                        return;
                    }

                    scrollChatToBottom();
                    var nodes = uniqueMessageNodes(visibleMessageNodes().concat(visiblePollMessageNodes())).reverse();
                    for (var n = 0; n < nodes.length; n++) {
                        var node = nodes[n];
                        if (!pollMatchesQuestion(node)) continue;
                        var nodeId = messageIdFromNode(node);
                        var hasSyntheticMessageId = (messageId || '').indexOf('||') >= 0;
                        if (!questionText && messageId && nodeId && !hasSyntheticMessageId && messageId !== nodeId && messageId.indexOf(nodeId) < 0 && nodeId.indexOf(messageId) < 0) {
                            continue;
                        }

                        var nodePoll = extractPoll(node);
                        var nodeAllowsMultiple = !!(nodePoll && nodePoll.allowsMultipleSelection);
                        if (nodeAllowsMultiple && nodeId && await sendVoteFromStoreId(nodeId)) {
                            clearInterval(poll);
                            resolve('poll-option-selected');
                            return;
                        }
                        if (nodeAllowsMultiple && await syncMultiplePollOptionsInDom(node)) {
                            clearInterval(poll);
                            resolve('poll-option-selected');
                            return;
                        }

                        if (await clickPollOptionInDom(node, optionText)) {
                            clearInterval(poll);
                            resolve('poll-option-selected');
                            return;
                        }

                        if (nodeId && await sendVoteFromStoreId(nodeId)) {
                            clearInterval(poll);
                            resolve('poll-option-selected');
                            return;
                        }
                        if (await sendVoteFromStoreQuestion()) {
                            clearInterval(poll);
                            resolve('poll-option-selected');
                            return;
                        }
                    }

                    if (attempts >= 35) {
                        clearInterval(poll);
                        if (await sendVoteFromStoreId(messageId) || await sendVoteFromStoreQuestion()) {
                            resolve('poll-option-selected');
                        } else {
                            reject('poll-option-not-found');
                        }
                    }
                    isTrying = false;
                }, 140);
            });
        };

        console.log('[Atoll] Monitor v3 attivo ✅');
    })();
    """
}
