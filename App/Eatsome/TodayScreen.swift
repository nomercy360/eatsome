import EatsomeCore
import SwiftUI

/// Screen `13b·1`. Today, and the app's home.
///
/// The page is the day itself: what the date is, what the day has come to, and
/// what happened in it. Three objects, in that order, and nothing else.
///
/// What it is not is as load-bearing as what it is. There is no large counter —
/// `6 / 90 days` is a twelve-point line beside the date, because it answers a
/// question nobody opens the app to ask and it used to be the biggest thing on
/// the screen. There is no week strip; it said what the counter said, less
/// precisely. There are no four stacked meters; energy is the bar because it is
/// the unit the day is denominated in, and the other three are figures beside
/// it, because a meter each made four things equally loud and made the page
/// scroll before it said anything.
///
/// The timeline is meals, and only meals. Workouts and nights used to sit in
/// the same column, read live from Health and marked with an olive ring; they
/// are gone. This app knows what it was told about food and nothing else, and a
/// row it could not have been told about — measured elsewhere, never written to
/// the log, disappearing the moment access is revoked — made the day look like a
/// report on a person rather than a record of what they ate.
struct TodayScreen: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(\.mainTabContentClearance) private var clearance

    /// The meal being looked at, if any. A cover rather than a push: the detail
    /// draws its own `‹ Today` and a navigation bar above that would be a
    /// second back button saying the same thing.
    @State private var opened: MealEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                if let message = store.loadError {
                    LoadWarning(message: message)
                        .padding(.bottom, 10)
                        .todayRow()
                }

                EatenCard(total: store.nutrients(), targets: store.dailyTargets)
                    .padding(.bottom, 10)
                    .todayRow()

                WellieMeta("The day")
                    .padding(.bottom, 2)
                    .todayRow()

                timeline

                Color.clear
                    .frame(height: max(20, clearance))
                    .todayRow()
            }
            .listStyle(.plain)
            .listRowSpacing(4)
            // A `List` pads every row to 44 points unless told otherwise, which
            // turns the one-line section label into a band with a gap either
            // side of it that no padding here can close.
            .environment(\.defaultMinListRowHeight, 0)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .fullScreenCover(item: $opened) { meal in
            SavedMealScreen(meal: meal) { opened = nil }
        }
        .wellieScreen()
    }

    // MARK: The date

    private var header: some View {
        let logged = store.daysLogged()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(EatsomeFormat.longDay(Date()))
                .font(WellieTheme.font(22, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            Text("\(logged) / \(EatsomeStore.loggingWindow) days")
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(EatsomeFormat.longDay(Date())). \(logged) of the last \(EatsomeStore.loggingWindow) days logged."
        )
    }

    // MARK: The day

    @ViewBuilder
    private var timeline: some View {
        let meals = store.today()
        if meals.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing recorded yet today.")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
                Text("Meals will appear here.")
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .todayRow()
        } else {
            ForEach(meals) { meal in
                Button { opened = meal } label: {
                    MealDayRow(meal: meal)
                }
                .buttonStyle(.plain)
                .todayRow()
                // Swipe rather than a button on the row: removing a meal is
                // rare and destructive, and a control that lives in the row is
                // one thumb-width from the tap that opens it.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.delete(meal) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
    }
}

/// The one thing the log can say that a screen must not silently absorb: some
/// of it did not read. It sits above the day because it changes what the
/// figures below mean.
private struct LoadWarning: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WellieTheme.attention)
            Text(message)
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WellieTheme.attentionSurface,
            in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
        )
    }
}

/// A meal that is already in the log, with its correction lane behind *Edit ›*.
///
/// The detail commits its own chip and stepper changes as `mealRevised`; what
/// this adds is the half a chip cannot do — a correction in words, which is the
/// only path that can name a food the model never mentioned and have it priced.
private struct SavedMealScreen: View {
    let meal: MealEntry
    let onClose: () -> Void

    @Environment(EatsomeStore.self) private var store
    @Environment(EatsomeAccount.self) private var account

