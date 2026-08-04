import Foundation
import Testing
@testable import ShamanCore

@Suite("Rep counting")
struct RepCounterTests {
    private func counter() -> RepCounter {
        RepCounter(lowThreshold: 100, highThreshold: 160, minRepIntervalMillis: 700)
    }

    @Test("A full down-up cycle is one rep")
    func countsOneRep() {
        var c = counter()
        c.ingest(170, at: 0)
        c.ingest(90, at: 800)
        let out = c.ingest(170, at: 1600)
        #expect(out.didCountRep)
        #expect(c.reps == 1)
    }

    @Test("Jitter at the bottom does not produce phantom reps")
    func hysteresisAbsorbsJitter() {
        var c = counter()
        c.ingest(170, at: 0)
        // Oscillating across the low threshold, which a single-threshold
        // counter would read as several reps.
        for (i, value) in [95.0, 105, 92, 110, 88, 120, 99].enumerated() {
            c.ingest(value, at: EpochMillis(800 + i * 50))
        }
        #expect(c.reps == 0)
        c.ingest(170, at: 2000)
        #expect(c.reps == 1)
    }

    @Test("Values inside the dead band never change phase")
    func deadBandHoldsPhase() {
        var c = counter()
        c.ingest(90, at: 0)
        #expect(c.phase == .bottom)
        c.ingest(130, at: 100)
        #expect(c.phase == .bottom, "130 is between 100 and 160 — still on the way up")
        c.ingest(155, at: 200)
        #expect(c.phase == .bottom)
        c.ingest(161, at: 800)
        #expect(c.phase == .top)
        #expect(c.reps == 1)
    }

    @Test("A rep faster than a human is rejected, not counted")
    func rejectsImpossiblyFastReps() {
        var c = counter()
        c.ingest(170, at: 0)
        c.ingest(90, at: 1000)
        #expect(c.ingest(170, at: 1700).didCountRep)
        c.ingest(90, at: 1750)
        let out = c.ingest(170, at: 1800)
        #expect(!out.didCountRep)
        #expect(out.rejected == .tooFast)
        #expect(c.reps == 1)
    }

    @Test("Starting mid-movement does not credit a partial rep")
    func requiresFullRangeBeforeFirstRep() {
        var c = counter()
        // Camera starts while already standing: top, but never went down.
        c.ingest(175, at: 0)
        c.ingest(172, at: 100)
        #expect(c.reps == 0)
    }

    @Test("NaN frames are ignored rather than corrupting the phase")
    func ignoresNaN() {
        var c = counter()
        c.ingest(90, at: 0)
        c.ingest(.nan, at: 100)
        #expect(c.phase == .bottom)
        c.ingest(170, at: 800)
        #expect(c.reps == 1)
    }

    @Test("Ten synthetic squats count as ten")
    func endToEndSyntheticSet() {
        var session = RepSession(movement: MovementDefinition.builtIn.first { $0.id == "squat" }!)
        var last: EpochMillis = 0
        for frame in PoseFixture.squatReps(10) {
            session.ingest(frame)
            last = frame.timestamp
        }
        #expect(session.counter.reps == 10)
        #expect(session.trackingQuality == 1.0)

        let record = session.finish(at: last)
        #expect(record.reps == 10)
        #expect(record.movementID == "squat")
        #expect(record.holdSeconds == nil)
    }

    @Test("A shallow squat that never reaches depth counts nothing")
    func shallowRepsDoNotCount() {
        var session = RepSession(movement: MovementDefinition.builtIn.first { $0.id == "squat" }!)
        // Bottoms out at 120°, above the 100° low threshold.
        for frame in PoseFixture.squatReps(5, bottom: 120) { session.ingest(frame) }
        #expect(session.counter.reps == 0)
    }

    @Test("Occluded joints are excluded from tracking quality and stop counting")
    func occlusionIsReported() {
        var session = RepSession(movement: MovementDefinition.builtIn.first { $0.id == "squat" }!)
        for frame in PoseFixture.squatReps(2) { session.ingest(frame) }
        let counted = session.counter.reps

        var t: EpochMillis = 9_000_000
        for angle in [170.0, 85, 170, 85, 170] {
            session.ingest(PoseFixture.squat(kneeAngle: angle, at: t, visibility: 0.1))
            t += 400
        }
        #expect(session.counter.reps == counted, "frames below the visibility floor must not count")
        #expect(session.trackingQuality < 1.0)
    }

    @Test("Plank accumulates hold time only while the hip angle is in band")
    func holdModeAccumulates() {
        var session = RepSession(movement: MovementDefinition.builtIn.first { $0.id == "plank" }!)
        // Plank measures shoulder-hip-ankle; the squat fixture drives knee
        // angle, so drive the metric directly through a purpose-built frame.
        var t: EpochMillis = 0
        for _ in 0..<30 {
            session.ingest(PoseFixture.plank(hipAngle: 175, at: t)); t += 100
        }
        let straight = session.holdSeconds
        #expect(abs(straight - 2.9) < 0.05, "29 gaps of 100ms after the first frame")

        for _ in 0..<10 {
            session.ingest(PoseFixture.plank(hipAngle: 140, at: t)); t += 100
        }
        #expect(session.holdSeconds == straight, "a sagging hip must stop the clock")
    }
}

extension PoseFixture {
    /// Shoulder-hip-ankle angle, for hold-mode tests.
    static func plank(hipAngle: Double, at timestamp: EpochMillis) -> PoseFrame {
        var world = [Landmark](repeating: Landmark(x: 0, y: 0, z: 0), count: 33)
        let radians = hipAngle * .pi / 180
        for j in [PoseJoint.leftHip, .rightHip] { world[j.rawValue] = Landmark(x: 0, y: 0, z: 0) }
        for j in [PoseJoint.leftShoulder, .rightShoulder] { world[j.rawValue] = Landmark(x: 0, y: 0.4, z: 0) }
        for j in [PoseJoint.leftAnkle, .rightAnkle] {
            world[j.rawValue] = Landmark(x: 0.8 * sin(radians), y: 0.8 * cos(radians), z: 0)
        }
        let image = [Landmark](repeating: Landmark(x: 0.5, y: 0.5, z: 0, visibility: 1.0), count: 33)
        return PoseFrame(timestamp: timestamp, landmarks: image, worldLandmarks: world)
    }
}
