import Foundation

struct ChatRequestTurn: Sendable {
    let role: String
    let text: String
    var images: [ImageAttachment] = []
    var reasoning: String = ""
}

enum ChatRequestBuilder {
    static func isOfficial(_ endpoint: String) -> Bool {
        URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() == "api.deepseek.com"
    }
    static func model(endpoint: String, selected: String, vision: String, hasImages: Bool) -> String {
        hasImages && isOfficial(endpoint) ? vision : selected
    }
    static func localBase(_ endpoint: String) -> URL? {
        guard var url = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        while url.path.hasSuffix("/") { url.path.removeLast() }
        if url.path.hasSuffix("/api/chat") { url.path.removeLast(9) }
        else if url.path.hasSuffix("/api") { url.path.removeLast(4) }
        return url.url
    }
    static func openAIMessages(_ turns: [ChatRequestTurn]) -> [[String: Any]] {
        turns.map { turn in
            var value: [String: Any] = ["role": turn.role, "content": turn.text]
            if !turn.images.isEmpty {
                value["content"] = [["type": "text", "text": turn.text]] + turn.images.map(\.openAIContent)
            }
            if turn.role == "assistant", !turn.reasoning.isEmpty { value["reasoning_content"] = turn.reasoning }
            return value
        }
    }
    static func ollamaMessages(_ turns: [ChatRequestTurn]) -> [[String: Any]] {
        turns.map { turn in
            var value: [String: Any] = ["role": turn.role, "content": turn.text]
            if !turn.images.isEmpty { value["images"] = turn.images.map(\.base64) }
            return value
        }
    }
}

struct ChatStreamChunk {
    var text = ""
    var reasoning = ""
    var model: String?
    var finished = false
    var truncated = false
    static func parse(_ data: Data, ollama: Bool) throws -> ChatStreamChunk {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw failure(String(localized: "Invalid response from the model."))
        }
        if let error = json["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? error as? String ?? String(localized: "The model request failed.")
            throw failure(message)
        }
        var result = ChatStreamChunk(model: json["model"] as? String)
        if ollama {
            let message = json["message"] as? [String: Any] ?? [:]
            result.text = message["content"] as? String ?? ""
            result.reasoning = message["thinking"] as? String ?? ""
            result.finished = json["done"] as? Bool == true
        } else if let choice = (json["choices"] as? [[String: Any]])?.first {
            let message = choice["delta"] as? [String: Any] ?? choice["message"] as? [String: Any] ?? [:]
            result.text = message["content"] as? String ?? ""
            result.reasoning = message["reasoning_content"] as? String ?? ""
            result.finished = choice["finish_reason"] is String || choice["message"] != nil
            result.truncated = choice["finish_reason"] as? String == "length"
        }
        return result
    }
    static func failure(_ message: String) -> NSError {
        NSError(domain: "AtollChat", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
