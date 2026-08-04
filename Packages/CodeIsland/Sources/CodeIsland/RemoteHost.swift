import Foundation

struct RemoteHost: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var host: String
    var user: String
    var port: Int?
    var identityFile: String
    var autoConnect: Bool
    /// Optional SSH_AUTH_SOCK path — lets password-manager-backed SSH agents
    /// (1Password, Bitwarden, etc.) sign the handshake when the GUI launch
    /// didn't inherit the env var from a shell. See issue #81.
    var authSocket: String
    /// Comma-separated cwd substrings. When non-empty, only remote sessions whose
    /// working directory contains one of these substrings are shown — lets users on
    /// a shared remote account scope the panel to their own project folders (#240).
    /// Empty = show every session from this host (previous behavior).
    var cwdFilter: String

    init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        user: String = "",
        port: Int? = nil,
        identityFile: String = "",
        autoConnect: Bool = false,
        authSocket: String = "",
        cwdFilter: String = ""
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.autoConnect = autoConnect
        self.authSocket = authSocket
        self.cwdFilter = cwdFilter
    }

    // Backward compatibility: hosts persisted before authSocket/cwdFilter existed decode with ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.host = try c.decode(String.self, forKey: .host)
        self.user = try c.decode(String.self, forKey: .user)
        self.port = try c.decodeIfPresent(Int.self, forKey: .port)
        self.identityFile = try c.decode(String.self, forKey: .identityFile)
        self.autoConnect = try c.decode(Bool.self, forKey: .autoConnect)
        self.authSocket = try c.decodeIfPresent(String.self, forKey: .authSocket) ?? ""
        self.cwdFilter = try c.decodeIfPresent(String.self, forKey: .cwdFilter) ?? ""
    }

    var sshTarget: String {
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.isEmpty {
            return host.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(trimmedUser)@\(host.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Legacy shared fallback socket path. The live per-user path is resolved at
    /// connect time via `RemoteInstaller.prepareRemoteSocketPath` (#193); this value
    /// is only used when probing the remote UID fails.
    var remoteSocketPath: String { "/tmp/codeisland.sock" }

    var displayAddress: String {
        if let port {
            return "\(sshTarget):\(port)"
        }
        return sshTarget
    }
}
