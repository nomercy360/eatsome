import Foundation
import Testing

@testable import ShamanCore

@Suite("Week rhythm")
struct WeekRhythmTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    /// Local noon on a day `offset` days before `reference`, so nothing in
    /// these fixtures sits near a boundary by accident.
    private func noon(_ offset: Int, before reference: Date, calendar: Calendar) -> EpochMillis {
        let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: reference))!
        return calendar.date(byAdding: .hour, value: 12, to: day)!.epochMillis
    }

    private func meal(_ at: EpochMillis, _ items: [MealItem]) -> MealEntry {
        MealEntry(eatenAt: at, items: items, source: .manual)
    }

    private func windowEnd(_ reference: Date, calendar: Calendar) -> EpochMillis {
        calendar.startOfDay(for: reference).addingTimeInterval(86_400).epochMillis
    }

    @Test("A day with nothing logged is still a dot")
    func emptyDaysAreKept() {
        let calendar = calendar
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let days = WeekRhythm.days(
            meals: [meal(noon(3, before: now, calendar: calendar), [MealItem(group: .fruit, portion: .medium)])],
            endingAt: windowEnd(now, calendar: calendar),
            days: 7,
            calendar: calendar
        )

        #expect(days.count == 7)
        #expect(days.count(where: \.isLogged) == 1)
        #expect(days.allSatisfy { $0.isLogged || $0.fill == 0 })
    }

    @Test("Oldest first, and the last dot is today")
    func ordering() {
        let calendar = calendar
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let days = WeekRhythm.days(meals: [], endingAt: windowEnd(now, calendar: calendar), days: 7, calendar: calendar)

        #expect(days.map(\.id) == days.map(\.id).sorted())
        #expect(calendar.isDate(days.last!.start, inSameDayAs: now))
    }

    @Test("Fill saturates at three meals so a busy day cannot outshine a full one")
    func fillSaturates() {
        let calendar = calendar
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let today = noon(0, before: now, calendar: calendar)
        let items = [MealItem(group: .vegetables, portion: .medium)]
        let days = WeekRhythm.days(
            meals: (0..<5).map { _ in meal(today, items) },
            endingAt: windowEnd(now, calendar: calendar),
            days: 7,
            calendar: calendar
        )

        #expect(days.last?.mealCount == 5)
        #expect(days.last?.fill == 1)
    }

    /// The dot summary and the score must not disagree about the same plate:
    /// four fruit rows on one platter are one plate of fruit in both.
    @Test("Per-day servings apply the per-meal group cap and the share")
    func servingsMatchTheScorer() {
        let calendar = calendar
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let platter = MealEntry(
            eatenAt: noon(0, before: now, calendar: calendar),
            items: (0..<4).map { _ in MealItem(group: .fruit, portion: .large) },
            source: .photo,
            share: .part
        )
        let days = WeekRhythm.days(
            meals: [platter],
            endingAt: windowEnd(now, calendar: calendar),
            days: 7,
            calendar: calendar
        )

        #expect(days.last?.servings(of: .fruit) == platter.servings(of: .fruit))
        #expect(days.last?.servings(of: .fruit) == MealScoring.perMealGroupCap * 0.5)
    }

    @Test("Days meeting a daily target are counted, not averaged")
    func daysMeetingCountsDays() {
        let calendar = calendar
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        // Six fruit on one day beats a three-a-day average, and still clears
        // the item on exactly one day.
        let heavy = MealEntry(
            eatenAt: noon(2, before: now, calendar: calendar),
            items: [MealItem(group: .fruit, portion: .large)],
            source: .manual
        )
        let days = WeekRhythm.days(
            meals: [heavy],
            endingAt: windowEnd(now, calendar: calendar),
            days: 7,
            calendar: calendar
        )

        #expect(WeekRhythm.daysMeeting([.fruit], atLeast: 2, in: days) == 1)
        #expect(WeekRhythm.daysMeeting([.fruit], atLeast: 3, in: days) == 0)
    }
}

