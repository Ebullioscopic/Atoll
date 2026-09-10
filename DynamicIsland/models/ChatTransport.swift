import Foundation

/// Network work is asynchronous; only delivered UI updates run on the main actor.
@MainActor
enum ChatTransport {
    static func json(_ url: URL, body: [String: Any]? = nil, timeout: TimeInterval = 15) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            try checkSize(request.httpBody)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ChatStreamChunk.failure(String(localized: "Invalid response from the model."))
        }
        if let error = value["error"] {
            throw ChatStreamChunk.failure((error as? [String: Any])?["message"] as? String ?? error as? String ?? String(localized: "The service request failed. Please check the connection."))
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ChatStreamChunk.failure(value["error"] as? String ?? String(localized: "The service request failed. Please check the connection."))
        }
        return value
    }

    static func checkSize(_ data: Data?) throws {
        guard (data?.count ?? 0) <= 40 * 1024 * 1024 else {
            throw ChatStreamChunk.failure(String(localized: "This conversation contains too much image data. Start a new chat or use smaller images."))
        }
    }

    static func bridgeInfo(_ base: URL) async throws -> [String: Any]? {
        // Only probe loopback services; do not send a user's conversation to a health endpoint.
        guard ["127.0.0.1", "localhost", "::1", "[::1]"].contains(base.host?.lowercased() ?? "") else { return nil }
        do {
            let info = try await json(base.appendingPathComponent("health"), timeout: 3)
            return info["backend"] as? String == "pi" ? info : nil
        } catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation(); return nil }
    }

    static func stream(_ request: URLRequest, ollama: Bool,
                       update: (ChatStreamChunk) -> Void) async throws {
        try checkSize(request.httpBody)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ChatStreamChunk.failure(String(format: String(localized: "The model request failed (HTTP %d)."), status))
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        let plainJSON = contentType.contains("application/json") && !ollama
        var collected = ""
        var event = ""
        var finished = false
        var received = false
        var totalBytes = 0
        func consumeLine(_ line: String) throws -> Bool {
            try Task.checkCancellation()
            if plainJSON { collected += line; return false }
            if ollama {
                if line.isEmpty { return false }
                let chunk = try ChatStreamChunk.parse(Data(line.utf8), ollama: true)
                update(chunk); received = true; finished = finished || chunk.finished
                try Task.checkCancellation()
                return chunk.finished
            }
            if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if data == "[DONE]" { finished = true; return true }
                event += (event.isEmpty ? "" : "\n") + data
            } else if line.isEmpty, !event.isEmpty {
                let chunk = try ChatStreamChunk.parse(Data(event.utf8), ollama: false)
                update(chunk); received = true; finished = finished || chunk.finished; event = ""
                try Task.checkCancellation()
            }
            return false
        }
        // AsyncBytes.lines omits empty lines. SSE requires those delimiters to
        // dispatch each event before EOF; decode bytes without dropping them.
        var lineData = Data()
        var skipLF = false
        var terminated = false
        for try await byte in bytes {
            try Task.checkCancellation()
            totalBytes += 1
            guard totalBytes < 8 * 1024 * 1024 else { throw ChatStreamChunk.failure(String(localized: "The response is too large.")) }
            if byte == 10 && skipLF { skipLF = false; continue }
            skipLF = byte == 13
            if byte == 10 || byte == 13 {
                guard let line = String(data: lineData, encoding: .utf8) else { throw ChatStreamChunk.failure(String(localized: "Invalid response from the model.")) }
                lineData.removeAll(keepingCapacity: true)
                if try consumeLine(line) { terminated = true; break }
            } else { lineData.append(byte) }
        }
        try Task.checkCancellation()
        if !terminated && !lineData.isEmpty {
            guard let line = String(data: lineData, encoding: .utf8) else { throw ChatStreamChunk.failure(String(localized: "Invalid response from the model.")) }
            _ = try consumeLine(line)
        }
        if plainJSON {
            let chunk = try ChatStreamChunk.parse(Data(collected.utf8), ollama: false)
            update(chunk); received = true; finished = chunk.finished
        } else if !event.isEmpty {
            let chunk = try ChatStreamChunk.parse(Data(event.utf8), ollama: false)
            update(chunk); received = true; finished = finished || chunk.finished
        }
        try Task.checkCancellation()
        guard received, finished else { throw ChatStreamChunk.failure(String(localized: "The connection ended before the reply was complete. You can retry this message.")) }
    }
}
