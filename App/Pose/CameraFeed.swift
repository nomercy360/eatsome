import AVFoundation
import Foundation

/// Camera plumbing, kept separate from pose estimation so the estimator can be
/// swapped or fed from a recorded file without touching capture.
final class CameraFeed: NSObject, @unchecked Sendable {
    enum FeedError: LocalizedError {
        case accessDenied
        case noCamera

        var errorDescription: String? {
            switch self {
            case .accessDenied: "Camera access is off. Enable it in Settings > Shaman."
            case .noCamera: "No usable camera on this device."
            }
        }
    }

    let session = AVCaptureSession()
    /// Called on `queue` for every frame. Keep the work here short.
    var onSampleBuffer: (@Sendable (CMSampleBuffer, AVCaptureVideoOrientation) -> Void)?

    private let queue = DispatchQueue(label: "app.shaman.camera", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false

    func start(position: AVCaptureDevice.Position = .back) async throws {
        guard await Self.requestAccess() else { throw FeedError.accessDenied }
        try configureIfNeeded(position: position)
        guard !session.isRunning else { return }
        // startRunning blocks; never call it on the main thread.
        await withCheckedContinuation { continuation in
            queue.async { [session] in
                session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func configureIfNeeded(position: AVCaptureDevice.Position) throws {
        guard !configured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 720p is plenty: BlazePose runs on a 256px crop, and a smaller buffer
        // means less thermal headroom spent on pixels the model discards.
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first, let input = try? AVCaptureDeviceInput(device: device) else {
            throw FeedError.noCamera
        }
        guard session.canAddInput(input), session.canAddOutput(output) else { throw FeedError.noCamera }

        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)

        configured = true
    }
}

extension CameraFeed: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onSampleBuffer?(sampleBuffer, connection.videoOrientation)
    }
}
