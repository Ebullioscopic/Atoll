import Foundation

@MainActor
final class RemoteManager: ObservableObject {
    static let shared = RemoteManager()

    @Published private(set) var hosts: [RemoteHost] = []
    @Published private(set) var connectionStatus: [String: SSHForwarder.Status] = [:]
    @Published private(set) var installRunning: [String: Bool] = [:]
    @Published private(set) var lastMessage: [String: String] = [:]

    var onDisconnect: ((String) -> Void)?

    private var forwarders: [String: SSHForwarder] = [:]
    // Per-user remote socket path resolved at connect time (#193). Keyed by host id;
    // reused by installHooks so the SSH -R forward and the remote hooks agree.
    private var remoteSocketPaths: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private let hostsKey = "remoteHosts"

    // Auto-reconnect (#92): when an ssh tunnel drops without the user asking for
    // it (laptop sleep / network blip / server bounce), schedule a retry with
    // exponential backoff instead of leaving the host silently disconnected.
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private var reconnectAttempts: [String: Int] = [:]

    private static let reconnectBackoffSeconds: [Int] = [5, 15, 45, 120, 300]
    private static let reconnectMaxAttempts = 10

    /// Delay (seconds) before the nth reconnect attempt (1-based). Clamped to the
    /// last entry for attempts beyond the table.
    static func reconnectDelay(attempt: Int) -> Int {
        guard attempt >= 1 else { return reconnectBackoffSeconds[0] }
        let idx = min(attempt - 1, reconnectBackoffSeconds.count - 1)
        return reconnectBackoffSeconds[idx]
    }

    private init() {
        load()
    }

    func startup() {
        for host in hosts where host.autoConnect {
            connect(id: host.id)
        }
    }

    func shutdown() {
        for host in hosts {
            disconnect(id: host.id)
        }
    }

    func addHost(_ host: RemoteHost) {
        hosts.append(host)
        save()
    }

    func updateHost(_ host: RemoteHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        let previous = hosts[index]
        let wasConnected = (connectionStatus[host.id] == .connected)
        hosts[index] = host
        save()
        // Only bounce the tunnel when a field the SSH connection depends on
        // changed. Local-only fields (name, cwdFilter — filtering happens in
        // HookServer, #240) must not interrupt live sessions.
        let connectionChanged = previous.host != host.host
            || previous.user != host.user
            || previous.port != host.port
            || previous.identityFile != host.identityFile
            || previous.authSocket != host.authSocket
        if wasConnected && connectionChanged {
            reconnect(id: host.id)
        }
    }

    func removeHost(id: String) {
        disconnect(id: id)
        hosts.removeAll { $0.id == id }
        connectionStatus[id] = .disconnected
        installRunning[id] = false
        lastMessage[id] = nil
        save()
    }

    func reconnect(id: String) {
        disconnect(id: id)
        connect(id: id)
    }

    func connect(id: String) {
        // User-initiated connect (or autoConnect at startup): clear any pending
        // reconnect countdown and reset the backoff attempt counter.
        cancelScheduledReconnect(id: id)
        reconnectAttempts[id] = nil
        connectInternal(id: id)
    }

    private func connectInternal(id: String) {
        guard let host = hosts.first(where: { $0.id == id }) else { return }
        guard !host.sshTarget.isEmpty else {
            connectionStatus[id] = .failed("invalid host")
            lastMessage[id] = "invalid host"
            return
        }

        let forwarder = forwarders[id] ?? SSHForwarder()
        forwarders[id] = forwarder
        forwarder.onStatusChange = { [weak self] status in
            Task { @MainActor in
                self?.handleStatusChange(status, for: host)
            }
        }

        connectionStatus[id] = .connecting
        lastMessage[id] = host.displayAddress

        Task {
            let remoteSocketPath = await RemoteInstaller.prepareRemoteSocketPath(host: host)
            await MainActor.run {
                self.remoteSocketPaths[host.id] = remoteSocketPath
                forwarder.connect(host: host, localSocketPath: HookServer.socketPath, remoteSocketPath: remoteSocketPath)
            }
        }
    }

    func disconnect(id: String) {
        cancelScheduledReconnect(id: id)
        reconnectAttempts[id] = nil
        forwarders[id]?.disconnect()
        forwarders[id] = nil
        remoteSocketPaths[id] = nil
        connectionStatus[id] = .disconnected
        installRunning[id] = false
        onDisconnect?(id)
    }

    private func handleStatusChange(_ status: SSHForwarder.Status, for host: RemoteHost) {
        connectionStatus[host.id] = status

        switch status {
        case .connected:
            // Tunnel is up again — forget previous failure counter.
            reconnectAttempts[host.id] = nil
            cancelScheduledReconnect(id: host.id)
            Task { await installHooks(for: host) }
        case .failed(let message):
            installRunning[host.id] = false
            lastMessage[host.id] = message
            onDisconnect?(host.id)
            scheduleReconnect(for: host)
        case .disconnected:
            // User-initiated disconnects go through disconnect(id:) which already
            // cleared reconnect state before we get here.
            installRunning[host.id] = false
            onDisconnect?(host.id)
        case .connecting:
            break
        }
    }

    private func scheduleReconnect(for host: RemoteHost) {
        // Only auto-reconnect hosts the user opted into; otherwise a failing
        // manually-triggered connect would keep retrying forever.
        guard host.autoConnect else { return }

        cancelScheduledReconnect(id: host.id)
        let nextAttempt = (reconnectAttempts[host.id] ?? 0) + 1
        guard nextAttempt <= Self.reconnectMaxAttempts else {
            lastMessage[host.id] = "Gave up after \(Self.reconnectMaxAttempts) reconnect attempts"
            return
        }
        reconnectAttempts[host.id] = nextAttempt
        let delay = Self.reconnectDelay(attempt: nextAttempt)
        lastMessage[host.id] = "Reconnecting in \(delay)s (attempt \(nextAttempt)/\(Self.reconnectMaxAttempts))"

        let hostId = host.id
        reconnectTasks[hostId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                // Task may have been cancelled after the sleep; double-check.
                guard self.reconnectTasks[hostId] != nil else { return }
                self.reconnectTasks[hostId] = nil
                self.connectInternal(id: hostId)
            }
        }
    }

    private func cancelScheduledReconnect(id: String) {
        reconnectTasks[id]?.cancel()
        reconnectTasks[id] = nil
    }

    private func installHooks(for host: RemoteHost) async {
        installRunning[host.id] = true
        let remoteSocketPath = remoteSocketPaths[host.id] ?? host.remoteSocketPath
        let result = await RemoteInstaller.installAll(host: host, remoteSocketPath: remoteSocketPath)
        installRunning[host.id] = false
        lastMessage[host.id] = result.message
        if !result.ok {
            connectionStatus[host.id] = .failed(result.message)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: hostsKey),
              let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) else {
            hosts = []
            return
        }
        hosts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        defaults.set(data, forKey: hostsKey)
    }
}
