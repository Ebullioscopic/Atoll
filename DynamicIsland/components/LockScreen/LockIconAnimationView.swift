/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Lottie
import Defaults

@MainActor
final class LockIconAnimator: ObservableObject {
    @Published private(set) var progress: CGFloat

    private var animationTask: Task<Void, Never>?
    private let animationDuration: TimeInterval = 0.35
    private let animationSteps: Int = 48

    init(initiallyLocked: Bool) {
        progress = initiallyLocked ? 1.0 : 0.0
    }

    deinit {
        animationTask?.cancel()
    }

    func update(isLocked: Bool, animated: Bool = true) {
        let target = isLocked ? 1.0 : 0.0
        let clampedTarget = max(0.0, min(1.0, target))

        if !animated {
            animationTask?.cancel()
            progress = clampedTarget
            return
        }

        guard abs(progress - clampedTarget) > 0.0005 else {
            progress = clampedTarget
            return
        }

        animationTask?.cancel()

        let startProgress = progress
        let delta = clampedTarget - startProgress
        let stepDuration = animationDuration / Double(animationSteps)
        let stepNanoseconds = UInt64(stepDuration * 1_000_000_000)

        animationTask = Task { [weak self] in
            guard let self else { return }

            for step in 0...animationSteps {
                if Task.isCancelled { return }

                if step > 0 {
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }

                let fraction = Double(step) / Double(animationSteps)
                let eased = easeOutCubic(fraction)
                progress = startProgress + CGFloat(eased) * CGFloat(delta)
            }

            progress = clampedTarget
        }
    }

    private func easeOutCubic(_ t: Double) -> Double {
        let clamped = max(0.0, min(1.0, t))
        return 1.0 - pow(1.0 - clamped, 3)
    }
}

struct LockIconProgressView: View {
    var progress: CGFloat
    var iconColor: Color = .white

    @ObservedObject private var lockScreenManager = LockScreenManager.shared
    @Default(.lockScreenLiveActivityIconStyle) private var iconStyle

    private var isLocked: Bool {
        progress >= 0.5 && !lockScreenManager.isFingerprintAnimating
    }

    var body: some View {
        // The system lock symbol rather than the bundled Lottie: the drawn one is
        // noticeably lighter in the stroke and reads as a different icon next to
        // everything else macOS puts on the lock screen. `.replace` gives the
        // open-to-closed change the shackle movement the animation was there for.
        Group {
            if iconStyle.showsLock {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .animation(.snappy(duration: 0.28), value: isLocked)
            }
        }
    }
}

/// Biometric affordance shown instead of the lock icon. The lock-screen manager
/// starts one shared scan state for both the in-app view and delegated overlay.
struct LockScreenFingerprintProgressView: View {
    var iconColor: Color = .white

    private static let animation = LottieAnimation.named("FingerprintScan")
    /// FingerprintScan.json is authored on an 800×600 canvas; this crops its
    /// empty outer area so the central fingerprint fills the indicator frame.
    private static let fingerprintCanvasCropScale: CGFloat = 2.65
    private static let successColor = ColorValueProvider(
        LottieColor(r: 0.18, g: 0.92, b: 0.34, a: 1)
    )

    @ObservedObject private var lockScreenManager = LockScreenManager.shared
    @Default(.lockScreenLiveActivityIconStyle) private var iconStyle

    var body: some View {
        Group {
            if iconStyle.showsFingerprint {
                ZStack {
                    Image(systemName: "touchid")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .opacity(lockScreenManager.isFingerprintAnimating ? 0 : 1)

                    if lockScreenManager.isFingerprintAnimating, let animation = Self.animation {
                        LottieView(animation: animation)
                            .playing(
                                .fromProgress(
                                    0,
                                    toProgress: 0.70,
                                    loopMode: .playOnce
                                )
                            )
                            .animationSpeed(5)
                            .valueProvider(
                                Self.successColor,
                                for: "**.Stroke 1.Color"
                            )
                            .configuration(.init(renderingEngine: .mainThread))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(Self.fingerprintCanvasCropScale)
                            .id(lockScreenManager.fingerprintAnimationGeneration)
                    }
                }
                    .accessibilityLabel(lockScreenManager.isFingerprintAnimating ? "Unlocking" : "Fingerprint unlock")
            }
        }
    }
}

struct LockIconLottieView: View {
    var progress: CGFloat

    private static let animation: LottieAnimation? = {
        if let animation = LottieAnimation.named("Lock") {
            return animation
        } else {
            print("⚠️ [LockIconLottieView] Missing Lock.json animation – falling back to SF Symbols")
            return nil
        }
    }()

    static var isAvailable: Bool {
        animation != nil
    }

    var body: some View {
        Group {
            if let animation = Self.animation {
                LottieView(animation: animation)
                    .currentProgress(progress)
                    .configuration(.init(renderingEngine: .mainThread))
            } else {
                Color.clear
            }
        }
    }
}
