import Foundation

/// The append-only file. One JSON value per line, never rewritten.
///
/// An unknown event kind is not a reason to stop: a kind this build does not
/// know decodes to `.unrecognized`, folds into nothing, and is written back and
/// uploaded byte for byte. A genuinely corrupt line is set aside and reported,
/// and nothing else — the mirror is a union of immutable events, so a phone
/// that cannot read one of its own lines can still safely pull and push the
/// rest.
public actor EventLog {
    public let url: URL
    private let codec = EventCodec()
    private var handle: FileHandle?

    public init(url: URL) throws {
        self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    /// Where the log lives by default: the app's Application Support directory.
    public static func defaultURL(
        for fileManager: FileManager = .default
    ) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("eatsome", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    /// What one read of the file produced.
    public struct Load: Sendable {
        /// Every event, including the ones this build cannot interpret. They
        /// are in here so that they are written back and uploaded rather than
        /// silently dropped.
        public var events: [LoggedEvent]
        /// Lines that are not a usable record at all. Worth showing; they
        /// block nothing.
        public var corrupt: [String]

        /// Events this build understands. What a projection folds.
        public var understood: [LoggedEvent] { events.filter { !$0.payload.isUnrecognized } }
        /// How many records came from a newer build. Worth surfacing in
        /// settings: "3 entries were written by a newer version" is a true and
        /// calming thing to say, where silence is not.
        public var fromNewerBuild: Int { events.count { $0.payload.isUnrecognized } }
    }

    public func load() throws -> Load {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var events: [LoggedEvent] = []
        var corrupt: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let text = String(line)
            guard let json = try? RawJSON(validating: text) else {
                corrupt.append(text)
                continue
            }
            do {
                events.append(try codec.event(from: json))
            } catch {
                corrupt.append(text)
            }
        }

        // Replay mutations in the order they were written, not the time the
        // thing happened. A correction logged at 9 pm for lunch must supersede
        // the lunch event even after another device's stream is appended.
        events = events.enumerated().sorted { lhs, rhs in
            lhs.element.recordedAt == rhs.element.recordedAt
                ? lhs.offset < rhs.offset
                : lhs.element.recordedAt < rhs.element.recordedAt
        }.map(\.element)

        return Load(events: events, corrupt: corrupt)
    }

    public func append(_ event: LoggedEvent) throws {
        try append([event])
    }

    public func append(_ events: [LoggedEvent]) throws {
        guard !events.isEmpty else { return }
        var out = Data()
        for event in events {
            out.append(try codec.line(for: event).bytes)
            out.append(UInt8(ascii: "\n"))
        }
        let handle = try openForAppending()
        try handle.seekToEnd()
        try handle.write(contentsOf: out)
        try handle.synchronize()
    }

    /// Append lines pulled from the mirror, verbatim, skipping any whose id is
    /// already in the file. Returns the events that were new. The line's own
    /// bytes are what is written — a kind from a newer build stays a kind
    /// from a newer build — and the id check is by probing the envelope, so a
    /// line that cannot even name itself is refused rather than appended.
    @discardableResult
    public func append(lines: [RawJSON]) throws -> [LoggedEvent] {
        guard !lines.isEmpty else { return [] }
        var known = Set(try load().events.map(\.id))
        var out = Data()
        var added: [LoggedEvent] = []
        for line in lines {
            let event = try codec.event(from: line)
            guard known.insert(event.id).inserted else { continue }
            out.append(line.bytes)
            out.append(UInt8(ascii: "\n"))
            added.append(event)
        }
        guard !added.isEmpty else { return [] }
        let handle = try openForAppending()
        try handle.seekToEnd()
        try handle.write(contentsOf: out)
        try handle.synchronize()
        return added
    }

    public func projection() throws -> Projection {
        Projection(replaying: try load().events)
    }

    private func openForAppending() throws -> FileHandle {
        if let handle { return handle }
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        return opened
    }

    deinit { try? handle?.close() }
}
