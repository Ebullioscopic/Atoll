# Code Island Buddy 真机测试流程

这份流程用于验证 Code Island 的 iPhone、Live Activity / Dynamic Island / StandBy、Apple Watch app 和 watchOS widget 在真实设备上的表现。

## 测试目标

- Mac 端 Code Island 能被 iPhone 发现并连接。
- Mac 当前 agent 状态能同步到 iPhone app。
- iPhone 开启实时活动后，锁屏、灵动岛、StandBy 能显示当前状态。
- iPhone 进入后台后一段时间，仍能通过轻量蓝牙摘要刷新实时活动。
- Apple Watch 能从 iPhone 同步状态、最近动态和问题状态。
- 断连、重连、锁屏、后台等边界状态不出现明显卡死或错误 UI。

## 设备与环境

| 项目 | 要求 |
| --- | --- |
| Mac | 已安装当前分支构建出的 CodeIsland Mac app |
| iPhone | 已通过 USB 连接到 Mac，并在 Xcode 中信任/配对 |
| Apple Watch | 已与这台 iPhone 配对，调试时已信任 Mac |
| 网络 | Mac 和 iPhone 在同一个 Wi-Fi；蓝牙开启 |
| 权限 | iPhone 允许本地网络、蓝牙、通知；Watch 允许通知 |
| Xcode | 顶部设备选择器能看到 iPhone；需要测 Watch 时能看到 Apple Watch |

## 先跑本地检查

在真机前先确认代码本身是干净的：

```bash
swift test -c release
scripts/check-companion-ui-regressions.sh
scripts/smoke-companion-ui.sh
scripts/smoke-companion-watch-ui.sh
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .build/CompanionUITestDerivedData \
  test
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandWatchApp \
  -configuration Release \
  -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO build
```

通过标准：

- 所有命令通过。
- `xcodebuild` 输出里没有 `error:`。
- 没有新增需要处理的 `warning:`。

上面的 UI Test 会用模拟状态自动覆盖 iPhone app 的提问态、长消息滚动和空闲态。它不依赖 Mac 连接，主要用来提前发现按钮消失、卡片不可访问、最近动态不可滚动这类回归。

如果要把同一套 UI Test 跑到真机，把 destination 改成 iPhone 的设备 ID：

```bash
xcodebuild -project ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj \
  -scheme CodeIslandCompanion \
  -configuration Debug \
  -destination 'platform=iOS,id=<你的 iPhone 设备 ID>' \
  -derivedDataPath .build/CompanionDeviceUITestDerivedData \
  test
```

真机 UI Test 需要 iPhone 解锁、屏幕保持亮起，并且 Xcode 调试通道稳定。它能自动操作 app 内部 UI，但不能代替人工确认系统级弹窗、灵动岛外观和锁屏展示。

## 1. 安装 iPhone App

1. 打开 `ios/CodeIslandCompanion/CodeIslandCompanion.xcodeproj`。
2. 顶部 scheme 选择 `CodeIslandCompanion`。
3. 顶部设备选择你的 iPhone。
4. 确认 `Signing & Capabilities` 中这几个 target 都使用你的 Developer Team：
   - `CodeIslandCompanion`
   - `CodeIslandCompanionWidget`
   - `CodeIslandWatchApp`
   - `CodeIslandWatchWidget`
5. 点击 Run。
6. iPhone 首次启动时允许：
   - 本地网络
   - 蓝牙
   - 通知

通过标准：

- iPhone 桌面出现 `Code Island`。
- app 可以打开，不弹出开发者证书未信任错误。
- app 首屏能看到发现 Mac 或等待连接状态。

失败排查：

- 证书未信任：iPhone 进入 `设置 -> 通用 -> VPN 与设备管理`，信任 `Apple Development: ...`。
- 安装失败：删除 iPhone 上旧版 `Code Island` 后重新 Run。
- 找不到设备：拔插 USB，解锁 iPhone，确认 Xcode `Window -> Devices and Simulators` 中 iPhone 是 connected。

## 2. Mac 端广播

1. 启动当前分支构建出的 CodeIsland Mac app。
2. 打开 CodeIsland 设置。
3. 进入 `Buddy`。
4. 打开 iPhone Buddy 广播。
5. 确认状态显示为等待或已连接。

通过标准：

- iPhone app 能发现这台 Mac。
- Mac 设置页中 iPhone Buddy 状态能从未连接变成连接中或已连接。

失败排查：

