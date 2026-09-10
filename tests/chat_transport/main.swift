import Foundation
import Darwin

// Run from Atoll. No application target, keys, sockets, or package dependencies:
// swiftc -target arm64-apple-macos15.5 DynamicIsland/models/ImageAttachment.swift \
//   DynamicIsland/models/ChatRequestBuilder.swift DynamicIsland/models/ChatTransport.swift \
//   tests/chat_transport/main.swift -o /tmp/atoll-chat-transport-tests
// /tmp/atoll-chat-transport-tests
// These assert desired behavior; known transport regressions intentionally fail.

struct Fixture {
    var type = "text/event-stream"
    var status = 200
    var parts: [Data]
    var finish = true
}

/// Register before URLSession.shared is first accessed. Intercept EVERY request:
/// an unexpected request fails locally rather than falling through to the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    private static var starts: [String: Int] = [:]
    private static var stops: [String: Int] = [:]

    static func install(_ fixture: Fixture, name: String) -> URLRequest {
        lock.lock()
        fixtures[name] = fixture
        lock.unlock()
        var request = URLRequest(url: URL(string: "https://atoll-transport.invalid/\(name)")!)
        request.timeoutInterval = 2
        return request
    }
    static func counts(_ name: String) -> (started: Int, stopped: Int) {
        lock.lock(); defer { lock.unlock() }
        return (starts[name, default: 0], stops[name, default: 0])
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let name = request.url!.lastPathComponent
        Self.lock.lock()
        let fixture = Self.fixtures[name]
        Self.starts[name, default: 0] += 1
        Self.lock.unlock()
        guard request.url?.host == "atoll-transport.invalid", let fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": fixture.type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for part in fixture.parts { client?.urlProtocol(self, didLoad: part) }
        if fixture.finish { client?.urlProtocolDidFinishLoading(self) }
    }
    override func stopLoading() {
        Self.lock.lock(); defer { Self.lock.unlock() }
        Self.stops[request.url!.lastPathComponent, default: 0] += 1
    }
}

func data(_ value: String) -> Data { Data(value.utf8) }
func event(_ text: String, finish: String? = nil) -> String {
    let choice: [String: Any] = ["delta": ["content": text], "finish_reason": finish as Any? ?? NSNull()]
    return String(data: try! JSONSerialization.data(withJSONObject: ["choices": [choice]]), encoding: .utf8)!
}

