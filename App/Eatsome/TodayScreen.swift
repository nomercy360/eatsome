import EatsomeCore
import SwiftUI

/// Screen `11`. Today, and the app's home.
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
                        .padding(.bottom, 12)
                        .todayRow()
                }

                EatenCard(total: store.nutrients(), targets: store.dailyTargets)
                    .padding(.bottom, 20)
                    .todayRow()

                WellieMeta("The day")
                    .padding(.horizontal, 4)
                    .padding(.bottom, 10)
                    .todayRow()

                timeline

                Color.clear
                    .frame(height: max(20, clearance))
                    .todayRow()
            }
            .listStyle(.plain)
            .listRowSpacing(0)
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
                .font(WellieTheme.font(22, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(WellieTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 6)
            Text("\(logged) / \(EatsomeStore.loggingWindow) days")
                .font(WellieTheme.figure(12, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 16)
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
            // A dashed outline and no fill: the mock draws the empty timeline
            // as the *place* a card will go, not as a card that happens to
            // have nothing in it. A filled card here read as a fourth object
            // on a screen that is supposed to have three.
            VStack(spacing: 6) {
                Text("Nothing recorded yet today.")
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text("Photograph a plate or write a sentence — meals will appear here.")
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 38)
            .padding(.horizontal, 24)
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .todayRow()
        } else {
            ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                Button { opened = meal } label: {
                    MealDayRow(meal: meal, compact: false)
                }
                .buttonStyle(.plain)
                .todayRow()
                .listRowBackground(MealGroupBackground(index: index, count: meals.count))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            energy
            ForEach(Array(figures.enumerated()), id: \.element.name) { index, macro in
                Rectangle()
                    .fill(WellieTheme.hairline)
                    .frame(height: 1)
                macroRow(macro)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieSurface(radius: WellieTheme.controlRadius)
    }

    /// Nothing eaten yet. The card is the same card; the figures on it go
    /// quiet, because a bright zero under a lime glow is the screen saying
    /// something is alive when nothing has happened.
    private var isEmpty: Bool { total.kcal.rounded() <= 0 }

    private var energy: some View {
        VStack(spacing: 2) {
            Text(EatsomeFormat.whole(total.kcal))
                .font(WellieTheme.figure(42, weight: .bold))
                .tracking(-1.5)
                .foregroundStyle(isEmpty ? WellieTheme.faint : WellieTheme.ink)
                .frame(height: 50)

            Text(targets.map { "of \(EatsomeFormat.whole($0.kcal)) kcal" } ?? "kcal")
                .font(WellieTheme.figure(12.5, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 18)
        // The mock's halo: a 200 × 110 ellipse fading to nothing by two thirds
        // of its radius, sitting behind the figure *and* the line under it,
        // starting a little above the number. It is not clipped to anything —
        // a glow with an edge is a rectangle that happens to be green.
        .background(alignment: .top) {
            if !isEmpty {
                RadialGradient(
                    colors: [WellieTheme.accent.opacity(0.5), WellieTheme.accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 68
                )
                .frame(width: 200, height: 200)
                .scaleEffect(y: 0.55)
                .frame(width: 200, height: 110)
                .offset(y: -6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenEnergy)
    }

    private var spokenEnergy: String {
        let eaten = EatsomeFormat.whole(total.kcal)
        guard let targets else { return "Eaten, \(eaten) kilocalories" }
        return "Eaten, \(eaten) of \(EatsomeFormat.whole(targets.kcal)) kilocalories"
    }

    private var figures: [MacroFigure] {
        [
            MacroFigure(kind: .protein, name: "Protein", value: total.protein, goal: targets?.protein),
            MacroFigure(kind: .carbs, name: "Carbs", value: total.carbohydrate, goal: targets?.carbohydrate),
            MacroFigure(kind: .fat, name: "Fat", value: total.fat, goal: targets?.fat),
        ]
    }

    private func macroRow(_ macro: MacroFigure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 12) {
                NutrientIcon(kind: macro.kind, size: 16)
                    .saturation(isEmpty ? 0 : 1)
                    .opacity(isEmpty ? 0.45 : 1)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                Text(macro.name)
                    .font(WellieTheme.font(13.5, weight: .semibold))
                    .foregroundStyle(isEmpty ? WellieTheme.muted : WellieTheme.ink)
            }
            Spacer(minLength: 8)
            Text(macro.amount)
                .font(WellieTheme.figure(13.5, weight: .bold))
                .foregroundStyle(isEmpty ? WellieTheme.muted : WellieTheme.ink)
            if let denominator = macro.denominator {
                Text(denominator)
                    .font(WellieTheme.figure(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.spoken)
    }
}

private struct MacroFigure {
    let kind: NutrientKind
    let name: String
    let value: Double
    /// Nil until the body details exist, because a figure with no reference is
    /// still worth printing and an invented reference is not.
    let goal: Double?

    /// `95 g`. The unit rides with the figure rather than trailing the
    /// denominator, so a row with no reference still says what it is.
    var amount: String { "\(EatsomeFormat.whole(value)) g" }

    /// `/ 400 g`, or nothing when there is nothing to compare against.
    var denominator: String? {
        goal.map { "/ \(EatsomeFormat.whole($0)) g" }
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
struct MealDayRow: View {
    let meal: MealEntry
    var compact = false

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
        .padding(.horizontal, 16)
        .padding(.vertical, compact ? 10 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var lines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WellieTheme.font(14, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            Text(subtitle)
                .font(WellieTheme.figure(11.5, weight: .regular))
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
            let parts = value.split(separator: " ")
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(parts.first.map(String.init) ?? value)
                    .font(WellieTheme.figure(13, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                if parts.count > 1 {
                    Text("kcal")
                        .font(WellieTheme.font(11, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                }
            }
            .lineLimit(1)
        }
    }

    private var thumb: some View {
        MealPhoto(hash: meal.photoHash, side: compact ? 34 : 38, radius: compact ? 11 : 12)
    }
}

private struct MealGroupBackground: View {
    let index: Int
    let count: Int

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: index == 0 ? WellieTheme.cardRadius : 0,
            bottomLeadingRadius: index == count - 1 ? WellieTheme.cardRadius : 0,
            bottomTrailingRadius: index == count - 1 ? WellieTheme.cardRadius : 0,
            topTrailingRadius: index == 0 ? WellieTheme.cardRadius : 0,
            style: .continuous
        )
    }

    var body: some View {
        shape
            .fill(WellieTheme.surface)
            .overlay { shape.strokeBorder(WellieTheme.hairline, lineWidth: 1) }
            // The line between rows, drawn on the background rather than by
            // the row, so the row stays one tappable object and the last one
            // does not carry a line into the card's own edge.
            .overlay(alignment: .bottom) {
                if index < count - 1 {
                    WellieRowDivider().padding(.horizontal, 16)
                }
            }
    }
}
