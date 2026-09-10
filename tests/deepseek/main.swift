import Foundation

func check(_ value: @autoclosure () -> Bool, _ label: String) {
    if !value() { fatalError(label) }
}
for (input, expected) in [
    ("https://api.deepseek.com", "https://api.deepseek.com/chat/completions"),
    (" https://api.deepseek.com/v1/ ", "https://api.deepseek.com/v1/chat/completions"),
    ("http://localhost:11434/v1", "http://localhost:11434/v1/chat/completions"),
    ("http://127.0.0.1:8000/v1/chat/completions", "http://127.0.0.1:8000/v1/chat/completions")
] {
    check(DeepSeekConfiguration.completionURL(input)?.absoluteString == expected, input)
}
for invalid in ["", "localhost:8000", "ftp://example.com", "https://", "https://host/v1?key=secret", "https://user:pass@host/v1"] {
    check(DeepSeekConfiguration.completionURL(invalid) == nil, invalid)
}
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
print("DeepSeek configuration and request tests passed")

let streamed = try DeepSeekConfiguration.request(endpoint: "https://api.deepseek.com", model: "deepseek-v4-flash", apiKey: "test-key", messages: [], stream: true, thinking: false)
let streamedBody = try JSONSerialization.jsonObject(with: streamed.httpBody!) as! [String: Any]
check(streamedBody["stream"] as? Bool == true, "Native chat must stream")
check((streamedBody["thinking"] as? [String:String])?["type"] == "disabled", "Thinking toggle must reach request")
check(payload["thinking"] == nil, "Custom servers do not receive unsupported thinking parameters by default")
