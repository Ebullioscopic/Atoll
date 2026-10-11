import Foundation
import Security

/// The persistent helper exposes one bounded fan-only request, never a shell or file operation.
@objc protocol CoolingXPCProtocol {
    func execute(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

enum CoolingXPC {
    // Derive the pair from our own signature so a locally signed fork does not
    // inherit the original publisher's background-task authorization record.
    static let appIdentifier: String = {
        let identifier = (try? signingInformation()[kSecCodeInfoIdentifier as String] as? String) ?? Bundle.main.bundleIdentifier
        guard let identifier,
              identifier.range(of: "^[A-Za-z0-9][A-Za-z0-9.-]{1,200}$", options: .regularExpression) != nil else {
            return "com.Ebullioscopic.Atoll"
        }
        return identifier.hasSuffix(".cooling") ? String(identifier.dropLast(".cooling".count)) : identifier
    }()
    static let serviceName = appIdentifier + ".cooling"
    static let plistName = serviceName + ".plist"

    /// Reads metadata from this executable's own signature, never from a caller-supplied path.
    private static func signingInformation() throws -> [String: Any] {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { throw CoolingSMC.Error.permission }
        return values
    }

    /// Reads the current executable's signing team; ad-hoc builds cannot install this service.
    static func signingTeam() throws -> String {
        guard let team = try signingInformation()[kSecCodeInfoTeamIdentifier as String] as? String,
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
