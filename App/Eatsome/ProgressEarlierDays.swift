import EatsomeCore
import SwiftUI

/// Screen `23`. A month ledger with the selected day's actual meals beneath it.
/// Lime describes proximity to the reader's own reference; an unfilled past
/// day simply means there was no log.
struct EarlierDaysSheet: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var month = Self.startOfMonth(Date())
    @State private var selected = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar {
        var result = Calendar.current
        result.firstWeekday = 2
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    monthHeader
                    weekdayHeader.padding(.top, 18)
                    calendarGrid.padding(.top, 7)
                    legend.padding(.top, 14)
                    selectedDay.padding(.top, 22)
                    Color.clear.frame(height: 28)
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
            Color.clear.frame(width: 72, height: 1)
            Spacer(minLength: 0)
            Text("Earlier days")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 0)
            Button("Done") { dismiss() }
                .font(WellieTheme.font(14, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .wellieSurface(radius: WellieTheme.rowRadius)
                .buttonStyle(.plain)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 16)
    }

    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.formatted(.dateTime.month(.wide)))
                .font(WellieTheme.font(22, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(WellieTheme.ink)
            Spacer()
            HStack(spacing: 6) {
                monthButton(symbol: "chevron.left", enabled: true) { moveMonth(-1) }
                monthButton(symbol: "chevron.right", enabled: canMoveForward) { moveMonth(1) }
            }
        }
        .padding(.top, 22)
    }

    private func monthButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? WellieTheme.ink : WellieTheme.faint)
                .frame(width: 28, height: 28)
                .background(enabled ? WellieTheme.surface : WellieTheme.well, in: Circle())
                .overlay { Circle().strokeBorder(enabled ? WellieTheme.hairline : Color.clear, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous month" : "Next month")
    }

    private var canMoveForward: Bool { month < Self.startOfMonth(Date()) }

    private func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: month) else { return }
        month = Self.startOfMonth(next, calendar: calendar)
        let today = calendar.startOfDay(for: Date())
        if calendar.isDate(month, equalTo: today, toGranularity: .month) {
            selected = today
        } else if let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month) {
            selected = calendar.startOfDay(for: end)
        }
    }

    private var weekdayHeader: some View {
        let labels = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(labels[1...]) + [labels[0]]
        return HStack(spacing: 8) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(WellieTheme.font(10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(WellieTheme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 4) {
            ForEach(calendarDates, id: \.self) { date in dayButton(date) }
        }
    }

    private var calendarDates: [Date] {
        let monthStart = Self.startOfMonth(month, calendar: calendar)
        guard let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start,
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else { return [] }
        let today = calendar.startOfDay(for: Date())
        let visibleEnd: Date
        if calendar.isDate(monthStart, equalTo: today, toGranularity: .month) {
            visibleEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end.addingTimeInterval(-1) ?? today
        } else {
            visibleEnd = calendar.dateInterval(of: .weekOfYear, for: monthEnd)?.end.addingTimeInterval(-1) ?? monthEnd
        }
        let count = max(0, calendar.dateComponents([.day], from: firstWeek, to: visibleEnd).day ?? 0) + 1
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek) }
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selected)
        let isThisMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: Date())
        let nutrients = store.projection.nutrients(on: date, calendar: calendar)
        let logged = !store.projection.meals(on: date, calendar: calendar).isEmpty
        return Button {
            guard !isFuture else { return }
            selected = calendar.startOfDay(for: date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(WellieTheme.figure(13, weight: isSelected || logged ? .bold : .semibold))
                .foregroundStyle(dayForeground(selected: isSelected, inMonth: isThisMonth, future: isFuture))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(dayBackground(selected: isSelected, logged: logged, future: isFuture, nutrients: nutrients))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(isSelected ? "Selected" : (logged ? "Logged" : "Not logged"))
    }

    private func dayForeground(selected: Bool, inMonth: Bool, future: Bool) -> Color {
        if selected { return WellieTheme.onInk }
        if future || !inMonth { return WellieTheme.faint }
        return WellieTheme.ink
    }

    @ViewBuilder
    private func dayBackground(selected: Bool, logged: Bool, future: Bool, nutrients: Nutrients) -> some View {
        if selected {
            WellieTheme.inkSurface
        } else if logged {
            let ratio = store.dailyTargets.map { nutrients.kcal / max($0.kcal, 1) } ?? 0.5
            WellieTheme.accent.opacity(ratio < 0.7 ? 0.30 : (ratio < 0.9 ? 0.50 : 0.72))
        } else if !future {
            WellieTheme.well
        } else {
            Color.clear
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("not logged", fill: WellieTheme.well)
            legendItem("light", fill: WellieTheme.accent.opacity(0.30))
            legendItem("near your reference", fill: WellieTheme.accent.opacity(0.72))
        }
    }

    private func legendItem(_ text: String, fill: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill).frame(width: 11, height: 11)
            Text(text).font(WellieTheme.font(11)).foregroundStyle(WellieTheme.muted)
        }
        .fixedSize()
    }

    private var selectedMeals: [MealEntry] { store.projection.meals(on: selected, calendar: calendar) }
    private var selectedNutrients: Nutrients { store.projection.nutrients(on: selected, calendar: calendar) }

    private var selectedDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            WellieMeta(EatsomeFormat.longDay(selected, calendar: calendar)).padding(.horizontal, 4)
            if selectedMeals.isEmpty {
                Text("Nothing logged.")
                    .font(WellieTheme.font(13.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .wellieSurface(radius: WellieTheme.cardRadius)
                    .padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(selectedMeals.enumerated()), id: \.element.id) { index, meal in
                        MealDayRow(meal: meal, compact: true)
                        if index < selectedMeals.count - 1 { WellieRowDivider().padding(.horizontal, 16) }
                    }
                }
                .wellieSurface(radius: WellieTheme.cardRadius)
                .padding(.top, 10)
                summary.padding(.top, 12)
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summaryText).font(WellieTheme.font(13)).foregroundStyle(WellieTheme.muted)
            Spacer(minLength: 8)
            Text(EatsomeFormat.whole(selectedNutrients.kcal))
                .font(WellieTheme.figure(17, weight: .heavy)).foregroundStyle(WellieTheme.ink)
            Text(store.dailyTargets.map { "of \(EatsomeFormat.whole($0.kcal)) kcal" } ?? "kcal")
                .font(WellieTheme.figure(11.5)).foregroundStyle(WellieTheme.muted)
        }
        .padding(.horizontal, 4)
    }

    private var summaryText: String {
        var parts = [selectedMeals.count == 1 ? "One meal" : "\(ProgressData.number(selectedMeals.count)) meals"]
        if let target = store.dailyTargets, selectedNutrients.protein >= target.protein { parts.append("protein goal hit") }
        return parts.joined(separator: " · ")
    }

    private static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
