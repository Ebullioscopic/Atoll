# Atoll 内置 Codex 实施状态

更新日期：2026-08-23

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
- Codex 刘海关闭态不再使用 Lottie 文字层；右侧只展示一个纯计数状态（如 `3 · 进行中`），优先级为已完成、等待批准、进行中，不再同时展示进行中和已完成，也不再增加关闭态高度。
- 只要存在任意 Codex 进行中任务，刘海关闭态左侧就使用深靛蓝玻璃终端、双行代码流推进和跟随式闪烁光标组成的克制循环动画；右侧摘要仍独立遵循“已完成、等待批准、进行中”的状态优先级，因此混合状态可同时表达“存在未查看完成”与“仍有任务运行”。
- Codex 固定忙碌态、固定已完成态、计数文案和配色保持不变；完成庆祝保持 3.5 秒，进行中新对话提醒延长为 6 秒，并以轻量缩放、模糊收敛、环形扫光和克制的微粒庆祝替代原有提示。
- Codex 新对话提醒改为纵向双层结构：上方用低对比小字号标注项目，下方由对话主题独占完整可用宽度进行跑马灯展示；删除无信息价值的“执行”标签和横向项目胶囊，主题在 0.28 秒后以 58pt/s 开始滚动，右侧使用渐隐边缘收束长文本。
- Codex 已完成数按“未查看完成”单独计数；点击 Codex 关闭态/完成提示进入任务页、直接切换到 Codex 任务页，或浏览活动托盘后关闭抽屉时清零未读徽标，已完成对话继续保留在历史托盘中。
- Codex 活动托盘按“需要处理 / 异常或可能失联 / 已完成待查看 / 进行中”分组，默认展示 10 条完成历史并支持查看更多；完成历史默认保留 7 天、最多 100 条紧凑记录。
- Codex 活动托盘折叠使用固定系统默认：有内容的行动类、最新完成和进行中分组默认展开，历史完成默认折叠；一级分组和项目分组仅在当前打开期间可手动折叠，关闭后不持久化，历史“查看更多”下次打开恢复收起。
- 同一 Codex 对话的多轮完成在活动托盘中合并为一张最新卡片；绿色完成卡片第一次进入抽屉当前可视区域时记录展示并保持高亮，抽屉关闭后立即记为已读并转为灰色历史状态，未滚动到可视区域的完成项继续保留未读提示。
- Codex 展开任务页高度提升至 420pt，最多直接展示 6 个独立对话区块；每个区块分别展示项目名、状态和相关内容，并可通过 Codex 会话深链跳转。
- 每个独立对话区块整体为单一点击目标；鼠标悬停时背景和描边增强并切换手型光标，点击区块任意位置都会打开对应 Codex 会话。
- 对话区块标题优先使用清理后的首条用户提示，附件包装会在截断前移除，标题限制为 24 个字符；Hooks 未提供标题或旧数据已截断时回退项目名。
- 对话状态使用颜色和文字双重表达：进行中为蓝色、已完成为绿色、等待批准为橙色，并同步用于状态圆点、文字、卡片背景和边框。
- Codex 全屏显示由独立设置控制，不需要将 Atoll 全局切换为 `Never hide`。

## 当前验证证据

