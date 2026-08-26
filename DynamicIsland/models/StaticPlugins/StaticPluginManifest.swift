/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

struct StaticPluginManifest: Codable, Equatable {
    /// 插件格式版本，宿主只加载明确支持的版本。
    let schemaVersion: Int
    /// 插件稳定标识，也是安装目录名的来源。
    let id: String
    /// 设置页展示名称。
    let name: String
    /// 设置页展示版本；v1 不比较版本大小。
    let version: String
    /// 包内 HTML 入口的相对路径。
    let entrypoint: String
    /// 刘海标签页展示配置。
    let tab: StaticPluginTabManifest
    /// 允许用户点击后交给系统浏览器打开的精确 URL。
    let allowedExternalURLs: [String]

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decode(String.self, forKey: .version)
        entrypoint = try values.decode(String.self, forKey: .entrypoint)
        tab = try values.decode(StaticPluginTabManifest.self, forKey: .tab)
        allowedExternalURLs = try values.decodeIfPresent([String].self, forKey: .allowedExternalURLs) ?? []
    }
}

struct StaticPluginTabManifest: Codable, Equatable {
    /// 刘海标签文字。
    let title: String
    /// SF Symbols 名称；无效名称由界面回退为默认图标。
    let icon: String
    /// 展开内容期望高度，最终由刘海可用范围限制。
    let preferredHeight: Double?
}

struct InstalledStaticPlugin: Identifiable, Equatable {
    /// 已完成校验的插件清单。
    let manifest: StaticPluginManifest
    /// 插件可读取的唯一根目录。
    let rootURL: URL
    /// 已确认位于根目录内的 HTML 入口。
    let entrypointURL: URL
    /// 允许交给系统浏览器处理的精确 URL 集合。
    let allowedExternalURLs: Set<URL>

    var id: String { manifest.id }
}
