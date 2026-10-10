// Test fixture: exercises the production socket/authorization client without
// AppleSMC, fan hardware, administrator prompts, or any privileged writes.
import Foundation
import Darwin

@main
struct CoolingSessionHelper {
    /// Authenticates an unprivileged IPC fixture that accepts heartbeats and rejects all fan writes.
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 6, args[1] == "--ipc-read-only" else { exit(1) }
        let fd = try CoolingSocket.connect(args[2])
        defer { Darwin.close(fd) }
        try CoolingSocket.send(CoolingReply(ok: true), to: fd)
        let hello = try CoolingSocket.receive(CoolingRequest.self, from: fd)
        guard hello.command == "hello", hello.token == args[5] else { exit(1) }
        try CoolingSocket.send(CoolingReply(ok: true), to: fd)
        while let request = try? CoolingSocket.receive(CoolingRequest.self, from: fd) {
            if request.command == "ping" {
                try CoolingSocket.send(CoolingReply(ok: true), to: fd)
            } else {
                try CoolingSocket.send(CoolingReply(ok: false, message: "Read-only test helper rejects fan writes."), to: fd)
            }
        }
    }
}
