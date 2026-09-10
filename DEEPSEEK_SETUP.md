# Atoll 聊天与 DeepSeek

本源码基于 dev 分支 e46a160，保留已有本地修改。2026-09-10 已完成原生聊天界面及请求链路升级。运行和验证命令见下文；可选 pi 服务源码位于仓库内的 `deepseek-bridge/`。

## 入口和操作

从菜单栏 Atoll → 打开聊天助手，或原有截图/聊天入口进入。

- 对话、图片和输入框在同一窗口；边缘可拖动调整尺寸，右上角双向箭头放大/还原窗口。
- 右上角文字按钮支持 80%–160% 缩放，点百分比重置；快捷键为 ⌘+/⌘−/⌘0。
- Esc 关闭窗口，保留本次运行的聊天和草稿；切换到其他应用时自动隐藏。
- Return 发送，Shift/Option+Return 换行。输入法组合文字时 Return/Esc 优先交给输入法。
- 回复中可停止，失败后可重试；“新对话”会清空本地消息并重置 pi 会话。
- PNG/JPEG/GIF/WebP 图片最多 8 张，每张最多 16 MB；支持选择、拖放和粘贴，点击缩略图查看原图。DeepSeek/Local Model 入口仅接受图片附件。
- 标题、列表、引用、代码块和表格原生排版；代码及整条消息可复制。可关闭“跟随最新回复”阅读前文。

## DeepSeek 官方接口

在模型选择页选择 DeepSeek，填写自己的 Key。

- Endpoint：`https://api.deepseek.com`
- 文本模型：如 `deepseek-v4-flash` 或 `deepseek-v4-pro`。
- 图片模型：独立可配置，默认 `deepseek-v4-flash-vision-exp`。

只有官方域名自动切换配置的图片模型；自定义 OpenAI 兼容接口始终使用所填模型。会发送完整的用户可见历史与图片，支持流式回复及接口返回的 reasoning 字段。官方模式可控制下一轮是否启用思考。

Key 沿用项目现有 Defaults 存储方式。模型名称及接口能力依据 [DeepSeek 文档](https://api-docs.deepseek.com/)；可用性由账户和服务端决定。

## 本机 pi 桥接与 Ollama

选择 **Local Model**：

- 本机已配置的 pi 桥接：`http://127.0.0.1:11435`。
- 直接 Ollama：如 `http://127.0.0.1:11434`，模型名填写本机已安装模型。

程序通过本机 `/health` 区分 pi 与直接 Ollama。pi 必须为协议 v2；健康检查会显示实际模型，工具/思考选项影响下一轮。桥接使用独立会话及请求 ID；停止和重置须收到后端确认后才继续发送。完整图片历史恢复无需额外模型调用。

已有 pi 服务可保留配置和密钥升级至 v2；安装说明见 [bridge README](deepseek-bridge/README.md)，升级、回滚及备份说明见 [UPGRADE.md](deepseek-bridge/UPGRADE.md)。仓库不含 API Key，也不安装 Ollama 模型。

## 构建和测试

在本仓库执行：

```sh
./scripts/build-local.command
./scripts/test-chat.command
```

使用 macOS 15.5、Xcode 16.4（16F6）及 arm64。脚本选择 `/Applications/Xcode.app`，无需修改全局 xcode-select。Debug 构建产物为 `../build/DerivedData/Build/Products/Debug/Atoll.app`。

测试覆盖请求构造、图片生命周期、Markdown/部分流、传输/取消、缩放边界、pi 会话及升级回滚。原生界面验收使用隔离的 QA 应用配置和本地模拟服务，不消耗真实模型额度。真实付费 DeepSeek 回复没有作为本次验收的一部分。

## 本地 Release 安装包

```sh
./scripts/build-release-local.command
python3 scripts/package-release-local.py
```

第二步将生成上一级目录的 `dist/Atoll.app` 和 `dist/Atoll-2.3.3-local-arm64.dmg`。将应用复制到“应用程序”即可安装。这是 Apple Silicon 本机签名版，未做 Developer ID 签名和 Apple 公证；打包时默认关闭上游自动更新。脚本拒绝覆盖已有 `dist/Atoll.app`，再次打包前请先保留或移走旧产物。
