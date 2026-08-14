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

import Foundation
import Network
import Defaults

/// WebSocket server for Atoll RPC.
/// Uses Apple's Network.framework (`NWListener`) — no external dependencies.
/// Listens on localhost:9020 for JSON-RPC 2.0 requests over WebSocket.
///
/// ## Loopback only, and checked twice
/// `NWListener(using:on:)` binds the **wildcard** address, so this port used to
/// accept connections from anything on the same network — a client identifies
/// itself by simply stating a `bundleIdentifier`, so a machine on the café Wi-Fi
/// could drive the extension API. It is now bound to the loopback address of
/// each family, and every accepted connection's peer is checked as well: a bind
/// is one line away from being widened by accident, and the check costs nothing.
///
/// Two listeners rather than one because a socket bound to `127.0.0.1` does not
/// accept `::1` and vice versa, and a client resolving "localhost" may arrive on
/// either. Each is optional: on a Mac with one family disabled the other still
/// serves.
@MainActor
final class ExtensionRPCServer {
    static let shared = ExtensionRPCServer()

    private var listeners: [NWListener] = []
    private var connections: [UUID: RPCClientConnection] = [:]
    private var shelfSubscribers: Set<String> = [] // bundleIdentifiers subscribed to shelf events
    private let port: UInt16 = 9020
    private let queue = DispatchQueue(label: "com.ebullioscopic.Atoll.rpc.server", qos: .userInitiated)
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard listeners.isEmpty else {
            logDiagnostics("RPC server already running")
            return
        }

        for host in Self.loopbackHosts {
            if let listener = makeListener(boundTo: host) {
                listeners.append(listener)
                listener.start(queue: queue)
            }
        }

