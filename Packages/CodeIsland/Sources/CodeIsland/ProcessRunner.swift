import Foundation

/// Synchronous process runner with a hard timeout. On timeout, sends SIGTERM,
/// waits 1s, then SIGKILL if the child is still alive — returns nil so callers
/// can't accidentally use partial output.
///
/// Drains stdout on a background queue so a full pipe buffer cannot wedge the
/// child between writes and our wait().
enum ProcessRunner {
    /// Resolve a process' controlling TTY via `ps -o tty=`.
    static func ttyForPid(_ pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        guard let data = run(path: "/bin/ps", args: ["-o", "tty=", "-p", "\(pid)"], timeout: 5),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let tty = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "?" else { return nil }
        return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
    }

    /// Reference cell for the pipe drain so the closure and the calling thread
    /// share storage cleanly. Synchronization is provided by the `drained`
    /// semaphore (signal happens-before wait), so `@unchecked Sendable` is
    /// load-bearing — Swift 6 strict-concurrency would otherwise flag the
    /// captured-var write.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    static func run(
        path: String,
        args: [String],
        env: [String: String]? = nil,
        timeout: TimeInterval = 10
    ) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        if let env {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            proc.environment = merged
        }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in exited.signal() }

        do { try proc.run() } catch { return nil }

        let box = DataBox()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            proc.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(proc.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        _ = drained.wait(timeout: .now() + 1)
        return proc.terminationStatus == 0 ? box.data : nil
    }
}
