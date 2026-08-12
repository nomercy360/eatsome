import ShamanCore
import SwiftUI

/// How a stored meal is named in a list.
enum MealDisplay {
    /// The dish, not its parts. "French toast" is what you logged; "bread" is
    /// its first ingredient, and an ingredient label naming the card is how a
    /// plate of french toast came to be titled "Bread". A dish assembled by
    /// hand has no name, and falls back to what is in it.
    static func title(_ meal: MealEntry) -> String {
        let dishNames = meal.dishes
            .compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = dishNames.first {
            let title = first.capitalizedFirst
            return dishNames.count > 1 ? "\(title) +\(dishNames.count - 1)" : title
        }
        if let first = meal.items.map(\.label).first(where: { !$0.isEmpty }) {
            return first.capitalizedFirst
        }
        return "Meal"
    }

    /// Time of day, then what the plate held — the two things that tell you
    /// which meal this was without opening it.
    static func subtitle(_ meal: MealEntry, calendar: Calendar = .current) -> String {
        var parts = [partOfDay(meal, calendar: calendar)]
        let foods = uniqueGroups(meal).prefix(3).joined(separator: ", ")
        if !foods.isEmpty { parts.append(foods) }
        // A half-counted meal looks identical to a whole one otherwise, and the
        // difference is the whole point of the switch.
        if meal.eaten == .part { parts.append("ate half") }
        return parts.joined(separator: " · ")
    }

    static func partOfDay(_ meal: MealEntry, calendar: Calendar = .current) -> String {
        Daypart(at: meal.eatenAt, calendar: calendar).displayName
    }

    /// "Breakfast · 8:00" — the meal card's second line in the thread.
    ///
    /// The clock time is there because the thread's own timestamps are when you
    /// *sent* the message, and those are routinely not when you ate: the whole
    /// point of "half a kebab at 2 am" is that it is being logged later.
    static func whenAndWhat(_ meal: MealEntry, calendar: Calendar = .current) -> String {
        let time = Date(epochMillis: meal.eatenAt)
            .formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        return "\(partOfDay(meal, calendar: calendar)) · \(time)"
    }

    /// What was on it, as a phrase: "Bread, banana ×2, syrup".
    ///
    /// Counted rather than deduplicated, because two rows of the same food on
    /// one plate is a fact about the plate — a glass of milk beside a yoghurt —
    /// and the line under a meal card is the only place it is visible without
    /// opening it.
    static func counted(_ meal: MealEntry) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for label in meal.items.map({ $0.label.lowercased() }) {
            if counts[label] == nil { order.append(label) }
            counts[label, default: 0] += 1
        }
        guard !order.isEmpty else { return "Nothing recognised" }

        let parts = order.prefix(4).map { name -> String in
            let count = counts[name] ?? 1
            return count > 1 ? "\(name) ×\(count)" : name
        }
        let phrase = parts.joined(separator: ", ")
        return order.count > 4 ? "\(phrase) and more" : phrase
    }

    /// The foods on a plate, deduplicated, in the order they were recognised.
    /// Labels rather than kinds: with the taxonomy gone, what a food is called
    /// is what a food is.
    static func uniqueGroups(_ meal: MealEntry) -> [String] {
        var seen = Set<String>()
        return meal.items.map(\.label).filter { seen.insert($0.lowercased()).inserted }
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

/// The dish a new ingredient is being named for. The name is what carries it
/// home: `MealDish.regrouped` files a flat row by `MealItem.dish`, and the
/// refiner returns rows with none — it is not told which dish a correction
/// belongs to, and guessing would be worse than not knowing. Coming from a
/// dish sheet there is nothing to guess.
struct AddingIngredient: Identifiable, Hashable {
    /// The dish's own id, so the presentation is keyed on the dish rather than
    /// on a name two dishes could share.
    let id: UUID
    let dish: String
}

/// The photograph, or a stand-in that does not pretend to be one.
struct MealThumbnail: View {
    let meal: MealEntry
    /// Nil fills whatever space it is given — the four-up grid on a history
    /// card sizes its slots by the card, not the other way round.
    var side: CGFloat? = 56
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
                        .font(.system(size: (side ?? 56) * 0.34, weight: .semibold, design: .rounded))
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


enum DayFormat {
    /// "Tuesday 11 Aug" — the line above the day counter on Today.
    ///
    /// Assembled rather than pattern-formatted, for the same reason `title` is:
    /// `.weekday(.wide).day().month(.abbreviated)` orders by locale and lands
    /// on "11 Tuesday Aug" in several of them.
    static func long(_ day: Date, calendar: Calendar = .current) -> String {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        let month = day.formatted(.dateTime.month(.abbreviated))
        return "\(weekday) \(calendar.component(.day, from: day)) \(month)"
    }

    /// The clock, in the reader's own 12- or 24-hour convention.
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()

    static func time(_ at: EpochMillis) -> String {
        clock.string(from: Date(epochMillis: at))
    }

    /// "Today", "Yesterday", then "Monday 3" the way the history screen labels
    /// its cards.
    static func title(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        // Assembled rather than pattern-formatted: `.weekday(.wide).day()`
        // orders by locale and lands on "3 Monday" in several of them.
        let weekday = day.formatted(.dateTime.weekday(.wide))
        return "\(weekday) \(calendar.component(.day, from: day))"
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
