import CryptoKit
import Foundation

public enum ImageDigest {
    /// Content hash of the original bytes. Also stored on `MealEntry` so a meal
    /// can be traced back to its photo without keeping the photo in the log.
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

    public func recognize(
        imageData: Data,
        mimeType: String,
        note: String? = nil
    ) async throws -> RecognitionArtifact {
        let key = cacheKey(for: imageData, note: note)

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

        let fresh = try await upstream.recognize(imageData: imageData, mimeType: mimeType, note: note)
        memory[key] = fresh
        // A cache write failure must not lose a successful recognition.
        try? JSONEncoder().encode(fresh).write(to: fileURL(key), options: .atomic)
        return fresh
    }

    public func cached(for imageData: Data, note: String? = nil) -> RecognitionArtifact? {
        memory[cacheKey(for: imageData, note: note)]
    }

    /// The note is part of the request, so it is part of the key: adding "fried
    /// in butter" to a photo you already submitted must ask again, not replay
    /// the answer that missed the butter.
    private func cacheKey(for imageData: Data, note: String?) -> String {
        var payload = imageData
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            payload.append(Data(note.utf8))
        }
        let digest = ImageDigest.sha256(payload)
        return namespace.isEmpty ? digest : "\(digest)-\(namespace)"
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
