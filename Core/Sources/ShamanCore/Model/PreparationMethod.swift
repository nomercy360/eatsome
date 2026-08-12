import Foundation

/// How a food was cooked, when the input said so.
///
/// All that survives of the v20 taxonomy. It drives no calculation — the
/// composition figures on a `MealItem` already price the food as prepared — and
/// exists so the correction sheet can ask "grilled or fried?" with chips rather
/// than free text. If that question ever goes, so does this.
public enum PreparationMethod: String, Codable, CaseIterable, Sendable, Hashable {
    case raw, boiled, steamed, baked, roasted, grilled
    case panFried = "pan_fried"
    case deepFried = "deep_fried"
    case smoked, cured, fermented, dried

    public var displayName: String {
        switch self {
        case .panFried: "Pan-fried"
        case .deepFried: "Deep-fried"
        default: rawValue.capitalized
        }
    }

    /// An unknown method is one written by a newer build. A meal that will not
    /// decode vanishes from the projection; a dropped adjective does not.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PreparationMethod(rawValue: raw) ?? .raw
    }
}
