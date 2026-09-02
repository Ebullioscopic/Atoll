/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import Defaults
import Foundation
import WebKit

public enum TelegramAuthState: Equatable {
    case idle
    case loading
    case signInRequired
    case authenticated
    case error(String)
}

private final class TelegramWeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: TelegramWebEngine?
    init(_ target: TelegramWebEngine) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(message)
    }
}

/// Watches Telegram Web for arriving messages and carries replies back to it.
///
/// Telegram has no local API a third-party app can read a conversation from --
/// the desktop client keeps its session to itself, and MTProto would mean
/// holding the user's account credentials. So this runs the official web
/// client in an offscreen `WKWebView`, exactly as the WhatsApp side does, and
/// reads the chat list it renders.
///
/// What is read is the chat list, not the conversation: a row's title, its
/// unread badge and the one-line preview Telegram itself puts there. That is
/// the surface Telegram keeps up to date for every chat at once without any of
/// them being open, which is what a notification needs. It also sets the limit
/// on what a card can show -- a photo arrives as the word Telegram writes in
/// the preview, because that is all the row carries.
@MainActor
public final class TelegramWebEngine: NSObject, ObservableObject {
    public static let shared = TelegramWebEngine()

    @Published public var authState: TelegramAuthState = .idle

    private var offscreenWindow: NSWindow?
    private var authTimer: Timer?
    private var authenticationTime: Date?
    private var isMonitorInjectedForCurrentDocument = false
    private var pendingMonitorInjectionTask: Task<Void, Never>?
    private var activeSendTask: Task<Void, Never>?

    /// The sign-in window's view, while that window is open.
    ///
    /// Signing in happens over there, and a session lives in the shared data
    /// store rather than in either view -- so the monitoring view goes on
    /// showing a sign-in page it will never leave on its own. Watching this
    /// one is how the engine learns the session exists and reloads.
    private weak var signInWebView: WKWebView?
    private var hasReloadedForSignIn = false

    private struct PendingMessage {
        let sender: String
        let messages: [ChatIncomingMessage]
        let chatId: String
        let avatarUrl: String?
    }

    private var messageQueue: [PendingMessage] = []
    private var drainTask: Task<Void, Never>?

    /// Messages arriving within this of a successful sign-in are the backlog
    /// that was already waiting, not news. Telegram paints the whole chat list
    /// at once when it connects, so without this every unread chat would fire a
    /// card the moment the app started.
    private static let startupQuietPeriod: TimeInterval = 6

    public private(set) lazy var webView: WKWebView = buildWebView()

    private override init() { super.init() }

    // MARK: - Lifecycle

    public func start() {
        guard authState == .idle else { return }
        authState = .loading
        isMonitorInjectedForCurrentDocument = false
        pendingMonitorInjectionTask?.cancel()
        pendingMonitorInjectionTask = nil
        activeSendTask?.cancel()
        activeSendTask = nil
        attachToOffscreenWindow()
        webView.load(URLRequest(url: URL(string: "https://web.telegram.org/k/")!))
        startAuthPolling()
        print("TelegramWebEngine: started ✅")
    }

    public func stop() {
        authTimer?.invalidate(); authTimer = nil
        pendingMonitorInjectionTask?.cancel(); pendingMonitorInjectionTask = nil
        activeSendTask?.cancel(); activeSendTask = nil
        drainTask?.cancel(); drainTask = nil
        messageQueue.removeAll()
        webView.stopLoading()
        // Ordered out, never released. The web view is this window's content
        // view and outlives it -- the engine holds it across a stop -- so
        // letting the window go left the view pointing at a dead window, and
        // the app died in whatever timer's autorelease pool drained next.
        // The window costs nothing while hidden, so it is made once and kept.
        offscreenWindow?.orderOut(nil)
        authenticationTime = nil
        isMonitorInjectedForCurrentDocument = false
        signInWebView = nil
        hasReloadedForSignIn = false
        authState = .idle
    }

    /// Signs the account out of this copy of the web client by dropping its
    /// data store, then starts again at the sign-in screen.
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

