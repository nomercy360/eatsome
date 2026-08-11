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

    /// The dot summary and meal portions must not disagree about the same plate:
    /// four fruit rows on one platter are one plate of fruit in both.
    @Test("Per-day servings apply the per-meal group cap and the share")
    func servingsMatchMealPortions() {
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
        #expect(days.last?.servings(of: .fruit) == MealPortions.perMealGroupCap * 0.5)
    }

}
