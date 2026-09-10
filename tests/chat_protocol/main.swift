import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    if !condition() { fatalError(label) }
}
let png = try ImageAttachment(data: Data([137,80,78,71,13,10,26,10]))
let turns = [ChatRequestTurn(role: "user", text: "看图片", images: [png]), ChatRequestTurn(role: "assistant", text: "一张图", reasoning: "visual analysis"), ChatRequestTurn(role: "user", text: "左上角呢？")]
let messages = ChatRequestBuilder.openAIMessages(turns)
expect((messages[0]["content"] as? [[String:Any]])?.count == 2, "Follow-up must retain original image bytes")
expect(messages[1]["reasoning_content"] as? String == "visual analysis", "Assistant reasoning must survive follow-up")
let ollama = ChatRequestBuilder.ollamaMessages(turns)
expect(ollama.count == 3, "Direct Ollama must receive all turns")
expect((ollama[0]["images"] as? [String])?.first == png.base64, "Ollama follow-up must retain images")
expect(ChatRequestBuilder.model(endpoint: "http://localhost:1234/v1", selected: "my-vision-model", vision: "official-vision", hasImages: true) == "my-vision-model", "Custom endpoint must not get official hard-coded model")
expect(ChatRequestBuilder.model(endpoint: "https://api.deepseek.com", selected: "text-model", vision: "vision-model", hasImages: true) == "vision-model", "Official endpoint uses configured vision model")
expect(ChatRequestBuilder.localBase("http://127.0.0.1:11435/api/chat/")?.absoluteString == "http://127.0.0.1:11435", "Normalize legacy chat URL")
expect(ChatRequestBuilder.localBase("https://user:pass@host") == nil, "Reject credentials in URL")
let chunk = try ChatStreamChunk.parse(Data(#"{"choices":[{"delta":{"content":"你好","reasoning_content":"思考"},"finish_reason":null}],"model":"actual"}"#.utf8), ollama: false)
expect(chunk.text == "你好" && chunk.reasoning == "思考" && chunk.model == "actual", "Parse content and reasoning separately")
let done = try ChatStreamChunk.parse(Data(#"{"done":true,"message":{"content":"完成"}}"#.utf8), ollama: true)
expect(done.finished && done.text == "完成", "Ollama completion is required")
var rejected = false
do { _ = try ChatStreamChunk.parse(Data(#"{"error":{"message":"invalid model"}}"#.utf8), ollama:false) } catch { rejected = true }
expect(rejected, "Streaming API error must not masquerade as empty success")
print("Chat protocol tests passed: multi-turn image/reasoning context, endpoint/model selection, streamed content and errors")
