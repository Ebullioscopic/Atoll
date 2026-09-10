import Foundation

/// Passive cursor sampling reveals a fullscreen notch without capturing clicks
/// from the underlying application. Entry/exit dwell prevents edge flicker.
struct FullscreenHoverState {
    enum Action { case none, reveal, hide }
    private(set) var isRevealed = false
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?

    mutating func update(inActivationArea: Bool, inContentArea: Bool, allowed: Bool,
                         now: TimeInterval, hoverDelay: TimeInterval) -> Action {
        guard allowed else {
            let action: Action = isRevealed ? .hide : .none
            self = Self()
            return action
        }
        if isRevealed {
            if inActivationArea || inContentArea { exitedAt = nil; return .none }
            if exitedAt == nil { exitedAt = now }
            guard now - (exitedAt ?? now) >= 0.25 else { return .none }
            self = Self()
            return .hide
        }
        guard inActivationArea else { enteredAt = nil; return .none }
        if enteredAt == nil { enteredAt = now }
        let delay = hoverDelay.isFinite ? max(0.15, min(hoverDelay, 2)) : 0.25
        guard now - (enteredAt ?? now) >= delay else { return .none }
        isRevealed = true
        enteredAt = nil
        return .reveal
    }
}
