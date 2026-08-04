import Foundation

public enum PoseGeometry {
    /// Angle at `vertex` between the rays to `a` and `b`, in degrees, computed
    /// in 3D world space.
    ///
    /// Note that an angle is already scale-invariant — normalising it by torso
    /// length would be a no-op. Torso length matters for the *distance* metrics
    /// below, where a raw separation in metres varies with body size.
    public static func angle(_ a: Landmark, vertex: Landmark, _ b: Landmark) -> Double {
        let v1 = (a.x - vertex.x, a.y - vertex.y, a.z - vertex.z)
        let v2 = (b.x - vertex.x, b.y - vertex.y, b.z - vertex.z)
        let dot = v1.0 * v2.0 + v1.1 * v2.1 + v1.2 * v2.2
        let n1 = (v1.0 * v1.0 + v1.1 * v1.1 + v1.2 * v1.2).squareRoot()
        let n2 = (v2.0 * v2.0 + v2.1 * v2.1 + v2.2 * v2.2).squareRoot()
        guard n1 > 1e-9, n2 > 1e-9 else { return .nan }
        return acos(min(1, max(-1, dot / (n1 * n2)))) * 180 / .pi
    }

    public static func distance(_ a: Landmark, _ b: Landmark) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    /// Shoulder-midpoint to hip-midpoint. The scale reference for distance
    /// metrics, so they read the same on any body.
    public static func torsoLength(_ frame: PoseFrame) -> Double? {
        guard let ls = frame[.leftShoulder], let rs = frame[.rightShoulder],
              let lh = frame[.leftHip], let rh = frame[.rightHip] else { return nil }
        let shoulder = Landmark(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2, z: (ls.z + rs.z) / 2)
        let hip = Landmark(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2, z: (lh.z + rh.z) / 2)
        let d = distance(shoulder, hip)
        return d > 1e-6 ? d : nil
    }
}

/// The 1€ filter. MediaPipe's detector-tracker pipeline is already stable
/// between frames, but the residual jitter lands exactly where it hurts: at the
/// moment the signal crosses a Schmitt threshold. Low speed → heavy smoothing;
/// fast movement → the filter gets out of the way, so the bottom of a squat is
/// not lagged into a missed rep.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTimestamp: EpochMillis?

    public init(minCutoff: Double = 1.0, beta: Double = 0.007, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    public mutating func filter(_ value: Double, at timestamp: EpochMillis) -> Double {
        guard let previous = lastValue, let previousTime = lastTimestamp else {
            lastValue = value; lastTimestamp = timestamp
            return value
        }
        let dt = Double(timestamp - previousTime) / 1000.0
        guard dt > 0 else { return previous }
        let rate = 1.0 / dt

        let derivative = (value - previous) * rate
        let smoothedDerivative = Self.lowPass(derivative, previous: lastDerivative,
                                              alpha: Self.alpha(cutoff: derivativeCutoff, rate: rate))
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let smoothed = Self.lowPass(value, previous: previous,
                                    alpha: Self.alpha(cutoff: cutoff, rate: rate))

        lastDerivative = smoothedDerivative
        lastValue = smoothed
        lastTimestamp = timestamp
        return smoothed
    }

    public mutating func reset() {
        lastValue = nil; lastDerivative = 0; lastTimestamp = nil
    }

    private static func alpha(cutoff: Double, rate: Double) -> Double {
        let tau = 1.0 / (2 * .pi * cutoff)
        return 1.0 / (1.0 + tau * rate)
    }

    private static func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}
