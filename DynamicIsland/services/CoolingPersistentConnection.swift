import Foundation
import ServiceManagement

/// Uses the macOS-managed, signed daemon after the user has approved one-time setup.
final class CoolingPersistentConnection: @unchecked Sendable {
    private let connection: NSXPCConnection
    private let lock = NSLock()
    private var connected = true

    /// Reports transport state without racing XPC's invalidation callbacks.
    var isConnected: Bool { lock.lock(); defer { lock.unlock() }; return connected }

    /// Opens an authenticated privileged XPC connection and verifies the helper with a heartbeat.
    init() throws {
        let requirement = try CoolingXPC.requirement(identifier: CoolingXPC.serviceName)
        connection = NSXPCConnection(machServiceName: CoolingXPC.serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: CoolingXPCProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.invalidationHandler = { [weak self] in self?.markDisconnected() }
        connection.interruptionHandler = { [weak self] in self?.markDisconnected() }
        connection.resume()
        do { let reply = try command(CoolingRequest(command: "ping")); guard reply.ok else { throw CoolingSMC.Error.permission } }
        catch { close(); throw error }
    }

    /// Marks an interrupted transport unavailable so the UI can explicitly retry without a password.
    private func markDisconnected() { lock.lock(); connected = false; lock.unlock() }

    /// Executes a bounded request off the UI thread with a deadline; fan errors preserve the connection.
    func command(_ request: CoolingRequest) throws -> CoolingReply {
        guard isConnected else { throw CoolingSMC.Error.unavailable }
        let data = try JSONEncoder().encode(request)
        guard data.count <= 4096 else { throw CoolingSMC.Error.invalidData }
        let result = CoolingXPCResult()
        guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in result.complete(.failure(error)) }) as? CoolingXPCProtocol else {
            close(); throw CoolingSMC.Error.unavailable
        }
        remote.execute(data) { bytes in
            do {
                guard bytes.count <= 4096 else { throw CoolingSMC.Error.invalidData }
                result.complete(.success(try JSONDecoder().decode(CoolingReply.self, from: bytes)))
            } catch { result.complete(.failure(error)) }
        }
        do { return try result.wait() }
        catch { close(); throw error }
    }

    /// Disconnects so the daemon restores Auto; its registered installation remains available.
    func close() {
        let wasConnected = isConnected
        markDisconnected()
        if wasConnected,
           let data = try? JSONEncoder().encode(CoolingRequest(command: "quit")),
           let remote = connection.remoteObjectProxyWithErrorHandler({ _ in }) as? CoolingXPCProtocol {
            let completion = CoolingXPCResult()
            remote.execute(data) { _ in completion.complete(.success(CoolingReply(ok: true))) }
            _ = try? completion.wait()
        }
        connection.invalidate()
    }
    deinit { close() }
}

/// Synchronizes reply/error callbacks and prevents a delayed XPC reply from escaping its timeout.
private final class CoolingXPCResult: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var value: Result<CoolingReply, Error>?
    /// Stores only the first completion, even if invalidation races a normal reply.
    func complete(_ result: Result<CoolingReply, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard value == nil else { return }
        value = result; semaphore.signal()
    }
    /// Waits on the worker queue, never blocking the main UI thread.
    func wait() throws -> CoolingReply {
        guard semaphore.wait(timeout: .now() + 15) == .success else { throw CoolingSMC.Error.unavailable }
        lock.lock(); let result = value; lock.unlock()
        guard let result else { throw CoolingSMC.Error.unavailable }
        return try result.get()
    }
}

enum CoolingPersistentSupport {
    /// Identifies the embedded daemon by its launchd property list.
    static var service: SMAppService { SMAppService.daemon(plistName: CoolingXPC.plistName) }

    /// Uses persistent authorization only after registration; tests retain their read-only fixtures.
    static func connectionIfRegistered() throws -> CoolingPersistentConnection? {
        switch service.status {
        case .enabled: return try CoolingPersistentConnection()
        case .requiresApproval:
            throw NSError(domain: "AtollCooling", code: 11, userInfo: [NSLocalizedDescriptionKey:
                "Approve Atoll’s fan helper in System Settings → General → Login Items & Extensions, then retry the connection."])
        // ServiceManagement may report notFound before the first registration,
        // even when the bundled plist is present. Keep session controls usable.
        case .notRegistered, .notFound: return nil
        default:
            throw NSError(domain: "AtollCooling", code: 12, userInfo: [NSLocalizedDescriptionKey:
                "The installed fan helper is unavailable. Remove it and install it again in Atoll’s Cooling settings."])
        }
    }
}
