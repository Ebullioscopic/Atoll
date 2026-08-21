import Defaults
import SwiftUI

struct CodexSettingsView: View {
    @ObservedObject private var controller = CodexFeatureController.shared
    @Default(.enableCodexIntegration) private var enabled
    @Default(.codexShowClosedStatus) private var showClosedStatus
    @Default(.codexShowTaskTab) private var showTaskTab
    @Default(.codexCompletionNotifications) private var completionNotifications
    @Default(.codexShowContentPreviews) private var showContentPreviews
    @Default(.codexShowInFullscreen) private var showInFullscreen

    var body: some View {
        Form {
            integrationSection

            if enabled {
                displaySection
                privacySection
                diagnosticsSection
            }
        }
        .navigationTitle("Codex")
        .onChange(of: enabled) { _, value in
            controller.setEnabled(value)
        }
    }

    private var integrationSection: some View {
        Section {
            Toggle("启用 Codex 状态集成", isOn: $enabled)
                .settingsHighlight(id: "codex-Enable Codex integration")

            LabeledContent("运行状态", value: controller.isRunning ? "运行中" : "已停止")
            LabeledContent("Helper", value: controller.helperInstallation?.helperVersion ?? "未安装")
            LabeledContent("Codex Hooks", value: controller.hooksInstalled ? "已安装" : "未安装")

            HStack {
                Button("安装或修复") {
                    controller.installOrRepair()
                }
                Button("卸载 Hooks", role: .destructive) {
                    controller.uninstallHooks()
                }
            }

            if let message = controller.lastOperationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Codex 集成")
        } footer: {
            Text("Atoll 使用包内 CodexHookHelper 接收本地 Codex Hooks，不启动网络服务，也不需要第三方扩展授权。")
        }
    }

    private var displaySection: some View {
        Section("显示") {
            Toggle("在刘海关闭态显示任务摘要", isOn: $showClosedStatus)
                .settingsHighlight(id: "codex-Show closed status")
            Toggle("在展开页显示 Codex 任务", isOn: $showTaskTab)
                .settingsHighlight(id: "codex-Show task tab")
            Toggle("任务完成时显示提示", isOn: $completionNotifications)
                .settingsHighlight(id: "codex-Completion notifications")
            Toggle("在全屏应用中继续显示 Codex 状态", isOn: $showInFullscreen)
                .settingsHighlight(id: "codex-Show in fullscreen")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("显示任务内容摘要", isOn: $showContentPreviews)
                .settingsHighlight(id: "codex-Show content previews")
        } header: {
            Text("隐私")
        } footer: {
            Text(showContentPreviews ? "任务内容会经过本地清洗后显示。" : "关闭后只显示项目名和任务状态。")
        }
    }

    private var diagnosticsSection: some View {
        Section("诊断") {
            LabeledContent("运行任务", value: "\(controller.diagnostics?.runningCount ?? 0)")
            LabeledContent("等待批准", value: "\(controller.diagnostics?.waitingCount ?? 0)")
            LabeledContent("最近完成", value: "\(controller.diagnostics?.recentCompletionCount ?? 0)")
            LabeledContent("待处理事件", value: "\(controller.diagnostics?.inboxPendingCount ?? 0)")
            LabeledContent("失败事件", value: "\(controller.diagnostics?.failedEventCount ?? 0)")

            HStack {
                Button("刷新") { controller.refresh() }
                Button("打开数据目录") { controller.openDataDirectory() }
            }
        }
    }
}
