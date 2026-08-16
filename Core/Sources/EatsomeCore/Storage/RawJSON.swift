import Foundation

/// The bytes of one JSON value, kept exactly as they were read.
///
/// This exists for one job: an event whose `kind` this build does not know
/// must survive a load-and-save cycle without a byte changing, so that a line
/// hashes the same in the build that wrote it and the build that merely
/// carried it. Swift's `Codable` cannot do that job. A `Decoder` hands you
/// typed values, never the text they were parsed from — `1.0` and `1` arrive
/// as the same `Double`, key order is whatever the container chose, and
/// `"é"` and `"é"` are one `String`. Anything rebuilt from a decoded tree
/// is a *normalised* copy that looks like the original and is not, which is
/// exactly the shape of failure this codebase keeps a list of.
///
/// So byte-faithfulness is achieved at the layer that owns bytes: the JSONL
/// reader keeps the line, and this type is the line. `EventLog` reads a line,
/// probes its envelope (`id`, `occurredAt`, `recordedAt`, `payload.kind`)
/// through `probe(_:)`, and if the kind is unknown it retains the whole line as
/// a `RawJSON` rather than decoding the payload. Writing it back is `bytes`,
/// verbatim. Whitespace inside the line is preserved along with everything
/// else, because nothing here parses and re-serialises.
///
/// It is deliberately not `Codable`: a `RawJSON` reached through a `Decoder`
/// has already lost its bytes and one reached through an `Encoder` cannot be
/// spliced into the output — Foundation offers no "emit these bytes here".
/// Anything that needs to *write* a mixed collection — a JSONL file, an upload
/// batch — assembles it with `array(_:)` and `object(_:)`, which splice bytes
/// and never re-serialise.
public struct RawJSON: Sendable, Hashable {
    /// UTF-8 text of exactly one JSON value. No leading or trailing whitespace
    /// is stripped; what went in is what comes out.
    public let bytes: Data

    /// The bytes as text. Always decodes: `init` refused anything that was not
    /// valid UTF-8 JSON.
    public var text: String { String(decoding: bytes, as: UTF8.self) }

    /// Wraps `bytes` after checking they form one syntactically valid JSON
    /// value. Validation is the only parsing that ever happens, and its result
    /// is discarded — it exists so that a corrupt line is refused here, at read
    /// time, rather than written back and refused by whoever reads it next.
    public init(validating bytes: Data) throws {
        guard !bytes.isEmpty else { throw ValidationError.empty }
        // Reject stray bytes JSONSerialization would tolerate but a strict
        // reader would not: it accepts surrounding whitespace, and a JSONL
        // line must not end in a newline (that is the record separator).
        guard bytes.last != UInt8(ascii: "\n"), bytes.last != UInt8(ascii: "\r") else {
            throw ValidationError.trailingLineBreak
        }
        do {
            _ = try JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])
        } catch {
            throw ValidationError.notJSON(underlying: String(describing: error))
        }
        self.bytes = bytes
    }

    /// `init(validating:)` for text.
    public init(validating text: String) throws {
        try self.init(validating: Data(text.utf8))
    }

    /// The bytes `JSONEncoder` produces for `value`, so a known event and a
    /// retained unknown one are the same type when they meet in a line or a
    /// batch. `encoder` is a parameter rather than a default so that the caller
    /// — `EventLog`, one place — owns the one encoder configuration and there
    /// is no second one hiding in here to drift from it.
    public init(encoding value: some Encodable, using encoder: JSONEncoder) throws {
        try self.init(validating: encoder.encode(value))
    }

    /// Decode a typed view of the value without giving up the bytes. This is
    /// how a reader learns an envelope's `id` and `payload.kind` before
    /// deciding whether it understands the rest: the probe type declares only
    /// the fields it needs, and the line is retained whole regardless of what
    /// the probe found.
    public func probe<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder) throws -> T {
        try decoder.decode(type, from: bytes)
    }

    // MARK: Splicing

    /// A JSON array whose elements are `elements`' bytes, verbatim, joined by
    /// commas. This is how a batch or a file of mixed known and unknown values
    /// is assembled without re-serialising the unknown ones.
    public static func array(_ elements: [RawJSON]) -> RawJSON {
        var out = Data([UInt8(ascii: "[")])
        for (i, element) in elements.enumerated() {
            if i > 0 { out.append(UInt8(ascii: ",")) }
            out.append(element.bytes)
        }
        out.append(UInt8(ascii: "]"))
        return RawJSON(trusted: out)
    }

    /// A JSON object with `members` in the order given, values spliced
    /// verbatim. Keys are encoded through `JSONEncoder`, which is a valid JSON
    /// string whatever it chooses to escape. Duplicate keys are a programmer
    /// error and trap.
    public static func object(_ members: KeyValuePairs<String, RawJSON>) -> RawJSON {
        var seen = Set<String>()
        var out = Data([UInt8(ascii: "{")])
        for (i, (key, value)) in members.enumerated() {
            precondition(seen.insert(key).inserted, "RawJSON.object: duplicate key \(key)")
            if i > 0 { out.append(UInt8(ascii: ",")) }
            out.append(RawJSON.encodedString(key))
            out.append(UInt8(ascii: ":"))
            out.append(value.bytes)
        }
        out.append(UInt8(ascii: "}"))
        return RawJSON(trusted: out)
    }

    /// Bytes assembled by this type from parts already validated. Not public:
    /// the only way in from outside is through validation.
    private init(trusted bytes: Data) { self.bytes = bytes }

    private static func encodedString(_ s: String) -> Data {
        // Encoding a bare String as a JSON fragment is supported since the
        // platforms this package targets (iOS 17 / macOS 14).
        // Cannot fail for a String.
        return (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
    }

    // MARK: Errors

    public enum ValidationError: Error, Equatable, Sendable {
        case empty
        case trailingLineBreak
        case notJSON(underlying: String)
    }

    /// Thrown by both halves of `Codable`. See the type's doc comment: a
    /// `Decoder` has no bytes to give and an `Encoder` cannot accept any, so
    /// either direction would silently normalise. This error is the loud
    /// alternative.
}

extension RawJSON: CustomStringConvertible {
    public var description: String { text }
}
