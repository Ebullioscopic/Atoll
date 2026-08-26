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
    /// 允许携带动态查询参数的外部 URL 前缀；校验器要求以 `?` 结尾。
    let allowedExternalURLPrefixes: [String]

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decode(String.self, forKey: .version)
        entrypoint = try values.decode(String.self, forKey: .entrypoint)
        tab = try values.decode(StaticPluginTabManifest.self, forKey: .tab)
        allowedExternalURLs = try values.decodeIfPresent([String].self, forKey: .allowedExternalURLs) ?? []
        allowedExternalURLPrefixes = try values.decodeIfPresent(
            [String].self,
            forKey: .allowedExternalURLPrefixes
        ) ?? []
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
    /// 允许交给系统浏览器处理并携带动态查询参数的已校验前缀。
    let allowedExternalURLPrefixes: Set<String>

    var id: String { manifest.id }
}

enum StaticPluginLayout {
    static let maximumVisibleScreenFraction: CGFloat = 0.7

    /// 仅在静态插件标签选中时返回对应插件的窗口内容尺寸。
    static func resolvedSize(
        baseSize: CGSize,
        isStaticPluginView: Bool,
        selectedPluginID: String?,
        enabledPlugins: [InstalledStaticPlugin],
        visibleScreenHeight: CGFloat?,
        fallbackMaximumHeight: CGFloat
    ) -> CGSize? {
        guard isStaticPluginView,
              let selectedPluginID,
              let preferredHeight = enabledPlugins.first(where: { $0.id == selectedPluginID })?
                .manifest.tab.preferredHeight else {
            return nil
        }
        return CGSize(
            width: baseSize.width,
            height: resolvedHeight(
                preferredHeight: CGFloat(preferredHeight),
                baseHeight: baseSize.height,
                visibleScreenHeight: visibleScreenHeight,
                fallbackMaximumHeight: fallbackMaximumHeight
            )
        )
    }

    /// 将插件请求高度限制在默认刘海高度和当前屏幕安全高度之间。
    static func resolvedHeight(
        preferredHeight: CGFloat,
        baseHeight: CGFloat,
        visibleScreenHeight: CGFloat?,
        fallbackMaximumHeight: CGFloat
    ) -> CGFloat {
        let maximumHeight = visibleScreenHeight.map {
            max(baseHeight, $0 * maximumVisibleScreenFraction)
        } ?? max(baseHeight, fallbackMaximumHeight)
        return min(max(preferredHeight, baseHeight), maximumHeight)
    }
}
