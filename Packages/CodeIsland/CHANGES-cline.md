# Cline (VSCode extension) 支持

本 branch 为 CodeIsland 添加了对 [Cline](https://github.com/clinebot/cline)（VSCode 扩展 `saoudrizwan.claude-dev`）的完整支持。

## 架构说明

Cline 是 VSCode 扩展，没有独立的 CLI 进程。与其他 CLI 工具（Claude Code、Cursor 等）不同，它：

- **无进程 PID 可监控** — `findClinePids` 永远返回空，避免误挂载 VSCode 主进程导致崩溃
- **文件轮询发现** — 通过读取 `~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/state/taskHistory.json` 来发现活跃会话，允许 10 分钟内的文件时间戳作为"活跃"判据
- **Hook 方式** — 通过 `~/Documents/Cline/Hooks/<EventName>` 可执行脚本转发事件；脚本在后台调用 `codeisland-bridge`，并立即向 Cline 返回 `{"cancel":false}`（Cline 要求每个 hook 必须输出合法 JSON）

## 变更文件

### 新增文件

| 文件 | 说明 |
|------|------|
| `Sources/CodeIsland/ClineView.swift` | Cline 吉祥物（绿色机器人 + 扳手），含 idle/working/alert 三态动画 |
| `Sources/CodeIsland/Resources/cli-icons/cline.png` | Cline 图标（notch panel 用） |

### 修改文件

#### `Sources/CodeIslandBridge/main.swift`

Cline 发送的 JSON 字段与标准格式不同，bridge 层做了以下适配：

- `hookName` → `hook_event_name`
- `taskId` → `session_id`
- `preToolUse.toolName` / `postToolUse.toolName` → `tool_name`
- `preToolUse.parameters` → `tool_input`
- 清除 `_ppid`（Cline hook 是 VSCode 派生的临时 shell，不应被当作持久进程追踪）

#### `Sources/CodeIslandCore/EventNormalizer.swift`

新增 Cline 事件名到内部标准名的映射：

| Cline 事件 | 内部事件 |
|------------|---------|
| `TaskStart` | `SessionStart` |
| `TaskResume` | `UserPromptSubmit` |
| `TaskComplete` | `TaskRoundComplete` |
| `TaskCancel` | `TaskRoundComplete` |

> `TaskComplete`/`TaskCancel` 映射到 `TaskRoundComplete` 而非 `Stop`。Cline 任务是单轮生命周期，收到完成/取消后会立即将会话置为 `.idle`，并丢弃随后乱序到达的旧工具事件，避免会话被重新点亮。

#### `Sources/CodeIslandCore/SessionSnapshot.swift`

- 将 `"cline"` 添加到 `supportedSources`
- 新增 `"TaskRoundComplete"` 事件处理：清除 currentTool、提取 last_assistant_message、推入补全效果；对 Cline 会话立即置为 `.idle`
- 添加 `"Cline"` 的 displayName

#### `Sources/CodeIslandCore/Models.swift`

为 Cline 的工具名添加别名，使 `toolDescription` 能正确提取描述：

| Cline 工具名 | 对应原工具 |
|-------------|-----------|
| `execute_command` | `Bash` |
| `read_file` | `Read` |
| `apply_diff` | `Edit` |
| `write_to_file` | `Write` |
| `search_files` | `Grep` |

#### `Sources/CodeIsland/AppState.swift`

- `findPids` switch 新增 `"cline"` case（返回空数组）
- `discoverActiveSessions` 调用 `findActiveClineSessions`
- `findActiveClineSessions`：读取 `taskHistory.json`，取最新任务，以 conversation 文件的 mtime 判断新鲜度（10 min），返回 `DiscoveredSession(source: "cline")`
- `readRecentFromClineHistory`：解析 `api_conversation_history.json`，提取最近 3 条消息
- `clineStorageRoot`：返回 Cline globalStorage 路径

#### `Sources/CodeIsland/ConfigInstaller.swift`

- 新增 `HookFormat.cline` 和 `HookFormat.none`
- 注册 Cline 的 `CLIConfig`（8 个 hook 事件：UserPromptSubmit、PreToolUse、PostToolUse、TaskStart、TaskResume、TaskCancel、TaskComplete、PreCompact）
- `installClineHooks`：在 `~/Documents/Cline/Hooks/` 下创建各事件的可执行 bash 脚本
- `isClineHooksInstalled`：检查脚本是否包含 `codeisland-bridge --source cline` 标记
- `uninstallClineHooks`：移除由 CodeIsland 安装的脚本
- `cliExists`：检测 Cline globalStorage 目录或 `~/Documents/Cline` 是否存在

#### `Sources/CodeIsland/MascotView.swift`

添加 `"cline"` → `ClineView` 的分支。

#### `Sources/CodeIsland/NotchPanelView.swift`

在 `cliIconFiles` 映射中添加 `"cline": "cline"`。

#### `Sources/CodeIsland/SettingsView.swift`

在 Mascots 设置页添加 `ClineBot` 条目（绿色 `#00B37D`）。

#### `Sources/CodeIsland/SoundManager.swift`

添加 `TaskRoundComplete` 事件到声音映射（使用 `8bit_complete` 音效）。

#### `build.sh`

当 `/Applications/Xcode.app` 存在时强制设置 `DEVELOPER_DIR`，避免 `xcode-select` 指向 CLT 时构建失败。

### 测试

#### `Tests/CodeIslandCoreTests/DerivedSessionStateTests.swift`

`testNormalizesClineTaskTerminalEvents`：验证 `TaskComplete`/`TaskCancel` 均规范化为 `TaskRoundComplete`。

#### `Tests/CodeIslandTests/AppStateToolUseCacheTests.swift`

`testClineTaskCompleteEndsSessionImmediately`：验证 Cline `TaskResume` 后 session 变为 `.processing`，收到 `TaskComplete` 后立即回到 `.idle`。

`testClineDropsStaleToolEventsAfterTaskComplete`：验证 `TaskComplete` 后乱序到达的旧工具事件不会重新激活会话。
