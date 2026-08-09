import CryptoKit
import Foundation

public enum ImageDigest {
    /// Content hash of the normalized model-input bytes. Also stored on
    /// `MealEntry`, so recognition, R2, and eval evidence name the same render.
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Wraps any recognizer with a content-addressed cache.
///
/// Retrying a failed save, reopening the confirm sheet, or logging the same
/// leftovers twice all hash to the same key and cost nothing the second time.
public actor CachingRecognizer: MealRecognizer {
    private let upstream: any MealRecognizer
    private let directory: URL
    private let namespace: String
    private var memory: [String: RecognitionArtifact] = [:]

    /// `namespace` separates answers that happen to share a photo but not a
    /// generator — usually the prompt version and model. Without it, switching
    /// providers to compare them would replay the first one's cached answer,
    /// which is the one measurement the cache must never fake.
    public init(upstream: any MealRecognizer, directory: URL, namespace: String = "") throws {
        self.upstream = upstream
        self.directory = directory
        self.namespace = Self.sanitize(namespace)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func sanitize(_ namespace: String) -> String {
        let safe = namespace.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(safe)
    }

    public func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
        guard !message.isEmpty else { throw MealRecognizerError.emptyMessage }
        let key = cacheKey(for: message)

        if let hit = memory[key] { return hit }
        if let onDisk = try? Data(contentsOf: fileURL(key)) {
            if let artifact = try? JSONDecoder().decode(RecognitionArtifact.self, from: onDisk) {
                memory[key] = artifact
                return artifact
            }
            // v1 caches contained only the parsed recognition. Preserve the
            // cached answer without another API call and mark its provenance.
            if let legacy = try? JSONDecoder().decode(MealRecognition.self, from: onDisk),
               let raw = String(data: onDisk, encoding: .utf8) {
                let artifact = RecognitionArtifact(
                    recognition: legacy,
                    rawModelJSON: raw,
                    promptVersion: "meal-v1-legacy-cache"
                )
                memory[key] = artifact
                return artifact
            }
        }

        let fresh = try await upstream.recognize(message)
        memory[key] = fresh
        // A cache write failure must not lose a successful recognition.
        try? JSONEncoder().encode(fresh).write(to: fileURL(key), options: .atomic)
        return fresh
    }

    public func cached(for message: MealMessage) -> RecognitionArtifact? {
        memory[cacheKey(for: message)]
    }

    /// The words are part of the request, so they are part of the key: adding
    /// "fried in butter" to a photo you already submitted must ask again, not
    /// replay the answer that missed the butter.
    ///
    /// The separator is not decoration. Concatenating bytes and text directly
    /// lets a photo whose trailing bytes happen to spell the next message's
    /// first word collide with it — vanishingly unlikely, and a collision here
    /// serves one meal's reading for another's, which is silent and unfixable.
    private func cacheKey(for message: MealMessage) -> String {
        var payload = message.imageData ?? Data()
        if let said = message.trimmedText {
            payload.append(Data([0]))
            payload.append(Data(said.utf8))
        }
        let digest = ImageDigest.sha256(payload)
        return namespace.isEmpty ? digest : "\(digest)-\(namespace)"
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
