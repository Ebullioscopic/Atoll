import CodeIslandCore
import Darwin
import Dispatch
import Foundation

/// Fail-closed listener startup errors surfaced at the activation seam.
public enum CodeIslandObservationListenerError: Error, Equatable {
    case alreadyRunning
    case socketPathOccupied
    case socketPathTooLong
    case systemCallFailed(operation: String, code: Int32)
}

/// A deadline-bounded client that transports only a sanitized observation.
public struct CodeIslandUnixObservationClient: Sendable {
    private let timeout: TimeInterval
    private let codec: CodeIslandObservationWireCodec

    public init(
        timeout: TimeInterval = 0.25,
        codec: CodeIslandObservationWireCodec = CodeIslandObservationWireCodec()
    ) {
        self.timeout = min(max(timeout, 0.01), 2)
        self.codec = codec
    }

    public func deliver(
        _ observation: SessionObservation,
        to socketURL: URL
    ) -> ObservationDeliveryOutcome {
        guard socketURL.isFileURL,
              let envelope = try? codec.encode(observation),
              let address = try? UnixSocketAddress(path: socketURL.path)
        else {
            return .hostUnavailable
        }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .hostUnavailable }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0 else {
            return .hostUnavailable
        }

        let deadline = DispatchTime.now().uptimeNanoseconds
            + UInt64(timeout * 1_000_000_000)
        var socketAddress = address.value
        let connectResult = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, address.length)
            }
        }
        if connectResult != 0 {
            guard errno == EINPROGRESS else { return .hostUnavailable }
            switch waitForSocket(descriptor, events: Int16(POLLOUT), deadline: deadline) {
            case .ready:
                var socketError: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_ERROR,
                    &socketError,
                    &length
                ) == 0, socketError == 0 else {
                    return .hostUnavailable
                }
            case .timedOut:
                return .timedOut
            case .failed:
                return .hostUnavailable
            }
        }

        switch sendAll(envelope, descriptor: descriptor, deadline: deadline) {
        case .ready:
            break
        case .timedOut:
            return .timedOut
        case .failed:
            return .hostUnavailable
        }
        _ = Darwin.shutdown(descriptor, SHUT_WR)

        switch waitForSocket(descriptor, events: Int16(POLLIN), deadline: deadline) {
        case .ready:
            var acknowledgement: UInt8 = 0
            let count = Darwin.recv(descriptor, &acknowledgement, 1, 0)
            guard count == 1 else { return .hostUnavailable }
            switch acknowledgement {
            case ListenerAcknowledgement.delivered.rawValue:
                return .delivered
            case ListenerAcknowledgement.shuttingDown.rawValue:
                return .hostShuttingDown
            default:
                return .hostUnavailable
            }
        case .timedOut:
            return .timedOut
        case .failed:
            return .hostUnavailable
        }
    }
}

/// Production Unix-domain listener used by one consented provider runtime.
///
/// `start` returns only after bind/listen and never unlinks a pre-existing path.
/// Connections carry the strict metadata envelope and receive a one-byte
/// acknowledgement; no provider decision can travel in either direction.
public final class CodeIslandUnixObservationListener: CodeIslandListenerControlling, @unchecked Sendable {
    private enum State {
        case stopped
        case running
        case passThrough
    }

    private let stateLock = NSLock()
    private let drainCondition = NSCondition()
    private let acceptQueue = DispatchQueue(label: "com.atoll.code-island.listener.accept")
    private let workerQueue = DispatchQueue(
        label: "com.atoll.code-island.listener.worker",
        attributes: .concurrent
    )
    private let codec: CodeIslandObservationWireCodec
    private let onObservation: @Sendable (SessionObservation) -> Void

    private var state: State = .stopped
    private var listenerDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var socketURL: URL?
    private var socketIdentity: UnixSocketIdentity?
    private var inFlightCount = 0

