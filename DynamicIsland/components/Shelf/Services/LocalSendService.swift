/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import Network
import Defaults
import UniformTypeIdentifiers
import Darwin

struct LocalSendDeviceInfo: Identifiable, Hashable, Sendable {
    let id: String
    let alias: String
    let ip: String
    let port: Int
    let https: Bool
    let model: String?

    var displayName: String {
        if let model, !model.isEmpty {
            return "\(alias) (\(model))"
        }
        return alias
    }

    var baseURL: String {
        let scheme = https ? "https" : "http"
        return "\(scheme)://\(ip):\(port)"
    }
}

enum LocalSendTransferState: Equatable {
    case idle
    case sending
    case completed
    case failed(String)
    case rejected(deviceID: String)
}

@MainActor
final class LocalSendService: NSObject, ObservableObject {
    static let shared = LocalSendService()

    @Published private(set) var devices: [LocalSendDeviceInfo] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSending = false
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var transferState: LocalSendTransferState = .idle
    @Published private(set) var rejectedDeviceIDs: Set<String> = []
    @Published var selectedDeviceID: String {
        didSet { Defaults[.localSendSelectedDeviceID] = selectedDeviceID }
    }

    private let multicastGroupHost = "224.0.0.167"
    private let defaultPort = 53317
    private var connectionGroup: NWConnectionGroup?
    private var registerListener: NWListener?
    private var cleanupTask: Task<Void, Never>?
    private var announceTask: Task<Void, Never>?
    private var activeRefreshTask: Task<Void, Never>?
    private var refreshSessionID = UUID()
    private var discoveredByID: [String: (device: LocalSendDeviceInfo, lastSeen: Date)] = [:]
    private var recentProbeIPs: [String] = []
    private var knownPeerIPs: [String] = []
    private var isStarted = false
    private var completionDismissTask: Task<Void, Never>?

    private override init() {
        selectedDeviceID = Defaults[.localSendSelectedDeviceID]
        super.init()
    }
    
    func clearRejectedStatus(for deviceID: String) {
        rejectedDeviceIDs.remove(deviceID)
    }
    
    func clearAllRejectedStatuses() {
        rejectedDeviceIDs.removeAll()
    }

    func startDiscovery() {
        guard !isStarted else { return }
        isStarted = true

        startRegisterListenerIfNeeded()

        do {
            let group = try NWMulticastGroup(for: [
                .hostPort(
                    host: .init(multicastGroupHost),
                    port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(defaultPort))
                )
            ])
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            let connectionGroup = NWConnectionGroup(with: group, using: params)
            connectionGroup.setReceiveHandler(maximumMessageSize: 65_536) { [weak self] message, content, _ in
                guard let content, let self else { return }
                Task { @MainActor in
                    self.handleIncoming(content: content, endpoint: message.remoteEndpoint)
                }
            }

            connectionGroup.stateUpdateHandler = { _ in }
            connectionGroup.start(queue: .global(qos: .utility))
            self.connectionGroup = connectionGroup

            sendAnnouncement()

            cleanupTask = Task { [weak self] in
                while let self, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    self.cleanupStale()
                }
            }

