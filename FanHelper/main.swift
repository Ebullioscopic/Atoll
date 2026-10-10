import Foundation
import Darwin

var helperPhase = "open AppleSMC"

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
    var leaseExpires = Date().addingTimeInterval(15)
    var lastTemperatureCheck = Date.distantPast
    var thermalError: String?
    helperPhase = "process cooling requests"
    while kill(parent, 0) == 0, Date() < leaseExpires {
        if Date().timeIntervalSince(lastTemperatureCheck) >= 2 {
            if let hottest = try? smc.hottestTemperature(), hottest < 95 {
                thermalError = nil
            } else {
                smc.restoreOwnedFans()
                thermalError = "Automatic cooling restored because temperatures are high or unavailable."
            }
            lastTemperatureCheck = Date()
        }
        var event = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let available = poll(&event, 1, 1000)
        if available < 0, errno == EINTR { continue }
        guard available >= 0 else { break }
        if available == 0 { continue }
        let request = try CoolingSocket.receive(CoolingRequest.self, from: fd, timeout: 3)
        leaseExpires = Date().addingTimeInterval(15)
        do {
            switch request.command {
            case "ping": break
            case "preset":
                guard !readOnlyProbe else { throw CoolingSMC.Error.permission }
                guard thermalError == nil else {
                    throw NSError(domain: "AtollCooling", code: 1, userInfo: [NSLocalizedDescriptionKey: thermalError!])
                }
                guard let fan = request.fanID, let fraction = request.fraction,
                      [0.3, 0.5, 0.7, 1.0].contains(fraction) else { throw CoolingSMC.Error.invalidData }
                try smc.setPreset(fraction, index: fan)
            case "auto":
                guard !readOnlyProbe else { throw CoolingSMC.Error.permission }
                guard let fan = request.fanID else { throw CoolingSMC.Error.invalidData }
                try smc.setAutomatic(index: fan)
            case "quit":
                smc.restoreOwnedFans()
                try CoolingSocket.send(CoolingReply(ok: true), to: fd)
                return
            default: throw CoolingSMC.Error.invalidData
            }
            try CoolingSocket.send(CoolingReply(ok: thermalError == nil, message: thermalError), to: fd)
        } catch {
            try CoolingSocket.send(CoolingReply(ok: false, message: error.localizedDescription), to: fd)
        }
    }
}

do { try runCoolingHelper() }
catch { fputs("Atoll cooling (\(helperPhase)): \(error.localizedDescription)\n", stderr); exit(1) }
