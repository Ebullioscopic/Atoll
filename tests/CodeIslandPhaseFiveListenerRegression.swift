import CodeIslandCore
import CodeIslandRuntime
import Darwin
import Foundation

private enum ListenerRegressionFailure: Error {
    case failed(String)
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ListenerRegressionFailure.failed(message) }
}

@main
private struct CodeIslandPhaseFiveListenerRegression {
    static func main() throws {
        let suffix = String(UUID().uuidString.prefix(8))
        let root = URL(fileURLWithPath: "/private/tmp/ai5-\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let socketURL = root.appendingPathComponent("observations.sock")
        let received = NSLockProtected<[SessionObservation]>([])
        let delivered = DispatchSemaphore(value: 0)
        let listener = CodeIslandUnixObservationListener { observation in
            received.withValue { $0.append(observation) }
            delivered.signal()
        }

        do {
            try listener.start(at: socketURL)
        } catch let error as CodeIslandObservationListenerError {
            if case .systemCallFailed(_, let code) = error,
               code == EPERM,
               ProcessInfo.processInfo.environment["CODEISLAND_REQUIRE_LIVE_SOCKET"] != "1" {
                return
            }
            throw error
        }
        defer { listener.stop() }

        try require(FileManager.default.fileExists(atPath: socketURL.path), "ready listener must own its socket")
        let permissions = try FileManager.default.attributesOfItem(atPath: socketURL.path)[.posixPermissions] as? NSNumber
        try require(permissions?.intValue == 0o600, "listener socket must be user-only")

        let observation = SessionObservation(
            provider: .codex,
            sessionID: OpaqueSessionID("thr_live")!,
            project: ProjectIdentity(displayName: "Atoll"),
            origin: nil,
            transition: .active,
            observedAt: Date(timeIntervalSince1970: 1_754_275_200)
        )
        let client = CodeIslandUnixObservationClient(timeout: 0.5)
        try require(client.deliver(observation, to: socketURL) == .delivered, "live observation must be acknowledged")
        try require(delivered.wait(timeout: .now() + 1) == .success, "listener must publish the sanitized observation")
        try require(received.value == [observation], "listener must publish exactly one observation")

        let competing = CodeIslandUnixObservationListener { _ in }
        do {
            try competing.start(at: socketURL)
            throw ListenerRegressionFailure.failed("a second listener must not replace an occupied path")
        } catch let error as CodeIslandObservationListenerError {
            try require(error == .socketPathOccupied, "occupied path must fail closed")
        }
        try require(FileManager.default.fileExists(atPath: socketURL.path), "competing start must preserve the live socket")

        listener.enterPassThrough()
        try require(
            client.deliver(observation, to: socketURL) == .hostShuttingDown,
            "pass-through listener must acknowledge shutdown without consuming"
        )
        listener.drain(timeout: 1)
        try require(received.value == [observation], "pass-through must not publish observations")

        listener.stop()
        try require(!FileManager.default.fileExists(atPath: socketURL.path), "stop must remove only the owned socket")
        try require(client.deliver(observation, to: socketURL) == .hostUnavailable, "missing Atoll must return promptly")

        try Data("not a socket".utf8).write(to: socketURL)
        do {
            try listener.start(at: socketURL)
            throw ListenerRegressionFailure.failed("a non-socket path must never be unlinked")
        } catch let error as CodeIslandObservationListenerError {
            try require(error == .socketPathOccupied, "non-socket path must fail closed")
        }
        let preserved = try Data(contentsOf: socketURL)
        try require(preserved == Data("not a socket".utf8), "foreign path must remain byte-for-byte intact")
    }
}

private final class NSLockProtected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storedValue)
        lock.unlock()
    }
}
