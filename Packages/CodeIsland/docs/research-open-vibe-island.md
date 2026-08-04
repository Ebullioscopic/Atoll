# open-vibe-island 对比研究

> 调研日期：2026-04-30
> 我方 HEAD：`257778b`（v1.0.24，准备发 v1.0.25）
> 对方 HEAD：`Octane0411/open-vibe-island` main，最近一次 force pull `2026-04-30 09:55`
> 对方协议：GPL v3（copyleft，不能 `git cp` 进我们 MIT 仓库）
> **研究原则**：只读代码看思路，按 vibe-notch 的 `CodeIsland*` 命名 / 三模块布局重写。具体出处见 `memory/feedback_no_verbatim_copy_from_competitors.md`

---

## TL;DR — 三句话总结

1. **对方做得最好、我们最缺的是 Apple Watch 通知链路**（iOS app + WatchHTTPEndpoint + SSE + WCSession 全套），我们目前只有 Android Watch，对应苹果生态主力用户群直接断档。
2. **对方做得更工程化的是「自检 / 意图 / 可修复诊断」三件套**：`HookHealthCheck` 结构化诊断、`AgentIntentStore` 三态意图、`AGENTS.md` 给 AI agent 的规范——这些是体力活但 UX 收益巨大。
3. **我们已经领先的部分**：AI 工具覆盖（17+ vs 10）、ESP32 硬件桥、Android Watch、sub-agent 精确折叠（#148）、`tool_use_id` 并发去重、诊断 log 体系——别在重构里把这些丢了。

---

## 1. 项目档案

| 维度 | vibe-notch (CodeIsland) | open-vibe-island | 差异 |
|---|---|---|---|
| License | MIT | GPL v3 | 我们更宽松（商业可闭源 fork） |
| Swift Package targets | 3：CodeIsland / CodeIslandCore / CodeIslandBridge | 4：OpenIslandApp / OpenIslandCore / OpenIslandHooks / OpenIslandSetup | 对方多一个独立 Setup CLI |
| 主状态类 | `AppState`（~3950 行单体） | `AppModel`（`@Observable`，配合 `SessionState.apply` reducer） | 对方更细，我们已 backlog 拆分 |
| 状态 reducer | `SessionSnapshot.reduceEvent` | `SessionState.apply` | 形态相同，命名不同 |
| Hook 二进制 | `codeisland-bridge` | `OpenIslandHooks` (Swift) + `open-island-hooks.py` (远程) | 对方多 Python 远程版 |
| 自动更新 | Sparkle 2 + Homebrew cask | Sparkle 2 only | 我们多一条 brew 通道 |
| 移动端 / 周边 | Android Watch（gradle 项目） + ESP32 桌面摆件 | iOS App + Apple Watch | **完全互补**：我们手腕侧覆盖 Wear OS，对方覆盖 watchOS |

---

## 2. 功能矩阵：领先 / 平手 / 落后

### ✅ 我们已经领先

