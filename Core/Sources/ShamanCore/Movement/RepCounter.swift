import Foundation

/// A Schmitt trigger over the movement metric.
///
/// Two thresholds with a dead band between them, and a rep is counted on the
/// transition back through the high threshold after having been below the low
/// one. The band is what makes this robust: a single threshold plus a jittery
/// signal at the bottom of a squat produces a burst of phantom reps, and no
/// amount of smoothing fully removes that — you need the hysteresis.
public struct RepCounter: Sendable {
    public enum Phase: String, Sendable {
        /// Haven't yet seen the metric at either extreme.
        case unknown
        case top
        case bottom
    }

    public enum Rejection: String, Sendable {
        /// Returned to the top faster than a human can move.
        case tooFast
    }

    public struct Output: Sendable {
        public var phase: Phase
        public var reps: Int
        public var didCountRep: Bool
        public var rejected: Rejection?
    }

    public let lowThreshold: Double
    public let highThreshold: Double
    public let minRepIntervalMillis: Int

    public private(set) var phase: Phase = .unknown
    public private(set) var reps: Int = 0

    private var enteredBottomAt: EpochMillis?
    private var lastRepAt: EpochMillis?

    public init(lowThreshold: Double, highThreshold: Double, minRepIntervalMillis: Int = 700) {
        precondition(lowThreshold < highThreshold, "low must be below high or there is no hysteresis band")
        self.lowThreshold = lowThreshold
        self.highThreshold = highThreshold
        self.minRepIntervalMillis = minRepIntervalMillis
    }

    public init(movement: MovementDefinition) {
        self.init(lowThreshold: movement.lowThreshold,
                  highThreshold: movement.highThreshold,
                  minRepIntervalMillis: movement.minRepIntervalMillis)
    }

    @discardableResult
    public mutating func ingest(_ value: Double, at timestamp: EpochMillis) -> Output {
        guard !value.isNaN else { return Output(phase: phase, reps: reps, didCountRep: false, rejected: nil) }

        if value <= lowThreshold {
            if phase != .bottom { enteredBottomAt = timestamp }
            phase = .bottom
            return Output(phase: phase, reps: reps, didCountRep: false, rejected: nil)
        }

        guard value >= highThreshold else {
            // Inside the dead band: hold whatever phase we were in. This branch
            // is the entire point of the trigger.
            return Output(phase: phase, reps: reps, didCountRep: false, rejected: nil)
        }

        guard phase == .bottom, let bottomAt = enteredBottomAt else {
            phase = .top
            return Output(phase: phase, reps: reps, didCountRep: false, rejected: nil)
        }

        // A full rep is measured from the bottom, and also from the previous rep,
        // so neither a twitch at the bottom nor a fast oscillation can double-count.
        let sinceBottom = timestamp - bottomAt
        let sinceLastRep = lastRepAt.map { timestamp - $0 } ?? .max
        guard sinceBottom >= EpochMillis(minRepIntervalMillis / 2),
              sinceLastRep >= EpochMillis(minRepIntervalMillis) else {
            phase = .top
            enteredBottomAt = nil
            return Output(phase: phase, reps: reps, didCountRep: false, rejected: .tooFast)
        }

        phase = .top
        enteredBottomAt = nil
        lastRepAt = timestamp
        reps += 1
        return Output(phase: phase, reps: reps, didCountRep: true, rejected: nil)
    }

    public mutating func reset() {
        phase = .unknown
        reps = 0
        enteredBottomAt = nil
        lastRepAt = nil
    }
}

/// Turns a stream of poses into a metric, then into reps or hold-time.
/// Framework-free, so a set can be replayed from a recorded fixture in a unit
/// test with no camera and no simulator.
public struct RepSession: Sendable {
    public let movement: MovementDefinition
    public private(set) var counter: RepCounter
    public private(set) var startedAt: EpochMillis?
    public private(set) var lastTimestamp: EpochMillis?
    public private(set) var holdSeconds: Double = 0

    private var filter: OneEuroFilter
    private var framesSeen = 0
    private var framesTracked = 0
    private var visibilityFloor: Double

    public init(movement: MovementDefinition, visibilityFloor: Double = 0.5) {
        self.movement = movement
        self.counter = RepCounter(movement: movement)
        self.filter = OneEuroFilter()
        self.visibilityFloor = visibilityFloor
    }

    public struct Update: Sendable {
        public var metric: Double?
        public var reps: Int
        public var phase: RepCounter.Phase
        public var didCountRep: Bool
        public var holdSeconds: Double
        /// False when required joints were missing or occluded in this frame.
        public var isTracking: Bool
    }

