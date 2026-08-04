import Foundation

// Behavior check for #246 tolerant decoding (runs the real CompanionModels.swift).
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL"): \(name)")
    if !condition { exit(1) }
}

// 1. Unknown status value from a newer Mac app → decodes as .idle, not throw.
let unknownStatus = """
{"version":1,"sequence":42,"source":"claude","status":"connecting",
 "messages":[{"role":"user","text":"hi"}],"updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: unknownStatus)
    check("unknown status falls back to idle", state.status == .idle)
} catch { check("unknown status decodes at all", false) }

// 2. Unknown pendingAction + unknown message role → degrade, not throw.
let unknownEnums = """
{"version":1,"sequence":43,"source":"claude","status":"processing",
 "messages":[{"role":"system","text":"x"}],"pendingAction":"handoff",
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: unknownEnums)
    check("unknown pendingAction degrades to nil", state.pendingAction == nil)
    check("unknown role degrades to assistant", state.messages.first?.role == .assistant)
} catch { check("unknown enums decode at all", false) }

// 3. Question missing descriptions/index/total → defaults, not throw.
let sparseQuestion = """
{"version":1,"sequence":44,"source":"claude","status":"waitingQuestion",
 "messages":[],"question":{"question":"Pick one","options":["a","b"]},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: sparseQuestion)
    check("sparse question decodes", state.question != nil)
    check("total defaults to >= 1", state.question!.total >= 1)
    check("index clamps to >= 0", state.question!.index >= 0)
} catch { check("sparse question decodes at all", false) }

// 4. Negative index / zero total clamp.
let weirdQuestion = """
{"version":1,"sequence":45,"source":"claude","status":"waitingQuestion",
 "messages":[],"question":{"question":"q","options":[],"index":-3,"total":0},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: weirdQuestion)
    check("negative index clamped", state.question!.index == 0)
    check("zero total clamped", state.question!.total == 1)
} catch { check("weird question decodes at all", false) }

// 5. Malformed question object degrades to nil instead of sinking the payload.
let brokenQuestion = """
{"version":1,"sequence":46,"source":"claude","status":"processing",
 "messages":[],"question":{"options":["a"]},
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: brokenQuestion)
    check("broken question degrades to nil", state.question == nil)
} catch { check("broken question payload decodes at all", false) }

// 6. Missing updatedAt / messages (older Mac app) → defaults.
let minimal = """
{"version":1,"sequence":47,"source":"codex","status":"running"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: minimal)
    check("minimal payload decodes", state.messages.isEmpty && state.sessions.isEmpty)
} catch { check("minimal payload decodes at all", false) }

// 7. Round-trip: what today's Mac sends still decodes exactly.
let full = """
{"version":1,"sequence":48,"sessionId":"s1","source":"claude","status":"waitingApproval",
 "toolName":"Bash","workspaceName":"proj",
 "messages":[{"role":"user","text":"do it"},{"role":"assistant","text":"ok"}],
 "pendingAction":"approval",
 "question":null,
 "sessions":[{"source":"claude","status":"waitingApproval","updatedAt":"2026-07-05T12:00:00Z"}],
 "updatedAt":"2026-07-05T12:00:00Z"}
""".data(using: .utf8)!
do {
    let state = try decoder.decode(CompanionStatePayload.self, from: full)
    check("full payload keeps status", state.status == .waitingApproval)
    check("full payload keeps pendingAction", state.pendingAction == .approval)
    check("full payload keeps sessions", state.sessions.count == 1)
    check("full payload keeps messages", state.messages.count == 2)
} catch { check("full payload decodes at all", false) }

print("ALL PASS")
