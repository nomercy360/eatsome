import Foundation

/// Append-only JSONL on disk. One event per line, never rewritten.
///
/// This is deliberately not SwiftData. The requirement is an append-only log,
/// and a file of JSON lines *is* one — no schema migrations to maintain, and
/// syncing it to a server is idempotent concatenation plus recorded-time replay. A read model is
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
    ///
    /// The skipped lines come back as raw text, and that is the whole of what
    /// makes a schema change survivable without touching every phone. This
    /// build cannot turn a v20 meal into a `LoggedEvent`, but it does not have
    /// to: the log is JSONL, an unreadable line is still a line, and forwarding
    /// it verbatim lets the server — which knows both shapes for one release —
    /// convert it and hand it back. Returning only a count is what forced the
    /// alternative, which was asking a person to open the old app on every
    /// device before upgrading and losing anything they missed.
    public func load() throws -> (events: [LoggedEvent], unreadable: [String]) {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var events: [LoggedEvent] = []
        var unreadable: [String] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let data = Data(line.utf8)
            if let probe = try? Self.decoder.decode(EventKindProbe.self, from: data),
               Self.retiredEventKinds.contains(probe.payload.kind) {
                continue
            }
            if let event = try? Self.decoder.decode(LoggedEvent.self, from: data) {
                events.append(event)
            } else {
                unreadable.append(String(line))
            }
        }
        // Replay mutations in the order they were written, not the time the
        // meal happened. A correction logged at 9 pm for lunch must supersede
        // the lunch event even after another device's stream is appended.
        events = events.enumerated().sorted { lhs, rhs in
            lhs.element.recordedAt == rhs.element.recordedAt
                ? lhs.offset < rhs.offset
                : lhs.element.recordedAt < rhs.element.recordedAt
        }.map(\.element)
        return (events, unreadable)
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

    /// These settings events were valid in older builds. They no longer affect
    /// the projection, but silently retaining their JSONL rows makes an in-place
    /// upgrade lossless and avoids misreporting them as corrupt records.
    private static let retiredEventKinds: Set<String> = [
        "habits_updated",
        "diet_saved",
        "diet_selected"
    ]

    private struct EventKindProbe: Decodable {
        let payload: Payload

        struct Payload: Decodable {
            let kind: String
        }
    }
}
