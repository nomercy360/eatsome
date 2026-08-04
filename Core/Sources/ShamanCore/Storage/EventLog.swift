import Foundation

/// Append-only JSONL on disk. One event per line, never rewritten.
///
/// This is deliberately not SwiftData. The requirement is an append-only log,
/// and a file of JSON lines *is* one — no schema migrations to maintain, and
/// syncing it to a server later is `cat` plus a sort by UUIDv7. A read model is
/// a fold over the file (`Projection`), which at personal-tracker volumes costs
/// single-digit milliseconds on launch.
public actor EventLog {
    public let url: URL
    private var handle: FileHandle?

    public init(url: URL) throws {
        self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    /// The legacy default directory is retained across the product rename so
    /// existing meal history remains visible after an in-place app update.
    public static func defaultURL(appName: String = "Shaman") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return base.appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    public func append(_ event: LoggedEvent) throws {
        var line = try Self.encoder.encode(event)
        line.append(0x0A)
        let handle = try openHandle()
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    public func append(_ events: [LoggedEvent]) throws {
        for event in events { try append(event) }
    }

    /// Skips lines that fail to decode rather than failing the load. A single
    /// corrupt line — a half-written record after a crash, or a payload kind
    /// written by a newer build — must not cost you the rest of your history.
    public func load() throws -> (events: [LoggedEvent], skipped: Int) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var events: [LoggedEvent] = []
        var skipped = 0
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let event = try? Self.decoder.decode(LoggedEvent.self, from: Data(line.utf8)) {
                events.append(event)
            } else {
                skipped += 1
            }
        }
        events.sort { $0.occurredAt < $1.occurredAt }
        return (events, skipped)
    }

    public func projection() throws -> Projection {
        Projection(replaying: try load().events)
    }

    public func close() {
        try? handle?.close()
        handle = nil
    }

    private func openHandle() throws -> FileHandle {
        if let handle { return handle }
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        return opened
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // One line per event: pretty-printing would break the format.
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
