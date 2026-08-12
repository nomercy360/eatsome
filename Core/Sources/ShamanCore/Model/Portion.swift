import Foundation

/// Legacy coarse quantity retained so development logs written before weighed
/// ingredients still decode. New recognition reports grams only.
public enum Portion: String, Codable, CaseIterable, Sendable, Hashable {
    case small
    case medium
    case large

    public var servings: Double {
        switch self {
        case .small: 0.5
        case .medium: 1.0
        case .large: 2.0
        }
    }

    public var plainName: String {
        switch self {
        case .small: "A little"
        case .medium: "Normal"
        case .large: "A lot"
        }
    }
}
