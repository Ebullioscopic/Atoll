/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Foundation

enum StaticPluginNavigationDecision: Equatable {
    case allow
    case cancel
    case openExternally(URL)
}

struct StaticPluginNavigationPolicy {
    /// 插件唯一允许读取的目录。
    let pluginRoot: URL
    /// 用户点击后可交给系统浏览器打开的精确 URL。
    let allowedExternalURLs: Set<URL>
    /// 用户点击后可交给系统浏览器打开的动态查询 URL 前缀。
    let allowedExternalURLPrefixes: Set<String>

    /// 只根据已验证的插件边界决定导航去向；`mainFrame == nil` 表示新窗口目标，仍需用户点击才允许外部打开。
    func decision(
        for url: URL,
        userActivated: Bool,
        mainFrame: Bool?
    ) -> StaticPluginNavigationDecision {
        if url.isFileURL {
            let rootPath = pluginRoot.standardizedFileURL.resolvingSymlinksInPath().path
            let candidatePath = url.standardizedFileURL.resolvingSymlinksInPath().path
            return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
                ? .allow
                : .cancel
        }

        let allowedExternalURL = allowedExternalURLs.contains(url)
            || allowedExternalURLPrefixes.contains { url.absoluteString.hasPrefix($0) }
        guard userActivated,
              mainFrame != false,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              allowedExternalURL else {
            return .cancel
        }
        return .openExternally(url)
    }
}

protocol StaticPluginExternalOpening {
    /// 使用宿主认可的系统机制打开外部 URL。
    func open(_ url: URL)
}

struct WorkspaceStaticPluginExternalOpener: StaticPluginExternalOpening {
    func open(_ url: URL) {
        _ = NSWorkspace.shared.open(url)
    }
}
