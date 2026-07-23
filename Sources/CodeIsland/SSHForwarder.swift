import Foundation

@MainActor
final class SSHForwarder {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status = .disconnected {
        didSet {
            guard oldValue != status else { return }
            onStatusChange?(status)
        }
    }

    var onStatusChange: ((Status) -> Void)?

    private var process: Process?
    private var stderrPipe: Pipe?
    private var generation: UInt64 = 0

    func connect(host: RemoteHost, localSocketPath: String, remoteSocketPath: String) {
        disconnect()

        let target = host.sshTarget
        guard !target.isEmpty else {
            status = .failed("invalid host")
            return
        }

        generation &+= 1
        let currentGeneration = generation
        status = .connecting

        // Remove any stale remote socket left over from a previous tunnel before
        // opening this one. macOS system SSH (LibreSSL) does not honour
        // StreamLocalBindUnlink=yes for -R forwarding, so a leftover socket causes
        // "remote port forwarding failed" on reconnect (#206). The cleanup spawns
        // its own short-lived SSH; run it off the main thread because a blocking
        // ConnectTimeout would otherwise freeze the menu-bar UI for seconds when the
        // host is unreachable. The tunnel starts only after cleanup returns, so the
        // -R bind never races the leftover socket.
        let cleanupArguments = Self.cleanupArguments(host: host, remoteSocketPath: remoteSocketPath)
        let cleanupEnvironment = buildEnvironment(host: host)
        DispatchQueue.global(qos: .userInitiated).async {
            Self.runCleanup(arguments: cleanupArguments, environment: cleanupEnvironment)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // A newer connect()/disconnect() may have superseded this attempt
                // while the cleanup SSH was in flight — bail if so.
                guard self.generation == currentGeneration else { return }
                guard case .connecting = self.status else { return }
                self.startTunnel(
                    host: host,
                    localSocketPath: localSocketPath,
                    remoteSocketPath: remoteSocketPath,
                    generation: currentGeneration
                )
            }
        }
    }

    /// Launch the long-lived `ssh -N -R` tunnel process. Always invoked on the main
    /// actor, after `runCleanup` has cleared any leftover remote socket.
    private func startTunnel(host: RemoteHost, localSocketPath: String, remoteSocketPath: String, generation currentGeneration: UInt64) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = buildArguments(host: host, localSocketPath: localSocketPath, remoteSocketPath: remoteSocketPath)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.environment = buildEnvironment(host: host)

        let stderr = Pipe()
        process.standardError = stderr
        stderrPipe = stderr

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation == currentGeneration else { return }
                // Release the stderr pipe/handler the moment the child exits. If we leave the
                // readabilityHandler registered, the closed FD keeps getting poked and the
                // handler is invoked in a tight loop, pinning CPU at 100% when ssh disconnects.
                self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
                self.stderrPipe = nil
                self.process = nil
                if case .disconnected = self.status { return }
                let code = proc.terminationStatus
                self.status = .failed("ssh exited (\(code))")
            }
        }

        do {
            try process.run()
            self.process = process
            startStderrMonitor(stderr, generation: currentGeneration)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak process] in
                guard let self else { return }
                guard self.generation == currentGeneration else { return }
                guard let process else { return }
                if process.isRunning {
                    self.status = .connected
                } else if case .connecting = self.status {
                    self.status = .failed("ssh exited (\(process.terminationStatus))")
                }
            }
        } catch {
            self.process = nil
            self.stderrPipe = nil
            status = .failed("ssh launch failed")
        }
    }

    func disconnect() {
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil

        if let process {
            status = .disconnected
            if process.isRunning {
                process.terminate()
            }
        } else {
            status = .disconnected
        }
        self.process = nil
    }

    /// Remove a stale Unix-domain socket on the remote host before forwarding by
    /// running `rm -f <remoteSocketPath>` over its own short-lived SSH.
    ///
    /// macOS system SSH (`/usr/bin/ssh`, LibreSSL build) ignores
    /// `StreamLocalBindUnlink=yes` for `-R` (remote) forwarding.  When a tunnel
    /// drops the listen socket is left behind and reconnect fails with
    /// "remote port forwarding failed for listen path …".  A quick `rm -f`
    /// over SSH sidesteps the issue.  See issue #206.
    ///
    /// `nonisolated` so it can run on a background queue: it touches no actor
    /// state — only the value-type `arguments`/`environment` handed in — and
    /// blocks on `waitUntilExit()`, which must never run on the main thread.
    nonisolated private static func runCleanup(arguments: [String], environment: [String: String]) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        proc.arguments = arguments
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.environment = environment

        try? proc.run()
        proc.waitUntilExit()
    }

    /// Build SSH arguments that remove a stale remote socket file.
    /// Extracted for testability.  See `cleanupStaleRemoteSocket`.
    static func cleanupArguments(host: RemoteHost, remoteSocketPath: String) -> [String] {
        var args: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
        ]
        if let port = host.port {
            args += ["-p", String(port)]
        }
        let trimmedIdentity = host.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIdentity.isEmpty {
            args += ["-i", trimmedIdentity]
        }
        args += [host.sshTarget, "rm", "-f", remoteSocketPath]
        return args
    }

    private func buildArguments(host: RemoteHost, localSocketPath: String, remoteSocketPath: String) -> [String] {
        var args: [String] = [
            "-N",
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-o", "StreamLocalBindUnlink=yes",
            "-o", "StreamLocalBindMask=0000",
            // Never reuse or spawn a multiplexing master connection (#190): a shared
            // ControlMaster makes `ssh -N` hand the forward to the master and exit 0
            // immediately, which we'd misread as a failed tunnel. Force a dedicated
            // connection that stays alive for the lifetime of this forwarder.
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
        ]

        if let port = host.port {
            args += ["-p", String(port)]
        }

        let trimmedIdentity = host.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIdentity.isEmpty {
            args += ["-i", trimmedIdentity]
        }

        args += ["-R", "\(remoteSocketPath):\(localSocketPath)"]
        args.append(host.sshTarget)
        return args
    }

    /// Merge the host-specific SSH_AUTH_SOCK (if any) into the spawn environment so
    /// agents fronted by a password manager (1Password, Bitwarden, etc.) can sign
    /// the handshake even when the GUI app didn't inherit the env var from a shell.
    /// See issue #81.
    private func buildEnvironment(host: RemoteHost) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let trimmed = host.authSocket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let expanded = (trimmed as NSString).expandingTildeInPath
            env["SSH_AUTH_SOCK"] = expanded
        }
        return env
    }

    private func startStderrMonitor(_ pipe: Pipe, generation: UInt64) {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                // EOF — ssh closed stderr (it exited). Self-unhook so the dispatch
                // source can't re-invoke this handler in a tight loop (100% CPU) if
                // the terminationHandler cleanup is skipped, e.g. because self was
                // already released or the generation moved on. Same bug class as #278.
                fileHandle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }

            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation == generation else { return }
                if case .connecting = self.status {
                    self.status = .failed(message)
                }
            }
        }
    }
}
