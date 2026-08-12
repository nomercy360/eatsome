import AVFoundation
import Foundation
import Observation
import ShamanCore

/// `AVAudioConverter` calls its input provider synchronously during one
/// conversion. Keeping the one-shot state in this object avoids capturing and
/// mutating a local variable from the provider's `@Sendable` closure. The
/// buffer never escapes that synchronous conversion call.
private final class VoiceConverterInput: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var wasSupplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !wasSupplied else {
            status.pointee = .noDataNow
            return nil
        }
        wasSupplied = true
        status.pointee = .haveData
        return buffer
    }
}

private struct SonioxStartRequest: Encodable {
    let apiKey: String
    let model: String
    let audioFormat: String
    let sampleRate: Int
    let numChannels: Int
    let context: SonioxContext
    let enableEndpointDetection: Bool

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case model
        case audioFormat = "audio_format"
        case sampleRate = "sample_rate"
        case numChannels = "num_channels"
        case context
        case enableEndpointDetection = "enable_endpoint_detection"
    }
}

private struct SonioxContext: Encodable {
    let general: [SonioxContextItem]
    let text: String
}

private struct SonioxContextItem: Encodable {
    let key: String
    let value: String
}

/// Live dictation, transcribed by Soniox as you speak.
///
/// It sends as *text*, which is the whole point of `7b`: what the transcriber
/// heard is what gets parsed, so a wrong word is visible and fixable before the
/// message goes rather than mysterious afterwards. Nothing here ever produces a
/// meal directly — the words land in the composer and are sent like anything
/// else.
///
/// The phone never holds the Soniox API key. It asks the Worker for a
/// short-lived, single-use temporary key and opens the socket with that, so a
/// key pulled off a device is worth a few minutes of transcription rather than
/// an account.
@MainActor
@Observable
final class VoiceDictation {
    /// Everything heard so far: the settled words plus whatever is still being
    /// revised. Shown live, and handed to the composer when you accept.
    private(set) var heard = ""
    private(set) var isRecording = false
    private(set) var error: String?
    /// Seconds recorded, for the timer beside the waveform.
    private(set) var elapsed: TimeInterval = 0
    /// Recent input levels, newest last — the waveform is a sign that the
    /// microphone is actually hearing something, which silence otherwise cannot
    /// distinguish from a broken session.
    private(set) var levels: [Float] = []

    /// False when the build has no backend to mint a key from, which greys the
    /// mic rather than letting it fail after the tap.
    var isAvailable: Bool { keySource != nil }

    private var keySource: VoiceKeySource?
    private var socket: URLSessionWebSocketTask?
    private let engine = AVAudioEngine()
    /// Words the model has committed to. Non-final tokens are appended after
    /// these for display and replaced wholesale on the next message, which is
    /// what makes the text settle rather than flicker.
    private var settled = ""
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    /// Invalidated by cancel/accept. Permission and key requests cannot be
    /// cancelled at the system boundary, so every continuation checks this
    /// identity before it is allowed to open audio or a socket.
    private var takeID: UUID?

    /// Soniox's own realtime model, and the raw format its docs name for PCM:
    /// signed 16-bit little-endian, one channel.
    private static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    private static let model = "stt-rt-v5"
    private static let sampleRate = 16_000.0

    func configure(_ source: VoiceKeySource?) {
        keySource = source
    }

    func start() {
        guard !isRecording, let keySource else { return }
        error = nil
        heard = ""
        settled = ""
        levels = []
        elapsed = 0
        isRecording = true
        let take = UUID()
        takeID = take
        startedAt = Date()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }

