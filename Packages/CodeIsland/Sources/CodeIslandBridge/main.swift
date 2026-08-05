import Foundation
import Darwin
import CodeIslandRuntime

// The Phase 2 helper is not installed by Atoll. If invoked directly, it accepts
// only the verified Codex parsing contract and always yields native control.
signal(SIGPIPE, SIG_IGN)
signal(SIGALRM) { _ in
    _exit(EXIT_SUCCESS)
}

let arguments = CommandLine.arguments
guard let sourceIndex = arguments.firstIndex(of: "--source"),
      arguments.indices.contains(sourceIndex + 1),
      arguments[sourceIndex + 1] == "codex" else {
    exit(EXIT_SUCCESS)
}

// Bound stdin and parsing. The helper has no socket or listener in Phase 2, and
// provider flow must remain safe even if its input pipe is never closed.
alarm(1)
var payload = Data()
var buffer = [UInt8](repeating: 0, count: 16_384)
while payload.count < 1_048_576 {
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
_ = evaluation.observation

let completion = NonOwningHookCompletionPolicy().completion(after: .hostUnavailable)
exit(completion.exitStatus)
