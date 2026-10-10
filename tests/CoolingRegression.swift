import Foundation
import Darwin

@main
struct CoolingRegression {
    static func require(_ condition: Bool, _ message: String) { precondition(condition, message) }

    static func main() throws {
        require(try CoolingSMC.fourCC("F0Ac") == 0x46304163, "SMC key byte order")
        let rpm = 7826.0
        let float = try CoolingSMC.rpmBytes(rpm, type: "flt ")
        require(CoolingSMC.Value(type: "flt ", bytes: float).number == rpm, "float RPM roundtrip")
        let encoded = try CoolingSMC.rpmBytes(1250, type: "fpe2")
        require(encoded == [0x13, 0x88], "fpe2 byte order")
        require(CoolingSMC.Value(type: "fpe2", bytes: encoded).number == 1250, "fpe2 roundtrip")
        require(CoolingSMC.Value(type: "ui8 ", bytes: []).number == nil, "short data rejected")
        require(CoolingSMC.Value(type: "sp78", bytes: [0x80, 0]).number == -128, "signed temperature")
        let fan = CoolingFan(id: 0, name: "Test", actualRPM: 0, targetRPM: 0, minimumRPM: 2317, maximumRPM: 7826, mode: .automatic)
        require(abs(try fan.rpm(at: 0.3) - 3969.7) < 0.01, "30% range")
        require(try fan.rpm(at: 1) == 7826, "100% range")
        do { _ = try fan.rpm(at: .nan); fatalError("NaN was accepted") } catch {}
        do { _ = try fan.rpm(at: 2); fatalError("invalid percentage accepted") } catch {}

        var sockets: [Int32] = [-1, -1]
        require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0, "socketpair")
        defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
        try CoolingSocket.send(CoolingRequest(command: "preset", fanID: 1, fraction: 0.7), to: sockets[0])
        let request = try CoolingSocket.receive(CoolingRequest.self, from: sockets[1])
        require(request.command == "preset" && request.fanID == 1 && request.fraction == 0.7, "IPC roundtrip")
        do {
            try CoolingSocket.send(CoolingRequest(command: String(repeating: "x", count: 4096)), to: sockets[0])
            fatalError("oversized message was accepted")
        } catch {}

        let helper = CommandLine.arguments[1]
        let session = CoolingHelperSession(helperOverride: helper, readOnlyProbe: true)
        _ = try session.command(CoolingRequest(command: "ping"))
        require(session.isConnected, "authenticated test helper did not connect")
        do {
            _ = try session.command(CoolingRequest(command: "preset", fanID: 0, fraction: 0.5))
            fatalError("test helper allowed a write")
        } catch {
            require(error.localizedDescription == "Read-only test helper rejects fan writes.", "unexpected rejection")
        }
        // Regression: a structured error must not tear down administrator access.
        require(session.isConnected, "command rejection closed the approved session")
        try session.heartbeat()
        _ = try session.command(CoolingRequest(command: "ping"))
        session.close()
        require(!session.isConnected, "disconnect did not close the session")

        // A toggle-off while authorization is pending must stop before sending
        // a fan command, even if the helper has since connected successfully.
        let cancelled = CoolingHelperSession(helperOverride: helper, readOnlyProbe: true)
        do {
            _ = try cancelled.command(CoolingRequest(command: "preset", fanID: 0, fraction: 1), shouldProceed: { false })
            fatalError("cancelled command was applied")
        } catch {
            require(error.localizedDescription == "Fan control was disabled before the command was applied.", "command reached helper after cancellation")
            require(!cancelled.isConnected, "cancelled authorization kept its helper alive")
        }
        print("PASS: SMC encoding, preset limits, bounded IPC, rejected-command session reuse, and authorization cancellation")
    }
}
