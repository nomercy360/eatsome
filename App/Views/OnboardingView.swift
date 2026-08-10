import AVFoundation
import ShamanCore
import SwiftUI

/// Screen set `2a`. The whole flow is the diet setup; everything else is
/// deferred until the moment it is actually needed.
///
/// Four questions, two permissions, and then food. Identity is established by
/// the app gate before this setup begins. No notification ask — that happens on
/// the first "Needs you". No tour. Skip all of it and you land on
/// Mediterranean with no protein target, because the app has to work on its
/// defaults or the defaults are wrong.
///
/// The camera and Health asks come last, immediately before the composer,
/// which is the whole reason they are still here: the research doc's five
/// screens leave them out, and an app that fires the system camera prompt cold
/// gets refused by people who would have said yes — there is no second chance
/// at that dialog. Explaining a permission one screen before it is used is the
/// best placement there is; deleting the explanation would have made the app
/// unusable for anyone who tapped Don't Allow.
///
/// The two habit questions are the last thing the person is asked and they come
/// from the chosen diet rather than from a hardcoded pair, so a low-sugar diet
/// simply does not ask them.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = 0
    @State private var chosen = DietPresets.default
    @State private var habits = DietHabits()
    @State private var proteinTarget: Double = 90
    @State private var wantsProtein = false

    /// The habit screen is skipped entirely for a diet that asks nothing, so
    /// the step counter has to be computed rather than written down — "2 of 3"
    /// above a screen that never appears is a progress bar that lies.
    private var steps: [Step] {
        var steps: [Step] = [.diet]
        if !chosen.habits.isEmpty { steps.append(.habits) }
        steps.append(.protein)
        steps.append(.camera)
        steps.append(.health)
        return steps
    }

    private enum Step { case diet, habits, protein, camera, health }

    var body: some View {
        Group {
            if step == 0 {
                welcome
            } else if step <= steps.count {
                question(steps[step - 1], index: step)
            } else {
                firstLog
            }
        }
        .animation(WellieMotion.step(reduceMotion), value: step)
        .wellieScreen()
    }

    // MARK: - 1 · Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("eatsome")
                .font(WellieTheme.font(15, weight: .bold))
                .padding(.top, 12)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 26) {
                OliveRow(olives: 5, size: 22)

                Text("Say what you ate.\nWe keep score in olives.")
                    .font(WellieTheme.font(32, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)

                // The promise is about the week, not about the food. Nothing
                // here names a diet: which one is scoring is the next screen's
                // question, and answering it before it is asked would make the
                // choice look like a formality.
                WellieProse(
                    """
                    A photo, a sentence, or a voice note — eatsome reads the meal and scores your \
                    week against a diet you choose. No calorie counting, no weighing.
                    """,
                    size: 16.5
                )

                VStack(alignment: .leading, spacing: 11) {
                    promise("Every figure traced to a food table")
                    promise("No perfect days to keep up")
                    promise("Change your diet, keep your history")
                }
            }

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Button("Continue") { step = 1 }
                    .buttonStyle(WelliePrimaryButtonStyle())
                Button("I've used eatsome before") { model.completeOnboarding() }
                    .buttonStyle(WellieQuietButtonStyle())
                Text("Your account keeps your history private")
                    .font(WellieTheme.metaFont(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(WellieTheme.muted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.ice.ignoresSafeArea())
    }

    private func promise(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WellieTheme.blue)
            Text(text)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
        }
    }

    // MARK: - The questions

    @ViewBuilder
    private func question(_ kind: Step, index: Int) -> some View {
        switch kind {
        case .diet: dietAsk(index)
        case .habits: habitsAsk(index)
        case .protein: proteinAsk(index)
        case .camera: cameraAsk(index)
        case .health: healthAsk(index)
        }
    }

    // MARK: - 2 · What counts

    private func dietAsk(_ index: Int) -> some View {
        page(index: index) {
            VStack(alignment: .leading, spacing: 16) {
                Text("What should your olives measure?")
                    .font(WellieTheme.font(26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    ForEach(Array(DietPresets.all.enumerated()), id: \.element.id) { position, spec in
                        if position > 0 { WellieRowDivider() }
                        dietRow(spec)
                    }
                }
                .wellieListCard()

                WellieProse(
                    """
                    You can fork any of these into your own plan later — rules, not modes. \
                    Skipping keeps Mediterranean.
                    """,
                    size: 14
                )
            }
        } actions: {
            Button("Continue") { advance() }
                .buttonStyle(WelliePrimaryButtonStyle())
        }
    }

    private func dietRow(_ spec: DietSpec) -> some View {
        let isOn = spec.id == chosen.id
        return Button { chosen = spec } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(spec.name)
                            .font(WellieTheme.font(15, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                        if spec.instrument != nil {
                            Text("Validated")
                                .font(WellieTheme.metaFont(8))
                                .tracking(0.6)
                                .textCase(.uppercase)
                                .foregroundStyle(WellieTheme.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(WellieTheme.blue.opacity(0.4), lineWidth: 1)
                                }
                        }
                    }
                    Text(shape(of: spec))
                        .font(WellieTheme.metaFont(9))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(WellieTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? WellieTheme.blue : WellieTheme.outline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(isOn ? WellieTheme.ice : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What the diet is about, in its own groups rather than in a slogan.
    ///
    /// Generated from the rules so it cannot describe a diet the engine is not
    /// actually going to score. Keto's line says what it is instead of what it
    /// sounds like, because naming it for the macro would be a promise the
    /// parser refuses to keep.
    private func shape(of spec: DietSpec) -> String {
        if spec.id == DietPresets.ketoStyle.id { return "A proxy, not carb counting" }
        let up = spec.goals
            .filter { !$0.shape.isUpperBound && !$0.shape.groups.isEmpty }
            .flatMap(\.shape.groups)
        let down = spec.goals.filter(\.shape.isUpperBound).flatMap(\.shape.groups)
        var parts: [String] = []
        if !up.isEmpty { parts.append("\(names(up)) up") }
        if !down.isEmpty { parts.append("\(names(down)) down") }
        if !spec.constraints.isEmpty {
            parts.append("\(names(spec.constraints.flatMap(\.shape.groups))) never")
        }
        return parts.joined(separator: " · ")
    }

    private func names(_ groups: [FoodGroup]) -> String {
        var seen: [FoodGroup] = []
        for group in groups where !seen.contains(group) { seen.append(group) }
        return seen.prefix(3).map(\.shortName).joined(separator: ", ")
    }

    // MARK: - 3 · Two things a photo can't see

    private func habitsAsk(_ index: Int) -> some View {
        page(index: index) {
            VStack(alignment: .leading, spacing: 20) {
                Text(chosen.habits.count == 1
                     ? "One thing a photo can't see"
                     : "\(Count.spell(chosen.habits.count)) things a photo can't see")
                    .font(WellieTheme.font(26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    "\(chosen.name) scores \(chosen.habits.count == 1 ? "one habit" : "these") once. Change them any time in settings.",
                    size: 14.5
                )

                ForEach(chosen.habits) { habit in
                    habitCard(habit)
                }
            }
        } actions: {
            Button("Continue") { advance() }
                .buttonStyle(WelliePrimaryButtonStyle())
        }
    }

    private func habitCard(_ habit: DietHabitQuestion) -> some View {
        let isYes = habits.answer(habit)
        return VStack(alignment: .leading, spacing: 14) {
            Text(habit.question)
                .font(WellieTheme.font(18, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 9) {
                answer(habit.yes, isOn: isYes) { habits.set(true, for: habit.id) }
                answer(habit.no, isOn: !isYes) { habits.set(false, for: habit.id) }
            }
        }
        .wellieCard(padding: 20)
    }

    private func answer(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WellieTheme.onAccent)
                }
                Text(text)
                    .font(WellieTheme.font(16, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? WellieTheme.onAccent : WellieTheme.body)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                isOn ? WellieTheme.blue : WellieTheme.well,
                in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
            )
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
                        .strokeBorder(WellieTheme.outline, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4 · Protein, optional


    private func proteinAsk(_ index: Int) -> some View {
        page(index: index) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Do you have a daily protein target?")
                    .font(WellieTheme.font(26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    """
                    We estimate protein from portion weights — good for a trend, not lab-grade. \
                    Skip this and it stays off.
                    """,
                    size: 14.5
                )

                HStack(spacing: 18) {
                    Spacer(minLength: 0)
                    adjust("minus", enabled: proteinTarget > 40) { proteinTarget -= 5 }
                    VStack(spacing: 2) {
                        Text("\(Int(proteinTarget)) g")
                            .font(WellieTheme.font(42, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .monospacedDigit()
                        Text("Per day")
                            .font(WellieTheme.metaFont(9.5))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(WellieTheme.muted)
                    }
                    adjust("plus", enabled: proteinTarget < 250) { proteinTarget += 5 }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 18)

                HStack(alignment: .top, spacing: 10) {
                    OliveRow(olives: 1, size: 13)
                        .frame(width: 13, alignment: .leading)
                        .clipped()
                    WellieProse(
                        """
                        Counts as one more goal in your olives — protein under target costs the day \
                        part of an olive, never all of it.
                        """,
                        size: 12.5
                    )
                }
                .wellieCard(padding: 14)
            }
        } actions: {
            Button("Set \(Int(proteinTarget)) g and finish") {
                wantsProtein = true
                advance()
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            Button("No target, thanks") {
                wantsProtein = false
                advance()
            }
            .buttonStyle(WellieQuietButtonStyle())
        }
    }

    // MARK: - 5 · Camera

    /// Explains before iOS does, so a refusal is a decision rather than
    /// permanent confusion. The system dialog appears once ever and a cold one
    /// is refused by people who would have said yes — which is why this screen
    /// survived a design that did not have it.
    private func cameraAsk(_ index: Int) -> some View {
        page(index: index) {
            VStack(alignment: .leading, spacing: 22) {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .fill(WellieTheme.ice)
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(WellieTheme.blue.opacity(0.4))
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("Beans · Vegetables · Olive oil")
                            .font(WellieTheme.font(12.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .padding(20)
                    }

                Text("One photo per meal is all it takes.")
                    .font(WellieTheme.font(26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    """
                    Point the camera at the plate before you start eating. eatsome names the foods \
                    it can see; you fix anything it gets wrong, or you don't.
                    """,
                    size: 15
                )

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(WellieTheme.blue)
                    WellieProse(
                        "Before the first photo is sent, you'll see exactly where it is stored, which AI reads it, and how to delete it.",
                        size: 13.5
                    )
                }
                .wellieCard(padding: 16)
            }
        } actions: {
            Button("Allow the camera") {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in advance() }
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            Button("I'll use photos I've already taken") { advance() }
                .buttonStyle(WellieQuietButtonStyle())
        }
    }

    // MARK: - 6 · Health

    /// Weight is what sets the protein target, so this sits after the protein
    /// question rather than before it: the ask makes sense once somebody has
    /// said they want a target, and it is skippable either way.
    private func healthAsk(_ index: Int) -> some View {
        page(index: index) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your watch already knows some of this.")
                    .font(WellieTheme.font(26, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    """
                    If you let eatsome read Health, three things appear on your Today screen. \
                    Nothing is calculated from them and nothing is written back.
                    """,
                    size: 15
                )

                VStack(spacing: 10) {
                    healthRow("moon.fill", "Sleep", "Last night, and how it compares")
                    healthRow("figure.run", "Workouts", "How many this week")
                    healthRow("scalemass.fill", "Weight",
                              wantsProtein ? "Sets your \(Int(proteinTarget)) g protein target" : "Also sets a protein target")
                }

                WellieCaption("Read only. eatsome never changes Health data. You can connect this later in Settings.")
            }
        } actions: {
            Button("Connect Apple Health") {
                Task {
                    await model.connectHealth()
                    advance()
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            Button("Not now") { advance() }
                .buttonStyle(WellieQuietButtonStyle())
        }
    }

    private func healthRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                .fill(WellieTheme.ice)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WellieTheme.blue)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(WellieTheme.font(15.5, weight: .semibold))
                Text(detail)
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
    }

    private func adjust(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(enabled ? WellieTheme.ink : WellieTheme.faint)
                .frame(width: 46, height: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(WellieTheme.outline, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - 7 · Straight to food

    /// Not a screen with a Done button. Onboarding ends by handing over the
    /// composer, because the thing that makes the app make sense is the first
    /// meal and every extra tap before it is a tap someone can leave on.
    private var firstLog: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today")
                    .font(WellieTheme.font(20, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer()
                OliveRow(olives: 0, size: 13)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                Text("What's the last thing you ate?")
                    .font(WellieTheme.font(21, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                WellieProse(
                    "Type it, say it, or snap what's left of it. Your first olive arrives in about a minute.",
                    size: 14
                )
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)

            Button("Log my first meal") { finish() }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, 26)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.background.ignoresSafeArea())
    }

    // MARK: - Shared frame

    /// "1 of 3" and a Skip that means it. A step counter with no way out is a
    /// funnel, not an introduction.
    private func page<Body: View, Actions: View>(
        index: Int,
        @ViewBuilder content: () -> Body,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(index) of \(steps.count)")
                    .font(WellieTheme.metaFont(10))
                    .tracking(0.6)
                    .textCase(.uppercase)
                Spacer()
                Button("Skip") { finish() }
                    .font(WellieTheme.font(15, weight: .semibold))
            }
            .foregroundStyle(WellieTheme.muted)
            .padding(.horizontal, 22)
            .frame(height: 44)

            ScrollView {
                content()
                    .padding(.horizontal, 26)
                    .padding(.bottom, 24)
            }

            VStack(spacing: 12) { actions() }
                .padding(.horizontal, 26)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .background(WellieTheme.background.ignoresSafeArea())
    }

    private func advance() { step += 1 }

    /// Skipping keeps whatever is already on screen. The defaults are the
    /// answers most people would give, and leaving them unrecorded would
    /// silently cost the habits their points — but the protein target is off
    /// unless it was asked for, because a goal nobody set is a goal the app
    /// invented.
    private func finish() {
        Task {
            await model.selectDiet(chosen)
            if !chosen.habits.isEmpty {
                await model.updateHabits(habits)
            }
            model.hasProteinGoal = wantsProtein
            model.completeOnboarding()
        }
    }
}
