/// 面板当前展示的 "面"——同一时刻只能有一个
enum IslandSurface: Equatable {
    /// 收起状态，只显示 compact bar
    case collapsed
    /// 用户主动展开，显示 session 列表
    case sessionList
    /// 显示权限审批卡片
    case approvalCard(sessionId: String)
    /// 显示问答卡片
    case questionCard(sessionId: String)
    /// 自动展开显示完成通知
    case completionCard(sessionId: String)

    var isExpanded: Bool { self != .collapsed }

    /// 当前 surface 关联的 session ID（如有）
    var sessionId: String? {
        switch self {
        case .collapsed, .sessionList: return nil
        case .approvalCard(let id), .questionCard(let id), .completionCard(let id): return id
        }
    }
}