@Suite("Diet copy")
struct DietCopyTests {
    private func goal(
        _ id: String,
        _ shape: DietGoal.Shape,
        passed: Bool,
        observed: Double,
        plainTitle: String? = nil
    ) -> DietResult.GoalResult {
        .init(id: id, title: "", plainTitle: plainTitle, shape: shape,
              passed: passed, observed: observed, target: shape.target)
    }

    @Test("Every rule in every shipped diet has a plain title, hand-written or not")
    func everyRuleIsNamed() {
        for spec in DietPresets.all {
            for rule in spec.goals {
                let plain = DietCopy.plainTitle(rule, in: spec)
                #expect(!plain.isEmpty, "\(spec.id)/\(rule.id) has no sentence")
                #expect(plain != rule.title, "\(spec.id)/\(rule.id) still uses the screener's phrasing")
            }
        }
    }

    /// The property the old per-item-id switch could not have: a rule nobody
    /// wrote copy for still reads as a sentence rather than as a threshold.
    @Test("A rule invented in the editor gets a sentence too")
    func inventedRulesReadAsEnglish() {
        let built = DietGoal(id: "x", title: "Fish ≥ 5 servings/week",
                             shape: .weeklyAtLeast([.fish], 5.0))
        #expect(DietCopy.plainTitle(built) == "Fish, five a week")
        #expect(DietCopy.plainTitle(DietGoal(id: "y", title: "", shape: .dailyAtLeastGrams(.protein, 90)))
            == "Protein, 90 g a day")
    }

    @Test("Advice counts what is actually left, in helpings you could carry")
    func adviceCountsTheShortfall() {
        #expect(DietCopy.advice(for: goal("a", .weeklyAtLeast([.fish], 3), passed: false, observed: 1))
            == "Two more meals with fish this week.")
        #expect(DietCopy.advice(for: goal("a", .weeklyAtLeast([.fish], 3), passed: false, observed: 2.4))
            == "One more meal with fish this week.")
        #expect(DietCopy.advice(for: goal("b", .dailyAtLeast([.vegetables], 2), passed: false, observed: 1))
            == "One more plate with something green on it.")
        // Groups nobody wrote a helping for still get a countable one.
        #expect(DietCopy.advice(for: goal("c", .weeklyAtLeast([.tea], 4), passed: false, observed: 1))
            == "Three more servings of tea this week.")
    }

    /// Nothing is owed on a rule you already hold, and an upper bound is not a
    /// task — the week screen files those under "you're keeping these low".
    @Test("Met rules, upper bounds and habits get no advice")
    func noAdviceWhereNothingIsOwed() {
        #expect(DietCopy.advice(for: goal("a", .weeklyAtLeast([.fish], 3), passed: true, observed: 3)) == nil)
        #expect(DietCopy.advice(for: goal("b", .weeklyBelow([.sweets], 3), passed: false, observed: 4)) == nil)
        #expect(DietCopy.advice(for: goal("c", .habit("h"), passed: false, observed: 0)) == nil)
    }

    @Test("Daily rules measure in days when a day count is supplied")
    func dailyRulesMeasureInDays() {
        let fruit = goal("d", .dailyAtLeast([.fruit], 3), passed: false, observed: 1.7)
        #expect(DietCopy.measure(for: fruit, daysMet: 4, windowDays: 7).text == "4 of 7 days")
        #expect(DietCopy.measure(for: fruit, daysMet: nil, windowDays: 7).text == "1.7 of 3")

        // A per-meal rule measures in meals, because days are not what it is
        // about — that is the whole reason the shape exists.
        let eachMeal = goal("e", .eachMeal([.vegetables]), passed: false, observed: 0.5)
        #expect(DietCopy.measure(for: eachMeal, daysMet: nil, windowDays: 7).text == "50% of meals")
    }
}
