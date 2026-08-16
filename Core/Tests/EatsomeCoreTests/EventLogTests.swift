import Foundation
import Testing

@testable import EatsomeCore

@Suite("The log")
struct EventLogTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    private func meal(kcal: Double = 400, at millis: EpochMillis) -> MealEntry {
        MealEntry(
            eatenAt: millis,
            dishes: [
                MealDish(
                    name: "Salmon don",
                    items: [
                        MealItem(
                            label: "salmon don",
                            grams: 400,
                            per100g: Nutrients(protein: 9, fat: 2.25, carbohydrate: 12, kcal: kcal / 4)
                        )
                    ]
                )
            ],
            source: .photo
        )
    }

    // MARK: An event from a newer build

    /// A line whose `kind` this build does not know must survive a read, a
    /// write, and another read without changing by one byte. The previous log
    /// set such a line aside as unreadable, which paused cloud reconciliation
    /// for the whole app and made adding an event kind a breaking change.
    @Test("A kind from a newer build round-trips byte for byte")
    func unknownKindSurvives() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)

        // Deliberately awkward: unsorted keys, a trailing zero, an escape, and
        // a field no build has ever seen.
        let future = #"""
        {"id":"018F3A5E-0000-7000-8000-000000000001","occurredAt":1754899200000,"recordedAt":1754899200000,"payload":{"kind":"mood_noted","data":{"scale":1.0,"note":"café","tags":["b","a"]}}}
        """#

        try await log.append(meal(at: 1_754_899_100_000).asEvent())
        try Data((future + "\n").utf8).append(to: url)

        let loaded = try await log.load()
        #expect(loaded.corrupt.isEmpty)
        #expect(loaded.events.count == 2)
        #expect(loaded.fromNewerBuild == 1)

        let retained = try #require(loaded.events.first { $0.payload.isUnrecognized })
        #expect(retained.payload.kind == "mood_noted")
        // The envelope was read even though the body was not.
        #expect(retained.occurredAt == 1_754_899_200_000)

        // And it writes back identically.
        let rewritten = try EventCodec().line(for: retained)
        #expect(rewritten.text == future)
    }

    /// The failure this is most likely to become: an event nobody can read
    /// quietly counting towards the number on the home screen.
    @Test("An unreadable event counts for nothing and appears nowhere")
    func unknownKindFoldsToNothing() throws {
        let line = try RawJSON(validating: #"""
        {"id":"018F3A5E-0000-7000-8000-000000000002","occurredAt":1754899200000,"recordedAt":1754899200000,"payload":{"kind":"period_started","data":{"day":"2026-08-11"}}}
        """#)
        let event = try EventCodec().event(from: line)

        var projection = Projection()
        projection.apply(event)

        #expect(projection.meals.isEmpty)
        #expect(projection.messages.isEmpty)

        let day = Date(epochMillis: 1_754_899_200_000)
        #expect(projection.meals(on: day).isEmpty)
        #expect(projection.daysLogged(90, endingAt: day) == 0)
        #expect(projection.nutrients(on: day) == .zero)
    }

    /// New is not the same as broken, and only one of them may stop the app.
    @Test("Corrupt means corrupt, not merely newer")
    func corruptIsDistinctFromUnknown() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        try await log.append(meal(at: 1_754_899_100_000).asEvent())
        try Data("{not json at all\n".utf8).append(to: url)
        try Data(#"{"id":"nope"}"# .utf8 + Data("\n".utf8)).append(to: url)

        let loaded = try await log.load()
        #expect(loaded.corrupt.count == 2)
        #expect(loaded.understood.count == 1)
        #expect(loaded.fromNewerBuild == 0)
    }

    /// The version is on every meal line, and a meal written in another shape
    /// is refused rather than guessed at. That is a corrupt line, not a newer
    /// one: newer kinds are retained, but a known kind whose body this build
    /// cannot vouch for stops reconciliation until someone looks.
    @Test("New meals carry schemaVersion 2; version 1 remains readable")
    func schemaVersionIsWrittenAndChecked() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        try await log.append(meal(at: 1_754_899_100_000).asEvent())
        let line = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        #expect(line.contains(#""schemaVersion":2"#))

        let legacy = line.replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":1"#)
        try Data(legacy.utf8).append(to: url)
        let unsupported = line.replacingOccurrences(of: #""schemaVersion":2"#, with: #""schemaVersion":3"#)
        try Data(unsupported.utf8).append(to: url)
        // Key order is the encoder's business, so strip the key wherever it sits.
        let unversioned = line.contains(#""schemaVersion":2,"#)
            ? line.replacingOccurrences(of: #""schemaVersion":2,"#, with: "")
            : line.replacingOccurrences(of: #","schemaVersion":2"#, with: "")
        #expect(!unversioned.contains("schemaVersion"))
        try Data(unversioned.utf8).append(to: url)

        let loaded = try await log.load()
        #expect(loaded.understood.count == 2)
        #expect(loaded.corrupt.count == 2)
        #expect(loaded.fromNewerBuild == 0)
    }

    @Test("Version-one sizes are ignored and missing forks become empty")
    func legacySizesDecodeWithoutInventingForks() throws {
        let event = meal(at: 1_754_899_100_000).asEvent()
        let codec = EventCodec()
        let current = try codec.line(for: event).text
        let versionOne = current.replacingOccurrences(
            of: #""schemaVersion":2"#,
            with: #""schemaVersion":1"#
        )
        let legacy = versionOne.replacingOccurrences(
            of: #""forks":[]"#,
            with: #""sizes":[{"retired":true}]"#
        )
        #expect(legacy.contains(#""sizes""#))
        #expect(!legacy.contains(#""forks""#))

        let decoded = try codec.event(from: try RawJSON(validating: legacy))
        guard case .mealLogged(let restored) = decoded.payload else {
            Issue.record("Expected a restored meal")
            return
        }
        guard case .mealLogged(let original) = event.payload else {
            Issue.record("Expected the fixture to be a meal")
            return
        }
        #expect(restored.items.allSatisfy { $0.forks.isEmpty })
        #expect(restored.nutrients == original.nutrients)
    }

    @Test("An unknown preparation or provenance is refused, not rounded to a plausible one")
    func unknownEnumsThrow() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([PreparationMethod].self, from: Data(#"["sous_vide"]"#.utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([NutrientSource].self, from: Data(#"["table"]"#.utf8))
        }
    }

    @Test("Pulled lines are appended verbatim, once, and a line already held is skipped")
    func pulledLinesUnion() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        let mine = meal(at: 1_754_899_100_000).asEvent()
        try await log.append(mine)
        let mineLine = try #require(String(data: Data(contentsOf: url), encoding: .utf8)).trimmingCharacters(in: .newlines)

        let theirs = """
        {"id":"019905a0-2f3a-7c1e-8b6c-0f2c9a1d5e77","occurredAt":1786788000000,"recordedAt":1786788012345,"payload":{"kind":"mood_noted","data":{"z":1.0,"a":9007199254740993}}}
        """
        let added = try await log.append(lines: [
            try RawJSON(validating: mineLine),
            try RawJSON(validating: theirs),
            try RawJSON(validating: theirs)
        ])
        #expect(added.count == 1)
        #expect(added.first?.payload.isUnrecognized == true)

        let text = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        #expect(text == mineLine + "\n" + theirs + "\n")
        let loaded = try await log.load()
        #expect(loaded.events.count == 2)
        #expect(loaded.fromNewerBuild == 1)
        #expect(loaded.corrupt.isEmpty)
    }

    // MARK: Ordering and folding

    @Test("A revision supersedes the entry it corrects, by write order")
    func revisionWins() throws {
        let original = meal(kcal: 400, at: 1_754_899_200_000)
        var corrected = original
        corrected.dishes[0].items[0].label = "salmon and tuna don"
        corrected.wasCorrected = true

        let projection = Projection(replaying: [
            LoggedEvent(occurredAt: original.eatenAt, recordedAt: 100, payload: .mealLogged(original)),
            LoggedEvent(occurredAt: original.eatenAt, recordedAt: 200, payload: .mealRevised(corrected))
        ])

        #expect(projection.meals.count == 1)
        #expect(projection.meals[original.id]?.items.first?.label == "salmon and tuna don")
        #expect(projection.meals[original.id]?.wasCorrected == true)
    }

    @Test("A batch splices a retained line beside an encoded one")
    func batchSplices() throws {
        let codec = EventCodec()
        let known = meal(at: 1_754_899_200_000).asEvent()
        let unknown = try codec.event(from: RawJSON(validating: #"""
        {"id":"018F3A5E-0000-7000-8000-000000000003","occurredAt":1,"recordedAt":1,"payload":{"kind":"whatever","data":{"x":1.0}}}
        """#))

        let batch = try codec.batch(deviceID: "device-abc", events: [known, unknown])
        // Valid JSON, and the retained line went in untouched — including the
        // `1.0` that any re-serialisation would have written as `1`.
        _ = try RawJSON(validating: batch.bytes)
        #expect(batch.text.contains(#""x":1.0"#))
        #expect(batch.text.contains(#""deviceId":"device-abc""#))
    }
}

// MARK: - Test helpers

private extension MealEntry {
    func asEvent() -> LoggedEvent {
        LoggedEvent(occurredAt: eatenAt, payload: .mealLogged(self))
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
