// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import ToolIsleCore

@main struct ToolIsleApp: App {
    @NSApplicationDelegateAdaptor(ToolIsleDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra {
            Button("打开 ToolIsle") { ToolWindowRouter.shared.open("home") }
            Button("Gitee 项目") { ToolWindowRouter.shared.open("gitee") }
            Button("Markdown 阅读器") { ToolWindowRouter.shared.open("markdown") }
            Divider()
            Button(NotchController.shared.visible ? "隐藏灵动岛入口" : "显示灵动岛入口") { NotchController.shared.toggle() }
            Button("关于与许可证") { ToolWindowRouter.shared.open("about") }
            Divider()
            Button("退出 ToolIsle") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: ToolIsleResources.image("MenuBarTemplate")).renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18).accessibilityLabel("ToolIsle")
        }
    }
}
@MainActor final class ToolIsleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = ToolIsleResources.image("AppIcon")
        ToolWindowRouter.shared.open("home")
        NotchController.shared.start()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ToolWindowRouter.shared.open("home"); return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL { ToolWindowRouter.shared.open("markdown", file: url) }
    }
}
enum ToolIsleResources {
    static var directory: URL {
        if let root = Bundle.main.resourceURL?.appendingPathComponent("Resources"), FileManager.default.fileExists(atPath: root.appendingPathComponent("AppIcon.png").path) { return root }
        return Bundle.module.resourceURL!.appendingPathComponent("Resources")
    }
    static func image(_ name: String) -> NSImage {
        NSImage(contentsOf: directory.appendingPathComponent(name + ".png")) ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "ToolIsle")!
    }
}
struct ToolDescriptor: Identifiable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let category: String
    let makeView: @MainActor (URL?) -> AnyView
}
@MainActor enum ToolRegistry {
    static let tools: [ToolDescriptor] = [
        .init(id: "gitee", title: "Gitee 项目", summary: "Watch / Star、Issues、评论与仓库文档", symbol: "tray.full", category: "协作", makeView: { _ in AnyView(GiteeWorkspace()) }),
        .init(id: "markdown", title: "Markdown 阅读", summary: "本地文档、表格、代码与图片", symbol: "doc.richtext", category: "阅读", makeView: { file in AnyView(LocalMarkdownView(initialURL: file)) }),
        .init(id: "json", title: "JSON 工具", summary: "校验、格式化与压缩", symbol: "curlybraces", category: "开发", makeView: { _ in AnyView(TextToolView(kind: "json")) }),
        .init(id: "timestamp", title: "时间戳", summary: "秒 / 毫秒与 ISO 8601 日期转换", symbol: "clock", category: "开发", makeView: { _ in AnyView(TextToolView(kind: "timestamp")) }),
        .init(id: "base64", title: "Base64", summary: "UTF-8 文本编码与解码", symbol: "textformat.abc", category: "开发", makeView: { _ in AnyView(TextToolView(kind: "base64")) })
    ]
}
@MainActor final class ToolWindowRouter: NSObject, NSWindowDelegate {
    static let shared = ToolWindowRouter()
    let account = GiteeAccount()
    private var windows: [String: NSWindow] = [:]
    func open(_ id: String, file: URL? = nil) {
        let key = id + (file?.standardizedFileURL.path ?? "")
        if let window = windows[key] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let content: AnyView
        let title: String
        if id == "home" { content = AnyView(ToolboxView()); title = "ToolIsle · 团队工具箱" }
        else if id == "about" { content = AnyView(AboutToolIsle()); title = "关于 ToolIsle" }
        else if let tool = ToolRegistry.tools.first(where: { $0.id == id }) { content = tool.makeView(file); title = tool.title + " · ToolIsle" }
        else { return }
        let window = NSWindow(contentViewController: NSHostingController(rootView: content.environmentObject(account)))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: id == "gitee" ? 1180 : 960, height: 680))
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); windows[key] = window; window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}
struct ToolboxView: View {
    @State private var search = ""
    @State private var category = "全部"
    @State private var favoritesOnly = false
    @AppStorage("toolisle.favorites") private var favoriteIDs = ""
    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: ToolIsleResources.image("AppIcon")).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading) { Text("ToolIsle").font(.largeTitle.bold()); Text("团队常用的小工具，随手可及。").foregroundStyle(.secondary) }
                Spacer(); Button("关于") { ToolWindowRouter.shared.open("about") }
            }
            HStack {
                TextField("搜索工具", text: $search).textFieldStyle(.roundedBorder)
                Picker("分类", selection: $category) { ForEach(["全部", "协作", "阅读", "开发"], id: \.self) { Text($0) } }.frame(width: 160)
                Toggle("仅收藏", isOn: $favoritesOnly).toggleStyle(.checkbox)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                    ForEach(ToolRegistry.tools.filter { tool in
                        (category == "全部" || tool.category == category) && (!favoritesOnly || favorites.contains(tool.id)) &&
                        (search.isEmpty || (tool.title + tool.summary).localizedCaseInsensitiveContains(search))
                    }) { tool in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: tool.symbol).font(.title).foregroundStyle(.tint)
                                Spacer()
                                Button { toggle(tool.id) } label: { Image(systemName: favorites.contains(tool.id) ? "star.fill" : "star") }.buttonStyle(.plain).help("收藏 / 取消收藏")
                            }
                            Text(tool.title).font(.title3.bold())
                            Text(tool.summary).font(.callout).foregroundStyle(.secondary).frame(height: 40, alignment: .topLeading)
                            Button("打开工具") { ToolWindowRouter.shared.open(tool.id) }.buttonStyle(.borderedProminent)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            Text("本地工具不上传内容；Gitee 请求只在你使用相关功能时发起。未经点击不会读取剪贴板。").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }
    private func toggle(_ id: String) {
        var values = favorites
        if values.contains(id) { values.remove(id) } else { values.insert(id) }
        favoriteIDs = values.sorted().joined(separator: ",")
    }
}
struct TextToolView: View {
    let kind: String
    @State private var input = ""
    @State private var output = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("从剪贴板粘贴") { input = NSPasteboard.general.string(forType: .string) ?? "" }
                Button("清空") { input = ""; output = ""; error = nil }
                Spacer()
                if kind == "json" {
                    Button("格式化 / 校验") { run { try TextTools.json(input, pretty: true) } }
                    Button("压缩") { run { try TextTools.json(input, pretty: false) } }
                } else if kind == "base64" {
                    Button("编码") { run { try TextTools.base64(input, decode: false) } }
                    Button("解码") { run { try TextTools.base64(input, decode: true) } }
                } else {
                    Button("当前时间") { input = String(Int64(Date().timeIntervalSince1970)) }
                    Button("秒 → 日期") { run { try TextTools.timestamp(input, milliseconds: false) } }
                    Button("毫秒 → 日期") { run { try TextTools.timestamp(input, milliseconds: true) } }
                    Button("日期 → 时间戳") { run { try TextTools.date(input) } }
                }
            }
            Text("输入（日期需包含时区，例如 2026-09-22T08:00:00+08:00）").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $input).font(.system(.body, design: .monospaced)).border(.quaternary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Text("结果").font(.headline); Spacer(); Button("复制结果") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) } }
            ScrollView([.vertical, .horizontal]) { Text(output).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 180)
        }.padding(20)
    }
    private func run(_ action: () throws -> String) { do { output = try action(); error = nil } catch { output = ""; self.error = error.localizedDescription } }
}
struct AboutToolIsle: View {
    @State private var license = "LICENSE"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ToolIsle 0.2.0").font(.largeTitle.bold())
            Text("基于 Atoll 开源项目建立的独立团队工具箱。非 Atoll 官方发行版。")
            Link("项目源码与反馈", destination: URL(string: "https://github.com/lideming0815/ToolIsle")!)
            Text("保留 Atoll 及 boring.notch 的原始版权和许可声明。新增代码按 GPL-3.0-or-later 分发。MarkdownUI 等第三方组件遵循各自许可证。")
            Picker("许可证", selection: $license) {
                ForEach(["LICENSE", "NOTICE", "COPYRIGHT_ASSETS", "THIRD_PARTY_LICENSES"], id: \.self) { Text($0) }
            }
            ScrollView { Text((try? String(contentsOf: ToolIsleResources.directory.appendingPathComponent(license), encoding: .utf8)) ?? "许可资源缺失，请查看源码仓库并重新构建。").font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(24)
    }
}
@MainActor final class NotchController: ObservableObject {
    static let shared = NotchController()
    @Published var expanded = false
    var visible: Bool { UserDefaults.standard.object(forKey: "toolisle.notch") as? Bool ?? true }
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    func start() {
        if visible { show() }
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.position() } }
    }
    func toggle() {
        UserDefaults.standard.set(!visible, forKey: "toolisle.notch")
        if visible { show() } else { panel?.orderOut(nil) }
    }
    private func show() {
        if panel == nil {
            let window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.backgroundColor = .clear; window.isOpaque = false; window.hasShadow = false
            window.level = .statusBar; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ToolIsleNotch(controller: self))
            panel = window
        }
        position(); panel?.orderFrontRegardless()
    }
    func hover(_ value: Bool) { expanded = value; position() }
    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = expanded ? 400 : 280
        let height: CGFloat = expanded ? 176 : max(32, screen.safeAreaInsets.top)
        panel?.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
}
struct ToolIsleNotch: View {
    @ObservedObject var controller: NotchController
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(nsImage: ToolIsleResources.image("AppIcon")).resizable().frame(width: 20, height: 20)
                Spacer(minLength: 180)
                Image(systemName: "square.grid.2x2")
            }.frame(height: 24)
            if controller.expanded {
                Text("ToolIsle · 团队工具箱").font(.headline)
                HStack {
                    Button("工具箱") { ToolWindowRouter.shared.open("home") }
                    Button("Gitee") { ToolWindowRouter.shared.open("gitee") }
                    Button("Markdown") { ToolWindowRouter.shared.open("markdown") }
                }.buttonStyle(.bordered)
                Text("长内容在独立窗口中阅读").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16).padding(.vertical, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
            .preferredColorScheme(.dark).onHover { controller.hover($0) }
    }
}
