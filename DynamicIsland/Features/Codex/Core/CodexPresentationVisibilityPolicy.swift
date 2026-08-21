import Foundation

enum CodexPresentationVisibilityPolicy {
    static func canShow(
        isBuiltInCodex: Bool,
        codexEnabled: Bool,
        thirdPartyEnabled: Bool,
        hideOnClosed: Bool,
        showCodexInFullscreen: Bool
    ) -> Bool {
        if isBuiltInCodex {
            guard codexEnabled else { return false }
            return !hideOnClosed || showCodexInFullscreen
        }
        return thirdPartyEnabled && !hideOnClosed
    }
}
