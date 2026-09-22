// Copyright (C) 2026 ToolIsle contributors. SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI
import MarkdownUI
import ToolIsleCore

struct MarkdownContext {
    var repo: GiteeRepository?
    var client: GiteeClient?
    var ref = ""
    var path = ""
    var localFile: URL?
    var localRoot: URL?
    static func repository(_ repo: GiteeRepository, client: GiteeClient, ref: String, path: String) -> Self {
        Self(repo: repo, client: client, ref: ref, path: path)
    }
    var baseURL: URL? {
        if repo != nil { return URL(string: "toolisle-document://repository/")!.appendingPathComponent(path.isEmpty ? "README.md" : path).deletingLastPathComponent() }
        return localFile?.deletingLastPathComponent()
    }
    func permittedLocalURL(_ url: URL) -> URL? {
        guard url.isFileURL, let root = localRoot?.resolvingSymlinksInPath().standardizedFileURL else { return nil }
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        return file.path.hasPrefix(root.path + "/") ? file : nil
    }
}
struct MarkdownBody: View {
    let text: String
    let context: MarkdownContext
    var openDocument: ((String) -> Void)? = nil
    @State private var externalImages = false
    @State private var rejectedLink = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("加载外部 HTTPS 图片", isOn: $externalImages).toggleStyle(.checkbox).font(.caption)
            Markdown(text, baseURL: context.baseURL, imageBaseURL: context.baseURL)
                .markdownTheme(.gitHub)
                .markdownImageProvider(SafeImageProvider(context: context, allowExternal: externalImages))
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "toolisle-document", url.host == "repository", context.repo != nil, let openDocument {
                        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        if (try? GiteePath.segments(path)) != nil { openDocument(path); return .handled }
                    }
                    if let local = context.permittedLocalURL(url), let openDocument {
                        openDocument(local.path); return .handled
                    }
                    if url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                        NSWorkspace.shared.open(url); return .handled
                    }
                    rejectedLink = true; return .discarded
                })
            if rejectedLink { Text("已阻止不安全的链接或超出授权目录的本地路径。").font(.caption).foregroundStyle(.orange) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct SafeImageProvider: ImageProvider {
    let context: MarkdownContext
    let allowExternal: Bool
    func makeImage(url: URL?) -> some View { SafeMarkdownImage(url: url, context: context, allowExternal: allowExternal) }
}
struct SafeMarkdownImage: View {
    let url: URL?
    let context: MarkdownContext
    let allowExternal: Bool
    @State private var image: NSImage?
    @State private var message = "图片未加载"
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Label(message, systemImage: "photo").font(.caption).foregroundStyle(.secondary) }
        }.task(id: "\(url?.absoluteString ?? "")/\(allowExternal)/\(context.ref)/\(context.localRoot?.path ?? "")") { await load() }
    }
    private func load() async {
        image = nil
        guard let url else { return }
        do {
            let data: Data
            if url.scheme == "toolisle-document", url.host == "repository", let repo = context.repo, let client = context.client {
                let file = try await client.file(repo, path: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), ref: context.ref)
                data = try file.value.bytes()
            } else if let file = context.permittedLocalURL(url) {
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 8_000_000 else { throw GiteeError.invalidContent }
                data = try Data(contentsOf: file)
            } else if allowExternal, url.scheme == "https", url.user == nil, url.password == nil {
                // Separate ephemeral transport; no Gitee Authorization header or cookies.
                var request = URLRequest(url: url)
                request.setValue("image/png,image/jpeg,image/gif,image/webp", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await GiteeNetwork().send(request)
                guard response.statusCode == 200, bytes.count <= 8_000_000, response.mimeType?.hasPrefix("image/") == true else { throw GiteeError.invalidContent }
                data = bytes
            } else { message = "外部图片已关闭，或本地图片超出授权目录"; return }
            try Task.checkCancellation()
            guard let decoded = NSImage(data: data), decoded.size.width <= 16_384, decoded.size.height <= 16_384 else { throw GiteeError.invalidContent }
            image = decoded
        } catch {
            if !(error is CancellationError) { message = "图片不可用：" + error.localizedDescription }
        }
    }
}
struct MarkdownReader: View {
    let text: String
    let title: String
    let context: MarkdownContext
    var openDocument: ((String) -> Void)? = nil
    @State private var source = false
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title).font(.headline).lineLimit(1).help(title)
                Spacer()
                Toggle("源码", isOn: $source).toggleStyle(.switch)
                Button("复制源码") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
            }.padding(.horizontal)
            ScrollView([.vertical, .horizontal]) {
                Group {
                    if source { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled) }
                    else { MarkdownBody(text: text, context: context, openDocument: openDocument) }
                }.frame(minWidth: 300, idealWidth: 700, maxWidth: 1200, alignment: .leading).padding(20)
            }
        }
    }
}
struct LocalMarkdownView: View {
    var initialURL: URL? = nil
    @State private var file: URL?
    @State private var root: URL?
    @State private var text = ""
    @State private var error: String?
    @State private var scoped: [URL] = []
    var body: some View {
        VStack {
            HStack {
                Button("打开 Markdown 文件") { selectFile() }
                Button("授权图片/链接根目录") { selectRoot() }.disabled(file == nil)
                Text("UTF-8 · 最大 2 MB · 不执行 HTML/脚本").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding()
            if let error { Text(error).foregroundStyle(.orange).padding(.horizontal) }
            if let file {
                MarkdownReader(text: text, title: file.lastPathComponent, context: MarkdownContext(localFile: file, localRoot: root)) { path in
                    load(URL(fileURLWithPath: path), resetRoot: false)
                }.id(file)
            } else { ContentUnavailableView("Markdown 阅读器", systemImage: "doc.richtext", description: Text("打开本地 .md 文件，支持标题、列表、代码块、表格和图片。")) }
        }.onAppear { if let initialURL, file == nil { load(initialURL, resetRoot: true) } }
            .onDisappear { for url in scoped { url.stopAccessingSecurityScopedResource() }; scoped = [] }
    }
    private func selectFile() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { load(url, resetRoot: true) }
    }
    private func selectRoot() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if url.startAccessingSecurityScopedResource() { scoped.append(url) }
            root = url.resolvingSymlinksInPath().standardizedFileURL
        }
    }
    private func load(_ url: URL, resetRoot: Bool) {
        do {
            guard ["md", "markdown", "mdown", "txt"].contains(url.pathExtension.lowercased()) else { throw GiteeError.invalidContent }
            if url.startAccessingSecurityScopedResource() { scoped.append(url) }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 2_000_000 else { throw GiteeError.invalidContent }
            let value = try String(contentsOf: url, encoding: .utf8)
            file = url; text = value; error = nil
            if resetRoot { root = url.deletingLastPathComponent().resolvingSymlinksInPath() }
        } catch { self.error = error.localizedDescription }
    }
}