        Task {
            do {
                // Asked before the key is bought. A refusal after minting one
                // would spend a request to record nothing.
                let allowed = await Self.microphoneIsAllowed()
                guard self.takeID == take, self.isRecording else { return }
                guard allowed else {
                    self.error = "eatsome needs the microphone to hear you. You can turn it on in Settings."
                    stop()
                    return
                }
                let key = try await keySource.temporaryKey()
                guard self.takeID == take, self.isRecording else { return }
                try await openSocket(with: key)
                try startCapture()
            } catch {
                guard self.takeID == take else { return }
                self.error = error.localizedDescription
                stop()
            }
        }
    }

    private static func microphoneIsAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Give up on this take. Nothing is kept — an abandoned dictation is not a
    /// draft, it is a thing you decided not to say.
    func cancel() {
        stop()
        heard = ""
        settled = ""
    }

    /// Finish, and hand back what was heard.
    func accept() -> String {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        return text
    }

    private func stop() {
        takeID = nil
        isRecording = false
        startedAt = nil
        ticker?.cancel()
        ticker = nil

        // Unconditionally, not `if engine.isRunning`. A take that failed before
        // `engine.start()` left its tap installed, and the next one crashed on
        // the duplicate. Removing a tap that was never installed is a no-op.
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        // An empty frame is how Soniox is told the audio has ended; closing the
        // socket outright would drop whatever is still being finalized.
        socket?.send(.string("")) { _ in }
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - The socket

    private func openSocket(with key: String) async throws {
        let task = URLSession.shared.webSocketTask(with: Self.endpoint)
        socket = task
        task.resume()

        let config = SonioxStartRequest(
            apiKey: key,
            model: Self.model,
            audioFormat: "pcm_s16le",
            sampleRate: Int(Self.sampleRate),
            numChannels: 1,
            context: SonioxContext(
                general: [
                    SonioxContextItem(key: "domain", value: "Food and nutrition"),
                    SonioxContextItem(key: "intent", value: "Describe a meal"),
                ],
                // Food words, given to the recognizer as context so "krapao"
                // and "shakshuka" come back spelled as themselves rather than
                // as the nearest everyday phrase.
                text: Self.foodContext
            ),
            // Left off deliberately: it ends the session on a pause, and people
            // pause mid-sentence while remembering what they had for lunch.
            enableEndpointDetection: false
        )
        let data = try JSONEncoder().encode(config)
        // Soniox requires the start request to be the first WebSocket message.
        // Wait until it is enqueued before the audio tap can emit binary frames.
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
        listen()
    }

    private static let foodContext = """
    The speaker is describing a meal they ate: foods, dishes, drinks, quantities \
    and times. Expect dish names from many cuisines.
    """

    private func listen() {
        socket?.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                switch result {
                case .failure(let error):
                    self.fail(error)
                case .success(let message):
                    self.handle(message)
                    self.listen()
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if let code = json["error_code"] {
            error = (json["error_message"] as? String) ?? "Transcription failed (\(code))."
            stop()
            return
        }

        var pending = ""
        for token in json["tokens"] as? [[String: Any]] ?? [] {
            guard let text = token["text"] as? String else { continue }
            if token["is_final"] as? Bool == true {
                settled += text
            } else {
                pending += text
            }
        }
        heard = (settled + pending).trimmingCharacters(in: .whitespaces)

        if json["finished"] as? Bool == true { stop() }
    }

    private func fail(_ error: any Error) {
        // A socket closed by `stop()` reports a failure on the pending receive.
        // That is the normal end of a take, not something to put on screen.
        guard isRecording else { return }
        self.error = error.localizedDescription
        stop()
    }

    // MARK: - The microphone

    /// Open the microphone.
    ///
    /// Two of the three guards here exist because `AVAudioEngine` reports these
    /// failures as Objective-C exceptions, which a Swift `throws` cannot catch:
    /// they terminate the process with nothing on screen and nothing in the
    /// composer's error line. The app was exiting silently on the second tap of
    /// the mic, and this is why.
    private func startCapture() throws {
        let session = AVAudioSession.sharedInstance()
        // `.record` with `.duckOthers`: ducking belongs to the playback
        // categories, and passing it here is a parameter error rather than a
        // no-op.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let input = engine.inputNode

        // 1. A tap left over from a take that never started.
        //
        // `stop()` only pulled the tap when the engine was *running*, and the
        // engine is not running if `start()` threw between installing the tap
        // and starting it — a failed key mint, a refused socket. The tap then
        // survived, and the next `installTap` on the same bus raised
        // "required condition is false: nullptr == Tap()" and killed the app.
        // Removing unconditionally is safe: removing a tap that is not there
        // does nothing.
        input.removeTap(onBus: 0)

        // 2. A route that is not ready yet.
        //
        // `outputFormat(forBus:)` answers 0 Hz when no input is available —
        // a call in progress, a headset mid-handshake — and installing a tap
        // with a zero sample rate raises rather than returning an error.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoiceError.microphoneUnavailable
        }

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: true
        ) else { throw VoiceError.microphoneUnavailable }

        guard let converter = AVAudioConverter(from: format, to: target) else {
            throw VoiceError.microphoneUnavailable
        }

        // AVAudioNode invokes this block on its real-time audio queue. Its
        // Objective-C block type is not annotated `@Sendable`, so without the
        // explicit annotation Swift inherits this method's MainActor isolation
        // and traps in `_swift_task_checkIsolatedSwift` on the first buffer.
        input.installTap(onBus: 0, bufferSize: 4_096, format: format) { @Sendable [weak self] buffer, _ in
            let level = Self.peak(of: buffer)
            guard let converted = Self.convert(buffer, using: converter, to: target) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.note(level)
                self.socket?.send(.data(converted)) { _ in }
            }
        }

        engine.prepare()
        try engine.start()
    }

    private func note(_ level: Float) {
        levels.append(level)
        if levels.count > 48 { levels.removeFirst(levels.count - 48) }
    }

    nonisolated private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channel[index]))
        }
        return min(1, peak * 2.2)
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> Data? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        let input = VoiceConverterInput(buffer: buffer)
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            input.next(status: status)
        }
        guard conversionError == nil,
              let channel = output.int16ChannelData,
              output.frameLength > 0
        else { return nil }

        return Data(bytes: channel[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
    }
}

enum VoiceError: LocalizedError {
    case microphoneUnavailable
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable: "The microphone isn't available right now."
        case .notConfigured: "Dictation isn't set up on this build."
        }
    }
}

/// Where a short-lived Soniox key comes from.
///
/// A protocol rather than a direct call so the app can be run against a stub,
/// and so the one place that knows the real key stays the Worker.
protocol VoiceKeySource: Sendable {
    func temporaryKey() async throws -> String
}

struct BackendVoiceKeys: VoiceKeySource {
    let backend: BackendSession

    func temporaryKey() async throws -> String {
        try await backend.voiceKey().apiKey
    }
}
