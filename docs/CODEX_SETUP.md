# Codex 绑定与消息接收设置

本项目的 Codex 模块不是通过网络账号登录来绑定，也不是通过 Atoll 第三方扩展授权来绑定。它的绑定关系是：

```text
Codex Hooks
    ↓
~/.codex/hooks.json
    ↓
Atoll/CodexHookHelper
    ↓
本地 inbox 与 tasks.json
    ↓
Atoll 刘海、Codex 任务页、活动托盘
```

只有 **Codex Hooks 已安装到当前 Codex 配置**，Atoll 才能收到任务事件。只打开界面显示开关，并不会自动产生消息。

## 1. 首次绑定：必须完成的步骤

### 第一步：打开 Codex 设置

在 Atoll 中进入：

```text
Atoll 设置 → 实用工具 → Codex
```

你会看到“Codex 集成”区域，包括启用开关、运行状态、Helper 状态、Codex Hooks 状态，以及“安装或修复”按钮。

![Codex 设置中的 Helper 与 Hooks 状态](https://raw.githubusercontent.com/liusong881002-bit/Atoll-CodexAtoll/main/docs/assets/codex-settings-hooks.png)

### 第二步：打开“启用 Codex 状态集成”

打开顶部的：

```text
启用 Codex 状态集成
```

打开后，Atoll 才会启动本地 Codex 事件处理器，并开始定期读取事件队列。关闭这个开关时，即使 Hooks 文件仍然存在，Atoll 也不会继续消费和展示 Codex 状态。

### 第三步：点击“安装或修复”

这是绑定 Codex 的关键动作。点击后，Atoll 会完成两件事：

1. 将 App 包内的 `CodexHookHelper` 复制到稳定路径，并设置为可执行文件；
2. 将 Atoll 自己的 Hook 命令合并到 Codex 的 `hooks.json` 中。

默认路径如下：

```text
Helper:
~/Library/Application Support/Atoll/Codex/bin/CodexHookHelper

Helper 安装状态：
~/Library/Application Support/Atoll/Codex/helper-installation.json

Codex Hooks 配置：
~/.codex/hooks.json
```

Atoll 不会用自己的配置覆盖整个 `hooks.json`。它会保留已有的其他 Hook，只添加或更新自己的命令；写入前会创建带时间戳和 UUID 的备份。

### 第四步：确认两个状态

安装完成后，设置页至少应显示：

```text
运行状态：运行中
Helper：显示版本号，而不是“未安装”
Codex Hooks：已安装
```

重点注意：

- **Helper 已安装 ≠ Hooks 已安装**。Helper 只是接收器，Hooks 才是 Codex 把事件发送给 Atoll 的连接。
- 如果 `Codex Hooks` 仍显示“未安装”，请再次点击“安装或修复”，不要只重启 Atoll。
- 如果 Helper 显示“未安装”，说明当前运行的 Atoll App 包中没有可用的 `CodexHookHelper`，应确认运行的是包含 Codex 模块的版本。

## 2. 如何确认已经真正收到 Codex 消息

绑定完成后，不要只看设置页。请启动一个真实 Codex 会话并提交一条新的提示。正常情况下会经历以下状态：

### 进行中

提交提示后，Codex 会发送 `UserPromptSubmit`，Atoll 会：

- 在刘海关闭态显示类似 `1 · 进行中`；
- 显示蓝色 Codex 忙碌动效；
- 在展开任务页显示项目名、提示摘要和运行时长；
- 在活动托盘中把会话归入“进行中”；
- 新一轮对话会触发一次进行中入场提示。

### 等待批准

如果 Codex 需要用户授权工具或操作，会发送 `PermissionRequest`，Atoll 会：

- 将状态变为“等待批准”；
- 使用橙色提示；
- 在活动托盘中归入“需要处理”；
- 展示工具名或经过清洗的批准说明。

Atoll 不代替你点击批准或拒绝。点击任务卡片后，会打开对应的 Codex 会话，由 Codex 原生界面完成决定。

### 已完成

任务完成后，Codex 会发送 `Stop`，Atoll 会：

- 显示绿色完成提示；
- 显示项目名和完成摘要；
- 在关闭态显示未查看完成数量；
- 把记录放入“最新完成”或“历史完成”；
- 允许从任务页或活动托盘点击回到对应 Codex 对话。

如果这三种状态都没有出现，优先检查 Hooks 安装状态，而不是先调整动画或显示设置。

## 3. “能收到消息”和“显示在哪里”是两套开关

这是最容易配置错的地方。

### 接收链路开关

```text
启用 Codex 状态集成 = 开
Codex Hooks = 已安装
```

这两项决定 Atoll 是否能够从 Codex 收到事件并更新本地状态。

### 展示位置开关

设置页下方的“显示”区域控制收到事件后显示在哪里：

- **在刘海关闭态显示任务摘要**：控制关闭态的 `1 · 进行中`、`1 · 已完成` 等摘要；
- **在展开页显示 Codex 任务**：控制 Codex 任务标签和展开任务页；
- **任务完成时显示提示**：控制绿色完成提醒；
- **在全屏应用中继续显示 Codex 状态**：控制全屏应用中的 Codex 状态可见性。

例如：

| 配置 | 结果 |
| --- | --- |
| 集成开 + Hooks 已安装 + 关闭态开 | 可以在刘海看到摘要 |
| 集成开 + Hooks 已安装 + 展开页开 | 可以在 Codex 任务页看到会话 |
| 集成开 + Hooks 已安装 + 所有显示关闭 | Atoll 仍可能收到并保存状态，但界面不会显示 |
| 集成关闭 | 不处理、不展示新的 Codex 状态 |
| 只打开显示开关，没有安装 Hooks | 没有事件来源，通常不会出现任务 |

## 4. 内容摘要和隐私设置

“显示任务内容摘要”决定 Atoll 是否在界面显示提示、批准说明和完成结果。

- 打开：显示经过本地清洗和截断的提示摘要、工具名、批准说明或完成结果；
- 关闭：只显示项目名、状态、数量和时间，不显示任务正文内容。

关闭摘要不会断开 Hooks，也不会停止状态同步；它只改变展示层的内容。

## 5. 常见问题排查

### 设置页显示“未安装”

1. 确认当前打开的是包含 Codex 模块的 Atoll；
2. 确认“启用 Codex 状态集成”已打开；
3. 点击“安装或修复”；
4. 退出并重新打开设置页，确认 Helper 和 Codex Hooks 都显示已安装；
5. 再启动新的 Codex 会话，不要只等待旧会话状态自动刷新。

### 显示“运行中”，但一直收不到任务

重点检查：

- `~/.codex/hooks.json` 是否存在；
- 文件中是否出现 `Application Support/Atoll/Codex/bin/CodexHookHelper`；
- Codex Hooks 是否覆盖当前使用的事件；
- 是否只打开了“显示”开关，却没有完成“安装或修复”；
- 是否正在使用另一个 Codex 配置文件。

如果你通过环境变量指定了自定义 Hook 配置路径，Atoll 会使用该路径，而不是默认的 `~/.codex/hooks.json`：

```text
ATOLL_CODEX_HOOKS_CONFIG
```

### 任务页没有显示，但关闭态有数量

打开：

```text
在展开页显示 Codex 任务
```

关闭态摘要和展开任务页是独立展示通道；前者可见不代表后者一定开启。

### 收到事件但看不到提示内容

检查：

```text
隐私 → 显示任务内容摘要
```

关闭时这是设计行为，Atoll 只显示项目名、状态和时间。

### 旧的 CodexAtoll 数据没有出现

本项目会尝试把旧的 `~/Library/Application Support/CodexAtoll` 状态迁移到新的 Atoll 路径。迁移只处理本地状态，不会把旧的独立 App 重新启用为第二个菜单栏 App。迁移完成后，新的数据位置是：

```text
~/Library/Application Support/Atoll/Codex
```

### 不要手动删除或覆盖 hooks.json

不要为了“重新绑定”直接删除整个 `~/.codex/hooks.json`。里面可能还有其他项目或工具的 Hook。优先使用 Atoll 设置页的“安装或修复”；如果必须排查，先备份文件，再只检查 Atoll Helper 命令是否存在。

## 6. 最小验收清单

完成绑定后，按下面清单逐项确认：

- [ ] Atoll 设置 → 实用工具 → Codex 已打开；
- [ ] 运行状态显示“运行中”；
- [ ] Helper 显示版本号；
- [ ] Codex Hooks 显示“已安装”；
- [ ] `~/.codex/hooks.json` 中存在 Atoll Helper 命令；
- [ ] 新建或继续一个 Codex 会话并提交新的提示；
- [ ] 刘海出现“进行中”状态或蓝色动效；
- [ ] 任务完成后出现绿色完成提示；
- [ ] 展开页或活动托盘能看到对应会话；
- [ ] 点击任务卡片可以打开对应 Codex 对话。

只有前四项通过，才能说明“绑定”完成；后面的项目用于确认事件已经穿过 Hook、Helper、Atoll 状态仓库和 UI 展示链路。
