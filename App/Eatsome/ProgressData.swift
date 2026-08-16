import EatsomeCore
import Foundation

/// What Progress asks of the log, computed once per draw and nowhere else.
///
/// Every figure here is a fold over `Projection`; nothing is stored. The one
/// idea the screen is built on is the difference between a day with nothing
/// in it and a day *before you started*: the first is drawn as a stub in the
/// bar row and excluded from every average, the second is drawn the same way
/// and is also why the longer windows are locked. Both are absences, and both
/// are shown rather than hidden.
struct ProgressData {
    /// The windows the mock offers, and when each opens. A window opens on the
    /// day its length is reached counting from the first thing ever logged —
    /// "opens day 30" — not from the thirtieth day *logged*, because the
    /// former is a date a person can look forward to and the latter moves.
    enum Window: Int, CaseIterable, Hashable, Identifiable {
        case fortnight = 14
        case month = 30
        case quarter = 90

        var id: Int { rawValue }
        var title: String { "\(rawValue) days" }
    }

    struct Day: Identifiable, Hashable {
        let date: Date
        /// Nil before the first thing was ever logged: not "zero", "not yet".
        /// A day inside the history with nothing logged is `.zero`, and is
        /// still excluded from averages — see `logged`.
        let nutrients: Nutrients?
        let logged: Bool
        let isToday: Bool

        var id: Date { date }
        var beforeStart: Bool { nutrients == nil }
    }

    let days: [Day]
    let window: Window
    /// Calendar days since the first thing was logged, today inclusive. Zero
    /// with an empty log.
    let daysSinceStart: Int
    let daysLogged: Int
    let averageKcal: Double?
    let averageProtein: Double?
    let proteinGoal: Double?
    /// Days that hit the protein goal, and the days they are counted against.
    /// **Completed days only.** Today is drawn in the accent because it is
    /// still moving, and a footnote that counted it as a miss at nine in the
    /// morning would say "you failed" beside a bar that is deliberately
    /// refusing to judge. The average still includes today: an average is a
    /// figure, a hit is a verdict.
    let proteinDaysHit: Int
    let proteinDaysCompleted: Int
    /// The last window that has opened, given `daysSinceStart`.
    let openWindows: Set<Window>

    init(
        projection: Projection,
        window: Window,
        targets: DailyTargets?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.window = window
        let today = calendar.startOfDay(for: now)
        let firstLogged: Date? = projection.meals.values
            .map { calendar.startOfDay(for: Date(epochMillis: $0.eatenAt)) }
            .min()

        let sinceStart = firstLogged.map {
            (calendar.dateComponents([.day], from: $0, to: today).day ?? 0) + 1
        } ?? 0
        daysSinceStart = sinceStart
        openWindows = Set(Window.allCases.filter { $0 == .fortnight || sinceStart >= $0.rawValue })

        var built: [Day] = []
        for offset in stride(from: window.rawValue - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let logged = !projection.meals(on: date, calendar: calendar).isEmpty
            let started = firstLogged.map { date >= $0 } ?? false
            built.append(Day(
                date: date,
                nutrients: started ? projection.nutrients(on: date, calendar: calendar) : nil,
                logged: logged,
                isToday: calendar.isDate(date, inSameDayAs: today)
            ))
        }
        days = built

        // Averages over the days that have something in them, and only those.
        // A day you did not log is not a day you ate nothing; folding it in as
        // zero would draw a person's average down for every day they were busy.
        let counted = built.filter(\.logged).compactMap(\.nutrients)
        daysLogged = counted.count
        averageKcal = counted.isEmpty ? nil : counted.map(\.kcal).reduce(0, +) / Double(counted.count)
        averageProtein = counted.isEmpty ? nil : counted.map(\.protein).reduce(0, +) / Double(counted.count)
        proteinGoal = targets?.protein
        let completed = built.filter { $0.logged && !$0.isToday }.compactMap(\.nutrients)
        proteinDaysCompleted = completed.count
        proteinDaysHit = targets.map { goal in completed.count { $0.protein >= goal.protein } } ?? 0

    }

    /// The bar heights, as fractions of the tallest logged day in the window,
    /// so the row is always drawn to its own scale. Nil for a stub.
    func fraction(_ day: Day, of key: KeyPath<Nutrients, Double>) -> Double? {
        guard day.logged, let value = day.nutrients?[keyPath: key] else { return nil }
        let peak = days.compactMap { $0.logged ? $0.nutrients?[keyPath: key] : nil }.max() ?? 0
        guard peak > 0 else { return 0 }
        return value / peak
    }

    /// The card under the trend. Its job is to say where you are without
    /// grading it — the number of days is a fact, three weeks is when a mean
    /// stops moving with every new day, and the thing to look forward to is a
    /// date rather than a score.
    var honesty: String {
        switch daysSinceStart {
        case 0:
            return "Nothing logged yet. Log a meal and the trend starts here."
        case 1..<21:
            let n = ProgressData.spelled(daysSinceStart)
            let opens = openWindows.contains(.month)
                ? "" : " — keep going and the 30-day view opens"
            return "\(n) in. Trends get honest around three weeks\(opens)."
        default:
            return openWindows.contains(.quarter)
                ? "Three weeks and more. What you see is a trend, not a week."
                : "Three weeks in. The 90-day view opens on day 90."
        }
    }

    /// "Seven days", "Twelve days", "23 days". Words below thirteen because that
    /// is how the sentence reads aloud; digits above because "Twenty-three
    /// days" is a longer line for no gain.
    static func spelled(_ days: Int) -> String {
        days == 1 ? "\(number(days)) day" : "\(number(days)) days"
    }

    /// "Three", "Twelve", "23" — capitalised, for the start of a phrase.
    static func number(_ value: Int) -> String {
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
                     "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        return value >= 0 && value < words.count ? words[value] : "\(value)"
    }
}
