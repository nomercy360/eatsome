import Foundation

/// When in the day a meal happened, coarsely.
///
/// Two jobs, which is why it is a type rather than a `switch` in a view. It
/// labels a meal card ("Breakfast · 8:00"), and it is the bucket the repeat-dish
/// chips are ranked within — lentil soup is a lunch, and offering it at 8 am
/// because it is your most-logged dish would be a worse suggestion than offering
/// nothing.
///
/// Six buckets, five names: mid-morning and afternoon are both "Snack" out loud,
/// because that is what a person calls food at 11 am and at 4 pm. They stay
/// separate underneath because for ranking they genuinely are — an 11 am yoghurt
/// and a 4 pm biscuit are not the same habit.
public enum Daypart: String, Codable, Sendable, CaseIterable, Hashable {
    case breakfast
    case midMorning
    case lunch
    case afternoon
    case dinner
    /// After 11 pm, and before 4 am — which is the same eating occasion seen
    /// from either side of midnight, so they share a bucket rather than
    /// splitting one habit across the ends of the list.
    case late

    public init(hour: Int) {
        switch hour {
        case 4..<11: self = .breakfast
        case 11..<12: self = .midMorning
        case 12..<15: self = .lunch
        case 15..<18: self = .afternoon
        case 18..<23: self = .dinner
        default: self = .late
        }
    }

    public init(at time: EpochMillis, calendar: Calendar = .current) {
        self.init(hour: calendar.component(.hour, from: Date(epochMillis: time)))
    }

    public var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .midMorning, .afternoon: "Snack"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .late: "Late"
        }
    }
}
