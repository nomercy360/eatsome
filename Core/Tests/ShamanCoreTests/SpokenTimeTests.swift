import Foundation
import Testing
@testable import ShamanCore

@Suite("A time inside a sentence")
struct SpokenTimeTests {
    @Test("The design's own messages parse to the design's own times")
    func theFramesParse() {
        // 7a: "3 french toasts (…) — 8 am" becomes "Breakfast · 8:00".
        #expect(SpokenTime.parse("3 french toasts (3 eggs, some milk) — 8 am")! == (8, 0))
        // 7a: "2 of this at 11 am" becomes "Snack · 11:00".
        #expect(SpokenTime.parse("2 of this at 11 am")! == (11, 0))
        // 7e promises this one out loud.
        #expect(SpokenTime.parse("half a kebab at 2 am")! == (2, 0))
    }

    @Test("Both clocks, and the twelve-hour edges")
    func clockShapes() {
        #expect(SpokenTime.parse("lunch at 13:20")! == (13, 20))
        #expect(SpokenTime.parse("8:30pm, a bowl of ramen")! == (20, 30))
        #expect(SpokenTime.parse("coffee at 7 a.m.")! == (7, 0))
        #expect(SpokenTime.parse("12 am")! == (0, 0))
        #expect(SpokenTime.parse("12 pm")! == (12, 0))
        #expect(SpokenTime.parse("12:15 am")! == (0, 15))
    }

    @Test("A bare number is a count, never a time")
    func countsAreNotTimes() {
        // The failure this refuses is silent: reading the 8 in "8 eggs" as a
        // time moves the meal eight hours and nothing on screen says so.
        #expect(SpokenTime.parse("8 eggs and toast") == nil)
        #expect(SpokenTime.parse("3 french toasts") == nil)
        #expect(SpokenTime.parse("7 g creatine") == nil)
        #expect(SpokenTime.parse("a glass of milk") == nil)
        #expect(SpokenTime.parse("100g rice") == nil)
    }

    @Test("Nonsense on the clock is refused rather than clamped")
    func impossibleTimes() {
        #expect(SpokenTime.parse("25:00") == nil)
        #expect(SpokenTime.parse("13 pm") == nil)
        #expect(SpokenTime.parse("9:75") == nil)
    }

    @Test("A message with no time keeps the time it was sent")
    func fallsBackToTheSendTime() {
        let sent: EpochMillis = 1_700_000_000_000
        #expect(SpokenTime.eatenAt(in: "banana and coffee", sentAt: sent) == sent)
        #expect(SpokenTime.eatenAt(in: nil, sentAt: sent) == sent)
    }

    @Test("A stated time that has not happened yet is last night's")
    func lateNightWrapsBack() {
        // Typed at 1 am: "at 11 pm" is two hours ago, not twenty-two away.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let oneAM = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 9, hour: 1, minute: 0
        ))!

        let eaten = SpokenTime.eatenAt(
            in: "half a pizza at 11 pm", sentAt: oneAM.epochMillis, calendar: calendar
        )
        let parts = calendar.dateComponents([.day, .hour], from: Date(epochMillis: eaten))
        #expect(parts.day == 8)
        #expect(parts.hour == 23)
    }

    @Test("Logging a meal as you eat it is not thrown back a day")
    func sameMinuteIsToday() {
        // "lunch at 13:00" sent at 13:00:04. Without the tolerance those four
        // seconds move the meal to yesterday, and the day's history with it.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let justAfter = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 9, hour: 13, minute: 0, second: 4
        ))!

        let eaten = SpokenTime.eatenAt(
            in: "lunch at 13:00", sentAt: justAfter.epochMillis, calendar: calendar
        )
        #expect(calendar.dateComponents([.day], from: Date(epochMillis: eaten)).day == 9)
    }
}

private func == (lhs: (hour: Int, minute: Int), rhs: (Int, Int)) -> Bool {
    lhs.hour == rhs.0 && lhs.minute == rhs.1
}