    // MARK: - Sending

    public func sendReply(chatId: String, text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard authState == .authenticated else {
            completion(.failure(Self.error(1, "Telegram is not connected.")))
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(Self.error(2, "Nothing to send.")))
            return
        }

        activeSendTask?.cancel()
        activeSendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // `callAsyncJavaScript` rather than `evaluateJavaScript`: the
                // script has to wait for the chat to open and the composer to
                // exist, and only this one awaits the promise it returns --
                // the other hands back null the moment the promise is made,
                // which would report every reply as sent.
                let outcome = try await self.webView.callAsyncJavaScript(
                    JS.sendReplyBody,
                    arguments: ["chatId": chatId, "body": trimmed],
                    contentWorld: .page
                )
                guard !Task.isCancelled else { return }
                // The script answers with a reason rather than throwing, so a
                // failure says which step gave up instead of "an error".
                if let outcome = outcome as? String, outcome != "sent" {
                    completion(.failure(Self.error(3, "Telegram did not accept the reply (\(outcome)).")))
                    return
                }
                completion(.success(()))
            } catch {
                guard !Task.isCancelled else { return }
                completion(.failure(error))
            }
        }
    }

    // MARK: - WebView

    private func buildWebView() -> WKWebView {
        let config = WKWebViewConfiguration()

        if #available(macOS 14.0, *) {
            // Its own store, so signing out of Telegram here cannot disturb the
            // WhatsApp session living in the other engine.
            let id = UUID(uuidString: "3F1C6A54-9B2E-4F7A-9E31-6D2C0A4B8E15")!
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        } else {
            config.websiteDataStore = WKWebsiteDataStore.default()
        }

        let handler = TelegramWeakScriptHandler(self)
        config.userContentController.add(handler, name: "atollTG")

        // Before anything else on the page: Telegram Web declines to boot while
        // it believes it is in a hidden tab, and a window this well hidden can
        // be marked occluded for reasons outside this engine's control.
        config.userContentController.addUserScript(
            WKUserScript(source: JS.forceVisible, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        config.userContentController.addUserScript(
            WKUserScript(source: JS.authCheck, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: config)
        wv.autoresizingMask = [.width, .height]
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        wv.navigationDelegate = self

        if #available(macOS 12.0, *) {
            wv.setValue(false, forKey: "drawsBackground")
        }

        return wv
    }

    /// A second view onto the same Telegram session, for the sign-in window to
    /// show.
    ///
    /// It shares this engine's `WKWebsiteDataStore` and its process pool, so
    /// signing in here signs in the client this engine is watching -- while
    /// leaving the monitoring view where it is. Moving the one view between
    /// windows would have been fewer objects and one more way to hand AppKit a
    /// live web view mid-teardown.
    public func makeSignInWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = webView.configuration.websiteDataStore
        config.processPool = webView.configuration.processPool

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 620), configuration: config)
        wv.customUserAgent = webView.customUserAgent
        wv.load(URLRequest(url: URL(string: "https://web.telegram.org/k/")!))
        signInWebView = wv
        hasReloadedForSignIn = false
        return wv
    }

    /// Telegram lays itself out from the window size and will not render a chat
    /// list into a zero-sized view, so the web client lives in a real window --
    /// one the user is never going to see.
    ///
    /// Hiding it is fussier than it sounds. A window parked entirely off screen
    /// at zero alpha is occluded, WebKit tells the page it is not visible, and
    /// Telegram Web answers by not booting at all: the static markup loads and
    /// the client never mounts, so nothing is ever detected and the connection
    /// never finishes. The window therefore keeps one point of overlap with the
    /// screen and a hair of opacity -- enough for AppKit to call it visible,
    /// far too little for anyone to see. It ignores the mouse, so that one
    /// point cannot be clicked either.
    private func attachToOffscreenWindow() {
        if let existing = offscreenWindow {
            existing.setFrame(Self.hiddenWindowFrame(), display: false)
            existing.orderFrontRegardless()
            return
        }

        let win = NSWindow(
            contentRect: Self.hiddenWindowFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.contentView = webView
        webView.frame = NSRect(origin: .zero, size: Self.hiddenWindowFrame().size)
        webView.needsLayout = true
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.isOpaque = false
        win.backgroundColor = .clear
        // Not zero: a fully transparent window counts as occluded, and an
        // occluded window is a hidden page.
        win.alphaValue = 0.01
        win.ignoresMouseEvents = true
        // This object is held by the engine for the life of the process, so
        // AppKit must not release it on close as it does by default for a
        // window created in code.
        win.isReleasedWhenClosed = false
        win.orderFrontRegardless()
        offscreenWindow = win
    }

    /// A 1280x900 frame whose corner just clips the screen.
    ///
    /// The size is the viewport Telegram lays itself out for; the position is
    /// whatever puts one point of it on screen, so the window is not occluded.
    private static func hiddenWindowFrame() -> NSRect {
        let size = CGSize(width: 1280, height: 900)
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NSRect(origin: .zero, size: size)
        }
        let frame = screen.frame
        return NSRect(
            x: frame.maxX - 1,
            y: frame.minY - size.height + 1,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Auth

    private func startAuthPolling() {
        authTimer?.invalidate()
        authTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollAuthState() }
        }
    }

    private func pollAuthState() {
        webView.evaluateJavaScript(JS.detectAuth) { [weak self] result, _ in
            guard let state = result as? String else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(authStateNamed: state)
                if state != "auth" { self.checkSignInWindowForSession() }
            }
        }
    }

    /// Reloads the monitoring view once the sign-in window has a session.
    ///
    /// The two views share a data store, so the session is already there; the
    /// monitoring view simply has a signed-out page on screen and no reason of
    /// its own to ask again. Once is enough -- after the reload its own check
    /// reports `auth` and this stops being consulted.
    private func checkSignInWindowForSession() {
        guard !hasReloadedForSignIn, let signInWebView else { return }
        signInWebView.evaluateJavaScript(JS.detectAuth) { [weak self] result, _ in
            guard result as? String == "auth" else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.hasReloadedForSignIn else { return }
                self.hasReloadedForSignIn = true
                print("TelegramWebEngine: signed in through the sign-in window, reloading the monitor")
                self.isMonitorInjectedForCurrentDocument = false
                self.webView.reload()
            }
        }
    }

    private func apply(authStateNamed state: String) {
        switch state {
        case "signIn":
            if authState != .signInRequired { authState = .signInRequired }
        case "auth":
            if authState != .authenticated {
                authState = .authenticated
                authenticationTime = Date()
                authTimer?.invalidate()
                authTimer = nil
                signInWebView = nil
                print("TelegramWebEngine: ✅ authenticated, injecting monitor")
                scheduleMonitorInjectionIfNeeded(delayNanoseconds: 1_500_000_000)
            } else {
                scheduleMonitorInjectionIfNeeded()
            }
        default:
            break
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
            guard self.authState == .authenticated, !self.isMonitorInjectedForCurrentDocument else { return }
            self.injectMessageMonitor()
        }
    }

    private func injectMessageMonitor() {
        webView.evaluateJavaScript(JS.messageMonitor) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    print("TelegramWebEngine: monitor injection failed: \(error)")
                } else {
                    self?.isMonitorInjectedForCurrentDocument = true
                    print("TelegramWebEngine: message monitor active ✅")
                }
            }
        }
    }

    // MARK: - Script messages

    func handleScriptMessage(_ message: WKScriptMessage) {
        guard message.name == "atollTG",
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        switch type {
        case "debug":
            print("TelegramWebEngine: \(dict["message"] as? String ?? "")")

        case "authState":
            apply(authStateNamed: dict["state"] as? String ?? "")

        case "newMessage":
            guard Defaults[.telegramEnabled] else { return }
            guard let chatId = dict["chatId"] as? String,
                  let sender = dict["sender"] as? String else { return }

            if let authenticationTime,
               Date().timeIntervalSince(authenticationTime) < Self.startupQuietPeriod {
                print("TelegramWebEngine: ⏭ skip startup: \(sender)")
                return
            }

            let body = (dict["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }

            let incoming = ChatIncomingMessage(
                id: dict["messageId"] as? String ?? "\(chatId)|\(body.hashValue)",
                text: body,
                groupSender: (dict["groupSender"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                timeLabel: (dict["time"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )

            deliver(
                incoming,
                sender: sender,
                chatId: chatId,
                avatar: (dict["avatarUrl"] as? String)?.nilIfEmpty
            )

        default:
            break
        }
    }

    // MARK: - Presentation

    private func deliver(_ message: ChatIncomingMessage, sender: String, chatId: String, avatar: String?) {
        let coordinator = DynamicIslandViewCoordinator.shared
        let pending = PendingMessage(sender: sender, messages: [message], chatId: chatId, avatarUrl: avatar)

        // A card is already up. If it belongs to this same chat the new line
        // joins it, so a run of messages reads as one conversation rather than
        // replacing itself; anything else waits its turn.
        if coordinator.expandingView.show,
           case .chat(.telegram, let visibleSender, let visibleMessages, let visibleChatId, let visibleAvatarUrl) = coordinator.expandingView.type {
            if visibleChatId == chatId {
                guard !visibleMessages.contains(where: { $0.id == message.id || $0.text == message.text }) else {
                    return
                }
                coordinator.toggleExpandingView(
                    status: true,
                    type: .chat(
                        service: .telegram,
                        senderName: visibleSender,
                        messages: visibleMessages + [message],
                        chatId: visibleChatId,
                        avatarUrl: visibleAvatarUrl ?? avatar
                    ),
                    autoHideDuration: 15
                )
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                return
            }

            let alreadyQueued = messageQueue.contains {
                $0.chatId == chatId && $0.messages.map(\.text) == [message.text]
            }
            if !alreadyQueued {
                messageQueue.append(pending)
                scheduleQueueDrain(coordinator: coordinator)
            }
            return
        }

        show(pending, coordinator: coordinator)
    }

    private func show(_ pending: PendingMessage, coordinator: DynamicIslandViewCoordinator) {
        print("TelegramWebEngine: 📩 \(pending.sender): \(pending.messages.map(\.text).joined(separator: " / "))")
        coordinator.cancelExpandingViewHide()
        coordinator.toggleExpandingView(
            status: true,
            type: .chat(
                service: .telegram,
                senderName: pending.sender,
                messages: pending.messages,
                chatId: pending.chatId,
                avatarUrl: pending.avatarUrl
            ),
            autoHideDuration: 15
        )
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
    }

    private func scheduleQueueDrain(coordinator: DynamicIslandViewCoordinator) {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(0.5))
                guard self != nil, !Task.isCancelled else { return }
                let showing = await MainActor.run { coordinator.expandingView.show }
                if !showing { break }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.drainTask = nil
                guard !self.messageQueue.isEmpty else { return }
                self.show(self.messageQueue.removeFirst(), coordinator: coordinator)
                if !self.messageQueue.isEmpty {
                    self.scheduleQueueDrain(coordinator: coordinator)
                }
            }
        }
    }

    private static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "TelegramWebEngine", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Navigation

extension TelegramWebEngine: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isMonitorInjectedForCurrentDocument = false
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Telegram is a single-page client: it signs in, swaps the whole page
        // for the chat list and never navigates again. So a finished load means
        // the monitor has to be re-established, and only the auth check can say
        // whether there is anything yet to monitor.
        pollAuthState()
        scheduleMonitorInjectionIfNeeded(delayNanoseconds: 1_500_000_000)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        authState = .error(error.localizedDescription)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("TelegramWebEngine: web content process terminated, reloading")
        isMonitorInjectedForCurrentDocument = false
        webView.reload()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Injected scripts

private enum JS {
    /// Makes the page believe it is on screen.
    ///
    /// `document.hidden` and `visibilityState` are what a web app checks before
    /// deciding it is in a background tab and can stop working. This engine's
    /// window is deliberately unviewable, which is the same thing as far as
    /// WebKit is concerned -- but not as far as the user is concerned, since
    /// they are waiting on their messages.
    static let forceVisible = """
    (function() {
        try {
            Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
            Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
            document.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
        } catch (e) {}
    })();
    """

    /// Reports sign-in state on a timer from inside the page, so a sign-in that
    /// completes between polls is noticed immediately.
    static let authCheck = """
    (function() {
        if (window.__atollTelegramAuthCheck) return;
        window.__atollTelegramAuthCheck = true;
        function check() {
            try {
                window.webkit.messageHandlers.atollTG.postMessage({
                    type: 'authState',
                    state: window.__atollTelegramAuthState()
                });
            } catch (e) {}
        }
        \(authStateFunction)
        check();
        setInterval(check, 3000);
    })();
    """

    static let detectAuth = """
    (function() {
        \(authStateFunction)
        return window.__atollTelegramAuthState();
    })()
    """

    /// Signed in is the chat list existing and being on screen. The sign-in
    /// flow mounts its own root instead, and while neither is up the client is
    /// still booting -- which is not a state worth reporting, since saying
    /// "sign in" too early would put a QR window in front of somebody who is
    /// already signed in.
    private static let authStateFunction = """
    window.__atollTelegramAuthState = function() {
        var chats = document.getElementById('page-chats');
        var chatList = document.querySelector('.chatlist, ul.chatlist');
        if (chats && chats.style.display !== 'none' && chatList) return 'auth';
        if (document.getElementById('auth-flow-root')
            || document.getElementById('auth-pages')
            || document.querySelector('.auth-page, [class*="authFlow"]')) return 'signIn';
        return 'loading';
    };
    """

    /// Reads the chat list on a timer and reports rows that have just become
    /// more unread than they were.
    ///
    /// Polling rather than a `MutationObserver`: Telegram rewrites a row's
    /// subtitle on every keystroke somebody types at the other end, on read
    /// receipts and on its own animations, so an observer fires constantly and
    /// still has to compare against a snapshot to know whether anything
    /// happened. Comparing on a timer is the same comparison, done a known
    /// number of times a second.
    static let messageMonitor = """
    (function() {
        if (window.__atollTelegramMonitor) return 'already';
        window.__atollTelegramMonitor = true;

        var ROW = '.chatlist-chat[data-peer-id], a.chatlist-chat, li.chatlist-chat';
        var seen = {};          // peerId -> { unread, text }
        var primed = false;     // first pass only records, never notifies

        function post(payload) {
            try { window.webkit.messageHandlers.atollTG.postMessage(payload); } catch (e) {}
        }

        function text(node) {
            return node ? (node.textContent || '').replace(/\\s+/g, ' ').trim() : '';
        }

        function unreadCount(row) {
            var badge = row.querySelector('.dialog-subtitle-badge-unread, .badge.unread, .dialog-subtitle-badge.badge');
            if (!badge) return 0;
            if (badge.classList.contains('dialog-subtitle-badge-pinned')) return 0;
            var n = parseInt(text(badge).replace(/[^0-9]/g, ''), 10);
            return isNaN(n) ? 0 : n;
        }

        function avatarUrl(row) {
            var img = row.querySelector('img.avatar-photo, avatar-element img, .avatar img');
            return img && img.src ? img.src : '';
        }

        // The row's title element and the time down its right-hand side share
        // the class `row-title`, so asking for that alone can hand back
        // "11:40" and whatever status glyph sits next to it. The peer's own
        // title is the thing wanted, and the details column is excluded by
        // name rather than hoped against.
        function title(row) {
            var el = row.querySelector('.row-title:not(.row-title-right) .peer-title')
                  || row.querySelector('.row-title:not(.row-title-right)')
                  || row.querySelector('.peer-title');
            if (!el) return '';
            var clone = el.cloneNode(true);
            var junk = clone.querySelectorAll('.dialog-title-details, .message-time, .message-status');
            for (var i = 0; i < junk.length; i++) { junk[i].remove(); }
            return text(clone);
        }

        // The time Telegram itself stamped the row with -- "11:40", or a day
        // name once it is older than that. It lives in the details column the
        // title deliberately excludes, so it is read from there by name and
        // shown as the service wrote it rather than reformatted here.
        function stamp(row) {
            var el = row.querySelector('.row-title-right .message-time, .message-time, .dialog-title-details .time');
            return el ? text(el) : '';
        }

        // Somebody typing is not a message. Telegram writes the indicator into
        // the same subtitle the preview comes from, so without this a card
        // announces "typing", and then announces the message underneath it as
        // a second line of the same conversation.
        function isTyping(row) {
            return !!row.querySelector('.peer-typing-container, .peer-typing');
        }

        // In a group the preview reads "Member: what they said". Telegram marks
        // the member's name as its own element, so the two are separated by
        // structure rather than by looking for a colon -- which would cut a
        // one-to-one message such as "no: absolutely not" in half.
        function preview(row) {
            var subtitle = row.querySelector('.row-subtitle, .dialog-subtitle .row-subtitle, .user-last-message');
            if (!subtitle) return { body: '', from: '' };
            var fromEl = subtitle.querySelector('.peer-title');
            var from = text(fromEl);
            var body = text(subtitle);
            if (from && body.indexOf(from) === 0) {
                body = body.slice(from.length).replace(/^\\s*:\\s*/, '');
            }
            return { body: body, from: from };
        }

        function scan() {
            var rows = document.querySelectorAll(ROW);
            if (!rows.length) return;

            for (var i = 0; i < rows.length; i++) {
                var row = rows[i];
                var peerId = row.dataset ? (row.dataset.peerId || '') : '';
                if (!peerId) continue;
                // No check for `.active` here. This client is Atoll's own and
                // nobody looks at it, so an open chat never means the user is
                // reading it -- it means Atoll just replied there. Treating
                // that as read discarded the chat's history every scan, and
                // the conversation you had just answered went quiet.

                if (isTyping(row)) continue;

                var unread = unreadCount(row);
                var p = preview(row);
                var previous = seen[peerId];
                seen[peerId] = { unread: unread, text: p.body };

                if (!primed || !previous) continue;
                if (unread === 0) continue;
                // Either the count went up, or it stayed put while the words
                // changed -- which is what a second message into an already
                // unread chat looks like when the badge is capped.
                if (unread <= previous.unread && p.body === previous.text) continue;
                if (!p.body) continue;

                post({
                    type: 'newMessage',
                    chatId: peerId,
                    messageId: peerId + '|' + p.body,
                    sender: title(row) || 'Telegram',
                    groupSender: p.from,
                    body: p.body,
                    time: stamp(row),
                    avatarUrl: avatarUrl(row)
                });
            }

            primed = true;
        }

        scan();
        setInterval(scan, 1200);
        post({ type: 'debug', message: 'chat list monitor running' });
        return 'ok';
    })();
    """

    /// Opens the chat, types into the composer and presses send.
    ///
    /// Three things make this fussier than it looks.
    ///
    /// The composer is a `contenteditable`, and Telegram tracks what is in it
    /// from the input events the browser raises as somebody types. So the text
    /// goes in through `insertText`, which raises them -- and when that is
    /// refused, because `execCommand` needs a focused editable in a document
    /// this offscreen window may not be able to give focus to, the content is
    /// set directly and the event raised by hand.
    ///
    /// Clicking send on an *empty* composer does not send nothing: it starts a
    /// voice recording. So the button is only clicked once the words are
    /// verifiably in the box, and never as a hopeful last resort.
    ///
    /// And the composer is shared by every chat, so typing before the right one
    /// is open types into whichever was open before. It waits for the row to go
    /// active rather than assuming the click took.
    ///
    /// Written as the body of an async function -- `chatId` and `body` arrive
    /// as arguments, which is also what keeps a reply full of quotes and
    /// newlines from having to be escaped into the source.
    static let sendReplyBody = """
    function sleep(ms) { return new Promise(function(r) { setTimeout(r, ms); }); }

    function row() {
        return document.querySelector('.chatlist-chat[data-peer-id="' + chatId + '"]');
    }

    function composer() {
        return document.querySelector('.chat:not(.hide) .input-message-input[contenteditable="true"]')
            || document.querySelector('.input-message-input[contenteditable="true"]');
    }

    function sendButton() {
        return document.querySelector('.chat:not(.hide) .btn-send')
            || document.querySelector('.btn-send');
    }

    function contents(input) {
        return (input.textContent || '').trim();
    }

    // The chat list opens a chat on mousedown, not on click -- so `.click()`
    // is heard by the handler that cancels the row's link and by nothing that
    // opens anything, which is why every reply failed with the chat never
    // opening. The whole press has to be delivered, with a button and
    // coordinates, since the handler reads both.
    function press(el) {
        var box = el.getBoundingClientRect();
        var x = box.left + box.width / 2;
        var y = box.top + box.height / 2;
        ['mousedown', 'mouseup', 'click'].forEach(function(type) {
            el.dispatchEvent(new MouseEvent(type, {
                bubbles: true,
                cancelable: true,
                view: window,
                button: 0,
                buttons: type === 'mousedown' ? 1 : 0,
                clientX: x,
                clientY: y
            }));
        });
    }

    var target = row();
    if (target) { press(target); } else { location.hash = '#' + chatId; }

    // Wait for this chat to be the open one, then for its composer. A chat
    // with no composer at all -- a channel you cannot post in -- gives up
    // rather than typing into the chat that was open before.
    var input = null;
    var everOpened = false;
    for (var waited = 0; waited < 8000; waited += 100) {
        var current = row();
        var isOpen = current ? current.classList.contains('active') : (location.hash === '#' + chatId);
        if (isOpen) {
            everOpened = true;
            input = composer();
            if (input) break;
        }
        await sleep(100);
    }
    if (!input) return everOpened ? 'no-composer-in-chat' : 'chat-did-not-open';

    input.focus();
    try {
        document.execCommand('selectAll', false, null);
        document.execCommand('insertText', false, body);
    } catch (e) {}

    if (contents(input) !== body.trim()) {
        // No focus to command, so put the text in and tell Telegram it was
        // typed. Its input handler reads the element, not the event.
        input.textContent = body;
        input.dispatchEvent(new InputEvent('input', { bubbles: true, data: body, inputType: 'insertText' }));
    }

    await sleep(120);

    if (!contents(input)) return 'composer-stayed-empty';

    var button = sendButton();
    if (!button) return 'no-send-button';
    button.click();

    // Telegram empties the composer when it accepts a message, so an empty box
    // is the confirmation. Anything else and the words are still sitting there
    // unsent, which the card should say rather than claim success.
    // Leaving the chat again is not tidiness, it is the whole point. While
    // this client sits in a conversation Telegram marks everything that
    // arrives there as read -- on the account, so it reads as read on the
    // phone too -- and the row's unread badge never leaves zero, which is
    // what the monitor watches. Replying to somebody once would otherwise
    // silence them for good. Opening a chat pushes a navigation item whose
    // pop closes it, and Escape is what pops it.
    async function leaveChat() {
        try { input.blur(); } catch (e) {}
        for (var tries = 0; tries < 8; tries++) {
            window.dispatchEvent(new KeyboardEvent('keydown', {
                key: 'Escape', code: 'Escape', keyCode: 27, which: 27,
                bubbles: true, cancelable: true
            }));
            await sleep(150);
            var open = row();
            if (!open || !open.classList.contains('active')) return true;
        }
        return false;
    }

    for (var settle = 0; settle < 3000; settle += 100) {
        if (!contents(input)) {
            await leaveChat();
            return 'sent';
        }
        await sleep(100);
    }
    await leaveChat();
    return 'still-in-composer';
    """
}
