import Foundation
import Testing
@testable import EatsomeCore

/// Every test here is a test of one thing: bytes in, the same bytes out.
/// The interesting inputs are the ones a decode-then-encode round trip would
/// quietly rewrite — key order, `1.0`, an integer above 2^53, a unicode
/// escape — because each of them would still *look* right afterwards.
@Suite("RawJSON")
struct RawJSONTests {
    // MARK: Byte-faithfulness

    /// A line the current build does not understand: a future kind with a
    /// future payload. Every trap is in it on purpose. `sourceDeviceId` is
    /// null, the id is a real UUIDv7 in lowercase, there is an escaped
    /// slash and an escaped non-ASCII character beside a literal one, keys
    /// are not sorted, `1.0` and `2.50` carry trailing zeros, an integer
    /// exceeds `Double`'s exact range, and one number uses an exponent.
    static let futureLine = """
    {"id":"019905a0-2f3a-7c1e-8b6c-0f2c9a1d5e77","occurredAt":1786788000000,"recordedAt":1786788012345,"payload":{"kind":"activity_logged","data":{"label":"sauna \\/ banya","kind":"sauna","durationMinutes":20,"minutesAfterTraining":1.0,"ratio":2.50,"nanos":9007199254740993,"tiny":1e-7,"note":"caf\\u00e9 café 🧖","tags":[],"meta":{},"peer":null,"nested":{"z":[1,{"y":true}],"a":false}}},"sourceDeviceId":null}
    """

    @Test("A realistic future event line round-trips byte for byte")
    func futureLineRoundTrips() throws {
        let raw = try RawJSON(validating: Self.futureLine)
        #expect(raw.text == Self.futureLine)
        #expect(raw.bytes == Data(Self.futureLine.utf8))
    }

    @Test(
        "Each thing a decode-encode cycle would rewrite is preserved",
        arguments: [
            #"{"b":1,"a":2}"#,                       // key order
            #"{"x":1.0}"#,                           // trailing zero
            #"{"x":2.50}"#,                          // trailing zero, two places
            #"{"x":1e3}"#,                           // exponent form
            #"{"x":-0}"#,                            // negative zero
            #"{"x":9007199254740993}"#,              // 2^53 + 1, not a Double
            #"{"x":123456789012345678901234567890}"#, // wider than UInt64
            #"{"s":"é"}"#,                      // escape kept as escape
            #"{"s":"é"}"#,                           // literal kept literal
            #"{"s":"a\/b"}"#,                        // escaped slash
            #"{"s":"🧖"}"#,                // surrogate pair escape
            #"{"a":{"b":{"c":[[],[{}]]}}}"#,         // nesting
            #"{ "a" : 1 , "b" : [ 1 , 2 ] }"#,       // interior whitespace
            "{}", "[]", "null", "true", "0", "\"\"", // fragments and empties
            #"{"a":null}"#, #"[null,null]"#,
        ]
    )
    func preservesLexicalForm(_ text: String) throws {
        let raw = try RawJSON(validating: text)
        #expect(raw.text == text)
    }

