# Atoll + pi + DeepSeek

本项目将已安装 Atoll 的 Local Model 接口连接到独立的 pi coding-agent RPC 后端，由 pi 管理模型、思考、会话和工具循环。

## Native v2 API

原生客户端源码已在 macOS 15.5、Xcode 16.4、arm64 环境下成功构建，使用 v2 独立会话与异步任务接口；完整契约见 [PROTOCOL.md](PROTOCOL.md)。`/health` 宣告 protocol_version 2；`/atoll/chat` 启动任务，按 SID/JID 轮询 content、phase、tools、model，stop 取消单个任务，reset 清除并永久退役当前进程中的旧 SID，客户端随后使用新 SID。

原生客户端每次提交完整的用户可见历史，包括先前的文字和图片；图片通过消息的 `images` Base64 数组传递。停止、闲置清理或模型切换后，桥接服务将历史恢复到新 Pi 客户端，不重放模型调用。历史中存在图片时，后续纯文字追问仍使用视觉模型。原版 `/api/chat` 和下列旧版命令继续使用独立的旧版会话；旧版的共享会话、截图文件名与后台等待提示限制仅适用于原版客户端。

## 架构与安装

原生客户端：`Atoll → http://127.0.0.1:11435/atoll/chat（v2）→ pi RPC → DeepSeek 官方 API`

原版客户端：`Atoll → http://127.0.0.1:11435/api/chat（legacy）→ pi RPC → DeepSeek 官方 API`

需要 macOS、Python 3、已安装 pi（本机验证版本 0.84.1）。进入本目录后运行 `python3 install.py` 安装用户级服务并设置 Atoll 的 Local Model 地址。服务登录自动启动。运行「配置 DeepSeek.command」填写 API Key；直接回车可保留已有 Key。

pi 使用独立配置：旧版位于 `~/Library/Application Support/AtollDeepSeekBridge/pi-agent`，v2 按会话位于同级的 `pi-native/{sid}`。不加载日常 pi 的扩展、skills、项目说明或会话。Key 通过子进程环境提供，不写入 pi models.json，不传给工具子进程。API Key 配置文件权限为 600。

## 原版客户端的使用与命令

在原版 Atoll 直接发送文字。默认启用思考和只读工具，模型默认 `deepseek-v4-flash-vision-exp`。原版界面仍显示 Local Model/Llama 等标签，实际使用服务配置的 DeepSeek 模型。

- `/status`：查看后端、思考、工具和会话轮数。
- `/thinking on`、`/thinking off`：切换下一条任务的思考模式。
- `/tools on`、`/tools off`：切换下一条任务的工具。
- `/result`：取回耗时任务的结果。请求等待 35 秒后返回提示，后台继续工作；重复发送此命令即可等待结果。
- `/reset`：终止 pi 及其工具进程并清除会话。

思考/工具命令是当前服务会话设置，重启后恢复配置文件默认值。每项任务最多 5 分钟、12 次工具执行。超限或出错会停止 pi 进程并清除会话，避免残留工具记录影响后续调用。

## 工具和权限

- `web_search`：Bing 公共网页搜索，返回最多 5 条结果；搜索服务不可用时明确返回失败。
- `read_webpage`：读取公开文本网页，禁止访问本机、私有网络和非标准网页端口。连接到经过校验的 IP，重定向重新校验。
- `list_files`：列出指定本地目录。
- `read_file`：读取指定 UTF-8 文本文件（最大 256 KB，返回内容限长）。

本地文件和目录每次访问均弹出 macOS 确认框，显示解析后的完整路径；只有点击“允许本次”才读取，读取结果会发给 DeepSeek。拒绝或超时不会读取。服务自身配置目录始终排除。未启用 shell、修改、删除、发送消息等工具。

## 原版接口的会话与界面限制

Atoll 原版没有发送会话 ID，转接服务仅维护一个共享的 pi 会话；30 分钟闲置后在下一次发消息时重建，服务重启也会清除。会话不保存到磁盘。**在 Atoll 界面清空聊天不会通知服务，换话题或清空记忆请发送 `/reset`。** 多个本机客户端使用同一会话，请勿用它同时处理独立对话。

原版接口的图片支持（2026-09-10）：

- 已安装原版 Atoll：首次需打开 `Atoll Image Access.app`，在 macOS 文件夹选择框授权 `Documents/ScreenAssistantScreenshots`（只读，不授权整个磁盘）。内置截图发送后，桥接服务按请求中的准确文件名读取 `~/Documents/ScreenAssistantScreenshots/screenshot_数字.png` 并上传。只解析本轮列出的截图，不扫描其他文件。
- 普通图片：在聊天中发送 `/image /绝对路径/图片.png`，下一行写问题。路径可含空格；发送此命令即授权读取并发送该图片。支持 PNG/JPEG/GIF/WebP，每张最多 16 MB。
- 不支持的附件明确报错，不会只发送文件名让模型猜测。原版拖入普通图片时需改用 `/image`。
- 图片会留在当前 pi 内存会话中用于后续提问；`/reset` 清除。发送图片会使用视觉模型，修改模型配置可能重建会话。

原版 Atoll 不显示 pi 的流式工具面板或推理过程，只显示最终文字及后台等待提示；原生 v2 客户端可轮询任务文字、阶段、工具名称和模型，接口不返回推理正文。

## 检查和恢复

已有安装升级：先用 `python3 upgrade.py --check` 只读检查；确认需要升级后，用 `python3 upgrade.py` 仅升级桥接运行时代码。保留配置、Key、Atoll 设置及图片访问权限，并保存带时间戳的可回滚备份。完整命令及回滚说明见 [UPGRADE.md](UPGRADE.md)。

已验证 v2 运行时代码升级、健康检查、失败回滚及 launchd bootstrap 有界重试。升级成功会打印本机运行时代码备份路径，请自行保存；`--check` 可核验安装状态和协议版本。测试使用模拟服务，不代表真实账户的模型调用已经验证。

`curl http://127.0.0.1:11435/health` 查看健康状态，不输出 Key。

`python3 uninstall.py` 停止服务、移除登录启动，并恢复安装前 Atoll 的两项设置；配置文件保留。

测试：`python3 -m unittest -v`。单元测试使用模拟 Key，不消耗真实 API。真实连接和工具测试需本机已配置 Key。

官方参考：
- https://api-docs.deepseek.com/quick_start/agent_integrations/pi_mono/
- pi 安装目录的 docs/rpc.md 和 docs/extensions.md
