import Foundation
import Darwin
import os

/// Session-scoped helper. No launch daemon or permanent root service is installed.
/// Commands are restricted to the four presets, Auto, and the watchdog heartbeat.
final class CoolingHelperSession {
    private let helperOverride: String?
    private let readOnlyProbe: Bool
    private let logger = os.Logger(subsystem: "com.Ebullioscopic.Atoll", category: "Cooling")
    private var stage = "idle"
    private var setupFailure: Error?

    /// Configures the bundled production helper or an explicit unprivileged test fixture.
    init(helperOverride: String? = nil, readOnlyProbe: Bool = false) {
        self.helperOverride = helperOverride
        self.readOnlyProbe = readOnlyProbe
    }

    private var fd: Int32 = -1
    private var authorizer: Process?
    private var directory: URL?
    /// Reports whether this session currently owns an authenticated helper socket.
    var isConnected: Bool { fd >= 0 }

    /// Closes the connection so the helper restores its owned fans before exiting.
    deinit { close() }

    /// Authorizes if needed, checks cancellation, and executes a restricted cooling request.
    /// Structured command errors preserve authorization; transport errors close the session.
    func command(_ request: CoolingRequest, shouldProceed: (() -> Bool)? = nil) throws -> CoolingReply {
        if fd < 0 {
            if let setupFailure { throw setupFailure }
            do { try authorize() }
            catch { setupFailure = error; throw error }
        }
        guard shouldProceed?() != false else {
            close()
            throw NSError(domain: "AtollCooling", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "Fan control was disabled before the command was applied."])
        }
        let reply: CoolingReply
        do {
            try CoolingSocket.send(request, to: fd)
            reply = try CoolingSocket.receive(CoolingReply.self, from: fd)
        } catch {
            logger.error("Cooling connection failed: \(error.localizedDescription, privacy: .public)")
            close()
            throw error
        }
        // A rejected fan command is not a broken connection. Keep the approved
        // session so another preset or Auto does not ask for a password again.
        guard reply.ok else {
            let message = reply.message ?? "Fan control failed."
            logger.error("Cooling command rejected: \(message, privacy: .public)")
            throw NSError(domain: "AtollCooling", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return reply
    }

    /// Clears a cached setup failure after the user explicitly requests another connection attempt.
    func resetAuthorizationFailure() { setupFailure = nil }

    /// Renews an existing helper lease without opening a new authorization session.
    func heartbeat() throws {
        guard fd >= 0 else { return }
        _ = try command(CoolingRequest(command: "ping"))
    }

    /// Closes the authenticated socket and removes its private endpoint; EOF triggers helper cleanup.
    func close() {
        if fd >= 0 {
            _ = shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
            fd = -1
        }
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        // The helper sees EOF and restores Auto before it exits. The AppleScript
        // process is allowed to collect that result rather than being killed.
        authorizer = nil
    }

    /// Creates a private socket, launches the helper through administrator authorization,
    /// and verifies peer credentials and the random session token before accepting commands.
    private func authorize() throws {
        stage = "locate helper"
        let helper = helperOverride ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/AtollFanHelper").path
        guard FileManager.default.isExecutableFile(atPath: helper) else {
            throw NSError(domain: "AtollCooling", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The cooling helper is missing. Reinstall this Atoll build."])
        }
        let folder = URL(fileURLWithPath: "/tmp/atoll-cooling-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        directory = folder
        let path = folder.appendingPathComponent("session").path
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { close(); throw CoolingSMC.Error.unavailable }
        defer { Darwin.close(listener) }
        var address = try CoolingSocket.address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 1) == 0 else {
            close(); throw CoolingSMC.Error.unavailable
        }
        let token = UUID().uuidString + UUID().uuidString
        let values = [helper, path, String(getpid()), String(geteuid()), token]
        let shellCommand = values.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let escaped = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        if readOnlyProbe {
            process.executableURL = URL(fileURLWithPath: helper)
            process.arguments = ["--ipc-read-only"] + Array(values.dropFirst())
        }
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        do {
            stage = "administrator authorization"
            try process.run()
            authorizer = process
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                var event = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
                if poll(&event, 1, 500) > 0 { break }
                if !process.isRunning {
                    let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    throw NSError(domain: "AtollCooling", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: text.contains("-128") ? "Fan control authorization was cancelled." : text.replacingOccurrences(of: token, with: "[session]").trimmingCharacters(in: .whitespacesAndNewlines)])
                }
            }
            var pending = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            guard poll(&pending, 1, 0) > 0 else { throw CoolingSMC.Error.unavailable }
            stage = "accept helper connection"
            fd = accept(listener, nil, nil)
            guard fd >= 0 else { throw CoolingSMC.Error.unavailable }
            CoolingSocket.suppressSIGPIPE(fd)
            var uid: uid_t = 0, gid: gid_t = 0
            stage = "verify helper credentials"
            let requiredUID: uid_t = readOnlyProbe ? geteuid() : 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == requiredUID else { throw CoolingSMC.Error.permission }
            stage = "receive helper greeting"
            let ready = try CoolingSocket.receive(CoolingReply.self, from: fd)
            guard ready.ok else { throw CoolingSMC.Error.unavailable }
            stage = "authenticate cooling session"
            try CoolingSocket.send(CoolingRequest(command: "hello", token: token), to: fd)
            let hello = try CoolingSocket.receive(CoolingReply.self, from: fd)
            guard hello.ok else { throw CoolingSMC.Error.permission }
            stage = "connected"
        } catch {
            let message = "Cooling setup failed at \(stage): \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            close()
            throw NSError(domain: "AtollCooling", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
