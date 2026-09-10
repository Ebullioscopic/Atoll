import Foundation

/// OpenAI-compatible DeepSeek configuration, shared by settings and requests.
enum DeepSeekConfiguration {
    private static func isLoopback(_ host: String) -> Bool {
        ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
    }

    static func completionURL(_ endpoint: String) -> URL? {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              scheme == "https" || isLoopback(host),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return nil }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        return components.url
    }

    static func isValid(endpoint: String, model: String, apiKey: String) -> Bool {
        guard let url = completionURL(endpoint),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let local = isLoopback(url.host ?? "")
        return local || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func request(endpoint: String, model: String, apiKey: String,
                        messages: [[String: Any]], stream: Bool = false, thinking: Bool? = nil) throws -> URLRequest {
        guard isValid(endpoint: endpoint, model: model, apiKey: apiKey),
              let url = completionURL(endpoint) else {
            throw NSError(domain: "DeepSeek", code: 1, userInfo: [NSLocalizedDescriptionKey:
                String(localized: "Check the DeepSeek endpoint, model name, and API key. Remote endpoints require HTTPS and an API key. Only loopback endpoints (localhost, 127.0.0.1, or [::1]) can use HTTP or omit the key.")])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": messages,
            "stream": stream
        ]
        if let thinking { body["thinking"] = ["type": thinking ? "enabled" : "disabled"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
