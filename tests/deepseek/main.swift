import Foundation

func check(_ value: @autoclosure () -> Bool, _ label: String) {
    if !value() { fatalError(label) }
}
for (input, expected) in [
    ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions"),
    (" https://api.deepseek.com/v1/ ", "https://api.deepseek.com/v1/chat/completions"),
    ("http://localhost:11434/v1", "http://localhost:11434/v1/chat/completions"),
    ("http://127.0.0.1:8000/v1/chat/completions", "http://127.0.0.1:8000/v1/chat/completions"),
    ("http://[::1]:8000/v1", "http://[::1]:8000/v1/chat/completions"),
    ("https://example.com/v1", "https://example.com/v1/chat/completions")
] {
    check(DeepSeekConfiguration.completionURL(input)?.absoluteString == expected, input)
}
for invalid in ["", "localhost:8000", "ftp://example.com", "https://", "https://host/v1?key=secret", "https://user:pass@host/v1"] {
    check(DeepSeekConfiguration.completionURL(invalid) == nil, invalid)
}
let configurationError = String(localized: "Check the DeepSeek endpoint, model name, and API key. Remote endpoints require HTTPS and an API key. Only loopback endpoints (localhost, 127.0.0.1, or [::1]) can use HTTP or omit the key.")
for endpoint in [
    "http://api.deepseek.com", " HTTP://example.com/v1 ",
    "http://localhost.example.com", "http://127.0.0.1.example.com",
    "http://localhost@evil.example", "http://192.168.1.1:8000",
    "http://127.0.0.2", "http://127.1", "http://2130706433",
    "http://[::2]", "http://[::ffff:127.0.0.1]", "http://localhost."
] {
    check(DeepSeekConfiguration.completionURL(endpoint) == nil, "Reject non-loopback HTTP URL: \(endpoint)")
    for key in ["", "secret-key"] {
        check(!DeepSeekConfiguration.isValid(endpoint: endpoint, model: "test", apiKey: key), "Settings reject HTTP: \(endpoint)")
        do {
            _ = try DeepSeekConfiguration.request(endpoint: endpoint, model: "test", apiKey: key, messages: [])
            fatalError("Request accepted non-loopback HTTP: \(endpoint)")
        } catch {
            let error = error as NSError
            check(error.domain == "DeepSeek" && error.code == 1, "Configuration error identity")
            check(error.localizedDescription == configurationError, "Localized HTTPS guidance")
        }
    }
}
for endpoint in ["http://localhost:8000", "HTTP://LOCALHOST:8000", "http://127.0.0.1:8000", "http://[::1]:8000"] {
    for key in ["", "local-key"] {
        check(DeepSeekConfiguration.isValid(endpoint: endpoint, model: "test", apiKey: key), "Settings accept exact loopback: \(endpoint)")
        let local = try DeepSeekConfiguration.request(endpoint: endpoint, model: "test", apiKey: key, messages: [])
        check(local.url != nil, "Construct loopback request")
        check(local.value(forHTTPHeaderField: "Authorization") == (key.isEmpty ? nil : "Bearer \(key)"), "Loopback key handling")
    }
}
check(DeepSeekConfiguration.isValid(endpoint: "https://example.com", model: "test", apiKey: "secret-key"), "Remote HTTPS with key")
check(!DeepSeekConfiguration.isValid(endpoint: "https://example.com", model: "test", apiKey: ""), "Remote HTTPS requires key")
check(!DeepSeekConfiguration.isValid(endpoint: "https://api.deepseek.com", model: "x", apiKey: " "), "Official API needs key")
check(DeepSeekConfiguration.isValid(endpoint: "http://localhost:11434/v1", model: "deepseek-r1:8b", apiKey: ""), "Local server permits no key")
check(!DeepSeekConfiguration.isValid(endpoint: "http://localhost:11434/v1", model: " ", apiKey: ""), "Model required")
let request = try DeepSeekConfiguration.request(endpoint: "http://localhost:11434/v1", model: " deepseek-r1:8b ", apiKey: "", messages: [["role": "user", "content": "hello"]])
check(request.httpMethod == "POST", "POST")
check(request.value(forHTTPHeaderField: "Authorization") == nil, "No empty bearer header")
let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
check(payload["model"] as? String == "deepseek-r1:8b", "Custom model")
check(payload["stream"] as? Bool == false, "Nonstream response parser")
let official = try DeepSeekConfiguration.request(endpoint: "https://api.deepseek.com", model: "deepseek-v4-flash", apiKey: " test-key ", messages: [])
check(official.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "Trimmed key")

let streamed = try DeepSeekConfiguration.request(endpoint: "https://api.deepseek.com", model: "deepseek-v4-flash", apiKey: "test-key", messages: [], stream: true, thinking: false)
let streamedBody = try JSONSerialization.jsonObject(with: streamed.httpBody!) as! [String: Any]
check(streamedBody["stream"] as? Bool == true, "Native chat must stream")
check((streamedBody["thinking"] as? [String:String])?["type"] == "disabled", "Thinking toggle must reach request")
check(payload["thinking"] == nil, "Custom servers do not receive unsupported thinking parameters by default")
print("DeepSeek configuration and request tests passed")
