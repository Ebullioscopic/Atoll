/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Foundation

// MARK: - HTTP Client
final class YouTubeMusicHTTPClient: ObservableObject {
    private let session: URLSession
    private let baseURL: String
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
    
    init(baseURL: String) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Authentication
    func authenticate() async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/DynamicIsland") else {
            throw YouTubeMusicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        let authResponse: AuthResponse = try Self.decoder.decode(AuthResponse.self, from: data)
        return authResponse.accessToken
    }
    
    // MARK: - Playback Info
    func getPlaybackInfo(token: String) async throws -> PlaybackResponse {
        let data = try await sendCommand(
            endpoint: "/song",
            method: "GET",
            token: token
        )
        return try Self.decoder.decode(PlaybackResponse.self, from: data)
    }
    
    // MARK: - Commands
    func sendCommand(
        endpoint: String,
        method: String = "POST",
        body: (any Codable & Sendable)? = nil,
        token: String
    ) async throws -> Data {
        let request = try createAuthenticatedRequest(
            endpoint: "/api/v1\(endpoint)",
            method: method,
            body: body,
            token: token
        )
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        return data
    }
    
    // MARK: - Private Helpers
    private func createAuthenticatedRequest(
        endpoint: String,
        method: String,
        body: (any Codable & Sendable)? = nil,
        token: String
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw YouTubeMusicError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw YouTubeMusicError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw YouTubeMusicError.authenticationRequired
        default:
            throw YouTubeMusicError.httpError(httpResponse.statusCode)
        }
    }
}

// MARK: - WebSocket Client
actor YouTubeMusicWebSocketClient {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let onMessage: @Sendable (Data) async -> Void
    private let onDisconnect: @Sendable (URLSessionWebSocketTask.CloseCode?, Data?) async -> Void
    private var authenticated = false
    private var isIntentionalDisconnect = false
    private var lastCloseCode: URLSessionWebSocketTask.CloseCode?
    private var lastCloseReason: Data?
    
    var isConnected: Bool { task?.state == .running }
    var isAuthenticated: Bool { authenticated }
    var closeCode: URLSessionWebSocketTask.CloseCode? { lastCloseCode }
    var closeReason: Data? { lastCloseReason }
    
    init(
        onMessage: @escaping @Sendable (Data) async -> Void,
        onDisconnect: @escaping @Sendable (URLSessionWebSocketTask.CloseCode?, Data?) async -> Void,
        session: URLSession = .shared
    ) {
        self.onMessage = onMessage
        self.onDisconnect = onDisconnect
        self.session = session
    }
    
    func connect(to url: URL, with token: String) async throws {
        await disconnect()
        
        // URL already has token query param from WebSocketURLBuilder.buildURL
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let newTask = session.webSocketTask(with: request)
        task = newTask
        authenticated = false
        isIntentionalDisconnect = false
        newTask.resume()
        
        Task { await listenForMessages() }
    }
    
    func disconnect() async {
        isIntentionalDisconnect = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        authenticated = false
    }
    
    private func listenForMessages() async {
        guard let currentTask = task else { return }
        
        while !Task.isCancelled && task != nil {
            do {
                let message = try await currentTask.receive()
                
                let data: Data
                switch message {
                case .data(let d):
                    data = d
                case .string(let s):
                    data = s.data(using: .utf8) ?? Data()
                @unknown default:
                    continue
                }
                
                if let wsMessage = WebSocketMessage(from: data), !authenticated {
                    if wsMessage.type == .playerInfo || wsMessage.type == .videoChanged || wsMessage.type == .playerStateChanged {
                        authenticated = true
                    }
                }
                
                await onMessage(data)
            } catch {
                break
            }
        }
        
        // Capture close code before clearing task
        lastCloseCode = task?.closeCode
        lastCloseReason = task?.closeReason
        
        let closeCode = lastCloseCode
        let closeReason = lastCloseReason
        task = nil
        
        // Only call onDisconnect for unexpected closures, not intentional disconnects
        if !isIntentionalDisconnect {
            await onDisconnect(closeCode, closeReason)
        }
    }
}

// MARK: - WebSocket URL Helper
struct WebSocketURLBuilder {
    static func buildURL(from baseURL: String, with token: String? = nil) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }

        switch components.scheme {
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            break
        }

        components.path = "/api/v1/ws"
        
        if let token = token {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        
        return components.url
    }
}

// MARK: - Errors
enum YouTubeMusicError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case authenticationRequired
    case webSocketNotConnected
    case encodingFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .authenticationRequired:
            return "Authentication required"
        case .webSocketNotConnected:
            return "WebSocket not connected"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        }
    }
}
