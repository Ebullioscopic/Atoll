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

import AppKit
import Combine
import Foundation
import MediaPlayer
import WebKit

/// Drives Spotify's Web Playback SDK inside a hidden WKWebView so Atoll can play
/// audio itself (a Spotify Connect device named "Atoll") without the desktop app.
/// Requires Spotify Premium and the `streaming` OAuth scope. The web view is the
/// audio sink; `deviceID` (set on the SDK `ready` event) is the target for
/// `SpotifyWebAPIClient.startPlayback(deviceID:)`.
@MainActor
final class SpotifyPlayerManager: ObservableObject {
    static let shared = SpotifyPlayerManager()

    @Published private(set) var deviceID: String?
    @Published private(set) var isReady = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isPaused = true
    @Published private(set) var currentTrack: String?
    @Published private(set) var currentArtist: String?
    @Published private(set) var currentTrackURI: String?
    @Published private(set) var artworkURL: String?

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var commandsConfigured = false
    private(set) var currentDuration: Double = 0
    private(set) var currentPosition: Double = 0
    private(set) var lastStateDate: Date = Date()
    /// Build the hidden web view and connect the SDK once. No-op if a player already
    /// exists (prevents duplicate "Atoll" devices) or if not authenticated.
    func start() {
        guard webView == nil, SpotifyOAuthManager.shared.isAuthenticated else { return }

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []   // allow SDK autoplay
        let ucc = WKUserContentController()
        ucc.add(MessageProxy(self), name: "spotify")
        config.userContentController = ucc

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        self.webView = web

        // WebKit suspends a web view that is off-screen or fully occluded, which kills the
        // Spotify Connect device (RBS assertion failures / NearSuspended). Host it in a 1×1,
        // ~invisible, click-through window that is genuinely ON-screen and on top, so the
        // web process — and thus the device + audio — stays alive.
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let win = NSWindow(contentRect: CGRect(x: screen.minX, y: screen.minY, width: 1, height: 1),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.ignoresMouseEvents = true
        win.hasShadow = false
        win.alphaValue = 0.02
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.contentView = web
        win.orderFrontRegardless()
        self.hostWindow = win

        // An https baseURL gives the page a secure context (EME/DRM requires it).
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://atoll.localhost/"))
        NSLog("[SpotifyPlayer] start: loading Web Playback SDK page (on-screen)")
    }

    func stop() {
        webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.disconnect();", completionHandler: nil)
        hostWindow?.orderOut(nil)
        hostWindow = nil
        webView = nil
        isReady = false
        deviceID = nil
        currentTrackURI = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    /// Tear down and reconnect so the SDK picks up a freshly-scoped token (e.g. after re-Connect).
    func restart() {
        stop()
        statusMessage = nil
        start()
    }

    // MARK: - Optional transport (the tab can drive the in-app player directly)
    func togglePlay() { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.togglePlay();", completionHandler: nil) }
    func nextTrack() { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.nextTrack();", completionHandler: nil) }
    func previousTrack() { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.previousTrack();", completionHandler: nil) }
    func resume() { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.resume();", completionHandler: nil) }
    func pause() { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.pause();", completionHandler: nil) }
    func seek(toMilliseconds ms: Double) { webView?.evaluateJavaScript("window.__atollPlayer && window.__atollPlayer.seek(\(Int(ms)));", completionHandler: nil) }

    // MARK: - System now-playing (Control Center / media keys / notch)
    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.nextTrack(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.previousTrack(); return .success }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard isReady, let title = currentTrack, !title.isEmpty else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: currentArtist ?? "",
            MPMediaItemPropertyPlaybackDuration: currentDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0
        ]
        center.nowPlayingInfo = info
        center.playbackState = isPaused ? .paused : .playing

        if let urlStr = artworkURL, let url = URL(string: urlStr) {
            Task { [weak self] in
                guard let data = try? await URLSession.shared.data(from: url).0,
                      let image = NSImage(data: data) else { return }
                await MainActor.run {
                    guard let self, self.currentTrack == title else { return }
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                    updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }
        }
    }

    // MARK: - JS -> Swift bridge
    fileprivate func handle(_ body: [String: Any]) {
        switch body["type"] as? String ?? "" {
        case "token_request":
            Task { [weak self] in
                let token = await SpotifyOAuthManager.shared.validAccessToken() ?? ""
                self?.webView?.evaluateJavaScript("window.__atollProvideToken('\(token)')", completionHandler: nil)
            }
        case "ready":
            deviceID = body["device_id"] as? String
            isReady = true
            statusMessage = nil
            configureRemoteCommands()
            NSLog("[SpotifyPlayer] READY device_id=%@", deviceID ?? "nil")
        case "not_ready":
            isReady = false
            NSLog("[SpotifyPlayer] not_ready (device went offline)")
        case "state":
            isPaused = body["paused"] as? Bool ?? true
            currentTrack = body["track"] as? String
            currentArtist = body["artist"] as? String
            currentTrackURI = body["uri"] as? String
            artworkURL = body["image"] as? String
            currentDuration = ((body["duration"] as? Double) ?? 0) / 1000
            currentPosition = ((body["position"] as? Double) ?? 0) / 1000
            lastStateDate = Date()
            updateNowPlaying()
        case "error":
            let kind = body["kind"] as? String ?? "?"
            let message = body["message"] as? String ?? ""
            NSLog("[SpotifyPlayer] ERROR %@: %@", kind, message)
            statusMessage = kind == "account"
                ? String(localized: "In-app playback needs Spotify Premium.")
                : "Player error (\(kind)): \(message)"
        case let other:
            NSLog("[SpotifyPlayer] event %@: %@", other, String(describing: body))
        }
    }

    // MARK: - SDK page
    private static let html = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"></head><body>
    <script src="https://sdk.scdn.co/spotify-player.js"></script>
    <script>
      var __tokenCbs = [];
      window.__atollProvideToken = function(token) {
        var cbs = __tokenCbs; __tokenCbs = [];
        for (var i = 0; i < cbs.length; i++) { cbs[i](token); }
      };
      function post(msg) {
        try { window.webkit.messageHandlers.spotify.postMessage(msg); } catch (e) {}
      }
      function updateMediaSession(s) {
        if (!('mediaSession' in navigator)) return;
        var t = (s && s.track_window && s.track_window.current_track) ? s.track_window.current_track : null;
        if (t) {
          try {
            navigator.mediaSession.metadata = new MediaMetadata({
              title: t.name || '',
              artist: (t.artists || []).map(function(a){ return a.name; }).join(', '),
              album: (t.album && t.album.name) ? t.album.name : '',
              artwork: ((t.album && t.album.images) ? t.album.images : []).map(function(i){ return { src: i.url }; })
            });
          } catch (e) {}
        }
        try { navigator.mediaSession.playbackState = (s && s.paused) ? 'paused' : 'playing'; } catch (e) {}
        try {
          if (navigator.mediaSession.setPositionState && s && s.duration) {
            navigator.mediaSession.setPositionState({ duration: s.duration/1000, position: (s.position||0)/1000, playbackRate: 1 });
          }
        } catch (e) {}
      }
      function setupMediaSessionHandlers(player) {
        if (!('mediaSession' in navigator)) return;
        var ms = navigator.mediaSession;
        function set(a, fn) { try { ms.setActionHandler(a, fn); } catch (e) {} }
        set('play', function(){ player.resume(); });
        set('pause', function(){ player.pause(); });
        set('previoustrack', function(){ player.previousTrack(); });
        set('nexttrack', function(){ player.nextTrack(); });
        set('seekto', function(d){ if (d && d.seekTime != null) player.seek(d.seekTime * 1000); });
      }
      window.addEventListener('error', function(e) {
        post({ type: 'error', kind: 'js', message: '' + (e && e.message ? e.message : e) });
      });
      window.onSpotifyWebPlaybackSDKReady = function() {
        post({ type: 'sdk_ready' });
        var player = new Spotify.Player({
          name: 'Atoll',
          getOAuthToken: function(cb) { __tokenCbs.push(cb); post({ type: 'token_request' }); },
          volume: 0.8
        });
        setupMediaSessionHandlers(player);
        player.addListener('ready', function(d) { post({ type: 'ready', device_id: d.device_id }); });
        player.addListener('not_ready', function(d) { post({ type: 'not_ready', device_id: d.device_id }); });
        player.addListener('player_state_changed', function(s) {
          updateMediaSession(s);
          var t = (s && s.track_window && s.track_window.current_track) ? s.track_window.current_track : null;
          post({ type: 'state',
                 paused: s ? s.paused : true,
                 position: s ? s.position : 0,
                 duration: s ? s.duration : 0,
                 track: t ? t.name : null,
                 artist: t ? (t.artists || []).map(function(a){ return a.name; }).join(', ') : null,
                 uri: t ? t.uri : null,
                 image: (t && t.album && t.album.images && t.album.images[0]) ? t.album.images[0].url : null });
        });
        player.addListener('initialization_error', function(e) { post({ type: 'error', kind: 'init', message: e.message }); });
        player.addListener('authentication_error', function(e) { post({ type: 'error', kind: 'auth', message: e.message }); });
        player.addListener('account_error', function(e) { post({ type: 'error', kind: 'account', message: e.message }); });
        player.addListener('playback_error', function(e) { post({ type: 'error', kind: 'playback', message: e.message }); });
        window.__atollPlayer = player;
        player.connect().then(function(ok) { post({ type: 'connect', ok: ok }); });
      };
    </script>
    </body></html>
    """
}

/// Weak proxy so the user-content-controller (which strongly retains its handlers)
/// doesn't create a retain cycle with the manager.
@MainActor
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: SpotifyPlayerManager?
    init(_ target: SpotifyPlayerManager) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        target?.handle(body)
    }
}
