import Foundation
import Darwin
import CodeIslandRuntime

// Atoll's managed helper accepts only the verified Codex parsing contract,
// derives a sanitized observation locally, and always yields native control.
signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
guard let sourceIndex = arguments.firstIndex(of: "--source"),
      arguments.indices.contains(sourceIndex + 1),
      arguments[sourceIndex + 1] == "codex" else {
    exit(EXIT_SUCCESS)
}
let socketURL: URL? = arguments.firstIndex(of: "--socket").flatMap { index in
    guard arguments.indices.contains(index + 1) else { return nil }
    return URL(fileURLWithPath: arguments[index + 1])
}

// Bound stdin, parsing, and delivery. Polling lets a complete event be parsed
// even when its provider pipe remains open, so Stop can still receive the
// event-specific no-op JSON Codex requires.
let inputDeadline = ProcessInfo.processInfo.systemUptime + 1
var payload = Data()
var buffer = [UInt8](repeating: 0, count: 16_384)
while payload.count < 1_048_576 {
    let remainingTime = inputDeadline - ProcessInfo.processInfo.systemUptime
    guard remainingTime > 0 else { break }
    let timeoutMilliseconds = Int32(
        min(1_000, max(1, (remainingTime * 1_000).rounded(.up)))
    )
    var input = pollfd(
        fd: STDIN_FILENO,
        events: Int16(POLLIN | POLLHUP),
        revents: 0
    )
    let pollResult = poll(&input, 1, timeoutMilliseconds)
    if pollResult == 0 { break }
    if pollResult < 0 {
        if errno == EINTR { continue }
        break
    }
    if input.revents & Int16(POLLERR | POLLNVAL) != 0 { break }

    let remaining = 1_048_576 - payload.count
    let byteCount = buffer.withUnsafeMutableBytes { bytes in
        read(STDIN_FILENO, bytes.baseAddress, min(bytes.count, remaining))
    }
    if byteCount > 0 {
        payload.append(contentsOf: buffer.prefix(Int(byteCount)))
    } else if byteCount == 0 {
        break
    } else if errno != EINTR {
        break
    }
}
let context = CodexHookContext(
    environment: ProcessInfo.processInfo.environment,
    currentDirectory: FileManager.default.currentDirectoryPath
)
let evaluation = CodexHookAdapter().evaluate(
    payload: payload,
    context: context,
    observedAt: Date()
)
let outcome: ObservationDeliveryOutcome
if let observation = evaluation.observation, let socketURL {
    outcome = CodeIslandUnixObservationClient().deliver(observation, to: socketURL)
} else {
    outcome = .hostUnavailable
}

let completion = NonOwningHookCompletionPolicy().completion(
    for: evaluation.hookEvent,
    after: outcome
)
if !completion.standardOutput.isEmpty {
    FileHandle.standardOutput.write(completion.standardOutput)
}
exit(completion.exitStatus)
