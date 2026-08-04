import AudioToolbox
import AVFoundation
import ShamanCore
import SwiftUI

struct WorkoutSetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List(model.config.movements) { movement in
                NavigationLink {
                    WorkoutView(movement: movement)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(movement.displayName)
                        Text(movement.coachingCue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Move")
        }
    }
}

struct WorkoutView: View {
    let movement: MovementDefinition

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var provider = MediaPipePoseProvider()
    @State private var session: RepSession
    @State private var reps = 0
    @State private var holdSeconds = 0.0
    @State private var phase = RepCounter.Phase.unknown
    @State private var isTracking = false
    @State private var error: String?

    init(movement: MovementDefinition) {
        self.movement = movement
        _session = State(initialValue: RepSession(movement: movement))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: provider.session)
                .ignoresSafeArea()

            VStack {
                if !isTracking {
                    Label(movement.coachingCue, systemImage: "viewfinder")
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
                Spacer()
                counter
                    .padding(24)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, 32)
            }

            if let error {
                Text(error)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .navigationTitle(movement.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Finish") { Task { await finish() } }
        }
        .task { await run() }
        .onDisappear { provider.stop() }
    }

    @ViewBuilder
    private var counter: some View {
        VStack(spacing: 4) {
            if case .hold = movement.mode {
                Text(String(format: "%.0fs", holdSeconds))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("\(reps)")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: reps)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(isTracking ? .secondary : .orange)
        }
    }

    private var statusText: String {
        guard isTracking else { return "Move so your whole body is in frame" }
        return switch phase {
        case .bottom: "Down — now come back up"
        case .top: "Up"
        case .unknown: "Ready"
        }
    }

    private func run() async {
        do {
            try await provider.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        for await frame in provider.frames {
            let update = session.ingest(frame)
            isTracking = update.isTracking
            phase = update.phase
            reps = update.reps
            holdSeconds = update.holdSeconds
            if update.didCountRep {
                AudioServicesPlaySystemSound(1057)
            }
        }
    }

    private func finish() async {
        provider.stop()
        let record = session.finish(at: Date().epochMillis)
        // Nothing happened; do not write an empty set into the log or HealthKit.
        if record.reps > 0 || (record.holdSeconds ?? 0) >= 5 {
            await model.completeSet(record)
        }
        dismiss()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
