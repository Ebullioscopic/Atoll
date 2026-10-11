import Foundation
import Security

/// The persistent helper exposes one bounded fan-only request, never a shell or file operation.
@objc protocol CoolingXPCProtocol {
    func execute(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

enum CoolingXPC {
    static let appIdentifier = "com.Ebullioscopic.Atoll"
    static let serviceName = "com.Ebullioscopic.Atoll.cooling"
    static let plistName = serviceName + ".plist"

    /// Reads the current executable's signing team; ad-hoc builds cannot install this service.
    static func signingTeam() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw NSError(domain: "AtollCooling", code: 10, userInfo: [NSLocalizedDescriptionKey:
                "Persistent fan control requires Atoll and its helper to be signed with the same developer identity."])
        }
        return team
    }

    /// Requires Apple's signing anchor, the exact executable identifier, and our own developer team.
    static func requirement(identifier: String) throws -> String {
        let requirement = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(try signingTeam())\""
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else {
            throw CoolingSMC.Error.permission
        }
        return requirement
    }

    /// Encodes a fan-only response; a serialization failure becomes a fixed rejection.
    static func encode(_ reply: CoolingReply) -> Data {
        (try? JSONEncoder().encode(reply)) ?? Data("{\"ok\":false,\"message\":\"Invalid helper response.\"}".utf8)
    }
}
