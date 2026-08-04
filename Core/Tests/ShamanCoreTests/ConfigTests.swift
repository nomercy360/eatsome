import Foundation
import Testing
@testable import ShamanCore

@Suite("Configuration")
struct ConfigTests {
    @Test("The bundled config decodes and matches the compiled defaults")
    func bundledConfigIsValid() throws {
        let url = try #require(
            Bundle.module.url(forResource: "shaman-config", withExtension: "json"),
            "shaman-config.json is missing from the target resources"
        )
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))

        #expect(config.movements.map(\.id) == AppConfig.fallback.movements.map(\.id))
        #expect(config.recognition.model == "gpt-5.6-luna")
        #expect(config.medas.windowDays == 7)
        #expect(config.medas.excludedItems == [8])
    }

    @Test("Config survives a round trip")
    func roundTrip() throws {
        let data = try JSONEncoder().encode(AppConfig.fallback)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.movements == AppConfig.fallback.movements)
        #expect(decoded.medas == AppConfig.fallback.medas)
    }

    @Test("Joints and metrics serialise as readable names")
    func humanReadableEncoding() throws {
        let squat = try #require(AppConfig.fallback.movement(id: "squat"))
        let json = try #require(String(data: try JSONEncoder().encode(squat), encoding: .utf8))

        #expect(json.contains("\"leftKnee\""), "joints must round-trip as names, not indices")
        #expect(json.contains("\"joint_angle\""))
        #expect(!json.contains("\"_0\""), "no synthesized associated-value keys in a hand-edited file")
    }

    @Test("An unknown joint name is rejected rather than silently defaulted")
    func rejectsUnknownJoint() {
        let json = #"{"type":"joint_angle","a":"leftHip","vertex":"kneecap","b":"leftAnkle","side":"both"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MovementMetric.self, from: Data(json.utf8))
        }
    }

    @Test("Loader falls back to the bundle when there is no remote and no cache")
    func fallsBackToBundle() async {
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("shaman-config-\(UUID().uuidString)")
            .appendingPathComponent("config.json")
        let loader = ConfigLoader(remoteURL: nil, cacheURL: cache)
        let (config, source) = await loader.load()

        #expect(source == .bundle)
        #expect(config.movements.count == AppConfig.fallback.movements.count)
    }

    @Test("Every built-in movement has a usable hysteresis band")
    func movementsAreWellFormed() {
        for movement in AppConfig.fallback.movements {
            #expect(movement.lowThreshold < movement.highThreshold, "\(movement.id) has no dead band")
            #expect(movement.minRepIntervalMillis > 0, "\(movement.id) has no debounce")
            #expect(!movement.requiredJoints.isEmpty, "\(movement.id) would count with the user out of frame")
            #expect(!movement.coachingCue.isEmpty, "\(movement.id) has no camera-placement hint")
        }
    }
}
