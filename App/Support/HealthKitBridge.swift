import EatsomeCore
import Foundation
import HealthKit

/// What Health can fill in for you, and nothing else.
///
/// One shape, and it is the profile — every field optional, because a denial is
/// indistinguishable from having no samples and both have to come back as
/// absent rather than as a number.
struct HealthProfileSnapshot: Sendable {
    var ageYears: Int? = nil
    var referenceSex: NutritionProfile.ReferenceSex? = nil
    var heightCentimeters: Double? = nil
    var weightKilograms: Double? = nil
    var bodyFatPercentage: Double? = nil
    var activityLevel: NutritionProfile.ActivityLevel? = nil

    var isEmpty: Bool {
        ageYears == nil
            && referenceSex == nil
            && heightCentimeters == nil
            && weightKilograms == nil
            && bodyFatPercentage == nil
            && activityLevel == nil
    }

    static let empty = HealthProfileSnapshot()
}

/// Read-only access to what Apple Watch, smart scales and the Health app have
/// already collected. HealthKit stays the source of truth; nothing read here is
/// ever copied into the append-only meal log.
///
/// **What Health knows about your body is read; what it knows about your day is
/// not.** Workouts and sleep were read here and drawn beside the meals; they
/// are gone, along with the authorization for them. Energy stays, because the
/// activity reference is *inferred* from it — which is a property of a body,
/// not an entry in a timeline.
///
/// A weight *history* is gone with them, for the same kind of reason: the
/// profile wants one figure, the trend screen has no weight series and no way
/// to get one, and a year of samples read to display a dash was work in aid of
/// a tile that could never say anything.
actor HealthKitBridge {
    static let shared = HealthKitBridge()

    enum BridgeError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Health data is not available on this device."
        }
    }

    private let store = HKHealthStore()

    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var heightType: HKQuantityType { HKQuantityType(.height) }
    private var bodyFatType: HKQuantityType { HKQuantityType(.bodyFatPercentage) }
    private var activeEnergyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private var basalEnergyType: HKQuantityType { HKQuantityType(.basalEnergyBurned) }
    private var dateOfBirthType: HKCharacteristicType { HKCharacteristicType(.dateOfBirth) }
    private var biologicalSexType: HKCharacteristicType { HKCharacteristicType(.biologicalSex) }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw BridgeError.unavailable }
        let readTypes: Set<HKObjectType> = [
            weightType,
            heightType,
            bodyFatType,
            activeEnergyType,
            basalEnergyType,
            dateOfBirthType,
            biologicalSexType
        ]
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Everything at once, so filling the profile in is one prompt and one
    /// wait rather than six.
    ///
    /// Nothing here throws on an empty answer. Read authorization is
    /// privacy-preserving by design — a refusal looks exactly like a person who
    /// has never stood on a scale — so a caller must never read a full snapshot
    /// as proof that access was granted.
    func loadProfile(now: Date = Date(), calendar: Calendar = .current) async throws -> HealthProfileSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else { throw BridgeError.unavailable }

        let weightStart = calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86_400)
        let heightStart = calendar.date(byAdding: .year, value: -20, to: now) ?? now.addingTimeInterval(-20 * 365 * 86_400)
        let bodyFatStart = calendar.date(byAdding: .year, value: -2, to: now) ?? now.addingTimeInterval(-2 * 365 * 86_400)
        let activityStart = calendar.date(byAdding: .day, value: -35, to: now) ?? now.addingTimeInterval(-35 * 86_400)

        async let weights: [HKQuantitySample] = samples(of: weightType, startingAt: weightStart, limit: 1)
        async let heights: [HKQuantitySample] = samples(of: heightType, startingAt: heightStart, limit: 1)
        async let bodyFat: [HKQuantitySample] = samples(of: bodyFatType, startingAt: bodyFatStart, limit: 1)
        async let activeEnergy: [HKQuantitySample] = samples(of: activeEnergyType, startingAt: activityStart)
        async let basalEnergy: [HKQuantitySample] = samples(of: basalEnergyType, startingAt: activityStart)

        return HealthProfileSnapshot(
            ageYears: age(now: now, calendar: calendar),
            referenceSex: referenceSex(),
            heightCentimeters: try await heights.first?.quantity.doubleValue(for: .meterUnit(with: .centi)),
            weightKilograms: try await weights.first?.quantity.doubleValue(for: .gramUnit(with: .kilo)),
            bodyFatPercentage: try await bodyFat.first.map { $0.quantity.doubleValue(for: .percent()) * 100 },
            activityLevel: Self.inferredActivity(
                activeEnergy: try await activeEnergy,
                basalEnergy: try await basalEnergy,
                now: now,
                calendar: calendar
            )
        )
    }

    private func age(now: Date, calendar: Calendar) -> Int? {
        guard let components = try? store.dateOfBirthComponents(),
              let birthday = calendar.date(from: components)
        else { return nil }
        return calendar.dateComponents([.year], from: birthday, to: now).year
    }

    private func referenceSex() -> NutritionProfile.ReferenceSex? {
        guard let sex = try? store.biologicalSex().biologicalSex else { return nil }
        switch sex {
        case .female: return .female
        case .male: return .male
        default: return nil
        }
    }

    /// Newest first. `limit` is 1 for the three fields where only the latest
    /// sample is wanted — a year of weights read to keep one of them is a year
    /// of samples decoded for nothing.
    private func samples<T: HKSample>(
        of type: HKSampleType,
        startingAt start: Date,
        limit: Int = HKObjectQueryNoLimit
    ) async throws -> [T] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
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

    /// PAL is total energy expenditure divided by basal expenditure. Health can
    /// supply both sides when a watch has enough complete days. The median of at
    /// least seven avoids one long workout choosing a person's permanent
    /// category; below seven this answers nil and the sheet asks them.
    private static func inferredActivity(
        activeEnergy: [HKQuantitySample],
        basalEnergy: [HKQuantitySample],
        now: Date,
        calendar: Calendar
    ) -> NutritionProfile.ActivityLevel? {
        let today = calendar.startOfDay(for: now)

        func totals(_ samples: [HKQuantitySample]) -> [Date: Double] {
            samples.reduce(into: [:]) { result, sample in
                guard sample.startDate < today else { return }
                let day = calendar.startOfDay(for: sample.startDate)
                result[day, default: 0] += sample.quantity.doubleValue(for: .kilocalorie())
            }
        }

        let active = totals(activeEnergy)
        let basal = totals(basalEnergy)
        let ratios = basal.compactMap { day, resting -> Double? in
            guard resting >= 500, let moving = active[day] else { return nil }
            return (resting + max(0, moving)) / resting
        }
        .sorted()

        guard ratios.count >= 7 else { return nil }
        let middle = ratios.count / 2
        let median = ratios.count.isMultiple(of: 2)
            ? (ratios[middle - 1] + ratios[middle]) / 2
            : ratios[middle]
        return NutritionProfile.ActivityLevel.inferred(fromPAL: median)
    }
}
