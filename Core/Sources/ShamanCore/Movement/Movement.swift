import Foundation

/// The scalar a movement is judged on.
///
/// There is deliberately no movement *classifier* here. You tell the app you are
/// about to do squats; it does not have to guess. Classification is the hard,
/// unreliable part of camera-based fitness, and skipping it costs nothing when
/// the user is also the person choosing from the list.
public enum MovementMetric: Sendable, Hashable {
    /// Angle at `vertex`, between the rays to `a` and `b`, in degrees.
    case jointAngle(a: PoseJoint, vertex: PoseJoint, b: PoseJoint, side: BodySide)
    /// Distance between two joints, divided by torso length so it is body-size
    /// independent. Used for things like jumping jacks where no single joint
    /// angle captures the movement.
    case normalizedDistance(PoseJoint, PoseJoint, side: BodySide)
}

public enum MovementMode: Sendable, Hashable {
    case reps
    /// Isometric holds: plank, wall sit. Scored on seconds inside the band.
    case hold(targetSeconds: Int)
}

// Flat, tagged JSON rather than Swift's synthesized `{"jointAngle":{"_0":...}}`.
// Same reason as `PoseJoint`: this is a file a human edits between camera tests.
extension MovementMetric: Codable {
    private enum CodingKeys: String, CodingKey { case type, a, vertex, b, side }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let side = try c.decodeIfPresent(BodySide.self, forKey: .side) ?? .both
        switch try c.decode(String.self, forKey: .type) {
        case "joint_angle":
            self = .jointAngle(
                a: try c.decode(PoseJoint.self, forKey: .a),
                vertex: try c.decode(PoseJoint.self, forKey: .vertex),
                b: try c.decode(PoseJoint.self, forKey: .b),
                side: side
            )
        case "normalized_distance":
            self = .normalizedDistance(
                try c.decode(PoseJoint.self, forKey: .a),
                try c.decode(PoseJoint.self, forKey: .b),
                side: side
            )
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown metric '\(other)'")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jointAngle(let a, let vertex, let b, let side):
            try c.encode("joint_angle", forKey: .type)
            try c.encode(a, forKey: .a)
            try c.encode(vertex, forKey: .vertex)
            try c.encode(b, forKey: .b)
            try c.encode(side, forKey: .side)
        case .normalizedDistance(let a, let b, let side):
            try c.encode("normalized_distance", forKey: .type)
            try c.encode(a, forKey: .a)
            try c.encode(b, forKey: .b)
            try c.encode(side, forKey: .side)
        }
    }
}

extension MovementMode: Codable {
    private enum CodingKeys: String, CodingKey { case type, targetSeconds }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "reps": self = .reps
        case "hold": self = .hold(targetSeconds: try c.decode(Int.self, forKey: .targetSeconds))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown mode '\(other)'")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reps:
            try c.encode("reps", forKey: .type)
        case .hold(let seconds):
            try c.encode("hold", forKey: .type)
            try c.encode(seconds, forKey: .targetSeconds)
        }
    }
}

public struct MovementDefinition: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let mode: MovementMode
    public let metric: MovementMetric
    /// Metric value at or below which you are in the bottom of the movement.
    public let lowThreshold: Double
    /// Metric value at or above which you are back at the top.
    ///
    /// The gap between the two is the hysteresis band, ~15-25° for angle
    /// metrics. A single threshold would count four reps as you wobble across
    /// it at the bottom of one.
    public let highThreshold: Double
    /// Floor on rep duration. Nothing human completes a squat in 300ms; if the
    /// signal says so, it is noise.
    public let minRepIntervalMillis: Int
    /// Landmarks that must be visible for a frame to be trusted, e.g. no
    /// counting squats when your knees are out of frame.
    public let requiredJoints: [PoseJoint]
    public let coachingCue: String

    public init(
        id: String,
        displayName: String,
        mode: MovementMode = .reps,
        metric: MovementMetric,
        lowThreshold: Double,
        highThreshold: Double,
        minRepIntervalMillis: Int = 700,
        requiredJoints: [PoseJoint] = [],
        coachingCue: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.mode = mode
        self.metric = metric
        self.lowThreshold = lowThreshold
        self.highThreshold = highThreshold
        self.minRepIntervalMillis = minRepIntervalMillis
        self.requiredJoints = requiredJoints
        self.coachingCue = coachingCue
    }
}

/// One completed set. Written to the event log, and mirrored into HealthKit by
/// the app layer so streaks and rings work outside this app.
public struct SetRecord: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let movementID: String
    public let startedAt: EpochMillis
    public let finishedAt: EpochMillis
    public let reps: Int
    public let holdSeconds: Double?
    /// Fraction of frames in the set where every required joint was visible.
    /// Low values mean the phone was badly placed, not that you did badly.
    public let trackingQuality: Double

    public init(
        id: UUID = UUIDv7.generate(),
        movementID: String,
        startedAt: EpochMillis,
        finishedAt: EpochMillis,
        reps: Int,
        holdSeconds: Double? = nil,
        trackingQuality: Double = 1.0
    ) {
        self.id = id
        self.movementID = movementID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.trackingQuality = trackingQuality
    }
}

extension MovementDefinition {
    /// Starting thresholds, from the sample-app defaults and a first pass by
    /// hand. These are the numbers you will actually tune — they live in
    /// `Config/shaman-config.json` so tuning them does not require a rebuild.
    public static let builtIn: [MovementDefinition] = [
        .init(
            id: "squat",
            displayName: "Squat",
            metric: .jointAngle(a: .leftHip, vertex: .leftKnee, b: .leftAnkle, side: .both),
            lowThreshold: 100,
            highThreshold: 160,
            requiredJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
            coachingCue: "Stand side-on to the phone, whole body in frame."
        ),
        .init(
            id: "pushup",
            displayName: "Push-up",
            metric: .jointAngle(a: .leftShoulder, vertex: .leftElbow, b: .leftWrist, side: .both),
            lowThreshold: 95,
            highThreshold: 155,
            requiredJoints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
            coachingCue: "Phone on the floor, side-on, about two metres away."
        ),
        .init(
            id: "lunge",
            displayName: "Lunge",
            metric: .jointAngle(a: .leftHip, vertex: .leftKnee, b: .leftAnkle, side: .left),
            lowThreshold: 105,
            highThreshold: 160,
            minRepIntervalMillis: 900,
            requiredJoints: [.leftHip, .leftKnee, .leftAnkle, .leftFootIndex],
            coachingCue: "Side-on. Front foot flat and visible."
        ),
        .init(
            id: "jumping_jack",
            displayName: "Jumping jack",
            metric: .normalizedDistance(.leftWrist, .rightWrist, side: .both),
            lowThreshold: 0.4,
            highThreshold: 1.6,
            minRepIntervalMillis: 400,
            requiredJoints: [.leftWrist, .rightWrist, .leftShoulder, .rightShoulder],
            coachingCue: "Face the phone, arms fully in frame overhead."
        ),
        .init(
            id: "plank",
            displayName: "Plank",
            mode: .hold(targetSeconds: 60),
            metric: .jointAngle(a: .leftShoulder, vertex: .leftHip, b: .leftAnkle, side: .both),
            lowThreshold: 160,
            highThreshold: 195,
            requiredJoints: [.leftShoulder, .leftHip, .leftAnkle],
            coachingCue: "Side-on. Hold the hip angle straight — sagging stops the clock."
        )
    ]
}