    @discardableResult
    public mutating func ingest(_ frame: PoseFrame) -> Update {
        framesSeen += 1
        if startedAt == nil { startedAt = frame.timestamp }
        defer { lastTimestamp = frame.timestamp }

        guard hasRequiredJoints(frame), let raw = Self.metric(movement.metric, in: frame) else {
            return Update(metric: nil, reps: counter.reps, phase: counter.phase,
                          didCountRep: false, holdSeconds: holdSeconds, isTracking: false)
        }
        framesTracked += 1

        let value = filter.filter(raw, at: frame.timestamp)

        if case .hold = movement.mode {
            let inPosition = value >= movement.lowThreshold && value <= movement.highThreshold
            if inPosition, let previous = lastTimestamp {
                holdSeconds += Double(frame.timestamp - previous) / 1000.0
            }
            return Update(metric: value, reps: 0, phase: inPosition ? .top : .unknown,
                          didCountRep: false, holdSeconds: holdSeconds, isTracking: true)
        }

        let out = counter.ingest(value, at: frame.timestamp)
        return Update(metric: value, reps: out.reps, phase: out.phase,
                      didCountRep: out.didCountRep, holdSeconds: holdSeconds, isTracking: true)
    }

    public var trackingQuality: Double {
        framesSeen == 0 ? 0 : Double(framesTracked) / Double(framesSeen)
    }

    public func finish(at timestamp: EpochMillis) -> SetRecord {
        SetRecord(
            movementID: movement.id,
            startedAt: startedAt ?? timestamp,
            finishedAt: timestamp,
            reps: counter.reps,
            holdSeconds: { if case .hold = movement.mode { return holdSeconds } else { return nil } }(),
            trackingQuality: trackingQuality
        )
    }

    private func hasRequiredJoints(_ frame: PoseFrame) -> Bool {
        movement.requiredJoints.allSatisfy { joint in
            (frame.imagePoint(joint)?.visibility ?? 0) >= visibilityFloor
        }
    }

    public static func metric(_ metric: MovementMetric, in frame: PoseFrame) -> Double? {
        switch metric {
        case .jointAngle(let a, let vertex, let b, let side):
            let values = joints(side).compactMap { mirror -> Double? in
                guard let pa = frame[mirror(a)], let pv = frame[mirror(vertex)], let pb = frame[mirror(b)]
                else { return nil }
                let angle = PoseGeometry.angle(pa, vertex: pv, pb)
                return angle.isNaN ? nil : angle
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)

        case .normalizedDistance(let a, let b, let side):
            guard let torso = PoseGeometry.torsoLength(frame) else { return nil }
            let values = joints(side).compactMap { mirror -> Double? in
                guard let pa = frame[mirror(a)], let pb = frame[mirror(b)] else { return nil }
                return PoseGeometry.distance(pa, pb) / torso
            }
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
    }

    /// `.both` evaluates the metric on each side and averages, which is what
    /// keeps a single occluded knee from dropping a rep.
    private static func joints(_ side: BodySide) -> [(PoseJoint) -> PoseJoint] {
        switch side {
        case .left: [{ $0.onLeft }]
        case .right: [{ $0.onRight }]
        case .both: [{ $0.onLeft }, { $0.onRight }]
        }
    }
}

extension PoseJoint {
    public var mirrored: PoseJoint {
        switch self {
        case .leftEyeInner: .rightEyeInner; case .rightEyeInner: .leftEyeInner
        case .leftEye: .rightEye; case .rightEye: .leftEye
        case .leftEyeOuter: .rightEyeOuter; case .rightEyeOuter: .leftEyeOuter
        case .leftEar: .rightEar; case .rightEar: .leftEar
        case .mouthLeft: .mouthRight; case .mouthRight: .mouthLeft
        case .leftShoulder: .rightShoulder; case .rightShoulder: .leftShoulder
        case .leftElbow: .rightElbow; case .rightElbow: .leftElbow
        case .leftWrist: .rightWrist; case .rightWrist: .leftWrist
        case .leftPinky: .rightPinky; case .rightPinky: .leftPinky
        case .leftIndex: .rightIndex; case .rightIndex: .leftIndex
        case .leftThumb: .rightThumb; case .rightThumb: .leftThumb
        case .leftHip: .rightHip; case .rightHip: .leftHip
        case .leftKnee: .rightKnee; case .rightKnee: .leftKnee
        case .leftAnkle: .rightAnkle; case .rightAnkle: .leftAnkle
        case .leftHeel: .rightHeel; case .rightHeel: .leftHeel
        case .leftFootIndex: .rightFootIndex; case .rightFootIndex: .leftFootIndex
        case .nose: .nose
        }
    }

    /// Movement definitions are written using left-side joints; these map a
    /// definition onto whichever side is being measured.
    var onLeft: PoseJoint { isRight ? mirrored : self }
    var onRight: PoseJoint { isRight ? self : mirrored }

    var isRight: Bool {
        switch self {
        case .rightEyeInner, .rightEye, .rightEyeOuter, .rightEar, .mouthRight,
             .rightShoulder, .rightElbow, .rightWrist, .rightPinky, .rightIndex,
             .rightThumb, .rightHip, .rightKnee, .rightAnkle, .rightHeel, .rightFootIndex:
            true
        default:
            false
        }
    }
}
