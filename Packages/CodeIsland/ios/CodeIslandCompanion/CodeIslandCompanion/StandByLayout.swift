import CoreGraphics

/// 单条会话行的高度估算：身份行 + 最多 3 行消息 + 工作指示行 + 内边距。
/// 用于按看板可用高度决定能完整容纳几条会话。
let standbySessionRowStride: CGFloat = 100

/// 看板标题区 + 顶部内边距的预留高度。
let standbySessionBoardHeaderHeight: CGFloat = 44

/// 单条会话消息固定最多显示的行数（iPad 上消息可展示 3 行）。
let standbyMaxMessageLines = 3

/// 看板布局：能完整显示几条会话，以及每条消息的行数上限。
struct StandBySessionBoardLayout: Equatable {
    let visibleCount: Int
    let messageLineLimit: Int
}

/// 依据看板可用高度与会话总数，决定显示几条会话；消息统一最多 3 行。
/// 放不下的会话由调用方显示「还有 N 个」（或分组模式滚动展示）。
func standbySessionBoardLayout(boardHeight: CGFloat, sessionCount: Int) -> StandBySessionBoardLayout {
    let usable = max(0, boardHeight - standbySessionBoardHeaderHeight)
    let maxRows = max(1, Int(usable / standbySessionRowStride))
    let visible = max(1, min(sessionCount, maxRows))
    return StandBySessionBoardLayout(visibleCount: visible, messageLineLimit: standbyMaxMessageLines)
}
