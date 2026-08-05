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

@Suite("MEDAS copy")
struct MedasCopyTests {
    private func item(id: Int, passed: Bool, observed: Double, target: Double, upper: Bool = false)
        -> MedasResult.ItemResult
    {
        .init(id: id, title: "", passed: passed, observed: observed, target: target, isUpperBound: upper)
    }

    @Test("Every scored item has a plain title")
    func everyItemIsNamed() {
        for medas in Medas.items {
            let plain = MedasCopy.plainTitle(medas.id)
            #expect(!plain.isEmpty)
            #expect(plain != medas.title, "item \(medas.id) still uses the screener's phrasing")
        }
    }

    @Test("Advice counts what is actually left")
    func adviceCountsTheShortfall() {
        #expect(MedasCopy.advice(for: item(id: 10, passed: false, observed: 1, target: 3))
            == "Two more meals with fish would clear it.")
        #expect(MedasCopy.advice(for: item(id: 10, passed: false, observed: 2.4, target: 3))
            == "One more meal with fish would clear it.")
    }

    /// Nothing is owed on an item you already hold, and an upper bound is not a
    /// task — the week screen files those under "you're keeping these low".
    @Test("Met items and upper bounds get no advice")
    func noAdviceWhereNothingIsOwed() {
        #expect(MedasCopy.advice(for: item(id: 10, passed: true, observed: 3, target: 3)) == nil)
        #expect(MedasCopy.advice(for: item(id: 11, passed: false, observed: 4, target: 3, upper: true)) == nil)
    }

    @Test("Daily items measure in days when a day count is supplied")
    func dailyItemsMeasureInDays() {
        let fruit = item(id: 4, passed: false, observed: 1.7, target: 3)
        #expect(MedasCopy.measure(for: fruit, daysMet: 4, windowDays: 7).text == "4 of 7 days")
        #expect(MedasCopy.measure(for: fruit, daysMet: nil, windowDays: 7).text == "1.7 of 3")
    }
}
