import Foundation
@testable import ShamanCore

/// Synthetic poses, so rep counting can be tested without a camera, a
/// simulator, or a human. This is the payoff for keeping the counter free of
/// any framework: a whole set replays in microseconds.
enum PoseFixture {
    /// Builds a frame in which the knee angle is exactly `kneeAngle` degrees on
    /// both sides, with the knee at the origin and the hip directly above it.
    static func squat(kneeAngle: Double, at timestamp: EpochMillis, visibility: Double = 1.0) -> PoseFrame {
        var world = [Landmark](repeating: Landmark(x: 0, y: 0, z: 0), count: 33)
        let radians = kneeAngle * .pi / 180

        for side in [PoseJoint.leftHip, .rightHip] { world[side.rawValue] = Landmark(x: 0, y: 0.4, z: 0) }
        for side in [PoseJoint.leftKnee, .rightKnee] { world[side.rawValue] = Landmark(x: 0, y: 0, z: 0) }
        for side in [PoseJoint.leftAnkle, .rightAnkle] {
            world[side.rawValue] = Landmark(x: 0.4 * sin(radians), y: 0.4 * cos(radians), z: 0)
        }
        for side in [PoseJoint.leftShoulder, .rightShoulder] { world[side.rawValue] = Landmark(x: 0, y: 0.9, z: 0) }

        let image = [Landmark](repeating: Landmark(x: 0.5, y: 0.5, z: 0, visibility: visibility), count: 33)
        return PoseFrame(timestamp: timestamp, landmarks: image, worldLandmarks: world)
    }

    /// A full squat: down to `bottom`, back up to `top`, sampled at 30fps, with
    /// a short dwell at each end. The dwell is not decoration — the 1€ filter
    /// lags a fast ramp by ~10°, and a real squat does pause at lockout.
    static func squatReps(
        _ count: Int,
        top: Double = 170,
        bottom: Double = 85,
        framesPerPhase: Int = 12,
        dwellFrames: Int = 5,
        startingAt start: EpochMillis = 1_700_000_000_000
    ) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var t = start
        let step: EpochMillis = 33

        func hold(_ angle: Double, _ n: Int) {
            for _ in 0..<n { frames.append(squat(kneeAngle: angle, at: t)); t += step }
        }
        func ramp(from: Double, to: Double) {
            for i in 1...framesPerPhase {
                let p = Double(i) / Double(framesPerPhase)
                frames.append(squat(kneeAngle: from + (to - from) * p, at: t))
                t += step
            }
        }

        hold(top, dwellFrames)
        for _ in 0..<count {
            ramp(from: top, to: bottom)
            hold(bottom, dwellFrames)
            ramp(from: bottom, to: top)
            hold(top, dwellFrames)
        }
        return frames
    }
}

extension MealEntry {
    /// `daysAgo` counted back from a fixed reference so tests never depend on
    /// the wall clock.
    static let referenceNow: EpochMillis = 1_700_000_000_000

    static func fixture(daysAgo: Double, _ foods: [(String, Double)]) -> MealEntry {
        MealEntry(
            eatenAt: referenceNow - EpochMillis(daysAgo * 86_400_000),
            dishes: [Fixture.dish(nil, foods.map { Fixture.item($0.0, grams: $0.1) })],
            source: .photo
        )
    }
}
