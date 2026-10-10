import Foundation
import Darwin

struct CoolingRequest: Codable {
    let command: String
    var fanID: Int?
    var fraction: Double?
    var token: String?
}

struct CoolingReply: Codable {
    let ok: Bool
    var message: String?
}

enum CoolingSocket {
    /// Builds a null-terminated Unix socket address, rejecting paths longer than the native buffer.
    static func address(_ path: String) throws -> sockaddr_un {
        guard path.utf8.count < 104 else { throw CoolingSMC.Error.invalidData }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: Array(path.utf8) + [0])
        }
        return address
    }

    /// Opens a Unix stream socket, connects to the app’s private endpoint, and suppresses SIGPIPE.
    static func connect(_ path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CoolingSMC.Error.unavailable }
        var address = try self.address(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { Darwin.close(fd); throw CoolingSMC.Error.unavailable }
        suppressSIGPIPE(fd)
        return fd
    }

    /// Makes writes to a closed peer return an error instead of terminating the process.
    static func suppressSIGPIPE(_ fd: Int32) {
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Encodes and writes one bounded JSON line, handling partial socket writes.
    static func send<T: Encodable>(_ value: T, to fd: Int32) throws {
        let bytes = Array(try JSONEncoder().encode(value)) + [10]
        guard bytes.count <= 4096 else { throw CoolingSMC.Error.invalidData }
        try bytes.withUnsafeBytes { pointer in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, pointer.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw CoolingSMC.Error.unavailable }
                offset += count
            }
        }
    }

    /// Receives one bounded JSON line before the deadline; rejects EOF, malformed data, and oversized messages.
    static func receive<T: Decodable>(_ type: T.Type, from fd: Int32, timeout: TimeInterval = 15) throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        var bytes: [UInt8] = []
        while Date() < deadline {
            var event = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(max(1, min(1000, deadline.timeIntervalSinceNow * 1000)))
            let result = poll(&event, 1, milliseconds)
            if result < 0, errno == EINTR { continue }
            guard result >= 0 else { throw CoolingSMC.Error.unavailable }
            if result == 0 { continue }
            var byte: UInt8 = 0
            guard Darwin.read(fd, &byte, 1) == 1 else { throw CoolingSMC.Error.unavailable }
            if byte == 10 { return try JSONDecoder().decode(type, from: Data(bytes)) }
            bytes.append(byte)
            guard bytes.count < 4096 else { throw CoolingSMC.Error.invalidData }
        }
        throw CoolingSMC.Error.unavailable
    }
}