    @State private var editing: MealEntry?
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        MealDetailScreen(
            meal: meal,
            mode: .saved(onEdit: { editing = $0 }),
            onBack: onClose
        )
        .fullScreenCover(item: $editing) { current in
            FixInWords(
                subject: MealTitle.of(current),
                isWorking: isWorking,
                failure: failure,
                onSubmit: { note in Task { await fix(note, on: current) } },
                onCancel: { editing = nil; failure = nil }
            )
        }
    }

    private func fix(_ note: String, on current: MealEntry) async {
        isWorking = true
        failure = nil
        defer { isWorking = false }
        switch await MealRefinement.apply(note, to: current, using: account.session) {
        case .success(let corrected):
            await store.record(.mealRevised(corrected), occurredAt: corrected.eatenAt)
            editing = nil
            onClose()
        case .failure(let reason):
            failure = reason
        }
    }
}

private extension View {
    /// Makes a native `List` row belong to the card system. Gesture arbitration
    /// and swipe actions stay system-owned; only the insets, separator and
    /// background are ours.
    func todayRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: 0,
                leading: WellieTheme.screenInset,
                bottom: 0,
                trailing: WellieTheme.screenInset
            )
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

// MARK: - What the day came to

/// Energy as the bar, the three macronutrients as figures beside it.
///
/// Energy gets the bar because it is the unit the whole day is denominated in.
/// The other three are figures beside it, and every one of them is a number
/// over a number — `95 / 400 g`, never `95 / 343–496 g`.
///
/// Each denominator is derived by a stated rule rather than chosen: protein is
/// a goal in grams per kilogram, fat is 30% of planned energy
/// (`DailyTargets.fatShare`, the middle of the adult AMDR), and carbohydrate is
/// the energy left after those two. The rule is where the honesty lives. A
/// range in this slot was the earlier answer and it was the wrong shape of
/// caution: `45–65%` is what the source publishes, but a person reading a card
/// reads whatever is under the slash as the thing to hit, so a band there was
/// read as a target nobody had set — and it made the one comparison the card
/// exists to draw impossible to make at a glance.
///
/// Salt is not here, and its absence is the invariant. It has no reference
/// worth scoring against, so it stays on the meal detail as a plain figure with
/// nothing beside it.
private struct EatenCard: View {
    let total: Nutrients
    let targets: DailyTargets?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            energyLine
            if targets != nil { energyBar.padding(.top, 9) }
            macros.padding(.top, 14)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieSurface()
        .onAppear { withAnimation(WellieMotion.fill(reduceMotion)) { filled = true } }
    }

    private var energyLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            WellieMeta("Eaten")
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(EatsomeFormat.whole(total.kcal))
                    .font(WellieTheme.font(23, weight: .heavy))
                    .foregroundStyle(WellieTheme.ink)
                Text(targets.map { "/ \(EatsomeFormat.whole($0.kcal)) kcal" } ?? "kcal")
                    .font(WellieTheme.font(12, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenEnergy)
    }

    private var spokenEnergy: String {
        let eaten = EatsomeFormat.whole(total.kcal)
        guard let targets else { return "Eaten, \(eaten) kilocalories" }
        return "Eaten, \(eaten) of \(EatsomeFormat.whole(targets.kcal)) kilocalories"
    }

    /// The track is worth `max(target, eaten)`, so a day that goes past its
    /// reference is drawn going past it — a bar pinned at 100% makes 3,000 kcal
    /// and 1,800 kcal look like the same day. When it overshoots, a two-point
    /// gap marks where the reference was; under it, that mark sits exactly
    /// under the end of the fill and is invisible, which is correct.
    @ViewBuilder
    private var energyBar: some View {
        if let targets {
            let scale = max(targets.kcal, total.kcal, 1)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(WellieTheme.raised)
                    Capsule()
                        .fill(WellieTheme.accent)
                        .frame(width: max(0, width * (filled ? total.kcal : 0) / scale))
                    if total.kcal > targets.kcal {
                        Capsule()
                            .fill(WellieTheme.surface)
                            .frame(width: 2)
                            .offset(x: width * targets.kcal / scale - 1)
                    }
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var macros: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(figures, id: \.name) { figure($0, stacked: true) }
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                ForEach(figures, id: \.name) { figure($0, stacked: false) }
            }
        }
    }

    private var figures: [MacroFigure] {
        [
            MacroFigure(name: "Protein", value: total.protein, goal: targets?.protein),
            MacroFigure(name: "Carbs", value: total.carbohydrate, goal: targets?.carbohydrate),
            MacroFigure(name: "Fat", value: total.fat, goal: targets?.fat),
        ]
    }

    private func figure(_ macro: MacroFigure, stacked: Bool) -> some View {
        let amount = HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(EatsomeFormat.whole(macro.value))
                .font(WellieTheme.font(14, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Text(macro.denominator)
                .font(WellieTheme.font(10.5, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)

        let label = Text(macro.name)
            .font(WellieTheme.font(10.5, weight: .semibold))
            .foregroundStyle(WellieTheme.muted)
            .lineLimit(1)

        return Group {
            if stacked {
                HStack(spacing: 8) { label; Spacer(minLength: 8); amount }
            } else {
                VStack(alignment: .leading, spacing: 3) { label; amount }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.spoken)
    }
}

private struct MacroFigure {
    let name: String
    let value: Double
    /// Nil until the body details exist, because a figure with no reference is
    /// still worth printing and an invented reference is not.
    let goal: Double?

    /// `/ 400 g`, or just the unit when there is nothing to compare against.
    var denominator: String {
        goal.map { "/ \(EatsomeFormat.whole($0)) g" } ?? "g"
    }

    /// Read out as a sentence rather than as the glyphs it is printed with:
    /// VoiceOver says "slash" for `/`, so "95 / 400 g" is otherwise announced
    /// as two unrelated numbers.
    ///
    /// It is built from the figures rather than by unpicking the printed
    /// string, which is what it used to do — `denominator` was the only stored
    /// form, so the spoken line stripped "/ " and " g" back off it to find the
    /// number again. One source, two renderings.
    var spoken: String {
        let amount = "\(name), \(EatsomeFormat.whole(value)) grams"
        guard let goal else { return amount }
        return "\(name), \(EatsomeFormat.whole(value)) of \(EatsomeFormat.whole(goal)) grams"
    }
}

// MARK: - One meal in the day

/// A meal in the timeline: a 36 pt photograph, two lines, one energy.
///
/// One row type, not a shape that several kinds fill in. `DayRow` was generic
/// over its mark and took a tint for its value, because a workout put an olive
/// ring where the photograph goes and an olive duration where the energy does;
/// with those rows gone the generic parameter had exactly one argument and the
/// tint exactly one value, and a shared shape with one filler is just the same
/// row spelled twice.
///
/// The clock stays in the second line rather than in a column of its own. That
/// column was a quarter of the width, and it was paying for an ordering cue the
/// sequence already gives.
private struct MealDayRow: View {
    let meal: MealEntry

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var title: String { MealTitle.of(meal) }
    private var subtitle: String { MealTitle.subtitle(meal) }

    /// A zero stays absent rather than printing "0 kcal" under a photograph of
    /// dinner, which is a worse answer than saying nothing.
    private var value: String {
        meal.nutrients.kcal.rounded() > 0
            ? "\(EatsomeFormat.whole(meal.nutrients.kcal)) kcal"
            : ""
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) { thumb; lines }
                    trailing
                }
            } else {
                HStack(spacing: 12) {
                    thumb
                    lines
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WellieTheme.surface,
            in: RoundedRectangle(cornerRadius: WellieTheme.rowRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WellieTheme.font(14.5, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Text(subtitle)
                .font(WellieTheme.font(12, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailing: some View {
        if !value.isEmpty {
            Text(value)
                .font(WellieTheme.font(13, weight: .bold))
                .foregroundStyle(WellieTheme.body)
                .lineLimit(1)
        }
    }

    private var thumb: some View {
        MealPhoto(hash: meal.photoHash, side: 36, radius: WellieTheme.thumbRadius)
    }
}
