import Foundation

/// BlazePose's 33-landmark topology, as emitted by MediaPipe Pose Landmarker.
///
/// The two indices that matter and that Apple's Vision body-pose request does
/// not have are `heel` and `footIndex`: without the foot you cannot tell squat
/// depth from camera angle, and lunge geometry degenerates. The other reason to
/// be on this topology is that ML Kit on Android emits the same 33 points, so
/// thresholds calibrated here port instead of being re-derived.
public enum PoseJoint: Int, CaseIterable, Sendable, Hashable {
    case nose = 0
    case leftEyeInner, leftEye, leftEyeOuter
    case rightEyeInner, rightEye, rightEyeOuter
    case leftEar, rightEar
    case mouthLeft, mouthRight
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftPinky, rightPinky
    case leftIndex, rightIndex
    case leftThumb, rightThumb
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case leftHeel, rightHeel
    case leftFootIndex, rightFootIndex
}

/// Joints encode as their case name, not their index. The movement thresholds
/// in `Config/shaman-config.json` are meant to be edited by hand while you are
/// tuning them, and `"leftKnee"` is reviewable in a way that `26` is not.
extension PoseJoint: Codable {
    public var name: String { String(describing: self) }

    private static let byName: [String: PoseJoint] = Dictionary(
        uniqueKeysWithValues: PoseJoint.allCases.map { ($0.name, $0) }
    )

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let joint = Self.byName[name] else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown joint '\(name)'")
            }
            self = joint
            return
        }
        let index = try container.decode(Int.self)
        guard let joint = PoseJoint(rawValue: index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Joint index \(index) out of range")
        }
        self = joint
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

public enum BodySide: String, Codable, Sendable, Hashable {
    case left, right
    /// Average the two sides. Steadier, and it stops a rep from being missed
    /// because one knee was occluded for four frames.
    case both
}

public struct Landmark: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var z: Double
    /// MediaPipe's per-landmark visibility, 0...1. Below ~0.5 the point is a guess.
    public var visibility: Double

    public init(x: Double, y: Double, z: Double, visibility: Double = 1.0) {
        self.x = x; self.y = y; self.z = z; self.visibility = visibility
    }
}

public struct PoseFrame: Sendable {
    public let timestamp: EpochMillis
    /// Normalized image coordinates, 0...1. Used for drawing the overlay.
    public let landmarks: [Landmark]
    /// Metres, origin at the midpoint of the hips. This is the one we measure
    /// angles from: it is what makes a knee angle independent of where you put
    /// the phone, which is the whole reason for choosing MediaPipe.
    public let worldLandmarks: [Landmark]

    public init(timestamp: EpochMillis, landmarks: [Landmark], worldLandmarks: [Landmark]) {
        self.timestamp = timestamp
        self.landmarks = landmarks
        self.worldLandmarks = worldLandmarks
    }

    public subscript(joint: PoseJoint) -> Landmark? {
        worldLandmarks.indices.contains(joint.rawValue) ? worldLandmarks[joint.rawValue] : nil
    }

    public func imagePoint(_ joint: PoseJoint) -> Landmark? {
        landmarks.indices.contains(joint.rawValue) ? landmarks[joint.rawValue] : nil
    }
}

/// Everything above this line is framework-free on purpose.
///
/// `MediaPipePoseProvider` in the app target is the only file that imports
/// MediaPipeTasksVision. Swapping the estimator — to Vision, to a newer
/// MediaPipe task, to a recorded fixture for tests — is one file, and the rep
/// counting logic never learns which one it is talking to.
public protocol PoseProvider: AnyObject, Sendable {
    var frames: AsyncStream<PoseFrame> { get }
    func start() async throws
    func stop()
}
