# Atoll 内置 Codex 实施状态

更新日期：2026-08-21

## 已完成

- Atoll 仓库成为唯一主工程，主产品仍为一个 `Atoll.app`。
- Codex Core、Hooks、Reducer、状态仓库、诊断和迁移逻辑已迁入 `DynamicIsland/Features/Codex`。
- 新增 `CodexHookHelper` Xcode 命令行 target，并由 Atoll 主 target 构建和嵌入 `Contents/Helpers`。
- Helper 保持 stdout 为空、失败退出码为 0，并将事件原子写入 `Application Support/Atoll/Codex/inbox`。
- Atoll 启动时会迁移旧 `Application Support/CodexAtoll` 状态，并安装或修复稳定路径下的 Helper 和 Codex Hooks。
- Codex 展示通过宿主内部 Manager 注册，不请求第三方扩展授权，也不调用 Codex 侧 RPC/XPC。
- 内置 Codex 不写入第三方扩展广播快照；第三方 AtollExtensionKit 通道继续保留。
- Atoll 设置的“实用工具”分类已新增 Codex 页面，覆盖启用、安装修复、显示、隐私、全屏和诊断。
- 刘海关闭态摘要、展开任务页、完成提示、等待批准和 Codex 对话跳转已接入宿主展示链路。
- Codex 刘海关闭态不再使用 Lottie 文字层；右侧收敛为纯计数摘要（如 `3 进行中`），不再展示项目名或任务内容；存在已完成任务时在下方增加一行（如 `1 已完成`）并增加关闭态高度。
- Codex 展开任务页高度提升至 420pt，最多直接展示 6 个独立对话区块；每个区块分别展示项目名、状态和相关内容，并可通过 Codex 会话深链跳转。
- 每个独立对话区块整体为单一点击目标；鼠标悬停时背景和描边增强并切换手型光标，点击区块任意位置都会打开对应 Codex 会话。
- Codex 全屏显示由独立设置控制，不需要将 Atoll 全局切换为 `Never hide`。

## 当前验证证据

- `CodexNativeCoreTests: PASS`：新路径、旧 Hook 升级、旧状态迁移幂等和全屏可见性策略。
- `CodexPresentationTests: PASS`：Codex 空闲时保留展开页标签和明确缺省态；关闭态默认只显示进行中计数且保持紧凑，存在完成记录时新增已完成计数行并增加 16pt 高度；展开页仍保留独立对话区块、状态、相关内容和逐条跳转元数据。
- `ExtensionExperienceRouteTests: PASS`：Live Activity 到任务页路由和 Codex URL 安全解析。
- 展开页聚焦回归已覆盖 420pt 高度、最多 6 个独立对话区块、逐条跳转元数据，以及第三方扩展原有高度上限保持不变。
- `CodexHookHelper` Debug target 构建成功。
- Helper 真实 stdin 测试：有效和无效输入均退出 0、stdout 0 字节；有效事件成功写入 envelope。
- Atoll Debug 与 Release 主 Scheme 无签名命令行构建成功，并在 App 包中生成可执行的 `Contents/Helpers/CodexHookHelper`。
- 2026-08-21 16:51 已将包含空闲 Codex 标签修复的 Release 构建安装到 `/Applications/Atoll.app`；按用户要求未保留旧版备份，当前只保留一个最新版 Atoll App。
- 安装后真实进程路径、正式 Bundle ID、ad-hoc 签名、包内 Helper、Codex Hooks 和状态文件均复验通过；通过全局展开快捷键获取的运行时 Accessibility 树已出现 Codex 专用 `terminal.fill` 子标签按钮。
- 2026-08-21 已直接运行 DerivedData 中的 Debug App（未覆盖 `/Applications/Atoll.app`）：Codex 展开页目视约 420pt，真实状态中的 1 条进行中与 2 条最近完成对话全部可见；Accessibility 确认容器为滚动区，3 条对话均暴露为可点击跳转按钮。
- 2026-08-21 本次独立区块改动已通过 `DerivedData/Dev/Build/Products/Debug/Atoll.app` 运行时验收：真实的 2 条进行中对话分别显示为两个圆角区块，每块独立展示项目名、状态时长、相关内容和 Codex 跳转按钮；进程路径与 Bundle ID `com.Ebullioscopic.Atoll.dev` 已核对。
- 2026-08-21 整卡交互的运行时 Accessibility 已确认：每个对话 section 暴露为覆盖项目名、状态和正文的单一按钮，并保留“打开对应的 Codex 对话”帮助提示；单区块与多元素 section 的交互边界由 `ExtensionExperienceRouteTests` 覆盖。
- 2026-08-21 本次关闭态计数改动已使用隔离状态运行 Debug App 验收：单行状态显示为 `2 进行中`，右侧不含具体任务内容；加入 1 条完成记录后显示为 `2 进行中` / `1 已完成` 两行，整体宽度保持不变，刘海向下增加 16pt；Accessibility 标签为“2 进行中，1 已完成”。验收后已恢复真实状态目录和默认 Debug 启动方式。
- 自维护版本默认不启动 Sparkle，也不再指向官方 Atoll appcast；配置自有 `AtollUpdateFeedURL` 或 `ATOLL_UPDATE_FEED_URL` 后才启用更新。
- 官方 Git remote 已从 `origin` 改名为 `upstream`；待提供自有仓库 URL 后再添加新的 `origin`。

## 尚需人工产品验收

- 使用签名后的 Atoll App 首次启动，确认 macOS 实际运行时能自动复制 Helper 并修改当前用户的 `~/.codex/hooks.json`。
- 在真实 Codex 任务中确认运行、等待批准、完成提示、任务页跳转和全屏显示的最终视觉效果。
- 本次已目视确认“进行中”对话的独立区块；“等待批准”和“已完成”区块由聚焦测试覆盖结构与内容，仍需在对应真实状态出现时补最终视觉验收。
- 本次关闭态计数与双行增高已在 Debug App 中完成目视验收，但尚未替换 `/Applications/Atoll.app`；正式安装包仍需在用户明确要求发布时单独验收。
- `/Applications/Atoll.app` 尚未替换为本次高度构建；点击已触发 Codex 深链，但 Computer Use 不允许读取 Codex App，目标任务定位仍需人工确认。
- 空闲 Codex 子标签已通过真实安装包的 Accessibility 树确认；自动化点击后的缺省态最终视觉截图仍受快捷键展开 3 秒自动关闭影响，可由用户直接展开点击完成目视确认。
- 验证 DMG 的正式 Release 签名和分发流程。当前无签名命令行构建不能替代完整 Xcode Archive/签名验收。
- 配置自有 Git 仓库 URL 与 Sparkle appcast 地址；本次未虚构不存在的远程地址。
- macOS 在验收时处于锁屏状态，设置 → 实用工具 → Codex 的最终视觉检查需解锁后补做；源码导航、搜索索引和 Debug/Release 编译已验证。

## 发布边界

- 独立 `/Users/liusong/Git/CodexAtoll` 仓库仅作为迁移来源，不再作为产品构建入口。
- 正式发布只应从本仓库的 `DynamicIsland` Scheme 生成 Atoll App。
- 官方 Atoll 上游 remote 与自有发布 remote 的最终地址仍应在建立自有远程仓库后配置。
- Release Bundle ID 暂保留 `com.Ebullioscopic.Atoll`，用于原位替换当前宿主；若未来要与官方 Atoll 并存发布，必须先改为自有 Bundle ID 并重新申请相关权限。