    public init(
        codec: CodeIslandObservationWireCodec = CodeIslandObservationWireCodec(),
        onObservation: @escaping @Sendable (SessionObservation) -> Void
    ) {
        self.codec = codec
        self.onObservation = onObservation
    }

    public func start(at socketURL: URL) throws {
        guard socketURL.isFileURL else {
            throw CodeIslandObservationListenerError.socketPathTooLong
        }
        let address: UnixSocketAddress
        do {
            address = try UnixSocketAddress(path: socketURL.path)
        } catch {
            throw CodeIslandObservationListenerError.socketPathTooLong
        }

        stateLock.lock()
        defer { stateLock.unlock() }
        guard state == .stopped else {
            throw CodeIslandObservationListenerError.alreadyRunning
        }

        var existing = stat()
        if lstat(socketURL.path, &existing) == 0 {
            throw CodeIslandObservationListenerError.socketPathOccupied
        }
        guard errno == ENOENT else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "lstat",
                code: errno
            )
        }

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "socket",
                code: errno
            )
        }
        var shouldCloseDescriptor = true
        defer {
            if shouldCloseDescriptor { Darwin.close(descriptor) }
        }
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 { _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) }

        var socketAddress = address.value
        let bindResult = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, address.length)
            }
        }
        guard bindResult == 0 else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "bind",
                code: errno
            )
        }
        var ownsCreatedPath = true
        defer {
            if ownsCreatedPath { _ = unlink(socketURL.path) }
        }

        guard chmod(socketURL.path, 0o600) == 0 else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "chmod",
                code: errno
            )
        }
        guard listen(descriptor, 16) == 0 else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "listen",
                code: errno
            )
        }
        guard let identity = UnixSocketIdentity.capture(at: socketURL) else {
            throw CodeIslandObservationListenerError.systemCallFailed(
                operation: "lstat",
                code: errno
            )
        }

        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: acceptQueue
        )
        source.setEventHandler { [weak self] in
            self?.acceptReadyConnections()
        }

        self.socketURL = socketURL.standardizedFileURL
        socketIdentity = identity
        listenerDescriptor = descriptor
        acceptSource = source
        state = .running
        shouldCloseDescriptor = false
        ownsCreatedPath = false
        source.resume()
    }

    public func enterPassThrough() {
        stateLock.lock()
        if state == .running { state = .passThrough }
        stateLock.unlock()
    }

    public func drain(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        drainCondition.lock()
        while inFlightCount > 0 {
            if !drainCondition.wait(until: deadline) { break }
        }
        drainCondition.unlock()
    }

    public func stop() {
        stateLock.lock()
        guard state != .stopped else {
            stateLock.unlock()
            return
        }
        state = .stopped
        let descriptor = listenerDescriptor
        let source = acceptSource
        let ownedURL = socketURL
        let ownedIdentity = socketIdentity
        listenerDescriptor = -1
        acceptSource = nil
        socketURL = nil
        socketIdentity = nil
        stateLock.unlock()

        source?.cancel()
        if descriptor >= 0 {
            _ = Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        if let ownedURL, let ownedIdentity,
           UnixSocketIdentity.capture(at: ownedURL) == ownedIdentity {
            _ = unlink(ownedURL.path)
        }
    }

    private func acceptReadyConnections() {
        stateLock.lock()
        let descriptor = listenerDescriptor
        stateLock.unlock()
        guard descriptor >= 0 else { return }

        while true {
            let connection = Darwin.accept(descriptor, nil, nil)
            if connection < 0 {
                if errno == EINTR { continue }
                return
            }
            _ = fcntl(connection, F_SETFD, FD_CLOEXEC)
            let flags = fcntl(connection, F_GETFL)
            if flags >= 0 { _ = fcntl(connection, F_SETFL, flags & ~O_NONBLOCK) }

            drainCondition.lock()
            inFlightCount += 1
            drainCondition.unlock()
            workerQueue.async { [self] in
                handleConnection(connection)
            }
        }
    }

    private func handleConnection(_ descriptor: Int32) {
        defer {
            Darwin.close(descriptor)
            drainCondition.lock()
            inFlightCount -= 1
            drainCondition.broadcast()
            drainCondition.unlock()
        }

        var noSignal: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSignal,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        guard let data = receiveEnvelope(from: descriptor) else {
            sendAcknowledgement(.rejected, to: descriptor)
            return
        }

        stateLock.lock()
        let currentState = state
        stateLock.unlock()
        guard currentState == .running else {
            sendAcknowledgement(.shuttingDown, to: descriptor)
            return
        }
        guard let observation = try? codec.decode(data) else {
            sendAcknowledgement(.rejected, to: descriptor)
            return
        }

        sendAcknowledgement(.delivered, to: descriptor)
        onObservation(observation)
    }

    private func receiveEnvelope(from descriptor: Int32) -> Data? {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while result.count <= CodeIslandObservationWireCodec.maximumEnvelopeSize {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                result.append(contentsOf: buffer.prefix(Int(count)))
                continue
            }
            if count == 0 { break }
            if errno == EINTR { continue }
            return nil
        }
        guard !result.isEmpty,
              result.count <= CodeIslandObservationWireCodec.maximumEnvelopeSize else {
            return nil
        }
        return result
    }

    private func sendAcknowledgement(
        _ acknowledgement: ListenerAcknowledgement,
        to descriptor: Int32
    ) {
        var byte = acknowledgement.rawValue
        _ = Darwin.send(descriptor, &byte, 1, 0)
    }
}

