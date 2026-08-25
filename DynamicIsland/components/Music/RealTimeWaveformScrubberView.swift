import SwiftUI
import Defaults

/// Applies exponential smoothing to AudioTap magnitudes across frames.
///
/// A reference type so `TimelineView` can advance it during body evaluation
/// without triggering SwiftUI "modifying state during view update" warnings.
private final class WaveformSmoother {
    private var magnitudes: [Float] = Array(repeating: 0.1, count: 6)

    func next(barCount: Int) -> [Float] {
        let tapMagnitudes = AudioTap.shared.getSmoothedMagnitudes()
        let newMags: [Float] = tapMagnitudes.count >= barCount
            ? Array(tapMagnitudes.prefix(barCount))
            : tapMagnitudes

        var smoothedMags = [Float](repeating: 0.1, count: newMags.count)
        for i in 0..<newMags.count {
            if i < magnitudes.count {
                smoothedMags[i] = magnitudes[i] * 0.85 + newMags[i] * 0.15
            } else {
                smoothedMags[i] = newMags[i]
            }
        }
        magnitudes = smoothedMags
        return smoothedMags
    }
}

struct RealTimeWaveformScrubberView: View {
    let color: Color
    let secondaryColor: Color?
    let progress: Double
    let minHeight: CGFloat

    // Hoisted out of the per-frame update path: these are read reactively via the
    // Defaults property wrapper instead of a dictionary subscript on every tick.
    @Default(.visualizerBarCount) private var barCount
    @Default(.sliderColor) private var sliderColor
    @Default(.colorExtractionMode) private var colorExtractionMode

    @State private var smoother = WaveformSmoother()

    private var fillStyle: AnyShapeStyle {
        (sliderColor == .albumArt && colorExtractionMode == .vibrant)
            ? AnyShapeStyle(color.spectrogramGradient(secondary: secondaryColor))
            : AnyShapeStyle(color)
    }

    var body: some View {
        // TimelineView(.animation) drives redraws in sync with the display refresh
        // and automatically pauses when the view is offscreen / the notch is closed,
        // replacing the always-on 60fps Timer that ran on the main runloop.
        TimelineView(.animation) { _ in
            let magnitudes = smoother.next(barCount: barCount)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background (Unplayed portion)
                    WaveformShape(magnitudes: magnitudes, minHeight: minHeight)
                        .fill(Color.gray.opacity(0.3))

                    // Foreground (Played portion)
                    WaveformShape(magnitudes: magnitudes, minHeight: minHeight)
                        .fill(fillStyle)
                        .opacity(0.8)
                        .mask(
                            HStack {
                                RoundedRectangle(cornerRadius: minHeight / 2)
                                    .frame(width: max(0, geometry.size.width * CGFloat(progress)))
                                Spacer(minLength: 0)
                            }
                        )
                }
                .clipShape(RoundedRectangle(cornerRadius: minHeight / 2))
            }
        }
    }
}

struct WaveformShape: Shape {
    var magnitudes: [Float]
    var minHeight: CGFloat
    
    var animatableData: AnimatableVector {
        get { AnimatableVector(values: magnitudes) }
        set { magnitudes = newValue.values }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        
        path.move(to: CGPoint(x: 0, y: height))
        
        var expandedMags: [Float] = []
        expandedMags.append(contentsOf: magnitudes)
        expandedMags.append(contentsOf: magnitudes.reversed())
        
        let count = expandedMags.count
        let step = width / CGFloat(max(1, count - 1))
        
        for i in 0..<count {
            let mag = expandedMags[i]
            let scaledMag = max(0.0, min(1.0, CGFloat(mag) * 1.5))
            
            let thickness = max(minHeight, height * scaledMag)
            let y = height - thickness
            let x = CGFloat(i) * step
            
            if i == 0 {
                path.addLine(to: CGPoint(x: x, y: y))
            } else {
                let prevMag = expandedMags[i - 1]
                let prevScaledMag = max(0.0, min(1.0, CGFloat(prevMag) * 1.5))
                let prevThickness = max(minHeight, height * prevScaledMag)
                let prevY = height - prevThickness
                let prevX = CGFloat(i - 1) * step
                
                let control1 = CGPoint(x: prevX + step / 2, y: prevY)
                let control2 = CGPoint(x: prevX + step / 2, y: y)
                
                path.addCurve(to: CGPoint(x: x, y: y), control1: control1, control2: control2)
            }
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        return path
    }
}

struct AnimatableVector: VectorArithmetic {
    var values: [Float]
    
    mutating func scale(by rhs: Double) {
        values = values.map { $0 * Float(rhs) }
    }
    
    var magnitudeSquared: Double {
        Double(values.reduce(0) { $0 + $1 * $1 })
    }
    
    static var zero: AnimatableVector {
        AnimatableVector(values: [])
    }
    
    static func + (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result[i] = l + r
        }
        return AnimatableVector(values: result)
    }
    
    static func - (lhs: AnimatableVector, rhs: AnimatableVector) -> AnimatableVector {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result[i] = l - r
        }
        return AnimatableVector(values: result)
    }
}
