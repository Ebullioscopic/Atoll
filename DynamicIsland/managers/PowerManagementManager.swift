/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Combine
import Foundation
import IOKit
import IOKit.pwr_mgt

/// 电源管理：屏幕常亮 + 合盖不休眠。
///
/// 两个功能机制完全不同，别混：
///
/// - **屏幕常亮** 走 `IOPMAssertionCreateWithName` + `PreventUserIdleDisplaySleep`。
///   标准的闲置断言，只挡「闲置导致的显示器休眠」，**挡不住合盖**。断言活在进程内，
///   进程退出即自动释放。
///
/// - **合盖不休眠** 走 `IOPMFindPowerManagement` 取 `IOPMrootDomain` 用户客户端连接，
///   再用 `IOConnectCallScalarMethod` 调**选择子 12**（设置 clamshell 睡眠状态），
///   传 `1` 禁用合盖睡眠、传 `0` 恢复默认。零权限、纯用户态、沙盒内也能用。
///
/// ## 走过的弯路（别再重来一遍）
///
/// 一开始以为能靠 `IORegisterForSystemPower` + `IOCancelPowerChange` 拦下来，
/// 三轮实测全部失败，日志（`Diagnostics.logURL`）给出的事实是：
///
/// 1. 合盖**只发** `kIOMessageSystemWillSleep`(0xE0000280)，
///    从不发文档中「可否决」的 `kIOMessageCanSystemSleep`(0xE0000270)；
/// 2. 对 `kIOMessageSystemWillSleep` 调 `IOCancelPowerChange` **无效** ——
///    调用照发，5 秒后系统照睡。Apple 文档在这点上是对的。
///
/// 正确解法是反汇编 State.app 得到的（它的 `IOPMFindPowerManagement` →
/// `IOConnectCallScalarMethod(conn, 12, [!enabled], 1, NULL, 0)` → `IOServiceClose`）。
///
/// ⚠️ **这个开关是内核全局状态，不随进程退出自动恢复**（跟 `pmset disablesleep` 同一性质，
/// 区别是重启会清）。所以 `applicationWillTerminate` 里必须调 `shutdown()` 复原，
/// 否则 Atoll 崩了会留下「合盖再也不睡」的系统。
final class PowerManagementManager: ObservableObject {
    static let shared = PowerManagementManager()

    /// `IOPMrootDomain` 用户客户端里「设置 clamshell 睡眠状态」的选择子。
    ///
    /// 数值 **12** 来自反汇编 State.app 的实际调用（`mov w1, #0xc`），不是照搬
    /// 网上流传的 `kPMSetClamshellSleepState = 11` —— 那个枚举跟本机实际对不上。
    /// 属未公开接口，将来系统版本可能变，故失败时不静默吞掉。
    private static let clamshellSleepStateSelector: UInt32 = 12

    /// 屏幕常亮是否生效。
    @Published private(set) var isKeepingScreenAwake = false

    /// 合盖不休眠是否生效。
    @Published private(set) var isPreventingLidSleep = false

    private var displayAssertionID = IOPMAssertionID(0)

    private init() {}

    // MARK: - 对外接口

    func toggleKeepScreenAwake() {
        setKeepScreenAwake(!isKeepingScreenAwake)
    }

    func togglePreventLidSleep() {
        setPreventLidSleep(!isPreventingLidSleep)
    }

    /// 退出前调用：释放断言并**恢复合盖睡眠**。后者尤其不能省。
    func shutdown() {
        setKeepScreenAwake(false)
        setPreventLidSleep(false)
    }

    /// 启动时无条件把 clamshell 睡眠复位成系统默认。
    ///
    /// 合盖不休眠改的是**内核全局状态**，不随进程退出自动恢复。正常退出走
    /// `shutdown()` 能复原，但崩溃或被强杀时 `applicationWillTerminate` 不会执行，
    /// 会给用户留下一台「合盖再也不睡」的机器。这个开关本来就不跨启动保持，
    /// 所以启动时直接复位，把上一次的残留一并清掉。
    func resetClamshellStateOnLaunch() {
        // 记实际结果，不能无条件报成功 —— 这条诊断日志存在的意义正是在无其它可见
        // 指示时捕获失败；内核调用失败却记「已恢复」会把这唯一的信号也抹掉。
        let succeeded = setClamshellSleepDisabled(false)
        Diagnostics.setActive(false)
        Diagnostics.log(succeeded
            ? "启动复位：clamshell 睡眠已恢复系统默认"
            : "启动复位失败：clamshell 睡眠状态复位调用未成功")
    }