private enum ListenerAcknowledgement: UInt8 {
    case delivered = 0x06
    case shuttingDown = 0x07
    case rejected = 0x15
}

private enum SocketWaitResult {
    case ready
    case timedOut
    case failed
}

private func waitForSocket(
    _ descriptor: Int32,
    events: Int16,
    deadline: UInt64
) -> SocketWaitResult {
    while true {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now < deadline else { return .timedOut }
        let remaining = deadline - now
        let milliseconds = max(1, min(Int32.max, Int32(remaining / 1_000_000)))
        var item = pollfd(fd: descriptor, events: events, revents: 0)
        let result = poll(&item, 1, milliseconds)
        if result > 0 {
            if item.revents & Int16(POLLNVAL | POLLERR) != 0 { return .failed }
            return .ready
        }
        if result == 0 { return .timedOut }
        if errno != EINTR { return .failed }
    }
}

private func sendAll(
    _ data: Data,
    descriptor: Int32,
    deadline: UInt64
) -> SocketWaitResult {
    data.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return .failed }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.send(descriptor, base.advanced(by: offset), bytes.count - offset, 0)
            if count > 0 {
                offset += count
                continue
            }
            if count == 0 { return .failed }
            if errno == EINTR { continue }
            guard errno == EAGAIN || errno == EWOULDBLOCK else { return .failed }
            let wait = waitForSocket(descriptor, events: Int16(POLLOUT), deadline: deadline)
            guard case .ready = wait else { return wait }
        }
        return .ready
    }
}

private struct UnixSocketAddress {
    var value: sockaddr_un
    let length: socklen_t

    init(path: String) throws {
        var address = sockaddr_un()
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= capacity else {
            throw CodeIslandObservationListenerError.socketPathTooLong
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                bytes.withUnsafeBufferPointer { source in
                    destination.update(from: source.baseAddress!, count: bytes.count)
                }
            }
        }
        value = address
        length = socklen_t(MemoryLayout<sockaddr_un>.size)
    }
}

private struct UnixSocketIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    let owner: uid_t

    static func capture(at url: URL) -> UnixSocketIdentity? {
        var information = stat()
        guard lstat(url.path, &information) == 0,
              information.st_mode & S_IFMT == S_IFSOCK else {
            return nil
        }
        return UnixSocketIdentity(
            device: information.st_dev,
            inode: information.st_ino,
            owner: information.st_uid
        )
    }
}
