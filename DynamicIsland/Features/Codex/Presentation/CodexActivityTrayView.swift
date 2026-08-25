import Defaults
import SwiftUI

private struct CodexActivityItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct CodexActivityTrayView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var controller = CodexFeatureController.shared
    @Default(.codexPinnedProjectNames) private var pinnedProjectNames
    @Default(.codexIgnoredSessionIDs) private var ignoredSessionIDs
    @Default(.codexShowContentPreviews) private var showContentPreviews
    @State private var showAllHistory = false
    @State private var collapsedBuckets: Set<CodexActivityBucket> =
        CodexActivityTrayExpansionPolicy.defaultCollapsedBuckets()
    @State private var collapsedProjects: Set<String> = []
    @State private var presentationVisibility = CodexActivityTrayPresentationVisibility()

    private let defaultHistoryLimit = 10
    private static let scrollCoordinateSpace = "codex-activity-tray-scroll"

    let onOpenURL: (() -> Void)?

    private var model: CodexActivityTrayModel {
        CodexActivityTrayBuilder().build(
            from: controller.snapshot,
            preferences: CodexActivityTrayPreferences(
                pinnedProjectNames: Set(pinnedProjectNames),
                ignoredSessionIDs: Set(ignoredSessionIDs),
                showContentPreviews: showContentPreviews
            )
        )
    }

    var body: some View {
        GeometryReader { viewportProxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if model.buckets.isEmpty && model.ignoredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.buckets) { bucketGroup in
                            bucketView(bucketGroup)
                        }

                        if !model.ignoredItems.isEmpty {
                            ignoredItemsView
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .coordinateSpace(name: Self.scrollCoordinateSpace)
            .onPreferenceChange(CodexActivityItemFramePreferenceKey.self) { itemFrames in
                presentationVisibility.updateLayout(
                    itemFrames: itemFrames,
                    viewportSize: viewportProxy.size
                )
                recordVisibleCompletions()
            }
        }
        .onAppear {
            presentationVisibility.beginPresentation(
                id: controller.beginActivityTrayPresentation(screenID: vm.screen)
            )
            resetPresentationState()
            recordVisibleCompletions()
        }
        .onDisappear {
            finishActivityTrayPresentation()
        }
        .accessibilityIdentifier("codex-activity-tray")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("活动托盘")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(summaryText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryText: String {
        if model.visibleItemCount == 0 {
            return model.ignoredItems.isEmpty ? "暂无待处理 Codex 任务" : "当前任务均已暂时忽略"
        }
        return "\(model.visibleItemCount) 个任务 · 按优先级排列"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("暂无 Codex 活动")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("新任务开始后，会按需要处理、异常、最新完成、进行中和历史完成分组显示。")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func bucketView(_ bucketGroup: CodexActivityTrayBucketGroup) -> some View {
        let isHistory = bucketGroup.bucket == .readHistory
        let displayedBucket = isHistory && !showAllHistory
            ? bucketGroup.limited(to: defaultHistoryLimit)
            : bucketGroup
        let isCollapsed = collapsedBuckets.contains(displayedBucket.bucket)

        return VStack(alignment: .leading, spacing: 9) {
            Button {
                toggleBucket(displayedBucket.bucket)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(width: 14, height: 18)
                    Image(systemName: displayedBucket.bucket.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(displayedBucket.bucket.swiftUIColor)
                    Text(displayedBucket.bucket.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("\(displayedBucket.itemCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(displayedBucket.bucket.swiftUIColor)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "展开此分组" : "折叠此分组")
            .accessibilityIdentifier("codex-activity-bucket-\(displayedBucket.bucket.rawValue)")
            .accessibilityHint(isCollapsed ? "点击标题展开分组" : "点击标题折叠分组")

            if !isCollapsed {
                ForEach(displayedBucket.groups) { projectGroup in
                    projectView(projectGroup, bucket: displayedBucket.bucket)
                }

                if isHistory && bucketGroup.itemCount > defaultHistoryLimit {
                    Button {
                        showAllHistory.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showAllHistory ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                            Text(showAllHistory ? "收起历史对话" : "查看更多历史对话（\(bucketGroup.itemCount - defaultHistoryLimit)）")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("codex-activity-history-more")
                }
            }
        }
    }

    private func toggleBucket(_ bucket: CodexActivityBucket) {
        if collapsedBuckets.contains(bucket) {
            collapsedBuckets.remove(bucket)
        } else {
            collapsedBuckets.insert(bucket)
        }
    }

    private func toggleProject(_ projectID: String) {
        if collapsedProjects.contains(projectID) {
            collapsedProjects.remove(projectID)
        } else {
            collapsedProjects.insert(projectID)
        }
    }

    private func resetPresentationState() {
        showAllHistory = false
        collapsedBuckets = CodexActivityTrayExpansionPolicy.defaultCollapsedBuckets()
        collapsedProjects.removeAll()
    }

    private func projectView(
        _ projectGroup: CodexActivityTrayProjectGroup,
        bucket: CodexActivityBucket
    ) -> some View {
        let isCollapsed = collapsedProjects.contains(projectGroup.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    toggleProject(projectGroup.id)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.66))
                            .frame(width: 18, height: 18)

                        Text(projectGroup.projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("\(projectGroup.items.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.52))

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "展开项目任务" : "折叠项目任务")

                Button {
                    controller.setProjectPinned(
                        projectGroup.projectName,
                        pinned: !projectGroup.isPinned
                    )
                } label: {
                    Image(systemName: projectGroup.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(projectGroup.isPinned ? .yellow : Color.white.opacity(0.48))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(projectGroup.isPinned ? "取消固定项目" : "固定项目")
            }
            .padding(.horizontal, 3)
            .accessibilityIdentifier("codex-activity-project-\(projectGroup.id)")

            if !isCollapsed {
                ForEach(projectGroup.items) { item in
                    itemView(item, bucket: bucket)
                }
            }
        }
    }

    private func itemView(_ item: CodexActivityTrayItem, bucket: CodexActivityBucket) -> some View {
        HStack(spacing: 8) {
            Button {
                if item.bucket == .unreadCompleted {
                    controller.acknowledgeCompletion(sessionID: item.sessionID)
                }
                controller.openCodexConversation(sessionID: item.sessionID)
                onOpenURL?()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.bucket == .readHistory ? Color.white.opacity(0.54) : .white)
                        .lineLimit(1)
                    Text(item.statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(bucket.swiftUIColor)
                    if !item.detailText.isEmpty {
                        Text(item.detailText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(item.bucket == .readHistory ? Color.white.opacity(0.42) : Color.white.opacity(0.68))
                            .lineLimit(2)
                    }
                    Text(item.nextAction)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(bucket.swiftUIColor.opacity(item.bucket == .readHistory ? 0.58 : 0.9))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("打开对应的 Codex 对话")
            .accessibilityIdentifier("codex-activity-item-\(item.id)")

            Menu {
                Button("暂时忽略此任务") {
                    controller.setSessionIgnored(item.sessionID, ignored: true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("任务选项")
        }
        .padding(11)
        .background(bucket.swiftUIColor.opacity(item.bucket == .readHistory ? 0.035 : 0.075))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(bucket.swiftUIColor.opacity(item.bucket == .readHistory ? 0.14 : 0.3), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(item.bucket == .readHistory ? 0.78 : 1)
        .background {
            if item.bucket == .unreadCompleted {
                GeometryReader { itemProxy in
                    Color.clear.preference(
                        key: CodexActivityItemFramePreferenceKey.self,
                        value: [
                            item.id: itemProxy.frame(in: .named(Self.scrollCoordinateSpace))
                        ]
                    )
                }
            }
        }
    }

    private func recordVisibleCompletions() {
        guard let exposure = presentationVisibility.activeExposure else { return }
        let unreadItems = model.buckets
            .first { $0.bucket == .unreadCompleted }?
            .items ?? []
        let visibleItems = unreadItems.filter { exposure.visibleItemIDs.contains($0.id) }
        controller.recordVisibleActivityTrayCompletions(
            visibleItems,
            screenID: vm.screen,
            presentationID: exposure.presentationID
        )
    }

    private func finishActivityTrayPresentation() {
        controller.finishActivityTrayPresentation(
            screenID: vm.screen,
            presentationID: presentationVisibility.finishPresentation()
        )
    }

    private var ignoredItemsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text("已忽略")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text("\(model.ignoredItems.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.48))
            }

            ForEach(model.ignoredItems.prefix(5)) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.64))
                            .lineLimit(1)
                        Text(item.projectName)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button("恢复") {
                        controller.setSessionIgnored(item.sessionID, ignored: false)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(11)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension CodexActivityBucket {
    var swiftUIColor: Color {
        switch self {
        case .needsAttention: return .orange
        case .blocked: return .red
        case .unreadCompleted: return .green
        case .running: return .blue
        case .readHistory: return Color.white.opacity(0.42)
        }
    }
}
