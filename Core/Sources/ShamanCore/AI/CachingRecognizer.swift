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
    private var memory: [String: MealRecognition] = [:]

    public init(upstream: any MealRecognizer, directory: URL) throws {
        self.upstream = upstream
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func recognize(imageData: Data, mimeType: String) async throws -> MealRecognition {
        let key = ImageDigest.sha256(imageData)

        if let hit = memory[key] { return hit }
        if let onDisk = try? Data(contentsOf: fileURL(key)),
           let decoded = try? JSONDecoder().decode(MealRecognition.self, from: onDisk) {
            memory[key] = decoded
            return decoded
        }

        let fresh = try await upstream.recognize(imageData: imageData, mimeType: mimeType)
        memory[key] = fresh
        // A cache write failure must not lose a successful recognition.
        try? JSONEncoder().encode(fresh).write(to: fileURL(key), options: .atomic)
        return fresh
    }

    public func cached(for imageData: Data) -> MealRecognition? {
        memory[ImageDigest.sha256(imageData)]
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }
}