        if listeners.isEmpty {
            Logger.log("RPC server could not bind to loopback on port \(port)", category: .extensions)
        }
    }

    /// The loopback address of each family. Both are attempted; one is enough.
    private static let loopbackHosts: [NWEndpoint.Host] = [
        .ipv4(.loopback),
        .ipv6(.loopback)
    ]

    private func makeListener(boundTo host: NWEndpoint.Host) -> NWListener? {
        let params = NWParameters(tls: nil)
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        // Without this the listener takes the wildcard address and the port is
        // reachable from the local network.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: host,
            port: NWEndpoint.Port(integerLiteral: port)
        )
        params.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            // The port comes from `requiredLocalEndpoint`, and passing it again
            // as `on:` is rejected outright: the two ways of saying where to
            // bind may not be combined.
            listener = try NWListener(using: params)
        } catch {
            Logger.log(
                "Failed to create RPC listener on \(host): \(error.localizedDescription)",
                category: .extensions
            )
            return nil
        }

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleListenerState(state, host: host)
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleNewConnection(connection)
            }
        }

        return listener
    }

    /// Rebinds without disturbing clients that are still connected: a listener
    /// failing says nothing about the connections it already handed over.
    private func restartListeners() {
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        start()
    }

    func stop() {
        for listener in listeners {
            listener.cancel()
        }
        listeners.removeAll()
        for (_, conn) in connections {
            conn.connection.cancel()
        }
        connections.removeAll()
        shelfSubscribers.removeAll()
        logDiagnostics("RPC server stopped")
    }

    // MARK: - Client Notifications

    func notifyActivityDismiss(bundleIdentifier: String, activityID: String) {
        sendNotification(
            to: bundleIdentifier,
            method: "atoll.activityDidDismiss",
            params: [
                "bundleIdentifier": .string(bundleIdentifier),
                "activityID": .string(activityID)
            ]
        )
    }

    func notifyWidgetDismiss(bundleIdentifier: String, widgetID: String) {
        sendNotification(
            to: bundleIdentifier,
            method: "atoll.widgetDidDismiss",
            params: [
                "bundleIdentifier": .string(bundleIdentifier),
                "widgetID": .string(widgetID)
            ]
        )
    }

    func notifyNotchExperienceDismiss(bundleIdentifier: String, experienceID: String) {
        sendNotification(
            to: bundleIdentifier,
            method: "atoll.notchExperienceDidDismiss",
            params: [
                "bundleIdentifier": .string(bundleIdentifier),
                "experienceID": .string(experienceID)
            ]
        )
    }

    func notifyAuthorizationChange(bundleIdentifier: String, isAuthorized: Bool) {
        sendNotification(
            to: bundleIdentifier,
            method: "atoll.authorizationDidChange",
            params: [
                "bundleIdentifier": .string(bundleIdentifier),
                "isAuthorized": .bool(isAuthorized)
            ]
        )
    }

    // MARK: - Shelf Event Subscriptions

    func registerShelfSubscription(for bundleIdentifier: String) {
        shelfSubscribers.insert(bundleIdentifier)
        logDiagnostics("Registered shelf subscription for \(bundleIdentifier)")
    }

    func notifyShelfItemsChanged(itemIDs: [String], action: String) {
        guard !shelfSubscribers.isEmpty else { return }
        let params: [String: RPCValue] = [
            "action": .string(action),
            "itemIDs": .array(itemIDs.map { .string($0) })
        ]
        for subscriber in shelfSubscribers {
            sendNotification(
                to: subscriber,
                method: "atoll.shelfItemsDidChange",
                params: params
            )
        }
        logDiagnostics("Notified \(shelfSubscribers.count) subscriber(s) of shelf change (\(action), \(itemIDs.count) items)")
    }

    // MARK: - Connection Handling

    private func handleListenerState(_ state: NWListener.State, host: NWEndpoint.Host) {
        switch state {
        case .ready:
            Logger.log("Started Atoll RPC WebSocket server on \(host):\(port)", category: .extensions)
        case .failed(let error):
            Logger.log(
                "RPC server on \(host) failed: \(error.localizedDescription)",
                category: .extensions
            )
            // Restart both families rather than the failed one alone: the state
            // handler cannot say which listener it belongs to, and a half-open
            // server is harder to reason about than a restarted one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.restartListeners()
            }
        case .cancelled:
            logDiagnostics("RPC server listener on \(host) cancelled")
        default:
            break
        }
    }

    private func handleNewConnection(_ nwConnection: NWConnection) {
        // Belt and braces: the listener is bound to loopback, and anything that
        // still arrives from elsewhere is dropped before it can send a byte.
        guard Self.isLoopback(nwConnection.endpoint) else {
            Logger.log(
                "Refused an RPC connection from \(nwConnection.endpoint) — this server is local-only",
                category: .extensions
            )
            nwConnection.cancel()
            return
        }

        let connID = UUID()
        let clientConn = RPCClientConnection(
            id: connID,
            connection: nwConnection,
            bundleIdentifier: nil
        )
        connections[connID] = clientConn

        nwConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(connID: connID, state: state)
            }
        }

        nwConnection.start(queue: queue)
        receiveMessage(connID: connID)
        logDiagnostics("RPC client connected (id: \(connID.uuidString.prefix(8)))")
    }

    /// Whether a peer is on this Mac.
    ///
    /// Pure and static so the interesting cases — an IPv4-mapped IPv6 peer that
    /// *is* loopback, a LAN address that merely starts with 127 in text form —
    /// can be decided by a test rather than by reading the code and hoping.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        switch endpoint {
        case .hostPort(let host, _):
            return isLoopback(host)
        case .unix:
            // A filesystem socket is as local as it gets.
            return true
        default:
            return false
        }
    }

    static func isLoopback(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let address):
            return address.isLoopback
        case .ipv6(let address):
            // `::ffff:127.0.0.1` arrives on a dual-stack socket and is loopback,
            // however little it looks like it.
            if let mapped = address.asIPv4 { return mapped.isLoopback }
            return address.isLoopback
        case .name(let name, _):
            return name == "localhost" || name == "localhost."
        @unknown default:
            return false
        }
    }

    private func handleConnectionState(connID: UUID, state: NWConnection.State) {
        switch state {
        case .failed, .cancelled:
            connections.removeValue(forKey: connID)
            logDiagnostics("RPC client disconnected (id: \(connID.uuidString.prefix(8)))")
        default:
            break
        }
    }

    private func receiveMessage(connID: UUID) {
        guard let clientConn = connections[connID] else { return }
        let connection = clientConn.connection

        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.logDiagnostics("RPC receive error for \(connID.uuidString.prefix(8)): \(error.localizedDescription)")
                    self.connections.removeValue(forKey: connID)
                }
                return
            }

            if let data = content, !data.isEmpty {
                Task { @MainActor in
                    await self.processMessage(data: data, connID: connID)
                }
            }

            // Continue receiving
            Task { @MainActor in
                self.receiveMessage(connID: connID)
            }
        }
    }

    private func processMessage(data: Data, connID: UUID) async {
        guard var clientConn = connections[connID] else { return }

        // Parse JSON-RPC request
        guard let request = try? decoder.decode(RPCRequest.self, from: data) else {
            let errorResponse = RPCErrorResponse(
                error: RPCErrorObject(code: RPCErrorCode.parseError, message: "Invalid JSON-RPC request"),
                id: nil
            )
            sendResponse(errorResponse, to: connID)
            return
        }

        // Resolve bundle identifier from first authorization request
        if clientConn.bundleIdentifier == nil,
           let params = request.params,
           let bi = params["bundleIdentifier"]?.stringValue {
            clientConn.bundleIdentifier = bi
            connections[connID] = clientConn
        }

        let service = ExtensionRPCService(
            bundleIdentifier: clientConn.bundleIdentifier ?? "unknown",
            server: self
        )

        let responseData = await service.handleRequest(request)
        sendRawData(responseData, to: connID)
    }

    // MARK: - Send Helpers

    private func sendResponse(_ response: Codable, to connID: UUID) {
        guard let data = try? encoder.encode(response) else { return }
        sendRawData(data, to: connID)
    }

    private func sendRawData(_ data: Data, to connID: UUID) {
        guard let clientConn = connections[connID] else { return }

        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "rpc-response", metadata: [metadata])

        clientConn.connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { error in
                if let error {
                    Task { @MainActor in
                        self.logDiagnostics("RPC send error: \(error.localizedDescription)")
                    }
                }
            }
        )
    }

    private func sendNotification(to bundleIdentifier: String, method: String, params: [String: RPCValue]) {
        let notification = RPCNotification(method: method, params: params)
        guard let data = try? encoder.encode(notification) else { return }

        for (_, clientConn) in connections where clientConn.bundleIdentifier == bundleIdentifier {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "rpc-notification", metadata: [metadata])

            clientConn.connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { _ in }
            )
        }
    }

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }
}

// MARK: - Client Connection

struct RPCClientConnection {
    let id: UUID
    let connection: NWConnection
    var bundleIdentifier: String?
}
