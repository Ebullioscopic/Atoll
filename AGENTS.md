# Atoll Codex 合并项目规则

- 本仓库是 Atoll 与 Codex 状态集成的唯一主仓，最终只发布一个 Atoll App。
- Codex 能力属于 Atoll 内置的实用工具，不得重新引入独立 CodexAtoll 菜单栏 App、独立设置 App 或第二套发布包。
- Codex 数据来源只允许使用 Codex Hooks；不解析 transcript，不启动网络服务。
- Codex Hook Helper 必须保持轻量、stdout 为空、失败不阻断 Codex，并随 Atoll App 一起构建和签名。
- Helper 和状态文件写入必须使用临时文件和原子替换。
- Codex 状态转换集中在 Reducer；宿主展示更新集中在 Codex Presentation Coordinator。
- 内置 Codex 不经过第三方扩展授权、RPC 或 XPC；AtollExtensionKit 通道仅保留给真正的第三方扩展。
- Codex 设置位于 Atoll 设置的“实用工具”分类，不新增独立菜单栏入口。
- 修改时保护当前分支已有的扩展 Live Activity 路由改动；通用能力可以保留，Codex 特判应迁入 Codex 功能模块。
- 修改后优先运行 Codex 聚焦测试、Helper 构建、Atoll 主 App 构建和必要的 Xcode 测试。
- 命令行构建不能替代最终 macOS App 运行时验收；未验证项目必须记录在实施状态文档中。

## 开发运行与版本唯一性

- 除非用户明确要求生成、安装或验收正式发布包，否则开发和界面验收默认使用 Debug 开发版，不执行 Release 打包，也不替换 `/Applications/Atoll.app`。
- 默认使用仓库根目录的 `./scripts/dev-run`，或在 Xcode 中运行 `DynamicIsland` Scheme；两种方式都应使用增量构建并直接启动当前工作区产物。
- Debug 开发版统一使用显示名 `Atoll Dev`、Bundle ID `com.Ebullioscopic.Atoll.dev` 和固定产物路径 `DerivedData/Dev/Build/Products/Debug/Atoll.app`，不得为单次修改复制或保留新的 `.app` 副本。
- 每次启动开发版前必须关闭所有正在运行的 Atoll 实例，包括 `/Applications/Atoll.app` 正式版和旧的 Debug 进程，确保同一时间只运行一个 Atoll。
- 运行时验收前必须核对实际进程的可执行文件路径和 Bundle ID，确认界面来自当前工作区构建；不能仅凭应用名称、菜单栏图标或当前可见样式判断版本。
- `/Applications/Atoll.app` 可以作为正式安装包保留在磁盘上，但开发期间不得与 `Atoll Dev` 同时运行。只有用户明确要求正式包时，才执行 Release 构建、安装或替换，并在交付中写明实际安装路径和运行版本。