- iPhone 和 Mac 不在同一 Wi-Fi 时，Multipeer 发现可能失败。
- macOS 防火墙或网络权限异常时，先关闭再打开 iPhone Buddy 广播。
- iPhone 端本地网络权限被拒绝时，进入 iPhone `设置 -> Code Island -> 本地网络` 打开。

## 3. iPhone 前台同步

1. iPhone 打开 `Code Island`，选择发现到的 Mac。
2. Mac 上打开一个 Codex / Claude / Gemini 等会话。
3. 在会话里发送一句测试消息，例如：`真机同步测试`。
4. 观察 iPhone app 首页。

通过标准：

- iPhone 显示当前 agent 名称。
- 小人图标和 Mac 端对应角色一致。
- 状态能在空闲、处理中、等待回答、问题等状态之间变化。
- 最近动态出现用户消息和助手消息。
- 工具调用、工作区、问题卡片没有明显截断或英文裸露。

建议记录：

- agent 名称：
- 工作区：
- 当前状态：
- 最近动态是否出现：
- 是否有 UI 截断：

## 4. Live Activity / Dynamic Island / 锁屏

1. 保持 iPhone app 已连接 Mac。
2. 在 iPhone app 点击 `开启实时活动`。
3. 回到桌面，观察灵动岛紧凑态。
4. 长按灵动岛，观察展开态。
5. 锁屏，观察锁屏实时活动。
6. 横放充电进入 StandBy，观察 StandBy 展示。

通过标准：

- 灵动岛紧凑态至少显示角色图标和当前状态提示。
- 灵动岛展开态不被系统 UI 遮挡，问题、工作区、状态不互相覆盖。
- 锁屏通知/实时活动显示角色、状态、当前消息摘要。
- StandBy 没有上下大块异常空白，核心信息完整可读。
- 切换 Mac 端状态后，实时活动能跟随更新。

失败排查：

- 灵动岛没有出现：确认没有其他 app 的 Live Activity 长时间占用；也可以先停止再重新开启实时活动。
- 锁屏不显示：确认通知权限允许，并在 iPhone `设置 -> 面容 ID 与密码 -> 锁定时允许访问` 中允许实时活动。
- StandBy 不出现：确认 iPhone 横放、锁屏、充电，且系统已启用 StandBy。

## 5. iPhone 后台接收测试

这是最关键的真机验收项，用来验证轻量后台方案是否有效。

1. iPhone app 前台连接 Mac。
2. 点击 `开启实时活动`。
3. 回到 iPhone 桌面，不要从多任务界面划掉 app。
4. 锁屏等待 1 分钟。
5. 在 Mac 上向当前会话发送一条新消息。
6. 观察锁屏/灵动岛是否更新。
7. 继续等待到 5 分钟，再发送第二条消息。
8. 继续等待到 10 分钟，再发送第三条消息。

通过标准：

- 1 分钟后台后，灵动岛或锁屏能收到新状态。
- 5 分钟后台后，至少能通过蓝牙摘要刷新角色、状态或消息摘要。
- 10 分钟后台后，如果系统没有唤醒 iPhone app，实时活动仍保持最后一次有效状态，不应显示错误或崩溃。
- 重新打开 iPhone app 后，完整状态能恢复为 Mac 当前状态。

建议记录：

| 时间点 | 操作 | iPhone 是否更新 | Watch 是否更新 | 备注 |
| --- | --- | --- | --- | --- |
| 前台 | Mac 发消息 |  |  |  |
| 后台 1 分钟 | Mac 发消息 |  |  |  |
| 后台 5 分钟 | Mac 发消息 |  |  |  |
| 后台 10 分钟 | Mac 发消息 |  |  |  |
| 重新打开 app | 回前台 |  |  |  |

重要边界：

- 不测试用户从多任务界面强杀 app 的情况。iOS 不保证强杀后还能后台接收。
- 不依赖 APNs，也不需要后端，所以后台表现会受 iOS 蓝牙和 Live Activity 调度策略影响。

## 6. Apple Watch 安装与同步

### 方式 A：随 iPhone app 安装

1. iPhone 已安装 `Code Island`。
2. 打开 iPhone 自带 `Watch` app。
3. 在 `我的手表 -> 可用 App` 中找到 `Code Island`。
4. 点击安装。
5. 在 Apple Watch 上打开 `Code Island`。

### 方式 B：Xcode 直接调试

1. Xcode 顶部 scheme 选择 `CodeIslandWatchApp`。
2. 顶部设备选择你的 Apple Watch。
3. 点击 Run。

通过标准：

