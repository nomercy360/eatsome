import AVFoundation
import Foundation
import MediaPipeTasksVision
import ShamanCore
import UIKit

/// The only file in the project that knows MediaPipe exists.
///
/// Written against Google's published Pose Landmarker iOS API. Nothing here is
/// adapted from any other pose-tracking codebase — the counting logic it feeds
/// lives in `ShamanCore` and was written from the geometry up.
///
/// `MediaPipeTasksVision` types collide with ours by name (`Landmark`), so
/// everything from the framework stays fully qualified at the boundary.
final class MediaPipePoseProvider: NSObject, PoseProvider, @unchecked Sendable {
    enum ProviderError: LocalizedError {
        case modelMissing

        var errorDescription: String? {
            switch self {
            case .modelMissing:
                "pose_landmarker_lite.task is not in the bundle. Run scripts/fetch_model.sh."
            }
        }
    }

    let frames: AsyncStream<PoseFrame>

    private let continuation: AsyncStream<PoseFrame>.Continuation
    private let camera = CameraFeed()
    private let modelName: String
    private var landmarker: PoseLandmarker?
    /// MediaPipe's live-stream mode requires strictly increasing timestamps and
    /// throws on anything else, so frames are stamped from the sample buffer
    /// clock and clamped rather than taken from `Date()`.
    private var lastTimestampMillis: Int = -1

    var session: AVCaptureSession { camera.session }

    init(modelName: String = "pose_landmarker_lite") {
        self.modelName = modelName
        var escapee: AsyncStream<PoseFrame>.Continuation!
        // Newest-first with a depth of 2: if counting ever falls behind capture,
        // dropping stale poses is correct — an old frame cannot help a rep count.
        self.frames = AsyncStream(bufferingPolicy: .bufferingNewest(2)) { escapee = $0 }
        self.continuation = escapee
        super.init()
    }

    func start() async throws {
        if landmarker == nil { landmarker = try makeLandmarker() }

        camera.onSampleBuffer = { [weak self] buffer, orientation in
            self?.process(buffer, orientation: orientation)
        }
        try await camera.start()
    }

    func stop() {
        camera.stop()
        camera.onSampleBuffer = nil
        continuation.finish()
    }

    private func makeLandmarker() throws -> PoseLandmarker {
        guard let path = Bundle.main.path(forResource: modelName, ofType: "task") else {
            throw ProviderError.modelMissing
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.poseLandmarkerLiveStreamDelegate = self
        return try PoseLandmarker(options: options)
    }

    private func process(_ buffer: CMSampleBuffer, orientation: AVCaptureVideoOrientation) {
        guard let landmarker else { return }

        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        guard seconds.isFinite else { return }
        let millis = max(lastTimestampMillis + 1, Int(seconds * 1000))
        lastTimestampMillis = millis

        guard let image = try? MPImage(sampleBuffer: buffer, orientation: orientation.imageOrientation)
        else { return }
        // Dropped frames are expected under load and are not an error worth
        // surfacing: the next one is 33ms away.
        try? landmarker.detectAsync(image: image, timestampInMilliseconds: millis)
    }
}

extension MediaPipePoseProvider: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: (any Error)?
    ) {
        guard error == nil,
              let result,
              let normalized = result.landmarks.first,
              let world = result.worldLandmarks.first,
              normalized.count == 33, world.count == 33
        else { return }

        continuation.yield(
            PoseFrame(
                timestamp: EpochMillis(timestampInMilliseconds),
                landmarks: normalized.map(Self.convert),
                worldLandmarks: world.map(Self.convert)
            )
        )
    }

    private static func convert(_ landmark: MediaPipeTasksVision.NormalizedLandmark) -> ShamanCore.Landmark {
        ShamanCore.Landmark(
            x: Double(landmark.x), y: Double(landmark.y), z: Double(landmark.z),
            visibility: landmark.visibility?.doubleValue ?? 1.0
        )
    }

    private static func convert(_ landmark: MediaPipeTasksVision.Landmark) -> ShamanCore.Landmark {
        ShamanCore.Landmark(
            x: Double(landmark.x), y: Double(landmark.y), z: Double(landmark.z),
            visibility: landmark.visibility?.doubleValue ?? 1.0
        )
    }
}

private extension AVCaptureVideoOrientation {
    var imageOrientation: UIImage.Orientation {
        switch self {
        case .portrait: .up
        case .portraitUpsideDown: .down
        case .landscapeLeft: .left
        case .landscapeRight: .right
        @unknown default: .up
        }
    }
}