    @Test("Equality and hashing are on bytes, so a normalised twin is a different value")
    func hashesBytes() throws {
        let a = try RawJSON(validating: #"{"x":1.0}"#)
        let b = try RawJSON(validating: #"{"x":1}"#)
        let a2 = try RawJSON(validating: #"{"x":1.0}"#)
        #expect(a != b)
        #expect(a == a2)
        #expect(a.hashValue == a2.hashValue)
    }

    // MARK: Validation

    @Test("Refuses what is not JSON, and says why")
    func refusesGarbage() {
        #expect(throws: RawJSON.ValidationError.empty) { try RawJSON(validating: "") }
        #expect(throws: RawJSON.ValidationError.trailingLineBreak) { try RawJSON(validating: "{}\n") }
        #expect(throws: RawJSON.ValidationError.self) { try RawJSON(validating: #"{"a":}"#) }
        #expect(throws: RawJSON.ValidationError.self) { try RawJSON(validating: #"{"a":1}{"b":2}"#) }
        #expect(throws: RawJSON.ValidationError.self) { try RawJSON(validating: "{'a':1}") }
        #expect(throws: RawJSON.ValidationError.self) { try RawJSON(validating: Data([0xFF, 0xFE])) }
    }

    // MARK: Probe — the two-pass read

    private struct Envelope: Decodable {
        struct Payload: Decodable { let kind: String }
        let id: UUID
        let occurredAt: Int64
        let recordedAt: Int64
        let payload: Payload
    }

    @Test("A probe reads the envelope while the line stays whole")
    func probeLeavesBytesAlone() throws {
        let raw = try RawJSON(validating: Self.futureLine)
        let env = try raw.probe(Envelope.self, using: JSONDecoder())
        #expect(env.payload.kind == "activity_logged")
        #expect(env.occurredAt == 1_786_788_000_000)
        #expect(env.recordedAt == 1_786_788_012_345)
        #expect(env.id.uuidString.lowercased() == "019905a0-2f3a-7c1e-8b6c-0f2c9a1d5e77")
        #expect(raw.text == Self.futureLine)
    }

    // MARK: Splicing — how a mixed file or batch is written

    private struct Known: Codable, Equatable { let kind: String; let n: Int }

    @Test("A known value and a retained line share one array without either being re-serialised")
    func splicesArray() throws {
        let encoder = JSONEncoder()
        let known = try RawJSON(encoding: Known(kind: "known", n: 1), using: encoder)
        let unknown = try RawJSON(validating: #"{"kind":"future","data":{"b":1.0,"a":9007199254740993}}"#)
        let batch = RawJSON.array([known, unknown])

        // The retained line appears verbatim inside the array.
        #expect(batch.text.contains(unknown.text))
        // The whole is itself valid JSON with two elements, and each is intact.
        let parsed = try JSONSerialization.jsonObject(with: batch.bytes) as? [Any]
        #expect(parsed?.count == 2)
        // A round trip through validation is a no-op, as it must be.
        #expect(try RawJSON(validating: batch.bytes) == batch)
        // And the known half decodes back to what it was.
        #expect(try known.probe(Known.self, using: JSONDecoder()) == Known(kind: "known", n: 1))
    }

    @Test("An object splices values in the order given, with keys escaped as JSON")
    func splicesObject() throws {
        let unknown = try RawJSON(validating: #"{"z":1.0,"a":2}"#)
        let obj = RawJSON.object([
            "deviceId": try RawJSON(validating: #""phone-1""#),
            "events": RawJSON.array([unknown]),
            "quote\"key": try RawJSON(validating: "null"),
        ])
        #expect(obj.text.hasPrefix(#"{"deviceId":"phone-1","events":[{"z":1.0,"a":2}],"#))
        let parsed = try JSONSerialization.jsonObject(with: obj.bytes) as? [String: Any]
        #expect(parsed?.keys.sorted() == ["deviceId", "events", "quote\"key"])
    }

    @Test("Empty splices are the empty containers")
    func emptySplices() {
        #expect(RawJSON.array([]).text == "[]")
        #expect(RawJSON.object([:]).text == "{}")
    }

    // MARK: Why it is not Codable

    /// Not a test of `RawJSON`; a test that the trap it exists for is real on
    /// this toolchain, so nobody "simplifies" it into a decoded tree later on
    /// the theory that Foundation would have preserved the bytes anyway.
    @Test("A decoded tree loses what RawJSON keeps")
    func decodedTreeNormalises() throws {
        let original = #"{"b":1.0,"a":9007199254740993}"#
        let tree = try JSONDecoder().decode([String: Double].self, from: Data(original.utf8))
        let again = try JSONEncoder().encode(tree)
        let text = String(decoding: again, as: UTF8.self)
        // Precision, or lexical form, or order — at least one is gone. Any
        // toolchain that passes this exactly would be the first.
        #expect(text != original)
        #expect(!text.contains("9007199254740993") || !text.contains("1.0") || !text.hasPrefix(#"{"b""#))
    }
}
