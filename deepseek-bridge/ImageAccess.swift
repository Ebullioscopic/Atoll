import AppKit
import Foundation

// Only this directory can be authorized; no general filesystem access API.
let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/ScreenAssistantScreenshots", isDirectory: true)
let storage = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AtollDeepSeekBridge/screenshot-directory.bookmark")
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(message.utf8)); exit(1)
}
let arguments = CommandLine.arguments
if !arguments.contains("--read") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()
    app.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.title = "允许 Atoll 读取截图目录"
    panel.message = "只选择 Documents/ScreenAssistantScreenshots。你在 Atoll 发送的截图将由桥接服务提交给 DeepSeek 分析。"
    panel.prompt = "允许截图目录"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = directory
    guard panel.runModal() == .OK, let selected = panel.url,
          selected.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath() else {
        fail("未授权指定的截图目录。")
    }
    do {
        let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        try bookmark.write(to: storage, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storage.path)
        print("Screenshot directory authorized.")
    } catch { fail("无法保存截图目录授权。") }
    exit(0)
}
guard arguments.count == 3, arguments[1] == "--read" else { fail("Expected screenshot filename.") }
let name = arguments[2]
guard name.range(of: #"^screenshot_[0-9]+\.png$"#, options: .regularExpression) != nil else { fail("Invalid screenshot filename.") }
do {
    let bookmark = try Data(contentsOf: storage)
    var stale = false
    let authorized = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    guard authorized.resolvingSymlinksInPath() == directory.resolvingSymlinksInPath(), !stale else { fail("Screenshot authorization needs renewal.") }
    let access = authorized.startAccessingSecurityScopedResource()
    defer { if access { authorized.stopAccessingSecurityScopedResource() } }
    let target = authorized.appendingPathComponent(name)
    guard target.resolvingSymlinksInPath().deletingLastPathComponent() == authorized.resolvingSymlinksInPath() else { fail("Invalid screenshot path.") }
    let file = try FileHandle(forReadingFrom: target)
    defer { try? file.close() }
    let data = try file.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
    guard data.count <= 16 * 1024 * 1024 else { fail("Screenshot exceeds 16 MB.") }
    print(data.base64EncodedString())
} catch { fail("Screenshot directory permission is required. Open Atoll Image Access to authorize it.") }
