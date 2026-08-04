import Foundation
import Testing
@testable import ShamanCore

@Suite("Pose geometry")
struct GeometryTests {
    @Test("A right angle measures 90 degrees")
    func rightAngle() {
        let angle = PoseGeometry.angle(
            Landmark(x: 0, y: 1, z: 0),
            vertex: Landmark(x: 0, y: 0, z: 0),
            Landmark(x: 1, y: 0, z: 0)
        )
        #expect(abs(angle - 90) < 1e-9)
    }

    @Test("A straight limb measures 180 degrees")
    func straightAngle() {
        let angle = PoseGeometry.angle(
            Landmark(x: 0, y: 1, z: 0),
            vertex: Landmark(x: 0, y: 0, z: 0),
            Landmark(x: 0, y: -1, z: 0)
        )
        #expect(abs(angle - 180) < 1e-6)
    }

    @Test("Angles are computed in 3D, so camera position does not change them")
    func angleIsThreeDimensional() {
        // Same joint configuration, rotated 40° about the vertical axis — as
        // happens when you set the phone down at a different angle. A 2D
        // projection of this would read a different knee angle; the whole point
        // of MediaPipe's world landmarks is that this one does not.
        let theta = 40.0 * .pi / 180
        func rotate(_ l: Landmark) -> Landmark {
            Landmark(x: l.x * cos(theta) - l.z * sin(theta), y: l.y, z: l.x * sin(theta) + l.z * cos(theta))
        }
        let hip = Landmark(x: 0, y: 0.4, z: 0)
        let knee = Landmark(x: 0, y: 0, z: 0)
        let ankle = Landmark(x: 0.3, y: -0.25, z: 0)

        let direct = PoseGeometry.angle(hip, vertex: knee, ankle)
        let rotated = PoseGeometry.angle(rotate(hip), vertex: rotate(knee), rotate(ankle))
        #expect(abs(direct - rotated) < 1e-9)
    }

    @Test("Degenerate input returns NaN rather than a plausible wrong number")
    func degenerateAngleIsNaN() {
        let angle = PoseGeometry.angle(
            Landmark(x: 0, y: 0, z: 0),
            vertex: Landmark(x: 0, y: 0, z: 0),
            Landmark(x: 1, y: 0, z: 0)
        )
        #expect(angle.isNaN)
    }

    @Test("Distance metrics are normalized by torso, so body size drops out")
    func distanceIsBodySizeIndependent() {
        func frame(scale: Double) -> PoseFrame {
            var world = [Landmark](repeating: Landmark(x: 0, y: 0, z: 0), count: 33)
            world[PoseJoint.leftShoulder.rawValue] = Landmark(x: -0.2 * scale, y: 0.5 * scale, z: 0)
            world[PoseJoint.rightShoulder.rawValue] = Landmark(x: 0.2 * scale, y: 0.5 * scale, z: 0)
            world[PoseJoint.leftHip.rawValue] = Landmark(x: -0.15 * scale, y: 0, z: 0)
            world[PoseJoint.rightHip.rawValue] = Landmark(x: 0.15 * scale, y: 0, z: 0)
            world[PoseJoint.leftWrist.rawValue] = Landmark(x: -0.6 * scale, y: 0.3 * scale, z: 0)
            world[PoseJoint.rightWrist.rawValue] = Landmark(x: 0.6 * scale, y: 0.3 * scale, z: 0)
            let image = [Landmark](repeating: Landmark(x: 0.5, y: 0.5, z: 0), count: 33)
            return PoseFrame(timestamp: 0, landmarks: image, worldLandmarks: world)
        }

        let metric = MovementMetric.normalizedDistance(.leftWrist, .rightWrist, side: .both)
        let small = RepSession.metric(metric, in: frame(scale: 1.0))!
        let large = RepSession.metric(metric, in: frame(scale: 1.6))!
        #expect(abs(small - large) < 1e-9)
    }

    @Test("Torso length is nil when the shoulders or hips are missing")
    func torsoRequiresFourPoints() {
        let world = [Landmark](repeating: Landmark(x: 0, y: 0, z: 0), count: 33)
        let frame = PoseFrame(timestamp: 0, landmarks: world, worldLandmarks: world)
        #expect(PoseGeometry.torsoLength(frame) == nil, "coincident shoulders and hips give no scale")
    }
}

@Suite("One Euro filter")
struct OneEuroFilterTests {
    @Test("A constant signal passes through unchanged")
    func constantSignal() {
        var filter = OneEuroFilter()
        var value = 0.0
        for t in stride(from: 0, through: 1000, by: 33) {
            value = filter.filter(150, at: EpochMillis(t))
        }
        #expect(abs(value - 150) < 1e-6)
    }

    @Test("Noise is attenuated around a stable mean")
    func attenuatesNoise() {
        var filter = OneEuroFilter()
        let noise = [150.0, 154, 146, 153, 147, 152, 148, 151, 149, 150, 153, 147]
        var filtered: [Double] = []
        for (i, sample) in noise.enumerated() {
            filtered.append(filter.filter(sample, at: EpochMillis(i * 33)))
        }
        let rawSpread = noise.max()! - noise.min()!
        let filteredTail = Array(filtered.dropFirst(4))
        let filteredSpread = filteredTail.max()! - filteredTail.min()!
        #expect(filteredSpread < rawSpread / 2)
    }

    @Test("A fast ramp is tracked, not flattened")
    func tracksFastMovement() {
        var filter = OneEuroFilter()
        var value = 0.0
        for i in 0...20 {
            value = filter.filter(170 - Double(i) * 5, at: EpochMillis(i * 33))
        }
        // Raw endpoint is 70. Some lag is expected and desirable; being stuck
        // near the start would mean missed reps.
        #expect(value < 95, "filter lagged the movement badly: \(value)")
        #expect(value > 65)
    }

    @Test("Reset clears history")
    func resetClearsState() {
        var filter = OneEuroFilter()
        _ = filter.filter(150, at: 0)
        filter.reset()
        #expect(filter.filter(20, at: 33) == 20)
    }
}
