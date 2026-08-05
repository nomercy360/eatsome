import ShamanCore
import SwiftUI

/// How a stored meal is named in a list.
enum MealDisplay {
    /// The dish, not its parts. "Greek yoghurt" is what you logged; "Dairy ·
    /// Fruit · Nuts" is what it counted as, and that belongs on the line below.
    static func title(_ meal: MealEntry) -> String {
        let labels = meal.items.compactMap(\.label).filter { !$0.isEmpty }
        if let first = labels.first { return first.capitalizedFirst }
        return uniqueGroups(meal).first?.plainName ?? "Meal"
    }

    /// Time of day, then what the plate held — the two things that tell you
    /// which meal this was without opening it.
    static func subtitle(_ meal: MealEntry, calendar: Calendar = .current) -> String {
        var parts = [partOfDay(meal, calendar: calendar)]
        let foods = uniqueGroups(meal).prefix(3).map(\.sentenceName).joined(separator: ", ")
        if !foods.isEmpty { parts.append(foods) }
        // A half-counted meal looks identical to a whole one otherwise, and the
        // difference is the whole point of the switch.
        if meal.eaten == .part { parts.append("ate half") }
        return parts.joined(separator: " · ")
    }

    static func partOfDay(_ meal: MealEntry, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: Date(epochMillis: meal.eatenAt)) {
        case ..<11: "Morning"
        case ..<16: "Lunch"
        case ..<21: "Evening"
        default: "Late"
        }
    }

    static func uniqueGroups(_ meal: MealEntry) -> [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meal.items.map(\.group).filter { seen.insert($0).inserted }
    }
}

extension String {
    /// Model labels arrive lowercase; a list row wants a capital and a sentence
    /// does not. `localizedCapitalized` would also capitalise "Toast" in "french
    /// toast", which is wrong.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

/// A row identity a `sheet(item:)` can key on. `UUID` is not `Identifiable`,
/// and making it so app-wide to satisfy one presentation would be a strange
/// thing to find later.
struct EditingFood: Identifiable, Hashable {
    let id: UUID
}

/// The photograph, or a stand-in that does not pretend to be one.
struct MealThumbnail: View {
    let meal: MealEntry
    var side: CGFloat = 56
    var radius: CGFloat = 18

    var body: some View {
        Group {
            if let photo = PhotoStore.shared.image(for: meal.photoHash) {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                WellieTheme.ice.overlay {
                    Image(systemName: meal.source == .recipe ? "text.book.closed.fill" : "fork.knife")
                        .font(.system(size: side * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(WellieTheme.blue)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The full-width photo at the top of capture, detail, and the failure state.
struct MealPhotoBanner: View {
    let image: UIImage?
    var height: CGFloat = 200
    var trailing: AnyView?

    var body: some View {
        RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
            .fill(WellieTheme.ice)
            .frame(height: height)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(WellieTheme.faint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            .overlay(alignment: .bottomTrailing) { trailing?.padding(14) }
    }
}

enum WeightFormat {
    static var usesMetric: Bool { Locale.current.measurementSystem == .metric }
    static var unit: String { usesMetric ? "kg" : "lb" }
    static var unitName: String { usesMetric ? "Kilograms" : "Pounds" }

    static func value(_ kilograms: Double) -> Double {
        usesMetric ? kilograms : kilograms * 2.204_622_621_8
    }

    static func string(_ kilograms: Double) -> String {
        "\(value(kilograms).formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}

/// A change with a direction and no opinion about it.
///
/// Deliberately not coloured green or red: down is not always good on weight and
/// up is not always an achievement on sleep. The arrow says which way, the
/// number says how far, and the judgement stays with the person.
struct Delta {
    let text: String
    let isUp: Bool
    let caption: String
}

/// Small numbers are words in this app's sentences — "Three meals", "Six of the
/// last seven days" — because a digit mid-sentence reads as data and the point
/// of the sentence is that it is not.
enum Count {
    static func spell(_ value: Int, capitalized: Bool = true) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
                     "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        guard value >= 0, value < words.count else { return "\(value)" }
        return capitalized ? words[value] : words[value].lowercased()
    }

    static func meals(_ value: Int) -> String {
        value == 1 ? "One meal" : "\(spell(value)) meals"
    }
}

enum DayFormat {
    /// "Today", "Yesterday", then "Monday 3" the way the history screen labels
    /// its cards.
    static func title(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day())
    }

    static func initials(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        return day.formatted(.dateTime.weekday(.abbreviated))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