- Watch app 能启动。
- iPhone 已连接 Mac 时，Watch 能显示同一个 agent 状态。
- Watch 页面左右/上下切换时，每屏只聚焦一个重点信息。
- 小人图标大小合适，和 Mac/iPhone 角色一致。
- 最近动态、问题、操作页都能进入。

失败排查：

- Watch 一直等待 iPhone：先打开 iPhone app，确认它已连接 Mac；再重新打开 Watch app。
- Watch 安装失败：重启 Watch 和 iPhone，确认 Watch 已解锁并信任 Mac。
- Xcode 看不到 Watch：打开 `Window -> Devices and Simulators`，确认 iPhone 和 Watch 都 connected。

## 7. Watch 后台与通知

1. iPhone app 前台连接 Mac，并开启实时活动。
2. Watch 打开 `Code Island`，确认已同步。
3. 按数码表冠回表盘。
4. 在 Mac 上触发新状态：
   - 普通消息
   - 等待用户回答
   - 处理中
   - 中断或错误
5. 观察 Watch 是否收到状态变化或通知。

通过标准：

- Watch app 重新打开时能看到最新 iPhone 状态。
- 等待回答/需要注意的状态应有明显提示。
- 页面切换或关键状态变化有合适的触感反馈。
- watchOS widget / Smart Stack 能显示最近一次状态摘要。

备注：

- WatchConnectivity 不是实时 socket。Watch 在后台时，系统可能延迟投递；重新打开 Watch app 时应立即追上最新状态。
- 需要强实时提醒的状态，后续应优先用通知或 complication/widget timeline 表达，而不是假设 Watch app 常驻后台。

## 8. 断连与恢复

### iPhone 断开 Mac

1. iPhone 已连接 Mac。
2. 在 Mac CodeIsland 设置里关闭 iPhone Buddy 广播。
3. 等 10 秒。
4. 重新打开广播。

通过标准：

- iPhone 不崩溃。
- UI 能显示离线/等待或保持最后有效状态。
- 广播恢复后可以重新连接。

### 网络变化

1. iPhone app 已连接。
2. 关闭 iPhone Wi-Fi，等待 10 秒。
3. 重新打开 Wi-Fi。
4. 必要时点 iPhone app 内重新连接。

通过标准：

- app 不崩溃。
- 重新连接后状态恢复。
- Live Activity 不出现明显错误文案。

### 蓝牙变化

1. iPhone app 已连接并开启实时活动。
2. 关闭 iPhone 蓝牙 10 秒。
3. 重新打开蓝牙。
4. 后台发送新消息验证恢复。

通过标准：

- 蓝牙关闭时不会崩溃。
- 蓝牙恢复后，后台摘要通道可以继续刷新。

## 9. 提问与操作链路

1. 在 Mac 端触发一个 `askUserQuestion` 或等待回答状态。
2. iPhone app 应展示问题卡片和选项。
3. 在 iPhone 选择一个选项。
4. 回到 Mac 会话，确认选择被送回。
5. Watch 打开同一状态，确认问题页能展示问题。

通过标准：

- iPhone 问题文案为中文，不出现 `AskUserQuestion` 裸露在主标题里。
- 选项可读、可滑动、不被截断。
- 选择后 Mac 端收到正确答案。
- Watch 能显示问题概要；复杂回答可以引导到 iPhone。

## 10. 最终发布前截图

建议每次发布前保存这些截图：

- iPhone 发现 Mac
- iPhone 空闲
- iPhone 处理中
- iPhone 等待回答
- iPhone 最近动态
- Dynamic Island 紧凑态
- Dynamic Island 展开态
- 锁屏实时活动
- StandBy
- Watch 状态页
- Watch 消息页
- Watch 操作页
- Watch 最近动态页
- Watch widget / Smart Stack

截图保存到：

```text
apple-companion/images/
```

## 11. 验收结论模板

```text
测试日期：
Mac 版本：
iPhone 型号 / iOS：
Apple Watch 型号 / watchOS：
Xcode 版本：

Mac -> iPhone 前台同步：通过 / 不通过
iPhone Live Activity：通过 / 不通过
iPhone 后台 1 分钟：通过 / 不通过
iPhone 后台 5 分钟：通过 / 不通过
iPhone 后台 10 分钟：通过 / 不通过
iPhone -> Watch 同步：通过 / 不通过
Watch 通知 / 触感：通过 / 不通过
断线重连：通过 / 不通过
提问回答链路：通过 / 不通过

遗留问题：
1.
2.
3.
```