| 项 | 我们 | 对方 | 备注 |
|---|---|---|---|
| AI 工具支持数 | 17+ | 10 | 多出 Trae、StepFun、AntiGravity、WorkBuddy、Hermes、Kiro、pi-mono、Copilot |
| Android Watch | 有 | 无 | gradle 项目 `android-watch/` |
| ESP32 物理桌面摆件 | 有 | 无 | `hardware/` 18 个 mascot 头文件 + Arduino sketch |
| Sparkle + Homebrew cask 双通道 | 有 | 仅 Sparkle | 对方没做 brew |
| sub-agent 精确折叠（Cursor 多并发不刷屏） | 有 (#148) | 似乎没处理 | `CLIProcessResolver.resolvedSessionPID` 取 ancestry 最 root |
| `tool_use_id` 精准配对 + 并发不误删 | 有 (#147) | 没看到对应处理 | `AppState+ToolUseCache` 五个方法 |
| Warp SQLite 精准 pane 跳转 | 有 | 有 | 实现都基于 SQLite + AX，独立做的 |
| Codex Desktop JSON-RPC | 有 | 有 | 双方独立做，协议一致 |
| JSONL 增量 tail（DispatchSource + offset） | 有 | 有但没看到 quickTypeProbe 字节预筛 | 我们额外做了 53% 时延优化 |
| 诊断 log 体系（`permission deny reason=...`） | 有 (#147) | 没看到 | Console.app grep 友好 |
| Hook 事件 ring buffer + 导出 | 有 (#103) | 没看到 | Plugin Sub-Sessions 设置面板 |
| 任务完成时是否自动展开（用户开关） | 有 (#146) | 没看到 | |

### 🤝 大致平手

| 项 | 备注 |
|---|---|
| Claude Code / Codex / Cursor / Gemini / OpenCode hook 集成 | 双方 hook 事件全集都接，差异在于细节 |
| Warp 跳转 / iTerm / Ghostty / Terminal.app | 双方都全 |
| 通知声音 / mute toggle | 双方都有 |
| i18n（中英） | 双方都有，我们之前还修过土耳其语翻译 |
| 签名 + 公证 DMG | 双方都有 |

### ❌ 我们落后或缺失

| 项 | 价值 | 优先级 | 详见 |
|---|---|---|---|
| **Apple Watch + iOS 通知链路** | ⭐⭐⭐⭐⭐ | P1 | §3.1 |
| **Hook Health Check 结构化自检** | ⭐⭐⭐⭐⭐ | P1 | §3.2 |
| **Permission Memory（AgentIntent 三态持久化）** | ⭐⭐⭐⭐ | P2 | §3.3 |
| **Claude / Codex Usage 显示（额度百分比）** | ⭐⭐⭐⭐ | P2 | §3.4 |
| **WorkspaceNameResolver（git worktree 友好命名）** | ⭐⭐⭐ | P2 | §3.5 |
| **SSH Remote 完整工具链**（Python hook + remote-setup） | ⭐⭐⭐ | P3 | §3.6 |
| **更多终端跳转**：cmux / Kaku / WezTerm / Zellij / tmux multiplexer | ⭐⭐⭐ | P3 | §3.7 |
| **独立 Setup CLI 二进制** | ⭐⭐ | P4 | §3.8 |
| **Session State 重构（process-as-source-of-truth）** | ⭐⭐ | P5 | §3.9 |
| **AGENTS.md（给 AI 协作者的规范）** | ⭐⭐ | P5 | §3.10 |

---

## 3. 可借鉴的功能详解

### 3.1 ⭐⭐⭐⭐⭐ Apple Watch + iOS 通知链路（P1）

**为什么重要**：刘海容易被全屏遮挡 / 被忽视；手腕震动是更强的感官通道。Agent 等审批 / 提问时，远离屏幕的用户能第一时间感知。我们已有 Android Watch，补 Apple Watch 后覆盖完整移动端。

**对方架构**（参考 `docs/watch-notification-design.md`）：
```
Mac App
 └ WatchHTTPEndpoint (NWListener TCP + Bonjour _openisland._tcp + 4 endpoints)
   ├ POST /pair      → 4 位配对码 → Bearer token
   ├ GET  /events    → SSE 长连，推 permission/question/completed
   ├ POST /resolution→ Watch 回传 allow/deny/选项
   └ GET  /status    → 连接状态
 └ WatchNotificationRelay (监听 AppModel 状态变化 → push SSE)

iPhone App (OpenIslandMobile)
 └ NWBrowser (Bonjour 发现 Mac)
 └ SSEClient (URLSession, infinite timeout, 401 自动重配对)
 └ NotificationManager (UNNotificationCategory: PERMISSION_REQUEST / QUESTION / SESSION_COMPLETED)
 └ WatchConnectivityManager (中继到 Watch)

Apple Watch App (OpenIslandWatch)
 └ WatchSessionManager (WCSession + UNNotificationCenter delegate)
 └ HapticManager
```

**我们的实施思路**（不抄代码，按 CodeIsland 命名）：
- `Sources/CodeIslandCore/WatchHTTPEndpoint.swift`：复用 NWListener 实现轻量 HTTP / SSE，注册 Bonjour `_codeisland._tcp`。手写 HTTP/1.1 解析（NWListener 给的是 raw TCP）。
- `Sources/CodeIslandCore/WatchNotificationRelay.swift`：监听 `AppState.refreshDerivedState` 时的 `summary.status` 变化，过滤出三类事件 push 出去。
- iOS app 用独立 Xcode project（`ios/CodeIslandMobile.xcodeproj`），SPM 不便混 iOS。`OpenIslandShared` 那种共享 framework 我们用 `CodeIslandCore` 跨平台编（macOS 14+ / iOS 17+）。
- 配对码用 6 位（对方 4 位偏短）。token 持久化在 Keychain。
- **trade-off**：iOS 后台 SSE 长连接经常被系统断开，需要重连逻辑 + 评估 Background Modes。
- **关键坑**：iOS 14+ 局域网权限要 `NSLocalNetworkUsageDescription` + `NSBonjourServices`。

**额外问题**：
- 我们已有 `RemoteManager.swift` / `RemoteInstaller.swift` 处理 Mac-to-Mac 远程，需要确认 HTTP server 端口、Bonjour 名称不要跟 Remote SSH 通道冲突。
- 我们 LICENSE 是 MIT，iOS app 上架时需要补 PRIVACY_POLICY.md（对方有 `PRIVACY_POLICY.md` 可参考结构，文字自己写）。

---

### 3.2 ⭐⭐⭐⭐⭐ Hook Health Check 结构化自检（P1，task #1）

**为什么重要**：用户报"hook 不工作"是最高频问题。我们目前只有 `verifyAndRepair`（HANDOFF 提到搬出主线程），但没有结构化诊断。对方 `HookHealthCheck.swift` 给每个 issue 都打了 severity（error / info）+ `isAutoRepairable` 标志，UI 可以直接渲染"问题列表 + 一键修复"。

**对方诊断维度**（每个 agent 一份 `HookHealthReport`）：
| Issue | severity | 可自动修复 |
|---|---|---|
| `binaryNotFound` | error | ❌ 需重装 app |
| `binaryNotExecutable` | error | ✅ chmod |
| `configMalformedJSON` | error | ❌ 需用户介入 |
| `staleCommandPath`（settings.json 里的 path 已不存在） | error | ✅ 重写路径 |
| `manifestMissing`（看到 hook 但没 manifest） | error | ✅ 重生成 |
| `pluginMissing`（OpenCode plugin 文件丢） | error | ✅ 重写 |
| `otherHooksDetected`（共存的第三方 hook） | info | — |

**我们的实施思路**：
- 新建 `Sources/CodeIslandCore/HookHealthCheck.swift`（不是 `Sources/CodeIsland`，因为要复用到 bridge）。
- 在 `ConfigInstaller` 旁边加 `HookHealthReport`，每个 source（claude / codex / cursor / opencode / gemini / kimi / qoder / qwen / factory / codebuddy / trae / stepfun / ...）都有一份。
- Settings UI 加一个"Health"面板，红绿灯 + 修复按钮。我们已有 Plugin Sub-Sessions 面板（#123），加在那附近。
- **额外发现**：对方 `containsClaudeIslandHook` 检查 `claude-island-state.py` 残骸——我们之前清过 vibe-island 残骸（HANDOFF v1.0.22 段），这个思路可以推广，做一个"已知遗留 hook 黑名单"持续显示在 health 面板。
- **trade-off**：扫多个 config 文件 I/O 不便宜，要节流（30s 一次或 settings 打开时再扫）。

---

### 3.3 ⭐⭐⭐⭐ Permission Memory / AgentIntent（P2，task #4）

**为什么重要**：对方设计的 tri-state `untouched / installed / uninstalled` + `firstLaunchCompleted` + `migrationVersion` 解决了一个真实痛点：**用户主动卸载某个 agent 的 hook 后，启动流程绝不应该静默重装**。

**对方核心模型**（`AgentHookIntent.swift` + `AgentIntentStore.swift`）：
```swift
enum AgentHookIntent: String { case untouched, installed, uninstalled }
// untouched：从未碰过 → 可以提示安装
// installed：用户决定安装 → 启动时 verify + 必要时修复
// uninstalled：用户决定卸载 → 启动时不能动它
```

**关键机制**：
- `migrationVersion` 防止重复 legacy 迁移。第一次升级：扫 disk 上现有 hook → 全部置为 installed → `firstLaunchCompleted = true`，跳过 onboarding。
- 单一来源真相：UserDefaults，注入式 default suite 方便测试。

**我们的实施思路**：
- 新建 `Sources/CodeIsland/AgentIntentStore.swift`。
- `AgentIdentifier` 我们要列全 17+ 个 source（不是对方的 11 个）。
- 我们目前 `Settings.swift` 里已经有部分 default 控制，需要把"是否安装某 hook"统一到 IntentStore，避免 setting / disk / actual install 三个真相。
- onboarding：我们目前没有显式 onboarding 流程，可以借这次加一个简化的"首次启动 → 选用哪些 agent"。
- **trade-off**：UserDefaults key 命名一旦定下不能改（`agentIntent.<rawValue>`），rawValue 必须稳定。

---

### 3.4 ⭐⭐⭐⭐ Claude / Codex Usage 显示（P2，新）

**为什么重要**：在灵动岛上能看到"5h 窗口已用 60% / 7d 窗口已用 32%"对重度用户是刚需。对方 `ClaudeUsage.swift` 拉的就是 Claude rate_limits 缓存。

**对方实现**：
- `ClaudeUsage.swift`：从 `/tmp/open-island-rl.json` 读 `five_hour` / `seven_day` 两个窗口的 used_percentage + resets_at。
- 这个 JSON 由 Claude Code 自己写（status line bridge 把 Claude 自带的 rate_limits 缓存到这个路径）。
- `ClaudeStatusLineInstallationManager`：托管 `~/.claude/settings.json` 的 statusLine.command，写入 `~/.open-island/bin/open-island-statusline`，已有自定义 statusLine 时**拒绝覆盖**（保护用户配置）。

**我们的实施思路**：
- 新建 `Sources/CodeIslandCore/ClaudeUsage.swift` + `Sources/CodeIslandCore/CodexUsage.swift`。
- statusLine bridge 二进制可以用 shell script 而不是另起一个 Swift target，开销更小。
- 灵动岛上不要默认显示（避免干扰），放进 settings → 展开面板可见。
- **trade-off**：Codex 的 5h/7d 窗口只有 ChatGPT Plus / Pro 用户有，免费版会 404。
- **关键坑**：用户已有自定义 statusLine 时一定要 detect + 拒绝。Pre-flight 检查：读 `~/.claude/settings.json`，看 `statusLine.command` 是否非空且非我们的 path。

---

### 3.5 ⭐⭐⭐ WorkspaceNameResolver（P2，新）

**为什么重要**：使用 `git worktree` 的 worktree-heavy 工作流（开多个分支并行 vibe）越来越多。原始 cwd 是 `~/code/foo/.git/worktrees/feat-bar`，session 卡片显示 `feat-bar` 没意义；解析回项目本名 `foo` + 分支 `feat/bar` 才对。

**对方实现**（`WorkspaceNameResolver.swift`）：
- 识别 `/.claude/worktrees/` 和 `/.git/worktrees/` 两个 marker
- 切回 marker 之前的 last path component 作为项目名
- 把 marker 之后的部分 `+` → `/` 还原为分支名（git worktree 默认把 `/` 在路径里替换成 `+`）

**我们的实施思路**：
- 新建 `Sources/CodeIslandCore/WorkspaceNameResolver.swift`。
- 集成到 `SessionSnapshot` 的 cwd → workspace 派生逻辑（应该在 `deriveSessionSummary` 附近）。
- 卡片标题逻辑：`"\(projectName) (\(branch))"`。
- **trade-off**：用户自定义 worktree 路径不带 `worktrees/` marker 时回退到 lastPathComponent。
- **额外**：可以扩展支持 `jj`（jujutsu）的 colocated workspace。

---

### 3.6 ⭐⭐⭐ SSH Remote 完整工具链（P3）

**为什么重要**：我们已有 `SSHForwarder.swift`（Mac 端主动起 ssh -R 转发 socket），但对方还提供：
- 远程端 `open-island-hooks.py`（Python，远程不需要 Swift）
- 一键 setup `scripts/remote-setup.sh user@server`（自动 scp 脚本 + 注入 hooks.json）
- `RemoteForward` SSH config 模板
- Mac-to-Mac UID 不匹配的映射方案
- sshd 端 `StreamLocalBindUnlink yes` 的明确文档

**我们目前缺**：远程端二进制 + setup 脚本 + UID 不匹配 docs。

**我们的实施思路**：
- 新建 `scripts/remote-setup.sh`：参数 `user@host`，scp `open-island-hooks.py` + 写远程 `~/.claude/settings.json`。
- 新建 `scripts/codeisland-hooks.py`（命名跟项目一致）：从 stdin 读 hook payload，连本地（forwarded）socket，超时即 fail-open。
- 在 `docs/` 下新建 `ssh-remote-setup.md`，把 UID / sshd_config / 排错全列清楚。
- Settings UI 的 Remote 面板加一个"复制远程安装命令到剪贴板"按钮。
- **trade-off**：Python 3.6+ 几乎到处都有，但 Alpine 容器要装 `python3` package。
- **关键坑**：socket 路径默认 `/tmp/codeisland-$(id -u).sock`，远程端要 `OPEN_ISLAND_SOCKET_PATH` 等价的 env var 覆写。

---

### 3.7 ⭐⭐⭐ 更多终端跳转（P3，task #2/#3）

**对方支持但我们缺**：

| 终端 | 我方 | 对方 | 跳转策略 |
|---|---|---|---|
| **cmux** | ❌ | ✅ | Unix socket API（`CMUX_SOCKET_PATH` env） |
| **Kaku** | ❌ | ✅（task #3） | CLI pane targeting（`kaku --pane <id>`） |
| **WezTerm** | ❌ | ✅ | `wezterm cli activate-pane --pane-id <id>` |
| **Zellij** | ❌ | ✅（task #2） | `zellij action focus-pane --pane-id <id>` |
| **tmux multiplexer** | 部分 | ✅ | `switch-client → select-window → select-pane` 链 |

**我们的实施思路**：
- 在 `TerminalActivator.swift` 加分支。每个终端用对应的 env var 探测 + CLI command 跳转。
- Hook payload 端：bridge 已经收 env vars（`Sources/CodeIslandBridge/main.swift` 的 ancestry/effectiveSource 块），需要把 `CMUX_*` / `ZELLIJ_*` / `KITTY_*` 等带过去。
- **趋势**：tmux 的 socket 多服务器场景（`-L socketname`）我们目前 `tmuxEnv` 字段已经记了，但 `TerminalActivator` 是否消费它要核对。
- **trade-off**：每加一种终端就多一份维护负担，先按 GitHub issue 的呼声排序（cmux > tmux > zellij > kaku/wezterm）。

---

### 3.8 ⭐⭐ 独立 Setup CLI 二进制（P4）

**对方**：第四个 SPM target `OpenIslandSetup`，支持 `swift run OpenIslandSetup install / status / uninstall / installKimi / ...`。

**价值**：自动化 / CI / 远程部署 / Homebrew formula 安装后处理。我们目前所有 hook 安装都在主 app 里，命令行无法操作。

**我们的实施思路**：
- 新建 SPM target `CodeIslandSetup`，复用 `CodeIslandCore.ConfigInstaller`。
- 跟现有 `codeisland-bridge` 一起打到 DMG `Contents/Helpers/` 里，brew formula 安装时 symlink 到 `/usr/local/bin/codeisland-setup`。
- **trade-off**：增加一个 helper binary 要重新过 codesign / notarize 流程，记得在 `scripts/build-dmg.sh` 加。

---

### 3.9 ⭐⭐ Session State 架构重构（P5）

**对方文档**：`docs/session-state-refactor.md`，核心思想：
- **process discovery 是唯一可靠的 visibility 来源**（Claude `/exit` 不发 SessionEnd 是已知 bug GitHub #17885）
- 删 attachment 三态、删 grace window、删 synthetic session
- "process not seen for 2+ polls (~6s)" 触发移除，防 ps 抖动
- 净删 ~1000 行代码

**与我们的关系**：HANDOFF 已经标 `AppState.swift ~3950 行待拆分`。这是个长期重构方向，不是单 PR 能完成。

**我们的思路**（如果要做）：
- 不要直接照搬对方"删 attachmentState"，因为我们 `SessionAttachmentState` 是否真的有 `attached/stale/detached` 三态要先核对（我没读完这块）。
- 先做 §3.2 / §3.3 / §3.4 这种增量加价值的功能，重构留到 v1.1.x。

---

### 3.10 ⭐⭐ AGENTS.md 协作规范（P5，新）

**对方**：根目录 `AGENTS.md`，给 Claude Code / Codex 这种协作者看的"在这个仓库怎么干活"规范。

**价值**：用户用 AI 让 agent 帮自己提 PR / 修 bug 时，agent 能直接读这个文件了解规范，省得每次都在 prompt 里重复。我们已有 `.superpowers/`，但 AGENTS.md 是新兴的事实标准。

**我们的实施**：根目录建 `AGENTS.md`，从 `HANDOFF.md` + `CLAUDE.md` 提炼出"工程规范" / "测试约定" / "发版 checklist"，给协作者看。

---

## 4. 我们独有的优势（保留清单 — 重构不要丢）

按重要性排序：

1. **17+ AI 工具支持**：Trae、StepFun、AntiGravity、WorkBuddy、Hermes、Kiro、pi-mono、Copilot 都是对方没有的。维护成本高但是核心差异化。
2. **ESP32 物理桌面摆件**：`hardware/` 下 18 个 mascot 头文件 + Arduino sketch，是我们独家硬件桥。
3. **Android Watch**：跟对方 Apple Watch 完美互补。
4. **sub-agent 折叠（#148）**：`CLIProcessResolver.resolvedSessionPID` 用 ancestry 最 root —— 对方似乎还会在 Cursor sub-agent 时刷出多张卡。
5. **`tool_use_id` 并发不误删（#147）**：`AppState+ToolUseCache` 五个方法 + `pendingToolUses` cache。对方代码里没看到等价 surgical drain，可能仍有这个 bug。
6. **诊断 log 体系**：subsystem `com.codeisland`，所有 deny 路径都打 `permission deny reason=...`。Console.app 一抓就定位。
7. **Sparkle + Homebrew cask 双发布通道**：Homebrew 用户的 `UpdateChecker.start()` 自动禁用 Sparkle 更新（避免双更新冲突）。
8. **Hook 事件 ring buffer + diagnostics 导出（#103）**：用户报 bug 时一键导出近期事件。
9. **Plugin Sub-Sessions UI 设置（#123）**：separate / merge / hide 三档。
10. **JSONL `quickTypeProbe` 字节预筛**：对方有 JSONLTailer 但没看到这个优化（我们 11.76ms → 5.49ms，-53%）。
11. **Warp `nolock=1` URI**：readonly + firmlink 归一化 + active>focused>newest 排序。
12. **多 mascot 设计**：Qwen 紫色六角星、StepFun 方块阶梯、AntiGravity 彩虹三角等定制美术。

---

## 5. 实施建议 / 优先级路线

### 短期（v1.1，~1 个月）
- **P1 · §3.2 Hook Health Check** — 已在 backlog (task #1)，结构化诊断 + UI 一键修复。
- **P1 · §3.3 Permission Memory** — 已在 backlog (task #4)，避免静默重装。
- **P2 · §3.4 Claude/Codex Usage 显示** — 增量功能，价值高、风险低。
- **P2 · §3.5 WorkspaceNameResolver** — 一个文件 + 集成到 `deriveSessionSummary`。

### 中期（v1.2，~2 个月）
- **P1 · §3.1 Apple Watch 链路** — 已在 backlog (task #5)，工程量最大。
  - 子任务 1：`WatchHTTPEndpoint` + Bonjour（纯 Mac 端，curl 测试）
  - 子任务 2：iOS app 骨架 + Bonjour 发现 + 配对
  - 子任务 3：本地通知 + Watch 镜像
  - 子任务 4：双向交互
  - 子任务 5：UI 打磨 + 后台 SSE 重连
  - 用 integration branch `feat/apple-watch` 集成，最后一个 PR 合 main
- **P3 · §3.6 SSH Remote 工具链** — Python hook + setup 脚本。
- **P3 · §3.7 更多终端**（tasks #2 / #3 + 新增）— 按用户呼声逐步加。

### 长期（v2.x）
- **P4 · §3.8 独立 Setup CLI**
- **P5 · §3.9 Session State 架构重构**（大改 `AppState`）
- **P5 · §3.10 AGENTS.md**

---

## 6. 不抄代码原则的提醒

研究对方代码时**只读不抄**（参考 `memory/feedback_no_verbatim_copy_from_competitors.md`）：

1. **GPL v3 vs MIT 不兼容**——直接 `git cp` 进我们仓库会传染 GPL，所有用户失去商业闭源 fork 权。
2. **社区识别成本**——逐行搬运在 issue / fork 比对里很容易被发现，损害项目声誉。
3. **命名要按 vibe-notch 风格**：`CodeIsland*` 前缀、`AppState`（不是 `AppModel`）、`SessionSnapshot`（不是 `SessionState`）、`HookEvent`（不是 `AgentEvent`）。
4. **算法 / 协议参考公开规范**——SSE 用 W3C HTML Living Standard，Bonjour 用 RFC 6762/6763，HTTP/1.1 解析按 RFC 9112，不引用对方源码。
5. **真要参考某段必须的逻辑**（比如 Warp SQLite schema），在 commit message 注明"参考 open-vibe-island 的思路，按本项目风格重写"，不隐藏来源也不直接搬运。

---

## 7. 参考资源

| 类别 | 来源 |
|---|---|
| 对方文档 | `/tmp/research/open-vibe-island/docs/`（已克隆） |
| 对方核心源码 | `Sources/OpenIslandCore/{HookHealthCheck,AgentIntentStore,WatchHTTPEndpoint,WatchNotificationRelay,ClaudeUsage,WorkspaceNameResolver}.swift` |
| 对方 iOS 端 | `ios/{OpenIslandMobile,OpenIslandWatch,Shared}/` |
| 对方 OpenCode plugin | `Sources/OpenIslandApp/Resources/open-island-opencode.js` |
| 对方 SSH 远程脚本 | `scripts/{remote-setup.sh,open-island-hooks.py}` |
| 我方 HANDOFF | `HANDOFF.md`（v1.0.24，HEAD `257778b`） |
| 我方 backlog | tasks #1-#5（pending），本文档对其细化 |

---

## 8. 下一步 Action

1. 把 backlog tasks #1-#5 的 description 用本文档对应章节链接更新（`task #1 → §3.2`，等等）。
2. v1.0.25 发完后再启动 P1 项；不要塞进当前 release。
3. Apple Watch 链路（§3.1）启动前先开 GitHub issue 收集用户对 Android Watch 现有体验的反馈，避免重复踩坑。
4. 每个落地项的 commit message 都注明"参考 open-vibe-island 思路，按 vibe-notch 风格重写"。
