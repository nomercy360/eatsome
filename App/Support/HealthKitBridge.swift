import Foundation
import HealthKit

struct ImportedWorkout: Identifiable, Sendable {
    let id: UUID
    let name: String
    let startedAt: Date
    let endedAt: Date
    let sourceName: String

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

struct SleepSummary: Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let asleep: TimeInterval
    let inBed: TimeInterval
    let awake: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    let sourceNames: [String]
}

struct WeightMeasurement: Identifiable, Sendable {
    let id: UUID
    let measuredAt: Date
    let kilograms: Double
    let sourceName: String
}

struct HealthSnapshot: Sendable {
    var workouts: [ImportedWorkout] = []
    var sleep: [SleepSummary] = []
    var weights: [WeightMeasurement] = []

    static let empty = HealthSnapshot()
}

/// Read-only access to the health data already collected by Apple Watch,
/// smart scales, and the Health app. HealthKit remains the source of truth;
/// imported samples are not copied into eatsome's event log.
actor HealthKitBridge {
    static let shared = HealthKitBridge()

    enum BridgeError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Health data is not available on this device."
        }
    }

    private let store = HKHealthStore()

    private var workoutType: HKWorkoutType { HKObjectType.workoutType() }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw BridgeError.unavailable }
        let readTypes: Set<HKObjectType> = [workoutType, sleepType, weightType]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func loadSnapshot(now: Date = Date(), calendar: Calendar = .current) async throws -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else { throw BridgeError.unavailable }

        let workoutStart = calendar.date(byAdding: .day, value: -90, to: now) ?? now.addingTimeInterval(-90 * 86_400)
        let sleepStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let weightStart = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)

        async let workouts: [HKWorkout] = samples(of: workoutType, startingAt: workoutStart)
        async let sleep: [HKCategorySample] = samples(of: sleepType, startingAt: sleepStart)
        async let weights: [HKQuantitySample] = samples(of: weightType, startingAt: weightStart)

        return try await HealthSnapshot(
            workouts: Self.mapWorkouts(workouts),
            sleep: Self.summarizeSleep(sleep),
            weights: Self.mapWeights(weights)
        )
    }

    private func samples<T: HKSample>(of type: HKSampleType, startingAt start: Date) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [T] ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func mapWorkouts(_ samples: [HKWorkout]) -> [ImportedWorkout] {
        samples.map {
            ImportedWorkout(
                id: $0.uuid,
                name: workoutName($0.workoutActivityType),
                startedAt: $0.startDate,
                endedAt: $0.endDate,
                sourceName: $0.sourceRevision.source.name
            )
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Walking"
        case .running: "Running"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .coreTraining: "Core training"
        case .functionalStrengthTraining: "Functional strength"
        case .traditionalStrengthTraining: "Strength training"
        case .highIntensityIntervalTraining: "HIIT"
        case .crossTraining: "Cross training"
        case .mixedCardio: "Mixed cardio"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing: "Stair climbing"
        case .dance: "Dance"
        case .mindAndBody: "Mind and body"
        default: "Workout"
        }
    }

    private static func mapWeights(_ samples: [HKQuantitySample]) -> [WeightMeasurement] {
        samples.map {
            WeightMeasurement(
                id: $0.uuid,
                measuredAt: $0.startDate,
                kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                sourceName: $0.sourceRevision.source.name
            )
        }
        .sorted { $0.measuredAt > $1.measuredAt }
    }

    private static func summarizeSleep(_ samples: [HKCategorySample]) -> [SleepSummary] {
        let sorted = samples
            .filter { $0.endDate > $0.startDate }
            .sorted { $0.startDate < $1.startDate }
        guard !sorted.isEmpty else { return [] }

        // A long in-bed interval overlaps all of its stage samples. Clustering
        // intervals that overlap or are close together keeps an overnight sleep
        // together while leaving daytime naps as separate sessions.
        var sessions: [[HKCategorySample]] = []
        var current: [HKCategorySample] = []
        var currentEnd = Date.distantPast
        let maximumGap: TimeInterval = 3 * 3_600

        for sample in sorted {
            if !current.isEmpty, sample.startDate.timeIntervalSince(currentEnd) > maximumGap {
                sessions.append(current)
                current = []
                currentEnd = .distantPast
            }
            current.append(sample)
            if sample.endDate > currentEnd { currentEnd = sample.endDate }
        }
        if !current.isEmpty { sessions.append(current) }

        return sessions.compactMap { session in
            let watchStages = session.filter { isWatchSample($0) && isAsleep($0) }
            let sleepSamples = watchStages.isEmpty ? session.filter(isAsleep) : watchStages
            guard let first = sleepSamples.first else { return nil }

            let start = sleepSamples.map(\.startDate).min() ?? first.startDate
            let end = sleepSamples.map(\.endDate).max() ?? first.endDate
            let asleep = unionDuration(sleepSamples.map { ($0.startDate, $0.endDate) })
            guard asleep > 0 else { return nil }

            return SleepSummary(
                id: first.uuid,
                startedAt: start,
                endedAt: end,
                asleep: asleep,
                inBed: duration(of: .inBed, in: session),
                awake: duration(of: .awake, in: session),
                core: duration(of: .asleepCore, in: sleepSamples),
                deep: duration(of: .asleepDeep, in: sleepSamples),
                rem: duration(of: .asleepREM, in: sleepSamples),
                sourceNames: Array(Set(session.map { $0.sourceRevision.source.name })).sorted()
            )
        }
        .sorted { $0.endedAt > $1.endedAt }
    }

    private static func isWatchSample(_ sample: HKSample) -> Bool {
        if sample.sourceRevision.productType?.lowercased().hasPrefix("watch") == true { return true }
        return sample.device?.model?.localizedCaseInsensitiveContains("watch") == true
    }

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
    }

    private static func duration(
        of value: HKCategoryValueSleepAnalysis,
        in samples: [HKCategorySample]
    ) -> TimeInterval {
        let intervals = samples.compactMap { sample -> (Date, Date)? in
            guard sample.value == value.rawValue else { return nil }
            return (sample.startDate, sample.endDate)
        }
        return unionDuration(intervals)
    }

    /// Multiple HealthKit sources can describe the same interval. Taking the
    /// union avoids double-counting overlapping samples.
    private static func unionDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        guard var active = sorted.first else { return 0 }
        var total: TimeInterval = 0

        for interval in sorted.dropFirst() {
            if interval.0 <= active.1 {
                if interval.1 > active.1 { active.1 = interval.1 }
            } else {
                total += active.1.timeIntervalSince(active.0)
                active = interval
            }
        }
        total += active.1.timeIntervalSince(active.0)
        return total
    }
}
