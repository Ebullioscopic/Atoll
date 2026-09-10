import Foundation
var checks = 0
func expect(_ value: Bool, _ message: String) { checks += 1; precondition(value, message) }
var state = FullscreenHoverState()
func step(_ time: Double, activation: Bool = false, content: Bool = false, allowed: Bool = true, delay: Double = 0.2) -> FullscreenHoverState.Action {
    state.update(inActivationArea: activation, inContentArea: content, allowed: allowed, now: time, hoverDelay: delay)
}
expect(step(0) == .none && !state.isRevealed, "Fullscreen starts hidden")
expect(step(1, activation: true) == .none, "Entry requires deliberate dwell")
expect(step(1.1) == .none, "Brief crossing cancels entry")
expect(step(2, activation: true) == .none, "Fresh entry starts fresh delay")
expect(step(2.3, activation: true) == .reveal && state.isRevealed, "Hover reveals")
expect(step(3, content: true) == .none && state.isRevealed, "Controls stay interactive inside content")
expect(step(4) == .none && state.isRevealed, "Exit has grace period")
expect(step(4.1, content: true) == .none, "Return cancels pending exit")
expect(step(5) == .none, "Later exit starts its own deadline")
expect(step(5.3) == .hide && !state.isRevealed, "Moving away hides again")
expect(step(6, activation: true) == .none, "Re-entry starts delay")
expect(step(6.3, activation: true) == .reveal, "Re-entry works")
expect(step(7, content: true, allowed: false) == .hide && !state.isRevealed, "Lock/manual hiding overrides hover immediately")
expect(step(8, activation: true, allowed: false) == .none, "Mouse cannot bypass hiding gate")
expect(step(9, activation: true) == .none, "Unlock does not reuse old dwell")
expect(step(9.3, activation: true) == .reveal, "Fresh hover after unlock works")
state = FullscreenHoverState()
expect(step(10, activation: true, delay: .nan) == .none, "Invalid duration does not reveal immediately")
expect(step(10.3, activation: true, delay: .nan) == .reveal, "Invalid duration recovers")
print("Fullscreen hover: \(checks) checks passed")
