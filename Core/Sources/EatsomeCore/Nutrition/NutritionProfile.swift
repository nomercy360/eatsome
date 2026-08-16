import Foundation

/// The inputs needed to turn population nutrition references into a personal
/// daily estimate. Every value is optional because Apple Health may answer only
/// some of them, and a missing input must produce no calorie estimate rather
/// than a plausible-looking default.
public struct NutritionProfile: Codable, Sendable, Equatable {
    /// The adult 2023 DRI equations are sex-specific. This asks which published
    /// equation to use; it is not a claim about identity.
    public enum ReferenceSex: String, Codable, Sendable, CaseIterable {
        case female
        case male

        public var displayName: String {
            switch self {
            case .female: "Female reference"
            case .male: "Male reference"
            }
        }
    }

    /// Physical activity level categories used by the 2023 Dietary Reference
    /// Intake equations for energy.
    public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
        case inactive
        case lowActive
        case active
        case veryActive

        public var displayName: String {
            switch self {
            case .inactive: "Inactive"
            case .lowActive: "Low active"
            case .active: "Active"
            case .veryActive: "Very active"
            }
        }

        public var detail: String {
            switch self {
            case .inactive: "Daily living, with little activity beyond it"
            case .lowActive: "Daily living plus regular walking"
            case .active: "Purposeful exercise most days"
            case .veryActive: "Hard training or physical work most days"
            }
        }

        /// Midpoints of the PAL examples published with the adult equations.
        public var approximatePAL: Double {
            switch self {
            case .inactive: 1.4
            case .lowActive: 1.6
            case .active: 1.75
            case .veryActive: 2.05
            }
        }

        public static func inferred(fromPAL pal: Double) -> ActivityLevel {
            switch pal {
            case ..<1.53: .inactive
            case ..<1.68: .lowActive
            case ..<1.85: .active
            default: .veryActive
            }
        }
    }

    public enum Goal: String, Codable, Sendable, CaseIterable {
        case maintain
        case loseWeight
        case gainMuscle

        public var displayName: String {
            switch self {
            case .maintain: "Keep my weight"
            case .loseWeight: "Lose weight"
            case .gainMuscle: "Gain muscle"
            }
        }

        public var detail: String {
            switch self {
            case .maintain: "Use estimated maintenance energy"
            case .loseWeight: "Plan a moderate energy deficit"
            case .gainMuscle: "Plan a small surplus and higher protein"
            }
        }
    }

    public var ageYears: Int?
    public var referenceSex: ReferenceSex?
    public var heightCentimeters: Double?
    public var weightKilograms: Double?
    /// A percentage from 0 to 100. Optional and not used by the DRI energy
    /// equation; it is retained to show approximate lean mass.
    public var bodyFatPercentage: Double?
    public var activityLevel: ActivityLevel?
    public var goal: Goal?

    public init(
        ageYears: Int? = nil,
        referenceSex: ReferenceSex? = nil,
        heightCentimeters: Double? = nil,
        weightKilograms: Double? = nil,
        bodyFatPercentage: Double? = nil,
        activityLevel: ActivityLevel? = nil,
        goal: Goal? = nil
    ) {
        self.ageYears = ageYears
        self.referenceSex = referenceSex
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.bodyFatPercentage = bodyFatPercentage
        self.activityLevel = activityLevel
        self.goal = goal
    }

    /// The published adult equations begin at 19. Upper bounds keep accidental
    /// years and unit mistakes from becoming health guidance.
    public var hasValidBodyInputs: Bool {
        guard let ageYears, 19...120 ~= ageYears,
              let heightCentimeters, 120...230 ~= heightCentimeters,
              let weightKilograms, 35...350 ~= weightKilograms,
              referenceSex != nil
        else { return false }
        return true
    }

    public var isComplete: Bool {
        hasValidBodyInputs && activityLevel != nil && goal != nil
    }

    public var bodyMassIndex: Double? {
        guard let heightCentimeters, let weightKilograms, heightCentimeters > 0 else { return nil }
        let metres = heightCentimeters / 100
        return weightKilograms / (metres * metres)
    }

    public var leanMassKilograms: Double? {
        guard let weightKilograms, let bodyFatPercentage,
              2...70 ~= bodyFatPercentage
        else { return nil }
        return weightKilograms * (1 - bodyFatPercentage / 100)
    }
}
