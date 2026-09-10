import Foundation
func check(_ value: Bool, _ name: String) { if !value { fatalError(name) } }
check(ChatPresentation.zoom(1, steps: 1) == 1.1, "Increase font size")
check(ChatPresentation.zoom(1, steps: -1) == 0.9, "Decrease font size")
check(ChatPresentation.zoom(1.6, steps: 1) == 1.6, "Upper bound")
check(ChatPresentation.zoom(0.8, steps: -1) == 0.8, "Lower bound")
check(ChatPresentation.clamp(.nan) == 1, "Corrupt preference recovers")
check(ChatPresentation.clamp(.infinity) == 1, "Infinite preference recovers")
check(ChatPresentation.clamp(2) == 1.6, "Oversized stored preference")
check(ChatPresentation.clamp(0.1) == 0.8, "Undersized stored preference")
var scale = 1.0
for _ in 0..<6 { scale = ChatPresentation.zoom(scale, steps: 1) }
check(scale == 1.6, "Repeated changes avoid rounding drift")
for _ in 0..<8 { scale = ChatPresentation.zoom(scale, steps: -1) }
check(scale == 0.8, "Repeated decrease reaches exact limit")
print("Chat presentation: 10 checks passed")
