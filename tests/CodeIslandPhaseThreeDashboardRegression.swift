import CodeIslandCore
import CodeIslandUI

@main
struct CodeIslandPhaseThreeDashboardRegression {
    static func main() {
        let setup = CodeIslandDashboardState.setupRequired(provider: .codex)
        guard setup.provider == .codex, setup.requiresActivation else {
            fatalError("The pre-activation dashboard must stay in setup mode for Codex")
        }

        let idle = CodeIslandDashboardState.idle(provider: .codex)
        guard idle.provider == .codex, !idle.requiresActivation else {
            fatalError("An activated provider with no sessions must render the idle state")
        }
    }
}
