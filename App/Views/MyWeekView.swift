import ShamanCore
import SwiftUI

/// Screen `2c`. The one place in the app that keeps the number.
///
/// The active diet's rules, reordered so the ones you can still act on come
/// first, in plain names. An unmet goal says what would fix it; a met one
/// collapses to a checked line. "Stay under" becomes "You're keeping these
/// low", which is the same fact said as a success — the goals you are passing
/// are not a list of things to worry about.
///
/// Constraints are in none of those lists. They get their own card, above the
/// goals, saying kept or broken with the meal named: an exclusion is the one
/// thing on this screen an average must never touch.
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

                if !result.constraints.isEmpty { constraintsCard(result) }
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

    private func hero(_ result: DietResult, days: [DayLog]) -> some View {
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

    private func headline(_ result: DietResult) -> String {
        if result.isUnderreported {
            return "Not enough days\nto score yet."
        }
        return "\(Count.spell(result.score)) of \(Count.spell(result.maxScore, capitalized: false))\nhabits held."
    }

    private func caption(_ result: DietResult, days: [DayLog]) -> String {
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

    private func winsCard(_ result: DietResult, days: [DayLog]) -> some View {
        // Ranked by the bar the person can actually see, not by the underlying
        // average — a daily item reads "4 of 7 days" and must sit where that
        // fraction puts it.
        let ranked = unmet(result)
            .map { ($0, DietCopy.measure(for: $0, daysMet: daysMet($0, in: days), windowDays: result.windowDays)) }
            .sorted { $0.1.fraction > $1.1.fraction }

        return VStack(alignment: .leading, spacing: 18) {
            WellieSectionTitle(text: "Easiest wins left", detail: daysLeftInWeek)

            ForEach(ranked, id: \.0.id) { item, measure in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(DietCopy.plainTitle(item, in: model.diet))
                            .font(WellieTheme.font(15.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                        Spacer(minLength: 8)
                        Text(measure.text)
                            .font(WellieTheme.font(13.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    WellieMeter(fraction: measure.fraction)
                    if let advice = DietCopy.advice(for: item) {
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
    private func daysMet(_ item: DietResult.GoalResult, in days: [DayLog]) -> Int? {
        guard case .dailyAtLeast(let groups, let target) = item.shape else { return nil }
        return WeekRhythm.daysMeeting(groups, atLeast: target, in: days)
    }

    // MARK: - Going well / keeping low

    private func goingWellCard(_ result: DietResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Going well")
                .font(WellieTheme.font(17, weight: .bold))
            ForEach(held(result)) { item in
                HStack(spacing: 11) {
                    WellieMark()
                    Text(DietCopy.plainTitle(item, in: model.diet))
                        .font(WellieTheme.font(15.5, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    Spacer(minLength: 0)
                }
            }
        }
        .wellieCard()
    }

    private func keepingLowCard(_ result: DietResult) -> some View {
        let over = limits(result).filter { !$0.passed }
        return VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(
                text: over.isEmpty ? "You're keeping these low" : "Mostly keeping these low",
                detail: over.isEmpty ? "Nothing to do here" : "One over, and it isn't a disaster"
            )
            ForEach(limits(result)) { item in
                HStack(spacing: 11) {
                    WellieMark(isMet: item.passed)
                    Text(DietCopy.plainTitle(item, in: model.diet))
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
    private func limitCount(_ item: DietResult.GoalResult) -> String {
        let weekly = isDaily(item)
            ? item.observed * Double(model.config.medas.windowDays)
            : item.observed
        let rounded = Int(weekly.rounded())
        guard !item.passed else { return "\(rounded)" }
        let target = Int((item.isUpperBound ? item.target * (isDaily(item) ? Double(model.config.medas.windowDays) : 1) : item.target).rounded())
        let over = max(1, rounded - target + 1)
        return "\(rounded) — \(Count.spell(over, capitalized: false)) over"
    }

    private func isDaily(_ item: DietResult.GoalResult) -> Bool {
        if case .dailyBelow = item.shape { return true }
        return false
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 10) {
            WellieCaption(footnoteText)
            Button("Where does this score come from?") { showingMethod = true }
                .font(WellieTheme.font(13.5, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }

    /// The wine caveat belongs to MEDAS and to nothing else, so it is not
    /// printed under a diet that never had a wine item to leave out.
    private var footnoteText: String {
        let spec = model.diet
        if spec.instrument != nil {
            return """
            Wine counts in the original screener, at seven glasses a week. It is not scored here, \
            and nothing above is affected by it.
            """
        }
        return """
        \(spec.name) is your own list of rules, not a published screener. Switching it re-scores \
        every week you have logged, without reading a photograph again.
        """
    }

    // MARK: - Buckets

    /// Reachable and unmet: lower bounds only, and never the two habits, which
    /// are a switch in Settings rather than something to eat. Ordering happens
    /// at the call site, against the fraction actually drawn.
    private func unmet(_ result: DietResult) -> [DietResult.GoalResult] {
        result.goals.filter { !$0.passed && !$0.isUpperBound && !$0.isHabit }
    }

    private func held(_ result: DietResult) -> [DietResult.GoalResult] {
        result.goals.filter { $0.passed && !$0.isUpperBound }
    }

    private func limits(_ result: DietResult) -> [DietResult.GoalResult] {
        result.goals.filter(\.isUpperBound)
    }

    // MARK: - Constraints

    /// Its own card, above the goals, never averaged into anything.
    ///
    /// "You scored four of five" and "there was chicken stock in the soup on
    /// Tuesday" are two facts, and the whole design of this screen is that the
    /// second does not get folded into the first — an average is precisely the
    /// instrument that would lose it.
    ///
    /// On a thin week a kept promise is not a fact: two logged meals keep every
    /// exclusion for free, which is the same hole `isUnderreported` exists to
    /// name for the score, so it is named here too.
    private func constraintsCard(_ result: DietResult) -> some View {
        let broken = result.brokenConstraints
        return VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(
                text: broken.isEmpty ? "Held all week" : "One thing to know",
                detail: result.isUnderreported
                    ? "Too few days logged to say for sure"
                    : (broken.isEmpty ? "Not part of the score — it either held or it didn't" : nil)
            )

            ForEach(result.constraints) { constraint in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 11) {
                        Image(systemName: constraint.isKept
                              ? "checkmark.circle.fill"
                              : "exclamationmark.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(constraint.isKept ? WellieTheme.blue : WellieTheme.attention)
                        Text(constraint.title)
                            .font(WellieTheme.font(15.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                        Spacer(minLength: 8)
                        Text(keptLabel(constraint, in: result))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .textCase(.uppercase)
                            .foregroundStyle(constraint.isKept ? WellieTheme.muted : WellieTheme.attention)
                    }
                    ForEach(constraint.breaks) { entry in
                        Text(breakLine(entry))
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.body)
                            .padding(.leading, 30)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .wellieCard(color: broken.isEmpty ? WellieTheme.surface : WellieTheme.attentionSurface)
    }

    private func keptLabel(_ constraint: DietResult.ConstraintResult, in result: DietResult) -> String {
        guard constraint.isKept else {
            let count = constraint.breaks.count
            return "\(count) break\(count == 1 ? "" : "s")"
        }
        guard !result.isUnderreported,
              let spec = model.diet.constraints.first(where: { $0.id == constraint.id })
        else { return "Kept" }
        let days = model.daysKept(spec)
        return days > 0 ? "Kept \(days) days" : "Kept"
    }

    /// Names the dish, because that is what a person recognises. "White meat on
    /// Tuesday" is a food group; "The soup — Tuesday" is a meal they had.
    private func breakLine(_ entry: DietResult.Break) -> String {
        let day = Date(epochMillis: entry.at).formatted(.dateTime.weekday(.wide))
        let what = entry.dish ?? entry.group?.sentenceName ?? "a meal"
        return "\(what.prefix(1).uppercased() + what.dropFirst()) — \(day)"
    }
}

/// Where the number comes from, for whichever diet is scoring the week.
///
/// It used to open "Fourteen habits, not a diet" and describe PREDIMED, which
/// was true when there was one diet and is a false claim about any other. The
/// validated paragraph is now conditional on the spec actually being the
/// instrument — a screen that calls a list of steppers a validated screener is
/// the app lending its own credibility to something that has not earned it.
struct ScoreMethodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    var body: some View {
        let spec = model.diet
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(headline(spec))
                            .font(WellieTheme.font(22, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        WellieProse(opening(spec), size: 15)
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
                        Text("Reading the same meals a different way")
                            .font(WellieTheme.font(17, weight: .bold))
                        WellieProse(
                            """
                            Nothing about a meal is stored as a score. A photograph is read once into \
                            food groups and weights, and the diet is applied afterwards — so changing \
                            it re-scores every week you have ever logged, immediately, without \
                            reading a single photograph again.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 14) {
                        Text(spec.goals.isEmpty ? "The rules" : "The \(Count.spell(spec.goals.count, capitalized: false))")
                            .font(WellieTheme.font(17, weight: .bold))
                        ForEach(spec.goals) { goal in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(DietCopy.plainTitle(goal, in: spec))
                                    .font(WellieTheme.font(15, weight: .semibold))
                                Text(goal.title)
                                    .font(WellieTheme.font(12.5, weight: .medium))
                                    .foregroundStyle(WellieTheme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .wellieCard()

                    if !spec.constraints.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            WellieSectionTitle(
                                text: "And what is not scored",
                                detail: "Kept or broken, never averaged"
                            )
                            ForEach(spec.constraints) { constraint in
                                Text(constraint.title)
                                    .font(WellieTheme.font(15, weight: .semibold))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            WellieCaption(
                                """
                                An exclusion is a promise rather than a target, so it never moves your \
                                olives in either direction. A week can score well and still have broken \
                                one, and that is worth being told rather than averaged away.
                                """
                            )
                        }
                        .wellieCard()
                    }
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

    private func headline(_ spec: DietSpec) -> String {
        spec.instrument == nil
            ? "\(Count.spell(spec.goals.count)) habits, not a diet."
            : "A published screener, not our opinion."
    }

    /// The validated paragraph belongs only to a spec that is the instrument.
    /// Everything else gets an honest one that claims nothing: it is a list of
    /// frequencies somebody chose, which is a perfectly good thing to be.
    private func opening(_ spec: DietSpec) -> String {
        let window = model.config.medas.windowDays
        guard let instrument = spec.instrument else {
            return """
            \(spec.name) is \(Count.spell(spec.goals.count, capitalized: false)) yes-or-no habits, \
            one point each, measured over a rolling \(window)-day window. It is a list of \
            frequencies — how often you eat things — rather than a published instrument, so treat \
            the number as your own yardstick rather than as a clinical finding.
            """
        }
        return """
        The score is the Mediterranean Diet Adherence Screener from the PREDIMED trial \
        (\(instrument)): yes-or-no habits, one point each, measured over a rolling \(window)-day \
        window. It is a validated instrument rather than something invented over a weekend, and it \
        is defined in terms of how often you eat things — which is exactly what a photograph can \
        establish. The wine item is not scored here.
        """
    }
}