            announceTask = Task { [weak self] in
                while let self, !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    self.sendAnnouncement()
                }
            }
        } catch {
            Logger.log("LocalSend discovery start failed: \(error.localizedDescription)", category: .extensions)
        }
    }

    func refreshDeviceScan() {
        activeRefreshTask?.cancel()
        startDiscovery()

        let sessionID = UUID()
        refreshSessionID = sessionID
        isRefreshing = true

        // Keep listener state and run a LocalSend-like refresh sequence:
        // multicast announce burst first, then targeted/fallback HTTP discovery.
        activeRefreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }

            let startedAt = Date()
            defer {
                if self.refreshSessionID == sessionID {
                    self.isRefreshing = false
                    self.activeRefreshTask = nil
                }
            }

            let burstDelays: [UInt64] = [100_000_000, 500_000_000, 2_000_000_000]
            for delay in burstDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self.sendAnnouncement()
            }

            guard !Task.isCancelled else { return }
            await self.probeNearbyDevicesDirectly(limit: 20, timeout: 0.14)

            guard !Task.isCancelled else { return }
            if !self.hasFreshDiscovery(since: startedAt),
               let localIP = self.ownIPv4Address() {
                await self.probeLocalSubnetLegacy(localIP: localIP, timeout: 0.12)
            }

            guard !Task.isCancelled else { return }
            self.pruneUnavailableDevices(since: startedAt)
        }
    }

    private func pruneUnavailableDevices(since date: Date) {
        let previousCount = discoveredByID.count
        discoveredByID = discoveredByID.filter { $0.value.lastSeen >= date }
        if discoveredByID.count != previousCount {
            refreshDevices()
        }
    }

    private func probeNearbyDevicesDirectly(limit: Int = 12, timeout: TimeInterval = 0.14) async {
        let port = defaultPort
        let candidates = candidateIPsForActiveProbe(limit: max(1, limit))
        guard !candidates.isEmpty else { return }
        let deadline = Date().addingTimeInterval(1.0)

        await withTaskGroup(of: LocalSendDeviceInfo?.self) { group in
            let maxConcurrent = 4
            var iterator = candidates.makeIterator()

            for _ in 0 ..< min(maxConcurrent, candidates.count) {
                guard let ip = iterator.next() else { break }
                group.addTask {
                    await Self.probeDeviceInfo(at: ip, port: port, timeout: 0.14)
                }
            }

            while let result = await group.next() {
                if Date() > deadline {
                    group.cancelAll()
                    return
                }

                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }

                if let device = result {
                    discoveredByID[device.id] = (device, Date())
                    rememberKnownPeerIP(device.ip)
                    rememberRecentProbeIP(device.ip)
                }

                if let ip = iterator.next() {
                    group.addTask {
                        await Self.probeDeviceInfo(at: ip, port: port, timeout: timeout)
                    }
                }
            }
        }

        refreshDevices()
    }

    private func candidateIPsForActiveProbe(limit: Int) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        if let selected = devices.first(where: { $0.id == selectedDeviceID })?.ip,
           seen.insert(selected).inserted {
            ordered.append(selected)
        }

        for ip in recentProbeIPs where seen.insert(ip).inserted {
            ordered.append(ip)
        }

        for ip in discoveredByID.values.map(\.device.ip) where seen.insert(ip).inserted {
            ordered.append(ip)
        }

        for ip in knownPeerIPs where seen.insert(ip).inserted {
            ordered.append(ip)
        }

        if ordered.count > limit {
            return Array(ordered.prefix(limit))
        }
        return ordered
    }

    private func probeLocalSubnetLegacy(localIP: String, timeout: TimeInterval) async {
        guard isValidIPv4(localIP) else { return }
        let parts = localIP.split(separator: ".")
        guard parts.count == 4 else { return }

        let prefix = parts.prefix(3).joined(separator: ".")
        let host = Int(parts[3]) ?? 0
        let candidates = (1 ... 254)
            .filter { $0 != host }
            .map { "\(prefix).\($0)" }

        await probeExactIPs(candidates, timeout: timeout, concurrency: 50)
    }

    private func probeExactIPs(_ ips: [String], timeout: TimeInterval, concurrency: Int) async {
        let port = defaultPort
        let unique = Array(NSOrderedSet(array: ips).compactMap { $0 as? String })
        guard !unique.isEmpty else { return }

        await withTaskGroup(of: LocalSendDeviceInfo?.self) { group in
            var iterator = unique.makeIterator()

            for _ in 0 ..< min(max(1, concurrency), unique.count) {
                guard let ip = iterator.next() else { break }
                group.addTask {
                    await Self.probeDeviceInfo(at: ip, port: port, timeout: timeout)
                }
            }

            while let result = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }

                if let device = result {
                    discoveredByID[device.id] = (device, Date())
                    rememberKnownPeerIP(device.ip)
                    rememberRecentProbeIP(device.ip)
                }

                if let ip = iterator.next() {
                    group.addTask {
                        await Self.probeDeviceInfo(at: ip, port: port, timeout: timeout)
                    }
                }
            }
        }

        refreshDevices()
    }

    private func hasFreshDiscovery(since date: Date) -> Bool {
        discoveredByID.values.contains { $0.lastSeen >= date }
    }

    private nonisolated static func probeDeviceInfo(at ip: String, port: Int, timeout: TimeInterval) async -> LocalSendDeviceInfo? {
        let schemes = ["http", "https"]
        let paths = ["/api/localsend/v2/info"]

        for scheme in schemes {
            for path in paths {
                guard var components = URLComponents(string: "\(scheme)://\(ip):\(port)\(path)") else { continue }
                components.queryItems = [
                    URLQueryItem(name: "fingerprint", value: "atoll.localsend.bridge")
                ]
                guard let url = components.url else { continue }

                var request = URLRequest(url: url)
                request.timeoutInterval = timeout
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

                do {
                    let (data, response) = try await probeSession.data(for: request)
                    guard let http = response as? HTTPURLResponse,
                          (200 ... 299).contains(http.statusCode),
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let fingerprint = json["fingerprint"] as? String,
                          let alias = json["alias"] as? String,
                          fingerprint != "atoll.localsend.bridge"
                    else {
                        continue
                    }

                    let model = json["deviceModel"] as? String
                    let usesHTTPS = (json["protocol"] as? String) == "https" || scheme == "https"

                    return LocalSendDeviceInfo(
                        id: fingerprint,
                        alias: alias,
                        ip: ip,
                        port: port,
                        https: usesHTTPS,
                        model: model
                    )
                } catch {
                    continue
                }
            }
        }

        return nil
    }

    private nonisolated static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.2
        config.timeoutIntervalForResource = 0.2
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: LocalSendTLSDelegate(), delegateQueue: nil)
    }()

    private func rememberRecentProbeIP(_ ip: String) {
        guard isValidIPv4(ip) else { return }
        recentProbeIPs.removeAll { $0 == ip }
        recentProbeIPs.insert(ip, at: 0)
        if recentProbeIPs.count > 12 {
            recentProbeIPs = Array(recentProbeIPs.prefix(12))
        }
    }

    private func rememberKnownPeerIP(_ ip: String) {
        guard isValidIPv4(ip) else { return }
        knownPeerIPs.removeAll { $0 == ip }
        knownPeerIPs.insert(ip, at: 0)
        if knownPeerIPs.count > 48 {
            knownPeerIPs = Array(knownPeerIPs.prefix(48))
        }
    }

    private func arpNeighborIPs() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-an"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let regex = try NSRegularExpression(pattern: #"\((\d{1,3}(?:\.\d{1,3}){3})\)"#)
            let nsrange = NSRange(output.startIndex..<output.endIndex, in: output)
            let matches = regex.matches(in: output, options: [], range: nsrange)

            let ownIP = ownIPv4Address()
            let ownPrefix = ownIP?.split(separator: ".").prefix(3).joined(separator: ".")

            var ips: [String] = []
            var seen = Set<String>()
            for match in matches {
                guard match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: output)
                else { continue }
                let ip = String(output[range])
                guard isValidIPv4(ip) else { continue }
                if ip.hasPrefix("169.254.") { continue }
                if ip == "255.255.255.255" { continue }

                if let ownPrefix {
                    let ipPrefix = ip.split(separator: ".").prefix(3).joined(separator: ".")
                    guard ipPrefix == ownPrefix else { continue }
                }

                if seen.insert(ip).inserted {
                    ips.append(ip)
                }
            }

            return ips
        } catch {
            return []
        }
    }

    private func localSubnetSweepIPs(radius: Int) -> [String] {
        guard let own = ownIPv4Address(), isValidIPv4(own) else { return [] }
        let parts = own.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return [] }

        let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
        let myHost = parts[3]
        let start = max(1, myHost - radius)
        let end = min(254, myHost + radius)

        return (start ... end)
            .filter { $0 != myHost }
            .map { "\(prefix).\($0)" }
    }

    private func ownIPv4Address() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            let family = current.pointee.ifa_addr.pointee.sa_family
            let flags = Int32(current.pointee.ifa_flags)
            guard family == UInt8(AF_INET),
                  (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) == 0
            else { continue }

            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var addr = current.pointee.ifa_addr.pointee
            let result = getnameinfo(
                &addr,
                socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let ip = String(cString: hostBuffer)
            if isValidIPv4(ip) {
                return ip
            }
        }

        return nil
    }

    private func isValidIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        for p in parts {
            guard let v = Int(p), (0 ... 255).contains(v) else { return false }
        }
        return true
    }

    func send(items: [Any]) async throws {
        let startedAt = Date()
        isSending = true
        sendProgress = 0
        transferState = .sending
        completionDismissTask?.cancel()

        do {
            guard let target = devices.first(where: { $0.id == selectedDeviceID }) ?? devices.first else {
                throw LocalSendServiceError.noDeviceSelected
            }

            let files = try await buildTransferFiles(from: items)
            guard !files.isEmpty else { throw LocalSendServiceError.noTransferableItems }

            let prepare = try await prepareUpload(files: files, to: target)
            guard !prepare.fileTokens.isEmpty else {
                sendProgress = 1
                await finishSending(startedAt: startedAt, success: true)
                return
            }

            let uploads: [(TransferFile, String)] = files.compactMap { file in
                guard let token = prepare.fileTokens[file.id] else { return nil }
                return (file, token)
            }

            // Compute total bytes to provide smooth overall progress
            let totalBytes = uploads.reduce(Int64(0)) { acc, entry in acc + Int64(entry.0.data.count) }
            var bytesCompleted: Int64 = 0

            for (index, entry) in uploads.enumerated() {
                let file = entry.0
                let fileSize = Int64(file.data.count)

                try await upload(file: file, sessionID: prepare.sessionID, token: entry.1, to: target) { fileFraction in
                    if totalBytes > 0 {
                        let currentSent = Int64(Double(fileSize) * fileFraction)
                        let overall = Double(bytesCompleted + currentSent) / Double(totalBytes)
                        Task { @MainActor in self.sendProgress = overall }
                    } else {
                        // Fallback to file-index-based progress when sizes unknown
                        Task { @MainActor in self.sendProgress = Double(index) / Double(max(uploads.count, 1)) }
                    }
                }

                bytesCompleted += fileSize
            }

            sendProgress = 1
            await finishSending(startedAt: startedAt, success: true)
        } catch let error as LocalSendServiceError {
            if case .transferRejected = error {
                rejectedDeviceIDs.insert(selectedDeviceID)
                transferState = .rejected(deviceID: selectedDeviceID)
            } else {
                transferState = .failed(error.localizedDescription)
            }
            await finishSending(startedAt: startedAt, success: false)
            throw error
        } catch {
            transferState = .failed(error.localizedDescription)
            await finishSending(startedAt: startedAt, success: false)
            throw error
        }
    }

    private func finishSending(startedAt: Date, success: Bool) async {
        let elapsed = Date().timeIntervalSince(startedAt)
        let minimumVisibleDuration: TimeInterval = 0.8
        if elapsed < minimumVisibleDuration {
            let remaining = minimumVisibleDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        isSending = false
        sendProgress = 0
        
        if success {
            transferState = .completed
            // Auto-dismiss completed state after 3 seconds
            completionDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if case .completed = self.transferState {
                    self.transferState = .idle
                }
            }
        } else {
            // Auto-dismiss failed/rejected state after 4 seconds
            completionDismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if case .failed = self.transferState {
                    self.transferState = .idle
                } else if case .rejected = self.transferState {
                    self.transferState = .idle
                }
            }
        }
    }

    private func sendAnnouncement() {
        let payload: [String: Any] = [
            "alias": Host.current().localizedName ?? "Atoll",
            "version": "2.1",
            "deviceModel": "Mac",
            "deviceType": "desktop",
            "fingerprint": "atoll.localsend.bridge",
            "port": defaultPort,
            // Use HTTP here so LocalSend peers can quickly fail over to UDP response
            // when Atoll is not serving LocalSend register endpoint.
            "protocol": "http",
            "download": false,
            "announcement": true,
            "announce": true
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        connectionGroup?.send(content: data, completion: { _ in })
    }

    private func startRegisterListenerIfNeeded() {
        guard registerListener == nil else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.includePeerToPeer = true

            let listener = try NWListener(
                using: params,
                on: NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(defaultPort))
            )

            listener.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    Task { @MainActor [weak self] in
                        Logger.log("LocalSend register listener failed: \(error.localizedDescription)", category: .extensions)
                        self?.registerListener = nil
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleRegisterConnection(connection)
                }
            }

            listener.start(queue: .global(qos: .utility))
            registerListener = listener
        } catch {
            Logger.log("LocalSend register listener start failed: \(error.localizedDescription)", category: .extensions)
        }
    }

    private func handleRegisterConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 131_072) { [weak self] content, _, _, _ in
            guard let self, let data = content, !data.isEmpty else {
                connection.cancel()
                return
            }

            Task { @MainActor in
                let response = self.processRegisterRequest(data: data, from: connection.endpoint)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func processRegisterRequest(data: Data, from endpoint: NWEndpoint) -> Data {
        guard let request = String(data: data, encoding: .utf8) else {
            return httpResponse(status: 400, json: ["error": "invalid-request"])
        }

        let parts = request.components(separatedBy: "\r\n\r\n")
        guard let head = parts.first,
              let firstLine = head.components(separatedBy: "\r\n").first
        else {
            return httpResponse(status: 400, json: ["error": "invalid-request"])
        }

        let tokens = firstLine.split(separator: " ")
        guard tokens.count >= 2 else {
            return httpResponse(status: 400, json: ["error": "invalid-request"])
        }

        let method = String(tokens[0]).uppercased()
        let rawPath = String(tokens[1])
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        if method == "POST", path == "/api/localsend/v2/register" || path == "/api/localsend/v3/register" {
            let callerIP = endpointIPv4(endpoint)
            let bodyText = parts.dropFirst().joined(separator: "\r\n\r\n")
            let bodyData = bodyText.data(using: .utf8)
            let json = bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }

            if let json,
               let fingerprint = json["fingerprint"] as? String,
               let alias = json["alias"] as? String,
               let callerIP,
               fingerprint != "atoll.localsend.bridge" {
                let device = LocalSendDeviceInfo(
                    id: fingerprint,
                    alias: alias,
                    ip: callerIP,
                    port: (json["port"] as? Int) ?? defaultPort,
                    https: (json["protocol"] as? String) == "https",
                    model: json["deviceModel"] as? String
                )
                discoveredByID[fingerprint] = (device, Date())
                rememberKnownPeerIP(callerIP)
                rememberRecentProbeIP(callerIP)
                refreshDevices()
            } else if let callerIP {
                // Be tolerant to partial HTTP payloads: still ACK register and probe caller directly.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let device = await Self.probeDeviceInfo(at: callerIP, port: defaultPort, timeout: 0.35) {
                        self.discoveredByID[device.id] = (device, Date())
                        self.rememberKnownPeerIP(device.ip)
                        self.rememberRecentProbeIP(device.ip)
                        self.refreshDevices()
                    }
                }
            }

            let responseJSON: [String: Any] = [
                "alias": Host.current().localizedName ?? "Atoll",
                "version": "2.1",
                "deviceModel": "Mac",
                "deviceType": "desktop",
                "token": "atoll.localsend.bridge",
                "fingerprint": "atoll.localsend.bridge",
                "download": false,
                "hasWebInterface": false
            ]
            return httpResponse(status: 200, json: responseJSON)
        }

        if method == "GET", path == "/api/localsend/v2/info" {
            let responseJSON: [String: Any] = [
                "alias": Host.current().localizedName ?? "Atoll",
                "version": "2.1",
                "deviceModel": "Mac",
                "deviceType": "desktop",
                "fingerprint": "atoll.localsend.bridge",
                "port": defaultPort,
                "protocol": "http",
                "download": false
            ]
            return httpResponse(status: 200, json: responseJSON)
        }

        return httpResponse(status: 404, json: ["error": "not-found"])
    }

    private func endpointIPv4(_ endpoint: NWEndpoint) -> String? {
        guard case let .hostPort(host, _) = endpoint else { return nil }
        let ip = host.debugDescription.replacingOccurrences(of: "\"", with: "")
        return isValidIPv4(ip) ? ip : nil
    }

    private func httpResponse(status: Int, json: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let headers = [
            "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")",
            "Content-Type: application/json",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(body)
        return response
    }

    private func handleIncoming(content: Data, endpoint: NWEndpoint?) {
        guard let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any],
              let fingerprint = json["fingerprint"] as? String,
              let alias = json["alias"] as? String
        else { return }

        if fingerprint == "atoll.localsend.bridge" { return }

        let ip: String
        if let announced = json["ip"] as? String {
            ip = announced
        } else if case let .hostPort(host, _) = endpoint {
            ip = host.debugDescription.replacingOccurrences(of: "\"", with: "")
        } else {
            return
        }

        let port = (json["port"] as? Int) ?? defaultPort
        let https = (json["protocol"] as? String) == "https"
        let model = json["deviceModel"] as? String

        let device = LocalSendDeviceInfo(
            id: fingerprint,
            alias: alias,
            ip: ip,
            port: port,
            https: https,
            model: model
        )

        discoveredByID[fingerprint] = (device, Date())
        rememberKnownPeerIP(ip)
        rememberRecentProbeIP(ip)
        refreshDevices()
    }

    private func cleanupStale() {
        let cutoff = Date().addingTimeInterval(-30)
        discoveredByID = discoveredByID.filter { $0.value.lastSeen > cutoff }
        refreshDevices()
    }

    private func refreshDevices() {
        devices = discoveredByID.values.map(\.device).sorted { $0.alias.localizedCaseInsensitiveCompare($1.alias) == .orderedAscending }
        if !devices.contains(where: { $0.id == selectedDeviceID }), let first = devices.first {
            selectedDeviceID = first.id
        }
    }

    private struct TransferFile {
        let id: String
        let name: String
        let mimeType: String
        let data: Data
    }

    private func buildTransferFiles(from items: [Any]) async throws -> [TransferFile] {
        var result: [TransferFile] = []
        for item in items {
            if let url = item as? URL, url.isFileURL {
                if let data = try? Data(contentsOf: url) {
                    result.append(TransferFile(
                        id: UUID().uuidString,
                        name: url.lastPathComponent,
                        mimeType: preferredTransferMimeType(for: url),
                        data: data
                    ))
                }
            } else if let url = item as? URL {
                let string = url.absoluteString
                result.append(TransferFile(
                    id: UUID().uuidString,
                    name: "link.url",
                    mimeType: "text/uri-list",
                    data: Data(string.utf8)
                ))
            } else if let text = item as? String {
                result.append(TransferFile(
                    id: UUID().uuidString,
                    name: "text.txt",
                    mimeType: "text/plain",
                    data: Data(text.utf8)
                ))
            }
        }
        return result
    }

    private func preferredTransferMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "svg" {
            // Some LocalSend receivers try gallery/image-specific write paths for SVG and fail.
            return "application/octet-stream"
        }
        return url.mimeType ?? "application/octet-stream"
    }

    private func prepareUpload(files: [TransferFile], to device: LocalSendDeviceInfo) async throws -> (sessionID: String, fileTokens: [String: String]) {
        var filesMap: [String: Any] = [:]
        for file in files {
            filesMap[file.id] = [
                "id": file.id,
                "fileName": file.name,
                "size": file.data.count,
                "fileType": file.mimeType
            ]
        }

        let payload: [String: Any] = [
            "info": [
                "alias": Host.current().localizedName ?? "Atoll",
                "version": "2.1",
                "deviceModel": "Mac",
                "deviceType": "desktop",
                "fingerprint": "atoll.localsend.bridge",
                "token": "atoll.localsend.bridge",
                "port": defaultPort,
                "protocol": device.https ? "https" : "http",
                "download": false
            ],
            "files": filesMap
        ]

        var lastError: Error?
        for baseURL in candidateBaseURLs(for: device) {
            do {
                return try await prepareUpload(payload: payload, baseURL: baseURL)
            } catch {
                lastError = error
                Logger.log("LocalSend prepare-upload failed via \(baseURL): \(error.localizedDescription)", category: .extensions)
                if !shouldRetryAcrossSchemes(error) {
                    throw error
                }
            }
        }

        throw lastError ?? LocalSendServiceError.invalidResponse
    }

    private func prepareUpload(payload: [String: Any], baseURL: String) async throws -> (sessionID: String, fileTokens: [String: String]) {
        guard let url = URL(string: "\(baseURL)/api/localsend/v2/prepare-upload") else {
            throw LocalSendServiceError.invalidTarget
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await trustedSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LocalSendServiceError.invalidResponse }

        if http.statusCode == 204 {
            return ("", [:])
        }
        // HTTP 403 means the transfer was rejected by the recipient
        if http.statusCode == 403 {
            throw LocalSendServiceError.transferRejected
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw LocalSendServiceError.server(status: http.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = json["sessionId"] as? String,
              let rawFileTokens = json["files"] as? [String: Any]
        else { throw LocalSendServiceError.invalidResponse }

        var fileTokens: [String: String] = [:]
        for (k, v) in rawFileTokens {
            if let s = v as? String {
                fileTokens[k] = s
            }
        }

        return (sessionID, fileTokens)
    }

    private func upload(file: TransferFile, sessionID: String, token: String, to device: LocalSendDeviceInfo, progress: @escaping (Double) -> Void) async throws {
        var lastError: Error?
        for baseURL in candidateBaseURLs(for: device) {
            do {
                try await upload(file: file, sessionID: sessionID, token: token, baseURL: baseURL, progress: progress)
                return
            } catch {
                lastError = error
                Logger.log("LocalSend upload failed via \(baseURL) for \(file.name): \(error.localizedDescription)", category: .extensions)
                if !shouldRetryAcrossSchemes(error) {
                    throw error
                }
            }
        }
        throw lastError ?? LocalSendServiceError.invalidResponse
    }

    private func upload(file: TransferFile, sessionID: String, token: String, baseURL: String, progress: @escaping (Double) -> Void) async throws {
        var components = URLComponents(string: "\(baseURL)/api/localsend/v2/upload")
        components?.queryItems = [
            URLQueryItem(name: "sessionId", value: sessionID),
            URLQueryItem(name: "fileId", value: file.id),
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = components?.url else { throw LocalSendServiceError.invalidTarget }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(file.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(file.data.count)", forHTTPHeaderField: "Content-Length")

        // Use uploadTask to receive per-byte progress via delegate
        let delegate = UploadProgressDelegate { sent, expected in
            guard expected > 0 else { return }
            let fraction = Double(sent) / Double(expected)
            progress(fraction)
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (data, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let task = session.uploadTask(with: request, from: file.data) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data = data, let response = response else {
                    continuation.resume(throwing: LocalSendServiceError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }

        session.finishTasksAndInvalidate()

        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8)
            throw LocalSendServiceError.server(status: status, body: body)
        }
    }

    private func candidateBaseURLs(for device: LocalSendDeviceInfo) -> [String] {
        let primary = device.baseURL
        let alternateScheme = device.https ? "http" : "https"
        let alternate = "\(alternateScheme)://\(device.ip):\(device.port)"
        return primary == alternate ? [primary] : [primary, alternate]
    }

    private func shouldRetryAcrossSchemes(_ error: Error) -> Bool {
        if case LocalSendServiceError.server = error {
            // A peer responded with a concrete HTTP error; fallback to another scheme is usually noise.
            return false
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            switch code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .secureConnectionFailed,
                 .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private lazy var trustedSession: URLSession = {
        URLSession(configuration: .default, delegate: LocalSendTLSDelegate(), delegateQueue: nil)
    }()
}

private class LocalSendTLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}

private final class UploadProgressDelegate: LocalSendTLSDelegate, URLSessionTaskDelegate {
    private let onProgress: (Int64, Int64) -> Void

    init(onProgress: @escaping (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        Task { @MainActor in
            onProgress(totalBytesSent, totalBytesExpectedToSend)
        }
    }
}

private extension URL {
    var mimeType: String? {
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension)
        else { return nil }
        return type.preferredMIMEType
    }
}

enum LocalSendServiceError: LocalizedError {
    case noDeviceSelected
    case noTransferableItems
    case invalidTarget
    case invalidResponse
    case server(status: Int, body: String?)
    case transferRejected

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            return "No LocalSend device selected"
        case .noTransferableItems:
            return "No transferable files or text found"
        case .invalidTarget:
            return "Invalid LocalSend target"
        case .invalidResponse:
            return "Invalid response from LocalSend peer"
        case .server(let status, let body):
            if let body, !body.isEmpty {
                return "LocalSend peer error (\(status)): \(body)"
            }
            return "LocalSend peer error (\(status))"
        case .transferRejected:
            return "Transfer was rejected by the recipient"
        }
    }
}
