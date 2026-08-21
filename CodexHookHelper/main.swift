import Foundation

do {
    let rawEvent = FileHandle.standardInput.readDataToEndOfFile()
    if !rawEvent.isEmpty {
        let payload = try JSONSerialization.jsonObject(with: rawEvent)
        if JSONSerialization.isValidJSONObject(payload) {
            let eventID = UUID()
            let receivedAt = Date()
            let root: URL
            if let override = ProcessInfo.processInfo.environment["ATOLL_CODEX_DATA_ROOT"],
               !override.isEmpty {
                root = URL(fileURLWithPath: override, isDirectory: true)
            } else {
                root = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Atoll/Codex", isDirectory: true)
            }
            let inbox = root.appendingPathComponent("inbox", isDirectory: true)
            try FileManager.default.createDirectory(
                at: inbox,
                withIntermediateDirectories: true
            )

            let formatter = ISO8601DateFormatter()
            let envelope: [String: Any] = [
                "event_id": eventID.uuidString,
                "received_at": formatter.string(from: receivedAt),
                "source": "codex-hook",
                "payload": payload,
            ]
            let data = try JSONSerialization.data(withJSONObject: envelope)
            let fileName = "\(Int(receivedAt.timeIntervalSince1970 * 1_000))-\(eventID.uuidString).json"
            let destination = inbox.appendingPathComponent(fileName)
            try data.write(to: destination, options: .atomic)
        }
    }
} catch {
    let message = "CodexHookHelper failed to enqueue event: \(error)\n"
    try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
}

// Hook failures must never block Codex. stdout intentionally remains empty.
