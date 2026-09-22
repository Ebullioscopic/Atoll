<p align="center"><img src=".github/assets/toolisle-logo.svg" width="96" alt="ToolIsle Logo"></p>

# ToolIsle · 团队工具箱

独立 macOS 团队工具箱，使用项目维护者提供的渐变螺旋星光 Logo。保留 Atoll 的来源与版权，但不是 Atoll 官方发行版。

## 新入口与上游代码

当前应用由根目录 `Package.swift` 构建：`ToolIsle/App` 是桌面界面，`ToolIsle/Core` 是可测试数据层。
原有 `DynamicIsland/` 与 `DynamicIsland.xcodeproj` 保留供参考和后续迁移，**不参与 ToolIsle 的构建与运行**。请勿使用旧 Xcode 工程发布新应用。

此前暂存的基础压缩载荷损坏，因此这轮重新建立了可核验的独立 target，而非把那个载荷标为已合并。新 target 不链接旧后台服务、Sparkle、XPC/RPC、AI 助手、媒体捕获或锁屏组件。

## 功能

- 菜单栏和可关闭的轻量灵动岛入口；搜索、分类、收藏和独立工具窗口。
- JSON 校验/格式化/压缩；秒/毫秒时间戳与 ISO 8601 日期转换；UTF-8 Base64 编解码。
- Gitee 个人访问令牌连接；Watch/Star 仓库分页；按仓库查看 Issues、状态/标题/标签筛选、未读更新、正文与分页评论。
- 仓库 README、目录浏览、分支/Tag/Commit 与指定文件读取；分支菜单显示前 100 个，也可直接输入任意完整 ref。
- 原生 Markdown 阅读：标题、表格、代码块、任务列表、引用、链接与图片；源码切换与复制。
- 打开本地 UTF-8 `.md`/`.markdown`/`.mdown`/`.txt` 文件。默认只读取文件所在目录内的相对资源；父目录图片需通过“授权图片/链接根目录”选择授权根目录。
- 手动刷新、完整分页入口、明确的限流/权限/网络错误。筛选仅作用于已加载内容，数量不是服务器总数。
- 会话内缓存与可选磁盘缓存；离线展示带时间标识。首次连接必须联网验证；已连接且启用磁盘缓存的账户可在断网启动时读取已有缓存。

## macOS 构建

macOS 14+，支持 Swift 6.0+ 的 Xcode 工具链。打开根目录 `Package.swift` 可编辑运行；生成可安装应用：

```bash
swift test
bash scripts/build-toolisle.sh release
open dist/ToolIsle.app
```

Debug 使用 `bash scripts/build-toolisle.sh debug`。正式 Bundle ID 为 `io.github.lideming0815.toolisle`，Debug 为其 `.dev` 后缀。
脚本生成 `ToolIsle.app` 与按实际架构命名的 ZIP，并执行 ad-hoc 签名校验；**不代表 Developer ID 签名或 Apple 公证**。团队正式分发需自行配置 Developer ID 和公证，不建议全局关闭 Gatekeeper。

图标已提交；重新生成需 Python、CairoSVG 2.7.1、Pillow 11.3.0，以及 Cairo 库，然后运行 `python3 scripts/prepare-toolisle.py`。

## Gitee 连接

在 Gitee 的个人设置中创建个人访问令牌，按读取需求授予资料、仓库、Issues、评论相关权限，在应用中粘贴并验证。只发送 GET 请求。未实现网页密码登录或 OAuth 应用注册；不收集、不保存 Gitee 密码。
令牌只保存在当前应用命名空间的 macOS Keychain；不会进入 URL、源代码、日志、Markdown 或 CI。HTTP 重定向被拒绝，避免转发授权头。
仓库文件中的相对图片通过同仓库、同 ref 的 Contents API 读取；外部 HTTPS 图片默认禁用，开启后使用无令牌、无 Cookie 的独立请求。Markdown 不执行 HTML/JavaScript。

磁盘缓存默认关闭。开启后按账户分隔、最多 7 天 / 100 项 / 10 MB，文件权限为当前系统用户可读写。**缓存未加密**；设备丢失风险应结合 FileVault 管理。退出账户会清理凭据与缓存，清理失败会明确显示错误。401/403/404 不会用离线缓存掩盖权限变化。

## 扩展工具

在 `ToolIsle/App/ToolIsleApp.swift` 的 `ToolRegistry.tools` 增加一个 `ToolDescriptor`，实现独立 SwiftUI View；纯逻辑放到 Core 并补充 XCTest。工具由窗口路由统一管理，默认不在启动时执行、不自动读取剪贴板。
当前仅支持编译期内置模块，不对外开放不受信任的动态插件。保留的旧 Atoll 扩展代码不在新进程中启动。

## 已知边界与验收

当前按仓库浏览，不是跨仓库全量聚合；不含写操作、推送通知、自动轮询、Mermaid、数学公式、完整 HTML、富文本编辑、多账户同时在线或私有化 Gitee 服务器。
自动化测试使用模拟 API 响应，不使用任何私人账号凭据。真实私有仓库权限、实际图片/附件差异、Keychain 与窗口交互仍需在团队 Mac 上验收。CI 编译通过不等于这些人工场景已经测试。

## 许可与来源

保留根目录 `LICENSE`、`NOTICE`、`COPYRIGHT_ASSETS`、`TRADEMARKS` 和原始代码版权；新增代码采用 GPL-3.0-or-later。上游 README 保存在 `Docs/Upstream-Atoll-ReadMe.md`。
MarkdownUI 2.4.1 为 MIT 组件，已进入维护模式；此版本用于稳定的原生阅读，渲染组件可独立替换。打包脚本从锁定依赖中收集完整许可证，应用“关于与许可证”可阅读。
原作者商标/赞助入口不作为 ToolIsle 的品牌入口。Logo 来源于维护者提供的 SVG；对外分发前由维护者确认素材权利与全部依赖许可。
