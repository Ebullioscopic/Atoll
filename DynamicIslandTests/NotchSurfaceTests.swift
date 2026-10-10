import AppKit
import SwiftUI

@main
@MainActor
private struct NotchSurfaceTests {
    static func main() {
        _ = NSApplication.shared
        let shape = AnyShape(NotchShape(topCornerRadius: 6, bottomCornerRadius: 14))
        let elapsed = render(width: 292, shape: shape)
        let music = render(width: 360, shape: shape)
        // Activities have different widths. Their left and right silhouettes
        // must still agree, including the formerly unpainted focus padding.
        for y in 0..<40 {
            for x in 0..<24 {
                precondition(abs(alpha(elapsed, x, y) - alpha(music, x, y)) < 0.02)
                precondition(abs(alpha(elapsed, 291 - x, y) - alpha(music, 359 - x, y)) < 0.02)
            }
        }
        precondition(alpha(elapsed, 10, 20) > 0.99, "Left padding must share the black surface")
        precondition(alpha(elapsed, 0, 35) < 0.01, "The rounded corner must remain transparent")
        precondition(alpha(elapsed, 291, 35) < 0.01, "Both outer corners must use the shared shape")

        // The bare collapsed surface (menu-bar expansion, ViewThatFits
        // fallback) must paint the same silhouette as the closed notch.
        // A plain rectangle here regresses to square bottom corners.
        let collapsed = renderCollapsed(width: 292)
        for y in 0..<40 {
            for x in 0..<292 {
                precondition(abs(alpha(elapsed, x, y) - alpha(collapsed, x, y)) < 0.02,
                             "Collapsed surface must match the closed silhouette")
            }
        }
        precondition(alpha(collapsed, 0, 35) < 0.01, "The collapsed surface must keep the rounded corner transparent")

        let state = ProbeState()
        let host = NSHostingView(rootView: AnimationProbe(state: state, shape: shape))
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
        func flush() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        flush()
        state.selection = true
        flush()
        precondition(state.lastAnimation == ClosedLiveActivityMotion.resize,
                     "Selection changes must animate the surrounding surface")
        state.tick += 1
        flush()
        precondition(state.lastAnimation == nil, "A clock tick must not replay the surface animation")
        let openAnimation = Animation.linear(duration: 0.9)
        state.inheritedAnimation = openAnimation
        state.compact = false
        state.selection = false
        flush()
        precondition(state.lastAnimation == openAnimation, "Opening must keep its existing animation")
        state.compact = true
        state.selection = true
        flush()
        precondition(state.lastAnimation == openAnimation, "Closing must also keep its existing animation")
        state.disableAnimations = true
        state.selection = false
        flush()
        precondition(state.animationsDisabled, "Menu-bar retraction must stay immediate")
    }

    static func render(width: CGFloat, shape: AnyShape) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: Color.clear.frame(width: width, height: 40)
            .modifier(NotchSurface(shape: shape, selection: false, animateSelectionChanges: true)))
        host.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    static func renderCollapsed(width: CGFloat, height: CGFloat = 40) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: AtollCollapsedSurface(width: width, height: height))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    static func alpha(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
        let scale = image.pixelsHigh / 40
        return image.colorAt(x: x * scale, y: y * scale)!.alphaComponent
    }
}

private final class ProbeState: ObservableObject {
    @Published var selection = false
    @Published var compact = true
    @Published var tick = 0
    var inheritedAnimation: Animation?
    var disableAnimations = false
    var lastAnimation: Animation?
    var animationsDisabled = false
}

private struct AnimationProbe: View {
    @ObservedObject var state: ProbeState
    var shape: AnyShape

    var body: some View {
        Text(verbatim: "\(state.tick) \(state.selection) \(state.compact)")
            .transaction { transaction in
                state.lastAnimation = transaction.animation
                state.animationsDisabled = transaction.disablesAnimations
            }
            .modifier(NotchSurface(shape: shape, selection: state.selection,
                                   animateSelectionChanges: state.compact))
            // Model the parent open/close/menu transaction explicitly: an
            // offscreen host does not inherit AppKit's event transaction.
            .transaction { transaction in
                transaction.animation = state.inheritedAnimation
                transaction.disablesAnimations = state.disableAnimations
            }
    }
}
