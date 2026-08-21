# Atoll Codex Native Integration Implementation Plan

**Goal:** 将独立 CodexAtoll 插件迁入 Atoll，形成一个仓库、一个 Atoll App、一个设置入口和一次构建发布链路。

**Scope:** 包含 Codex Hooks、Helper、事件状态、原生刘海展示、任务跳转、设置、旧数据迁移、测试和文档；保留 Atoll 对真正第三方扩展的支持。

**Architecture:** Atoll 主进程内运行 `CodexFeatureController`，从由同包 Helper 原子写入的本地事件队列恢复状态，并通过宿主内部 Manager 直接提交展示模型。Codex 不再经过第三方扩展授权、RPC 或 XPC。

## Global Constraints

- 唯一用户产品是 Atoll.app；Helper 是包内辅助可执行文件，不是第二个 App。
- 数据来源只使用 Codex Hooks，不解析 transcript，不启动网络服务。
- Hook Helper stdout 为空且任何失败都返回成功，不阻断 Codex。
- Hook 配置只增删本功能拥有的条目，必须兼容旧 CodexAtoll 路径并避免重复。
- 事件、状态和 Helper 更新采用原子替换。
- 状态转换集中在 Reducer；展示集中在 Codex Presentation Coordinator。
- 现有第三方 AtollExtensionKit 能力保持兼容。
- 不自动删除旧 App 或用户数据；只迁移并提示。

### Task 1: 迁入 Codex 核心状态与 Hook 边界

**Files:** `DynamicIsland/Features/Codex/Core/*`, `DynamicIsland/Features/Codex/Hooks/*`, `CodexFeatureTests/*`

**Interfaces:** Hook stdin JSON -> 原子事件文件；事件文件 -> Reducer -> `CodexTaskStoreSnapshot`。

**Implementation:** 迁入现有已验证模型、清洗、Reducer、Repository、Installer 和配置合并逻辑；路径切换到 `Application Support/Atoll/Codex`，同时识别旧目录。

**Verification:** Reducer、Hook 合并、原子写入、旧 Hook 识别和状态迁移聚焦测试。

### Task 2: 新增同包 Hook Helper

**Files:** `CodexHookHelper/main.swift`, `DynamicIsland.xcodeproj/project.pbxproj`, `Contents/Helpers/*`

**Interfaces:** Xcode Helper target -> `Atoll.app/Contents/Helpers/CodexHookHelper` -> Atoll 安装器复制到稳定 Application Support 路径。

**Implementation:** 新增命令行 target，主 App 构建依赖并 CodeSignOnCopy；启动或设置修复时按版本原子替换。

**Verification:** Helper target 构建；检查 App 包中 Helper 存在且可执行；模拟 Hook 时 stdout 为空并生成事件。

### Task 3: 接入宿主生命周期与原生展示

**Files:** `DynamicIsland/Features/Codex/Runtime/*`, `DynamicIsland/Features/Codex/Presentation/*`, `DynamicIsland/DynamicIslandApp.swift`, 相关展示 Manager/View。

**Interfaces:** `CodexFeatureController` 发布 snapshot；`CodexPresentationCoordinator` 直接调用宿主内部 Manager，不调用 RPC/XPC。

**Implementation:** Atoll 启动时按开关启动处理，退出时停止；复用 descriptor 渲染能力但标记为内置来源；支持关闭态、详情 Tab、完成提示、等待批准和任务跳转。

**Verification:** 模拟事件驱动显示模型；点击路由测试；第三方扩展路由回归测试；启动/停止幂等测试。

### Task 4: 融入 Atoll 设置和全屏策略

**Files:** `DynamicIsland/components/Settings/SettingsView.swift`, `DynamicIsland/Features/Codex/Settings/CodexSettingsView.swift`, Defaults keys, fullscreen rendering policy。

**Interfaces:** 设置 -> Controller/Presentation；Codex 全屏开关 -> 宿主内容门控。

**Implementation:** 在“实用工具”增加 Codex；提供启用、安装修复、显示、隐私、全屏和诊断；删除独立 App 才有的菜单栏及 Atoll 授权选项。

**Verification:** 设置搜索与导航可达；开关实时生效；全屏策略不改变系统隐私指示优先级。

### Task 5: 旧版本迁移和单产品收尾

**Files:** migration、README、`docs/IMPLEMENTATION_STATUS.md`、构建配置。

**Interfaces:** 旧 `Application Support/CodexAtoll` 和旧 Hook -> 新 `Application Support/Atoll/Codex`。

**Implementation:** 单次幂等迁移；不删除旧 App；归档独立仓库说明；确认发布物只有 Atoll App。

**Verification:** 旧状态/Hook fixture 迁移；二次运行无重复；App Archive/Debug bundle 内容检查；最终需求矩阵审计。
