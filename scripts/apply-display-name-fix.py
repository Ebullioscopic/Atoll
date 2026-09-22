"""One-time, checked migration. The build commits results and removes this script."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
files = {}
def change(path, old, new, count=1):
    text = files.get(path, (root/path).read_text())
    assert text.count(old) == count, (path, text.count(old), count, old[:100])
    files[path] = text.replace(old, new)

p = 'DynamicIsland/DynamicIslandViewCoordinator.swift'
change(p, '@AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {', '''// Empty means automatic. Do not persist whichever display had keyboard focus
    // at launch; resolve the active built-in display again after every hot-plug.
    @AppStorage("preferred_screen_name") var preferredScreen = "" {''')
change(p, '            selectedScreen = preferredScreen', '''            selectedScreen = NotchDisplaySelection.screen(
                preferredName: preferredScreen,
                allowsFallback: Defaults[.automaticallySwitchDisplay]
            )?.localizedName ?? "Unknown"''')
change(p, '@Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"', '@Published var selectedScreen: String = NotchDisplaySelection.screen()?.localizedName ?? "Unknown"')
change(p, '        selectedScreen = preferredScreen', '''        selectedScreen = NotchDisplaySelection.screen(
            preferredName: preferredScreen,
            allowsFallback: Defaults[.automaticallySwitchDisplay]
        )?.localizedName ?? "Unknown"''')

p = 'DynamicIsland/DynamicIslandApp.swift'
change(p, 'MenuBarExtra("dynamic.island",', 'MenuBarExtra("ToolIsle",')
change(p, 'Button("Restart Atoll")', 'Button("Restart ToolIsle")')
change(p, '''                guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

                let workspace = NSWorkspace.shared

                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
                {

                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true

                    workspace.openApplication(at: appURL, configuration: configuration)
                }
''', '''                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(
                    at: Bundle.main.bundleURL, configuration: configuration)
''')
change(p, '''            guard let self = self, let window = self.window else { return }
            DispatchQueue.main.async {
                window.alphaValue =
                    self.coordinator.selectedScreen == self.coordinator.preferredScreen ? 1 : 0
            }''', '''            DispatchQueue.main.async { [weak self] in
                self?.adjustWindowPosition(changeAlpha: true)
            }''')
change(p, '''            if !Defaults[.showOnAllDisplays] {
                let viewModel = self.vm
                let window = self.createDynamicIslandWindow(
                    for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
            }''', '''            self.adjustWindowPosition(changeAlpha: !Defaults[.showOnAllDisplays])''')
change(p, '''        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createDynamicIslandWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }''', '''        // Resolve the target before constructing the window to avoid a flash on
        // the focused external display. The multi-display path remains unchanged.
        adjustWindowPosition(changeAlpha: true)''')
change(p, '''            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screens.first(where: {
                $0.localizedName == coordinator.preferredScreen
            }) {
                coordinator.selectedScreen = coordinator.preferredScreen
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main {
                coordinator.selectedScreen = mainScreen.localizedName
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }
''', '''            guard let selectedScreen = NotchDisplaySelection.screen(
                preferredName: coordinator.preferredScreen,
                allowsFallback: Defaults[.automaticallySwitchDisplay]
            ) else {
                window?.alphaValue = 0
                return
            }
            coordinator.selectedScreen = selectedScreen.localizedName
''')

p = 'DynamicIsland/components/Settings/SettingsView.swift'
change(p, '''                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \\.self) { screen in''', '''                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    Text("Automatic (built-in display first)").tag("")
                    ForEach(screens, id: \\.self) { screen in''')
change(p, '                        Text(Defaults[.releaseName])', '                        Text(verbatim: "ToolIsle · \\(Defaults[.releaseName])")')
change('DynamicIsland/components/Settings/SettingsWindowController.swift', 'window.title = "Atoll Settings"', 'window.title = "ToolIsle Settings"')
change('DynamicIsland/components/Onboarding/WelcomeView.swift', 'Text("Atoll")', 'Text(verbatim: "ToolIsle")')
p = 'DynamicIsland/components/Onboarding/OnboardingView.swift'
change(p, '"Atoll includes a mirror feature', '"ToolIsle includes a mirror feature')
change(p, '"Atoll can show all your upcoming events', '"ToolIsle can show all your upcoming events')

p = 'DynamicIsland.xcodeproj/project.pbxproj'
s = (root/p).read_text()
assert s.count('PRODUCT_NAME = Atoll;') == 2
s = s.replace('Atoll.app', 'ToolIsle.app').replace('/Contents/MacOS/Atoll', '/Contents/MacOS/ToolIsle')
s = s.replace('PRODUCT_NAME = Atoll;', 'PRODUCT_NAME = ToolIsle;\n\t\t\t\tPRODUCT_MODULE_NAME = Atoll;')
s = s.replace('INFOPLIST_KEY_CFBundleDisplayName = Atoll;', 'INFOPLIST_KEY_CFBundleDisplayName = ToolIsle;')
s = s.replace('CURRENT_PROJECT_VERSION = 1637;', 'CURRENT_PROJECT_VERSION = 1638;')
s = s.replace('= "Atoll uses ', '= "ToolIsle uses ').replace('= "Atoll needs ', '= "ToolIsle needs ')
files[p] = s
change('DynamicIsland.xcodeproj/xcshareddata/xcschemes/DynamicIsland.xcscheme', 'BuildableName = "Atoll.app"', 'BuildableName = "ToolIsle.app"', 3)
p = 'DynamicIsland/Info.plist'
s = (root/p).read_text()
files[p] = s.replace('<string>Atoll uses ', '<string>ToolIsle uses ').replace('<string>Atoll needs ', '<string>ToolIsle needs ')
change('tests/test_privacy_configuration.py', 'Atoll uses AppleScripts', 'ToolIsle uses AppleScripts')

for path, content in files.items():
    (root/path).write_text(content)
    print('Updated:', path)
(root/'TOOLISLE-DISPLAY-FIX.md').write_text('''# ToolIsle 显示器与名称修复（2026-09-22）

基于回滚提交 `39ed49bb5924c3814ac70f0206501b460b73232d`，保留 Atoll 原 Xcode 应用和已批准 Logo。

## 范围
- 新增独立且可测试的屏幕选择函数；只接入原启动、选屏设置和窗口定位路径。
- 自动模式优先当前可用的内置刘海屏，再选择内置屏；仅外接屏可用时回退至系统主屏。
- 不覆盖明确保存的手动选屏；关闭自动回退时，指定屏幕不可用则隐藏，原多屏模式保留。
- 应用产物、显示名、主菜单、欢迎页及设置标题改为 ToolIsle；构建号为 1638。
- 保留内部模块名 Atoll，避免改写原 @testable import；测试宿主和 Scheme 产物路径同步调整。
- 保留所有媒体、锁屏、计时器、剪贴板、Shelf、XPC/RPC、权限声明、上游依赖和生命周期。

## 验证包使用
先退出其他 Atoll/ToolIsle。设置 → General → System features，关闭 Show on all displays，
在 Show on a specific display 选择 Automatic (built-in display first)，或明确选择笔记本内置屏。
重新接入外接显示器、切换系统主屏、合盖后开盖，观察位置。手动外接屏和原多屏模式也需要实体 Mac 回归。

本次只改对外名称，不同时重构内部 Bundle ID、数据目录或扩展协议。
Release 仍使用 `com.Ebullioscopic.Atoll`，因此与官方 Atoll 共享该配置域；不要同时运行，先备份现有应用和重要配置。
上一包是 Debug（`.dev` 配置域），与官方 Release 使用不同的配置域。官方 v2.3.3 源码也以 NSScreen.main 作为默认屏幕，
但 NSScreen.main 表示当前键盘焦点所在的屏幕，不保证是内置屏。由于没有用户本机的偏好设置，不能断言这是两包差异的唯一原因。

更新器本轮未移除或改写；验证期间不要安装应用内更新，以免回到上游版本。
这是临时签名、未经 Apple 公证的 Apple Silicon 测试包，不是正式发行版。

## 测试边界
新增测试直接编译生产选择函数，覆盖 19 个显示器列表/偏好/回退场景。
构建工作流执行原隐私和计时器测试、Release 构建、LFS 资源及签名检查和不带 --uitesting 的启动检查。
请以下载包内实际测试日志为准；CI 无实体笔记本刘海和外接屏，不把模拟列表测试当作热插拔实测。

原版权、LICENSE、NOTICE、素材许可及历史署名保留。尚未进行全仓库品牌替换，也未重新实现工具箱。
''')
