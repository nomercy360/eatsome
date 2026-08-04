import Foundation
import HealthKit
import ShamanCore

/// Mirrors finished sets into HealthKit.
///
/// Worth the hour it costs: rings, streaks, and a history that outlives this
/// app come for free, and none of it has to be built or maintained here.
actor HealthKitBridge {
    static let shared = HealthKitBridge()

    private let store = HKHealthStore()
    private var authorized = false

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types: Set = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned)
        ]
        do {
            try await store.requestAuthorization(toShare: types, read: [])
            authorized = true
            return true
        } catch {
            return false
        }
    }

    func save(_ record: SetRecord, config: AppConfig) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !authorized, await !requestAuthorization() { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = Self.activityType(for: record.movementID)

        let start = Date(epochMillis: record.startedAt)
        let end = Date(epochMillis: record.finishedAt)
        // A one-rep "workout" is noise in Health; only whole sets go across.
        guard end > start else { return }

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                "ShamanMovement": record.movementID,
                "ShamanReps": record.reps,
                "ShamanTrackingQuality": record.trackingQuality
            ])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Losing a HealthKit mirror is not worth losing the set over — the
            // event log already has it.
        }
    }

    private static func activityType(for movementID: String) -> HKWorkoutActivityType {
        switch movementID {
        case "plank": .coreTraining
        case "jumping_jack": .highIntensityIntervalTraining
        default: .functionalStrengthTraining
        }
    }
}