@MainActor final class Suite {
    var failures = 0
    var checks = 0
    func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if condition { print("PASS: \(message)") }
        else { failures += 1; print("FAIL: \(message)") }
    }

    func stream(_ name: String, fixture: Fixture, ollama: Bool = false,
                text: String, success: Bool, chunkCount: Int? = nil) async {
        let request = StubProtocol.install(fixture, name: name)
        var chunks: [ChatStreamChunk] = []
        var caught: Error?
        do { try await ChatTransport.stream(request, ollama: ollama) { chunks.append($0) } }
        catch { caught = error }
        let detail = caught.map { " (\($0.localizedDescription))" } ?? ""
        expect((caught == nil) == success, "\(name): completion/error contract\(detail)")
        expect(chunks.map(\.text).joined() == text, "\(name): delivered text == \(String(reflecting: text))")
        if let chunkCount { expect(chunks.count == chunkCount, "\(name): \(chunkCount) incremental updates") }
    }

    func run() async {
        let first = event("Hello ")
        let last = event("世界", finish: "stop")
        let sse = "data: \(first)\n\ndata: \(last)\n\ndata: [DONE]\n\n"
        await stream("sse-standard", fixture: .init(parts: [data(sse)]), text: "Hello 世界", success: true, chunkCount: 2)
        await stream("sse-fragmented-crlf", fixture: .init(parts: sse.replacingOccurrences(of: "\n", with: "\r\n").utf8.map { Data([$0]) }),
                     text: "Hello 世界", success: true, chunkCount: 2)
        await stream("sse-heartbeat", fixture: .init(parts: [data(": ping\n\ndata: \(first)\n\n: ping\n\ndata: \(last)\n\ndata: [DONE]\n\n")]),
                     text: "Hello 世界", success: true, chunkCount: 2)
        await stream("sse-one-event-eof", fixture: .init(parts: [data("data: \(last)")]), text: "世界", success: true, chunkCount: 1)
        await stream("sse-multiline-event", fixture: .init(parts: [data("data: {\"choices\": [\n") , data("data: {\"delta\": {\"content\": \"joined\"}, \"finish_reason\": \"stop\"}]}\n\ndata: [DONE]\n\n")]),
                     text: "joined", success: true, chunkCount: 1)
        await stream("sse-incomplete", fixture: .init(parts: [data("data: \(first)\n\n")]), text: "Hello ", success: false, chunkCount: 1)
        await stream("sse-only-done", fixture: .init(parts: [data("data: [DONE]\n\n")]), text: "", success: false)
        await stream("sse-server-error", fixture: .init(parts: [data("data: {\"error\": {\"message\": \"stub failure\"}}\n\n")]), text: "", success: false)
        let ndjson = "{\"message\":{\"content\":\"你好\",\"thinking\":\"分析\"},\"done\":false}\n{\"message\":{\"content\":\"！\"},\"done\":true}\n"
        await stream("ollama-fragmented", fixture: .init(type: "application/x-ndjson", parts: ndjson.utf8.map { Data([$0]) }),
                     ollama: true, text: "你好！", success: true, chunkCount: 2)
        await stream("ollama-incomplete", fixture: .init(type: "application/x-ndjson", parts: [data("{\"message\":{\"content\":\"partial\"},\"done\":false}\n")]),
                     ollama: true, text: "partial", success: false)
        let json = "{\n\"choices\":[{\"message\":{\"content\":\"whole\"},\"finish_reason\":\"stop\"}]\n}"
        await stream("plain-json", fixture: .init(type: "application/json; charset=utf-8", parts: [data(json)]), text: "whole", success: true)
        await stream("case-insensitive-json-type", fixture: .init(type: "Application/JSON", parts: [data(json)]), text: "whole", success: true)
        await stream("http-failure", fixture: .init(status: 429, parts: [data("{}")] ), text: "", success: false, chunkCount: 0)

        // A completed SSE event must reach the UI while the server is still open.
        let liveRequest = StubProtocol.install(.init(parts: [data("data: \(first)\n\n")], finish: false), name: "sse-live")
        var liveText = ""
        let live = Task { @MainActor in
            try await ChatTransport.stream(liveRequest, ollama: false) { liveText += $0.text }
        }
        for _ in 0..<100 {
            if liveText == "Hello " { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(liveText == "Hello ", "sse-live: event delivered before EOF or DONE")
        live.cancel()
        _ = try? await live.value

        // Cancel from the first update with both lines already buffered. No second
        // chunk may reach UI, and the stream must throw instead of returning success.
        let request = StubProtocol.install(.init(type: "application/x-ndjson", parts: [data(ndjson)]), name: "cancel-buffered")
        var updates = 0
        var task: Task<Void, Error>!
        task = Task { @MainActor in
            try await ChatTransport.stream(request, ollama: true) { _ in
                updates += 1
                task.cancel()
            }
        }
        do { try await task.value; expect(false, "cancel-buffered: throws cancellation") }
        catch { expect(error is CancellationError || (error as NSError).code == NSURLErrorCancelled, "cancel-buffered: throws cancellation") }
        expect(updates == 1, "cancel-buffered: no later UI update")

        // Cancellation while bytes.lines is waiting must tear down the URL task.
        let idleRequest = StubProtocol.install(.init(parts: [], finish: false), name: "cancel-idle")
        let idle = Task { @MainActor in try await ChatTransport.stream(idleRequest, ollama: false) { _ in } }
        for _ in 0..<100 {
            if StubProtocol.counts("cancel-idle").started > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(StubProtocol.counts("cancel-idle").started > 0, "cancel-idle: request started before cancellation")
        idle.cancel()
        do { try await idle.value; expect(false, "cancel-idle: throws cancellation") }
        catch { expect(error is CancellationError || (error as NSError).code == NSURLErrorCancelled, "cancel-idle: throws cancellation") }
        // URLProtocol stopLoading is dispatched on the loading thread; task.value
        // may throw before that callback is delivered. Wait for the actual ACK.
        for _ in 0..<100 {
            if StubProtocol.counts("cancel-idle").stopped > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        expect(StubProtocol.counts("cancel-idle").stopped > 0, "cancel-idle: underlying URL task stopped")

        // Control ACKs must not silently accept invalid JSON / HTML success pages.
        let valid = StubProtocol.install(.init(type: "application/json", parts: [data("{\"status\":\"cancelled\",\"job_id\":\"test-job\"}")]), name: "valid-json-control")
        do {
            let value = try await ChatTransport.json(valid.url!, body: [:])
            expect(value["status"] as? String == "cancelled", "control response accepts valid JSON ACK")
        } catch { expect(false, "control response accepts valid JSON ACK") }
        let invalid = StubProtocol.install(.init(type: "text/html", parts: [data("<html>wrong route</html>")]), name: "invalid-json-control")
        do { _ = try await ChatTransport.json(invalid.url!, body: [:]); expect(false, "control response rejects malformed JSON") }
        catch { expect(true, "control response rejects malformed JSON") }
        let backendError = StubProtocol.install(.init(type: "application/json", parts: [data("{\"error\":\"stop not applied\"}")]), name: "error-json-control")
        do { _ = try await ChatTransport.json(backendError.url!, body: [:]); expect(false, "control response rejects error payload") }
        catch { expect(true, "control response rejects error payload") }
        print("Transport suite: \(checks) checks, \(failures) failures. All requests intercepted by URLProtocol.")
    }
}

URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
guard URLProtocol.registerClass(StubProtocol.self) else { fatalError("Could not register local URLProtocol stub") }
// A broken cancellation path must fail the test process instead of hanging CI.
DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
    fputs("FAIL: transport test watchdog timed out\n", stderr)
    exit(2)
}
Task { @MainActor in
    let suite = Suite()
    await suite.run()
    URLProtocol.unregisterClass(StubProtocol.self)
    exit(suite.failures == 0 ? 0 : 1)
}
dispatchMain()
