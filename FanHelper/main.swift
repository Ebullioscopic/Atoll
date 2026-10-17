import Foundation
import Darwin

var helperPhase = "open AppleSMC"

/// Runs the authenticated, session-scoped cooling helper and restores owned fans on exit.
/// Production writes require root; explicit read-only modes support inspection and IPC tests.
func runCoolingHelper() throws {
    var arguments = CommandLine.arguments
    let readOnlyProbe = arguments.count > 1 && arguments[1] == "--ipc-read-only"
    if readOnlyProbe { arguments.remove(at: 1) }
    let smc = try CoolingSMC()
    if arguments.count == 2, arguments[1] == "--read-only" {
        let data = try JSONEncoder().encode(smc.fans())
        print(String(decoding: data, as: UTF8.self))
        let temperature = try smc.hottestTemperature()
        print("Hottest temperature: \(temperature.map { String($0) } ?? "unavailable")")
        return
    }
    helperPhase = "validate helper arguments and privileges"
    guard arguments.count == 5, (readOnlyProbe || geteuid() == 0),
          let parent = Int32(arguments[2]), parent > 1,
          let owner = UInt32(arguments[3]), owner > 0,
          kill(parent, 0) == 0 else { throw CoolingSMC.Error.permission }
    helperPhase = "connect to Atoll"
    let fd = try CoolingSocket.connect(arguments[1])
    defer { smc.restoreOwnedFans(); Darwin.close(fd) }
    var uid: uid_t = 0, gid: gid_t = 0
    helperPhase = "verify Atoll credentials"
    guard getpeereid(fd, &uid, &gid) == 0, uid == owner else {
        throw NSError(domain: "AtollCooling", code: 1, userInfo: [NSLocalizedDescriptionKey: "Atoll connection owner mismatch (expected \(owner), got \(uid))."])
    }
    helperPhase = "authenticate session"
    try CoolingSocket.send(CoolingReply(ok: true), to: fd)
    let hello = try CoolingSocket.receive(CoolingRequest.self, from: fd)
    guard hello.command == "hello", hello.token == arguments[4] else { throw CoolingSMC.Error.permission }
    try CoolingSocket.send(CoolingReply(ok: true), to: fd)
    helperPhase = "read temperatures"
    // Prime the sensor cache before accepting a preset; there is no write here.
    guard try smc.hottestTemperature() != nil else { throw CoolingSMC.Error.unavailable }
    let engine = CoolingDaemonEngine(hardwareProvider: { smc })
    defer { engine.close() }
    helperPhase = "process cooling requests"
    while kill(parent, 0) == 0, engine.tick() {
        var event = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let available = poll(&event, 1, 1000)
        if available < 0, errno == EINTR { continue }
        guard available >= 0 else { break }
        if available == 0 { continue }
        let request = try CoolingSocket.receive(CoolingRequest.self, from: fd, timeout: 3)
        if readOnlyProbe, request.command == "preset" || request.command == "auto" {
            try CoolingSocket.send(CoolingReply(ok: false, message: CoolingSMC.Error.permission.localizedDescription), to: fd)
            continue
        }
        try CoolingSocket.send(engine.execute(request), to: fd)
        if request.command == "quit" { return }
    }
}

do {
    if CommandLine.arguments == [CommandLine.arguments[0], "--daemon"] { try runCoolingDaemon() }
    else { try runCoolingHelper() }
}
catch { fputs("Atoll cooling (\(helperPhase)): \(error.localizedDescription)\n", stderr); exit(1) }
