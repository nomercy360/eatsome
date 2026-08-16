import EatsomeCore
import SwiftUI

/// Screen `13g`, second frame. Earlier days, one card per day.
///
/// A sheet rather than a tab, because a person comes here from the trend to
/// check one day and go back. Only days with something in them are cards: a
/// day with nothing logged is not a light day, it is an unlogged one, and a
/// card saying "0 kcal" would be the confident wrong number the trend just
/// refused to draw.
struct EarlierDaysSheet: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// How far back the sheet reaches. Ninety, like the trend's longest window.
    private static let reach = 90

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    let cards = days
                    if cards.isEmpty {
                        Text("Nothing logged yet.")
                            .font(WellieTheme.font(14, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                            .padding(.top, 60)
                    }
                    ForEach(cards) { day in
                        DayCard(day: day, targets: store.dailyTargets)
                            .padding(.top, 20)
                    }
                    Color.clear.frame(height: 32)
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .wellieScreen()
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 60, height: 1)
            Spacer(minLength: 0)
            Text("Earlier days")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Text("Done")
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .wellieSurface(radius: WellieTheme.rowRadius)
            }
            .buttonStyle(.plain)
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 16)
    }

    private var days: [LoggedDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<Self.reach).compactMap { offset -> LoggedDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let meals = store.projection.meals(on: date, calendar: calendar)
            // A day with nothing in it gets no card, rather than a card saying
            // nothing: that would be a day you did not log dressed as a day
            // you did.
            guard !meals.isEmpty else { return nil }
            return LoggedDay(
                date: date,
                offset: offset,
                meals: meals,
                nutrients: store.projection.nutrients(on: date, calendar: calendar)
            )
        }
    }
}

private struct LoggedDay: Identifiable {
    let date: Date
    /// Days ago. Zero is today.
    let offset: Int
    let meals: [MealEntry]
    let nutrients: Nutrients

    var id: Date { date }

    /// "Today", "Yesterday", then the weekday for the rest of the week, then
    /// the date — the way a person refers to a day when it is recent enough to
    /// have a name.
    var title: String {
        switch offset {
        case 0: "Today"
        case 1: "Yesterday"
        case 2..<7: date.formatted(.dateTime.weekday(.wide))
        default: EatsomeFormat.longDay(date)
        }
    }

    /// "Three meals · protein goal hit". One count, and at most one remark.
    ///
    /// The remarks are two facts, not a grade: the protein goal was met, or the
    /// day was light — under 70% of the energy reference. Both are stated
    /// only against a reference the person has entered, and neither is a
    /// verdict on the day; a light day is a fact about a number.
    func subtitle(targets: DailyTargets?) -> String {
        var parts = [count]
        if let targets {
            if nutrients.protein >= targets.protein {
                parts.append("protein goal hit")
            } else if offset > 0, nutrients.kcal < targets.kcal * 0.7 {
                parts.append("light day")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var count: String {
        switch meals.count {
        case 0: ""
        case 1: offset == 0 ? "One meal so far" : "One meal"
        default: "\(ProgressData.number(meals.count)) meals"
        }
    }
}

private struct DayCard: View {
    let day: LoggedDay
    let targets: DailyTargets?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
            if let targets { bar(targets).padding(.top, 12) }
            if !day.meals.isEmpty { strip.padding(.top, 14) }
            macros.padding(.top, 16)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieSurface(radius: WellieTheme.controlRadius)
    }

    private var top: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.title)
                    .font(WellieTheme.font(19, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text(day.subtitle(targets: targets))
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(EatsomeFormat.whole(day.nutrients.kcal))
                    .font(WellieTheme.font(19, weight: .heavy))
                    .foregroundStyle(WellieTheme.ink)
                Text(targets.map { "of \(EatsomeFormat.whole($0.kcal)) kcal" } ?? "kcal")
                    .font(WellieTheme.font(11.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(day.title). \(day.subtitle(targets: targets)). \(EatsomeFormat.whole(day.nutrients.kcal))"
                + (targets.map { " of \(EatsomeFormat.whole($0.kcal))" } ?? "") + " kilocalories."
        )
    }

    private func bar(_ targets: DailyTargets) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(WellieTheme.hairline)
                Capsule()
                    .fill(WellieTheme.accent)
                    .frame(width: geometry.size.width * min(1, day.nutrients.kcal / max(targets.kcal, 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    /// A thumb per meal, and on today's card a hatched space after them: the
    /// day is not over. It says "more to come", not how many — a count of
    /// meals still expected would presume a number of meals a day, and the
    /// app has no such number.
    private var strip: some View {
        HStack(spacing: 8) {
            ForEach(day.meals.prefix(4)) { _ in
                RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous)
                    .fill(WellieTheme.raised)
                    .frame(width: 62, height: 62)
                    .overlay {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(WellieTheme.accent)
                    }
            }
            if day.offset == 0 {
                Hatched()
                    .frame(height: 62)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text("more to come")
                            .font(WellieTheme.font(11.5, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private var macros: some View {
        let figures = [("Protein", day.nutrients.protein), ("Carbs", day.nutrients.carbohydrate), ("Fat", day.nutrients.fat)]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { ForEach(figures, id: \.0) { macro($0.0, $0.1) } }
            } else {
                HStack(spacing: 18) { ForEach(figures, id: \.0) { macro($0.0, $0.1) } }
            }
        }
    }

    private func macro(_ name: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(WellieTheme.font(12, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            Text("\(EatsomeFormat.whole(value)) g")
                .font(WellieTheme.font(14, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(EatsomeFormat.whole(value)) grams")
    }
}

/// 45° repeating stripes: a place where something would go.
private struct Hatched: View {
    var body: some View {
        RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous)
            .fill(WellieTheme.well)
            .overlay {
                Canvas { context, size in
                    let step: CGFloat = 8
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(WellieTheme.hairline), lineWidth: 1)
                        x += step
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }
}
