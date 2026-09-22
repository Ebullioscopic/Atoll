# ToolIsle Gitee 阅读修复版

本版以 Gitee 阅读版提交 `48ed165374f43ba419cba6f6eee0e0e97caff049` 为基线，保留原 Atoll Target、显示器修复、Logo、媒体、锁屏、权限和扩展服务。版本 2.3.3，构建号 1640，包标记 gitee.2。

## 本次变化

- 设置侧栏的 Integrations / 集成分组新增独立 **Gitee** 页面，关闭功能或处于极简模式时也可访问。
- 通用设置中的 Gitee 区块已移除。账户、令牌、Watch / Star 项目选择、读取诊断及阅读选项集中在 Gitee 页面。
- 阅读窗口、刘海页面中的账户/项目入口直接打开这个设置页面，不再弹出另一份账户设置表单。
- 项目勾选立即保存到当前账户的本机查看列表，不修改平台 Watch / Star。
- 仓库路由优先采用 API 的 namespace.path 与 path，不把显示名称当成 REST 路径。
- 对旧 html_url/full_name 中克隆地址后缀 `.git` 进行兼容，例如 `https://gitee.com/example/project.git` 用于构造 `example/project` 的 Issues 请求。明确由 API path 字段指定的仓库名称不被无差别替换。
- 旧的已选项目在读取时会经过新解析规则，无须清空全部设置；项目列表刷新后按仓库 ID 更新元数据。
- 失败信息分项目显示 HTTP 状态，提供进入设置和仅重试失败项目；网络/DNS 失败与 401/403/404 区分。

## 使用

1. 先退出旧 ToolIsle 与官方 Atoll，备份原应用，再运行新包。
2. 打开 ToolIsle Settings，在左侧 Integrations / 集成中选择 Gitee。
3. 开启阅读功能。在该页连接或更换令牌，选择需要查看的项目。
4. 已选项目保留；可点击“刷新已选项目 Issues”验证。下方显示规范化后的仓库路径及具体失败状态。
5. 返回阅读窗口，验证正文、评论以及 A → B → 返回 A 的连续阅读。

令牌应只输入本机应用，不能写进 Git、截图或公开日志。曾在聊天中明文发送的令牌建议撤销并更换。本修复代码、CI 和报告不包含用户令牌。

## 验证边界

本地直接访问 Gitee 的尝试在 DNS 解析阶段失败，没有获得真实账户响应。没有将用户凭据传入公开 GitHub Actions。因此，模拟请求链、代码测试及 WebKit 测试不能被称为真实私有账户端到端验证，也不能证明用户令牌已失效或权限不足。

回归测试覆盖：历史项目数据的 .git 后缀、API namespace/path 的优先级、非法地址、旧路径 404 的模拟复现、规范路径列表/详情/评论请求、跨仓库链接与后退状态。macOS 全量构建、真实 WebKit 导航和普通启动结果以该次构建输出的报告为准。设置截图仅包含演示数据。

## 构建与分发

继续使用 `DynamicIsland.xcodeproj` / `DynamicIsland` scheme。构建脚本是 `scripts/build_gitee_settings_preview.sh`，应用包是 `ToolIsle.app`。

Apple Silicon / arm64，声明最低 macOS 14.6。临时签名、未经 Apple 公证。此次不改上游 Bundle ID、配置域或更新器：不要同时运行官方 Atoll 或旧包；验证期间不要接受上游应用内更新。不要为运行测试包全局关闭系统安全功能。

原 LICENSE、NOTICE、COPYRIGHT_ASSETS 及 Markdown 依赖许可证全部保留。工作分支和 PR 用于审查，不自动合并至 dev。