    // MARK: - 屏幕常亮

    @discardableResult
    func setKeepScreenAwake(_ enabled: Bool) -> Bool {
        guard enabled != isKeepingScreenAwake else { return true }

        if enabled {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                // 断言名会出现在 `pmset -g assertions` 等系统诊断输出里，
                // 那里对非 ASCII 处理不可靠（破折号会显示成乱码），故只用 ASCII。
                "Atoll: keep screen awake" as CFString,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                Diagnostics.log("屏幕常亮断言创建失败: \(result)")
                return false
            }

            displayAssertionID = assertionID
            isKeepingScreenAwake = true
            Diagnostics.log("屏幕常亮已开启")
            return true
        } else {
            // 释放可能失败（ID 失效等），据实返回；调用方（如隐藏图标的 onChange）才能知道
            // 系统断言是否真的撤下，而不是只看被无条件置 false 的 isKeepingScreenAwake。
            var released = true
            if displayAssertionID != IOPMAssertionID(0) {
                let result = IOPMAssertionRelease(displayAssertionID)
                released = (result == kIOReturnSuccess)
                if !released { Diagnostics.log("屏幕常亮断言释放失败: \(result)") }
                displayAssertionID = IOPMAssertionID(0)
            }
            isKeepingScreenAwake = false
            Diagnostics.log("屏幕常亮已关闭")
            return released
        }
    }

    // MARK: - 合盖不休眠

    @discardableResult
    func setPreventLidSleep(_ enabled: Bool) -> Bool {
        guard enabled != isPreventingLidSleep else { return true }

        guard setClamshellSleepDisabled(enabled) else {
            Diagnostics.log("设置 clamshell 睡眠状态失败，合盖不休眠未生效")
            return false
        }

        isPreventingLidSleep = enabled
        Diagnostics.setActive(enabled)
        Diagnostics.log("合盖不休眠已\(enabled ? "开启" : "关闭")")
        return true
    }

    /// 直接设置内核里的 clamshell 睡眠开关。
    ///
    /// - Parameter disabled: `true` = **禁用**合盖睡眠（合盖不休眠生效），
    ///   `false` = 恢复系统默认（合盖照常睡）。
    ///
    /// 方向别搞反 —— 传反了表现为「开了等于没开」，很难察觉。这个语义由两条独立
    /// 推理交叉确认：① State 的 `-[… setClamshellCausingSleep:]` 把实参异或 1 后
    /// 才传给内核（`eor w8, w20, #0x1`），即 `causingSleep=NO` → `input=1`；
    /// ② 该选择子在内核侧对应 `setClamShellSleepDisable(bool)`，是「禁用」语义。
    @discardableResult
    private func setClamshellSleepDisabled(_ disabled: Bool) -> Bool {
        let connection = IOPMFindPowerManagement(0)
        guard connection != 0 else {
            Diagnostics.log("IOPMFindPowerManagement 返回 0")
            return false
        }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        let result = IOConnectCallScalarMethod(
            connection,
            Self.clamshellSleepStateSelector,
            &input,
            1,
            nil,
            nil
        )

        Diagnostics.log(
            "IOConnectCallScalarMethod(selector=\(Self.clamshellSleepStateSelector), "
            + "input=\(input)) -> 0x\(String(result, radix: 16))"
        )
        return result == kIOReturnSuccess
    }

}

// MARK: - 诊断

extension PowerManagementManager {
    /// 合盖不休眠不产生任何 IOPM 断言，`pmset -g assertions` 看不到它；
    /// 合盖期间又看不到屏幕，NSLog 在 `open` 启动的 GUI 进程里也抓不到。
    /// 所以单独落一份日志，出问题时才有抓手。
    enum Diagnostics {
        static let logURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Atoll-power.log")

        private static let activeKey = "atollDiagLidPreventionActive"

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return f
        }()

        static func setActive(_ active: Bool) {
            UserDefaults.standard.set(active, forKey: activeKey)
        }

        static func log(_ message: String) {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let fm = FileManager.default
            if !fm.fileExists(atPath: logURL.path) {
                try? fm.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                fm.createFile(atPath: logURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