- `CodexNativeCoreTests: PASS`：新路径、旧 Hook 升级、旧状态迁移幂等和全屏可见性策略。
- `CodexPresentationTests: PASS`：Codex 空闲时保留展开页标签和明确缺省态；关闭态固定为单行，进行中显示为 `数量 · 进行中`，存在未查看完成记录时只显示优先级更高的 `数量 · 已完成`，宽度和高度均不增加；`3 个已完成 + 1 个进行中` 的混合状态已覆盖右侧显示 `3 · 已完成`、左侧继续启用忙碌动画；展开页仍保留独立对话区块、状态、相关内容和逐条跳转元数据。
- `CodexCompletionAcknowledgementTests: PASS`：首次展示状态持久化但不清零、关闭后确认并清零、重复确认幂等、最近完成历史保留、旧状态兼容，以及新完成任务重新计数。
- `CodexActivityTrayCompletionDeduplicationTests: PASS`：同一会话多轮完成去重、最新一轮重新变为未读、首次展示保持高亮、同一展示周期防重复确认、抽屉关闭确认，以及抽屉可视区域判定。
- `CodexPresentationTests: PASS`：已读完成记录仍在活动托盘中保留，12 条完成历史可完整生成，默认历史上限与保留策略已覆盖。
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
- 2026-08-21 对话标题和状态颜色已在真实混合状态下运行验收：已完成卡片显示清理、截短后的用户提示标题及绿色状态样式，进行中卡片显示蓝色状态样式；当前运行任务属于改动前已截断的附件包装数据，因此按设计回退项目名，后续新 Hook 事件会直接写入干净标题。
- 2026-08-21 本次顶部单状态改动已通过聚焦回归和 Debug 主 App 构建；运行进程已核对为 `DerivedData/Dev/Build/Products/Debug/Atoll.app`、Bundle ID `com.Ebullioscopic.Atoll.dev`。Computer Use 启动后红色录屏状态会占用顶部右翼，因此本次未把该录屏画面作为 Codex 文本的最终视觉验收证据。
- 2026-08-23 “进行中”动态忙碌图标改动已通过 `git diff --check` 和 Debug 主 App 构建；`./scripts/dev-run` 已核对实际运行进程来自 `DerivedData/Dev/Build/Products/Debug/Atoll.app`、Bundle ID `com.Ebullioscopic.Atoll.dev`，没有替换 `/Applications/Atoll.app`。用于运行态检查的临时 Codex 会话已发送 `SessionEnd` 并确认转为 `ended`。
- 2026-08-23 Codex 临时提示动效已通过 `CodexPresentationTests`，覆盖新对话 6 秒、完成庆祝 3.5 秒及标准展示模式；`CodexHookHelper` Debug target 与 Atoll Debug 主 App 均构建成功，运行进程路径和 Debug Bundle ID 已复验。
- 2026-08-23 修复完成庆祝被后台 0.5 秒常规刷新提前覆盖的问题：Presentation Coordinator 在 3.5 秒完成脉冲期间只更新最新快照，普通刷新不得恢复稳定态；新完成事件接管并重新开始完整窗口，旧恢复任务不会覆盖新庆祝。聚焦状态门测试已通过。
- 2026-08-23 修复新对话在已有 Codex Live Activity 时不触发提醒的问题：Reducer 为 `UserPromptSubmit` 发出独立进行中事件，Presentation Coordinator 将其转换为 `running-pulse` 更新并保持完整 6 秒；即使当前仍有未读完成记录，提醒内容和蓝色动效也取自刚开始的新对话，不再被历史完成状态拦截。
- 自维护版本默认不启动 Sparkle，也不再指向官方 Atoll appcast；配置自有 `AtollUpdateFeedURL` 或 `ATOLL_UPDATE_FEED_URL` 后才启用更新。
- 官方 Git remote 已从 `origin` 改名为 `upstream`；待提供自有仓库 URL 后再添加新的 `origin`。

## 尚需人工产品验收

- 使用签名后的 Atoll App 首次启动，确认 macOS 实际运行时能自动复制 Helper 并修改当前用户的 `~/.codex/hooks.json`。
- 在真实 Codex 任务中确认运行、等待批准、完成提示、任务页跳转和全屏显示的最终视觉效果。
- 本次已目视确认“进行中”对话的独立区块；“等待批准”和“已完成”区块由聚焦测试覆盖结构与内容，仍需在对应真实状态出现时补最终视觉验收。
- 本次 Codex 任务页已增加滚动期间的关闭手势抑制；当前 Debug App 已核对启动路径和 Bundle ID，但因 ScreenCaptureKit 捕捉失败，尚未完成“连续上滑展示第 4–6 条且页面不退出”的最终视觉验收。
- 本次关闭态单状态布局尚需在没有录屏状态占位时补最终目视验收；尚未替换 `/Applications/Atoll.app`，正式安装包仍需在用户明确要求发布时单独验收。
- 本次“进行中”动态忙碌图标已完成代码、30pt 黑色背景独立渲染和 Debug 构建验证；Computer Use 会触发 macOS 红色录屏状态并占用同一刘海区域，因此代码流推进和跟随式光标的实际节奏仍需在停止录屏后由用户目视确认。
- 本次新对话入场和完成庆祝动效已完成代码、聚焦时序测试和 Debug 运行链路验证；Computer Use 的屏幕采集没有捕获 Atoll 顶层刘海窗口，因此两段动画的最终节奏和观感仍需在不录屏时由用户目视确认。
- 本次活动托盘已完成聚焦测试和 Debug 构建；真实展开后点击“查看更多”、历史列表滚动以及已读徽标与历史记录分离的最终视觉验收仍需在停止录屏后补做。
- 本次“完成卡片首次展示保留高亮、抽屉关闭后转为已读”已完成纯逻辑回归和 Debug 主 App 构建；仍需在真实未读完成数据下目视确认首次展开、关闭后计数刷新和卡片转灰的最终节奏。
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
