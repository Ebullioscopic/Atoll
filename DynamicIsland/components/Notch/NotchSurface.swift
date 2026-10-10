import SwiftUI

/// Shared motion for compact activity content and its surrounding surface.
enum ClosedLiveActivityMotion {
    static let resize = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let valueUpdate = Animation.smooth(duration: 0.25)
    static let transition: AnyTransition = .asymmetric(
        insertion: .opacity
            .combined(with: .scale(scale: 0.965, anchor: .center))
            .animation(resize),
        removal: .opacity
            .combined(with: .scale(scale: 0.92, anchor: .center))
            .animation(.smooth(duration: 0.22))
    )
}

/// Bare notch-sized black surface shared by every code path that paints
/// outside `mainLayoutBase` (menu-bar expansion, `ViewThatFits` fallback).
/// The shape must always be the collapsed silhouette so the bottom fillet
/// stays identical to the closed notch. Physical-notch callers use the
/// default closed notch; island screens pass the closed pill explicitly.
struct AtollCollapsedSurface: View {
    var width: CGFloat
    var height: CGFloat
    var shape: AnyShape = AnyShape(NotchShape())

    var body: some View {
        Color.black
            .frame(width: width, height: height)
            .clipShape(shape)
    }
}

/// Paint and clip one continuous surface, regardless of the activity inside it.
/// Selection changes can resize it without replaying that motion on every tick.
struct NotchSurface<Selection: Equatable>: ViewModifier {
    var shape: AnyShape
    var selection: Selection
    var animateSelectionChanges: Bool

    func body(content: Content) -> some View {
        content
            .background(Color.black)
            .clipShape(shape)
            .transaction(value: selection) { transaction in
                // Preserve the existing open/close animation and immediate
                // menu-bar retraction instead of overriding their transactions.
                guard animateSelectionChanges, !transaction.disablesAnimations,
                      transaction.animation == nil else { return }
                transaction.animation = ClosedLiveActivityMotion.resize
            }
    }
}
