import ShamanCore
import SwiftUI

/// Screen `2c`. The one place in the app that keeps the number.
///
/// The fourteen items, reordered so the ones you can still act on come first,
/// in plain names. An unmet target says what would fix it; a met one collapses
/// to a checked line. "Stay under" becomes "You're keeping these low", which is
/// the same fact said as a success — the items you are passing are not a list
/// of things to worry about.
struct MyWeekView: View {
    @Environment(AppModel.self) private var model
    @State private var showingMethod = false
    @State private var openDay: DayLog?

    var body: some View {
        let result = model.adherence()
        let days = model.weekDays()

        ScrollView {
            LazyVStack(spacing: WellieTheme.cardSpacing) {
                hero(result, days: days)

                if !unmet(result).isEmpty { winsCard(result, days: days) }
                if !held(result).isEmpty { goingWellCard(result) }
                if !limits(result).isEmpty { keepingLowCard(result) }

                footnote
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle("My week")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMethod) { ScoreMethodView() }
        // A sheet rather than a push, matching `7f`: a day slides over whatever
        // you were reading and swipes away again, which is what makes tapping a
        // dot cheap enough to do idly.
        .sheet(item: $openDay) { DaySheet(day: $0.start) }
        .wellieScreen()
    }

    // MARK: - Hero

    private func hero(_ result: MedasResult, days: [DayLog]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last \(Count.spell(result.windowDays, capitalized: false)) days")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                    Text(headline(result))
                        .font(WellieTheme.font(24, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                // The figure appears only when the week can carry it. On a thin
                // week it is not a low score, it is not a score.
                if !result.isUnderreported {
                    Text("\(result.score)")
                        .font(WellieTheme.font(44, weight: .bold))
                        .foregroundStyle(WellieTheme.blue)
                }
            }

            WellieWeekDots(days: dots(days), behind: WellieTheme.ice) { id in
                openDay = days.first { $0.id == id }
            }

            WellieProse(caption(result, days: days))
        }
        .wellieCard(color: WellieTheme.ice, padding: 24)
    }

    private func headline(_ result: MedasResult) -> String {
        if result.isUnderreported {
            return "Not enough days\nto score yet."
        }
        return "\(Count.spell(result.score)) of \(Count.spell(result.maxScore, capitalized: false))\nhabits held."
    }

    private func caption(_ result: MedasResult, days: [DayLog]) -> String {
        let logged = """
        \(Count.spell(result.daysLogged)) of the last \
        \(Count.spell(result.windowDays, capitalized: false)) days logged.
        """
        let gaps = days.filter { !$0.isLogged }
        guard !gaps.isEmpty else { return "\(logged) Nothing is missing." }
        if gaps.count == 1, let day = gaps.first {
            let name = day.start.formatted(.dateTime.weekday(.wide))
            return "\(logged) \(name) is missing, which pulls the week down a little."
        }
        return "\(logged) The days without meals are the ones holding it back."
    }

    private func dots(_ days: [DayLog]) -> [WellieWeekDots.Day] {
        let calendar = Calendar.current
        return days.map {
            .init(
                id: $0.id,
                initials: DayFormat.initials($0.start, calendar: calendar),
                fill: $0.fill,
                isToday: calendar.isDateInToday($0.start)
            )
        }
    }

    // MARK: - Easiest wins

    private func winsCard(_ result: MedasResult, days: [DayLog]) -> some View {
        // Ranked by the bar the person can actually see, not by the underlying
        // average — a daily item reads "4 of 7 days" and must sit where that
        // fraction puts it.
        let ranked = unmet(result)
            .map { ($0, MedasCopy.measure(for: $0, daysMet: daysMet($0, in: days), windowDays: result.windowDays)) }
            .sorted { $0.1.fraction > $1.1.fraction }

        return VStack(alignment: .leading, spacing: 18) {
            WellieSectionTitle(text: "Easiest wins left", detail: daysLeftInWeek)

            ForEach(ranked, id: \.0.id) { item, measure in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(MedasCopy.plainTitle(item.id))
                            .font(WellieTheme.font(15.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                        Spacer(minLength: 8)
                        Text(measure.text)
                            .font(WellieTheme.font(13.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    WellieMeter(fraction: measure.fraction)
                    if let advice = MedasCopy.advice(for: item) {
                        Text(advice)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .wellieCard()
    }

    /// The rolling window has no deadline, but the week you are living in does,
    /// and that is the one a person is planning dinners against.
    private var daysLeftInWeek: String? {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return nil }
        let remaining = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: week.end).day ?? 0
        switch remaining {
        case ..<1: return nil
        case 1: return "Today is the last day of the week"
        default: return "\(Count.spell(remaining)) days still to go"
        }
    }

    /// Daily lower-bound items measure in days met, not in a per-day average —
    /// "4 of 7 days" is a week you can picture; "1.7 of 3" is arithmetic.
    private func daysMet(_ item: MedasResult.ItemResult, in days: [DayLog]) -> Int? {
        guard let medas = Medas.items.first(where: { $0.id == item.id }),
              case .dailyAtLeast(let groups, let target) = medas.rule
        else { return nil }
        return WeekRhythm.daysMeeting(groups, atLeast: target, in: days)
    }

    // MARK: - Going well / keeping low

    private func goingWellCard(_ result: MedasResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Going well")
                .font(WellieTheme.font(17, weight: .bold))
            ForEach(held(result)) { item in
                HStack(spacing: 11) {
                    WellieMark()
                    Text(MedasCopy.plainTitle(item.id))
                        .font(WellieTheme.font(15.5, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    Spacer(minLength: 0)
                }
            }
        }
        .wellieCard()
    }

    private func keepingLowCard(_ result: MedasResult) -> some View {
        let over = limits(result).filter { !$0.passed }
        return VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(
                text: over.isEmpty ? "You're keeping these low" : "Mostly keeping these low",
                detail: over.isEmpty ? "Nothing to do here" : "One over, and it isn't a disaster"
            )
            ForEach(limits(result)) { item in
                HStack(spacing: 11) {
                    WellieMark(isMet: item.passed)
                    Text(MedasCopy.plainTitle(item.id))
                        .font(WellieTheme.font(15.5, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    Spacer(minLength: 8)
                    Text(limitCount(item))
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(item.passed ? WellieTheme.muted : WellieTheme.attention)
                }
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    /// Upper bounds are stated per day or per week by the screener; either way
    /// what a person wants to see is the count over the window.
    private func limitCount(_ item: MedasResult.ItemResult) -> String {
        let weekly = Medas.items.first { $0.id == item.id }.map { medas -> Double in
            if case .dailyBelow = medas.rule { return item.observed * Double(model.config.medas.windowDays) }
            return item.observed
        } ?? item.observed
        let rounded = Int(weekly.rounded())
        guard !item.passed else { return "\(rounded)" }
        let target = Int((item.isUpperBound ? item.target * (isDaily(item) ? Double(model.config.medas.windowDays) : 1) : item.target).rounded())
        let over = max(1, rounded - target + 1)
        return "\(rounded) — \(Count.spell(over, capitalized: false)) over"
    }

    private func isDaily(_ item: MedasResult.ItemResult) -> Bool {
        guard let medas = Medas.items.first(where: { $0.id == item.id }) else { return false }
        if case .dailyBelow = medas.rule { return true }
        return false
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 10) {
            WellieCaption(
                """
                Wine counts in the original screener, at seven glasses a week. It is not scored \
                here, and nothing above is affected by it.
                """
            )
            Button("Where does this score come from?") { showingMethod = true }
                .font(WellieTheme.font(13.5, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    // MARK: - Buckets

    /// Reachable and unmet: lower bounds only, and never the two habits, which
    /// are a switch in Settings rather than something to eat. Ordering happens
    /// at the call site, against the fraction actually drawn.
    private func unmet(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter { !$0.passed && !$0.isUpperBound && !isHabit($0) }
    }

    private func held(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter { $0.passed && !$0.isUpperBound }
    }

    private func limits(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter(\.isUpperBound)
    }

    private func isHabit(_ item: MedasResult.ItemResult) -> Bool {
        guard let medas = Medas.items.first(where: { $0.id == item.id }) else { return false }
        if case .habit = medas.rule { return true }
        return false
    }
}

/// The screener, named and explained. Reached from the week screen and from
/// Settings, so the number is never something the app just asserts.
struct ScoreMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Fourteen habits, not a diet.")
                            .font(WellieTheme.font(22, weight: .bold))
                        WellieProse(
                            """
                            The score is the Mediterranean Diet Adherence Screener from the PREDIMED \
                            trial: fourteen yes-or-no habits, one point each, measured over a rolling \
                            \(model.config.medas.windowDays)-day window. It is a validated instrument \
                            rather than something invented over a weekend, and it is defined in terms \
                            of how often you eat things — which is exactly what a photograph can \
                            establish.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard(color: WellieTheme.ice)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Where the numbers come from")
                            .font(WellieTheme.font(17, weight: .bold))
                        WellieProse(
                            """
                            eatsome never asks a model how many calories are on a plate. It asks one \
                            question with a number in it — what does this weigh — and looks the rest \
                            up: every figure you see is a published composition table multiplied by \
                            that weight. The tables are the USDA's and Japan's MEXT, and each food \
                            names the row it came from.
                            """,
                            size: 15
                        )
                        WellieProse(
                            """
                            So a figure is only as good as the weight behind it, which is the honest \
                            limit and the one worth knowing. Correct a weight in words on the fix \
                            screen and everything downstream of it moves. Food eatsome could not \
                            recognise is counted as missing rather than as nothing, and today's card \
                            says so when it happens.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("The fourteen")
                            .font(WellieTheme.font(17, weight: .bold))
                        ForEach(Medas.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MedasCopy.plainTitle(item.id))
                                    .font(WellieTheme.font(15, weight: .semibold))
                                Text(item.title)
                                    .font(WellieTheme.font(12.5, weight: .medium))
                                    .foregroundStyle(WellieTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .wellieCard()
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("How the score works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
        }
        .wellieScreen()
    }
}
