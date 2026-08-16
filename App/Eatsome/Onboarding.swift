import EatsomeCore
import SwiftUI

/// Screen `2a`. The questions the daily reference cannot be computed without.
///
/// This replaces a 1,247-line version, and the three reasons it is a fraction
/// of the size are worth stating, because each one was a decision rather than a
/// tidy-up:
///
/// - **It asks only what the arithmetic needs.** `DailyTargets.forProfile`
///   returns nil without an age, a reference equation, a height, a weight, an
///   activity level and a goal, and it needs nothing else. The old flow also
///   asked about body fat, which no equation here uses, and offered a tour of
///   features. Every question that cannot change a number on Today is gone.
/// - **Health goes first, and then only the blanks are asked.** Most of these
///   are already on the phone. The old flow asked for Health and then asked all
///   the questions anyway; this one reads first and puts what came back beyond
///   the reach of the questions, so a person with a watch answers two things
///   rather than six.
/// - **The controls belong to You.** `ChoiceRows`, `NumberRow` and
///   `ProfileWheel` are shared with `NumbersSheet` (`ProfileFields.swift`), so
///   there is no second form vocabulary to keep in step — changing your height
///   later looks like giving it in the first place.
///
/// There is no `hasOnboarded` flag, and its absence is the design. Completeness
/// of the profile *is* the condition: `EatsomeRoot` shows this when
/// `DailyTargets.forProfile` cannot answer, which means a person whose profile
/// arrives complete by pull never sees it, and nobody can be stuck behind a
/// boolean that disagrees with their own data. It is checked at launch and
/// after a sign-in only — clearing a field in You afterwards is editing, not
/// starting again.
struct Onboarding: View {
    /// Called from the last screen. The flow is dismissed by this rather than
    /// by watching the profile become complete, because those are two different
    /// moments: the profile is complete as soon as the last question is
    /// answered, and the reference screen exists to be read after that.
    let onDone: () -> Void

    @Environment(EatsomeStore.self) private var store

    /// The three parts of the flow. `asking` walks `questions`, which is fixed
    /// once Health has had its turn — computing it live would let the list
    /// shrink under somebody as they answered it.
    private enum Phase: Equatable {
        case health
        case asking(Int)
        case reference
    }

    @State private var phase = Phase.health
    @State private var questions: [Question] = []
    @State private var readingHealth = false
    @State private var healthResult: String?

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            progress
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch phase {
                    case .health:
                        healthStep
                    case .asking(let index):
                        if let question = questions[safe: index] {
                            questionStep(question, profile: $store.profile)
                        }
                    case .reference:
                        referenceStep
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(WellieTheme.background)
        .wellieScreen()
    }

    // MARK: - Where you are

    /// A back arrow and a hairline meter. No "step 3 of 6": the number of
    /// questions depends on what Health answered, so a denominator promised at
    /// the top would be a different one for every person and a lie for anyone
    /// who went back.
    private var progress: some View {
        HStack(spacing: 12) {
            Button {
                back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(canGoBack ? WellieTheme.accent : WellieTheme.faint)
                    .wellieHitTarget()
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .accessibilityLabel("Back")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(WellieTheme.raised)
                    Capsule()
                        .fill(WellieTheme.accent)
                        .frame(width: max(4, geometry.size.width * completion))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 8)
    }

    /// How far along, as a fraction. Health is the first of `questions.count + 2`
    /// stops and the reference is the last.
    private var completion: Double {
        let total = Double(max(1, questions.count + 1))
        switch phase {
        case .health: return 0.06
        case .asking(let index): return Double(index) / total
        case .reference: return 1
        }
    }

    private var canGoBack: Bool { phase != .health }

    private func back() {
        switch phase {
        case .health:
            break
        case .asking(let index):
            phase = index == 0 ? .health : .asking(index - 1)
        case .reference:
            phase = questions.isEmpty ? .health : .asking(questions.count - 1)
        }
    }

    private func forward() {
        switch phase {
        case .health:
            // Fixed here, once, from whatever Health did or did not fill in.
            questions = Question.allCases.filter { !$0.isAnswered(in: store.profile) }
            phase = questions.isEmpty ? .reference : .asking(0)
        case .asking(let index):
            phase = index + 1 < questions.count ? .asking(index + 1) : .reference
        case .reference:
            break
        }
    }

    // MARK: - Health

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start with Health")
                .font(WellieTheme.font(30, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            WellieProse(
                "Your phone may already know your height, your weight and how much you move. "
                    + "If it does, we use it and skip those questions.",
                size: 16
            )

            VStack(alignment: .leading, spacing: 10) {
                point("Read, never written")
                point("Your body only — not your workouts or your sleep")
                point("Anything missing, we just ask")
            }
            .padding(.top, 2)

            if let healthResult {
                WellieCaption(healthResult)
            }
        }
    }

    private func point(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WellieTheme.accent)
                .padding(.top, 3)
            Text(text)
                .font(WellieTheme.font(14.5, weight: .regular))
                .foregroundStyle(WellieTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Fill the blanks and move on, whatever came back.
    ///
    /// It never says access was granted. Read authorization in HealthKit is
    /// privacy-preserving by design — a refusal is indistinguishable from
    /// somebody who has never stood on a scale — so an empty answer says
    /// nothing was there and the flow simply asks the questions itself.
    private func fillFromHealth() async {
        readingHealth = true
        healthResult = nil
        defer { readingHealth = false }
        do {
            try await HealthKitBridge.shared.requestAuthorization()
            let health = try await HealthKitBridge.shared.loadProfile()
            var filled = 0
            func take<T>(_ field: WritableKeyPath<NutritionProfile, T?>, _ value: T?) {
                guard store.profile[keyPath: field] == nil, let value else { return }
                store.profile[keyPath: field] = value
                filled += 1
            }
            take(\.ageYears, health.ageYears)
            take(\.referenceSex, health.referenceSex)
            take(\.heightCentimeters, health.heightCentimeters)
            take(\.weightKilograms, health.weightKilograms)
            take(\.bodyFatPercentage, health.bodyFatPercentage)
            take(\.activityLevel, health.activityLevel)
            healthResult = filled == 0 ? "Nothing to read — we'll ask instead." : nil
        } catch {
            healthResult = "Health could not be read on this phone. We'll ask instead."
        }
        forward()
    }

    // MARK: - One question

    private func questionStep(_ question: Question, profile: Binding<NutritionProfile>) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.title)
                .font(WellieTheme.font(26, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = question.detail {
                WellieProse(detail, size: 15)
            }

            switch question {
            case .goal:
                ChoiceRows(selection: profile.goal)
            case .referenceSex:
                ChoiceRows(selection: profile.referenceSex)
            case .activity:
                ChoiceRows(selection: profile.activityLevel)
            case .age:
                wheelCard {
                    ProfileWheel(title: "Age", unit: "years", value: profile.ageYears.doubleBinding,
                                 range: 19...120, step: 1, decimals: 0, start: 35)
                }
            case .height:
                wheelCard {
                    ProfileWheel(title: "Height", unit: "cm", value: profile.heightCentimeters,
                                 range: 120...230, step: 1, decimals: 0, start: 170)
                }
            case .weight:
                wheelCard {
                    ProfileWheel(title: "Weight", unit: "kg", value: profile.weightKilograms,
                                 range: 35...350, step: 0.5, decimals: 1, start: 70)
                }
            }
        }
    }

    private func wheelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .wellieSurface()
    }

    // MARK: - What it comes to

    /// The reference, and the rule behind each figure.
    ///
    /// Every line says it is an estimate, because every line is: the energy is
    /// a published equation applied to figures a person typed, and the three
    /// macronutrients are shares of that. Printing them without the word would
    /// be the confident wrong number the rest of the app is arranged against.
    @ViewBuilder
    private var referenceStep: some View {
        if let targets = store.dailyTargets {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your daily reference")
                    .font(WellieTheme.font(28, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse("An estimate, and a starting point. Change any of it in You, whenever you like.", size: 15)

                VStack(spacing: 0) {
                    referenceRow("Energy", "\(EatsomeFormat.whole(targets.kcal)) kcal",
                                 rule: goalRule(targets), emphasised: true)
                    WellieRowDivider()
                    referenceRow("Protein", "\(EatsomeFormat.whole(targets.protein)) g",
                                 rule: "A goal in grams per kilogram of body weight")
                    WellieRowDivider()
                    referenceRow("Fat", "\(EatsomeFormat.whole(targets.fat)) g",
                                 rule: "30% of the energy above — the middle of the adult range")
                    WellieRowDivider()
                    referenceRow("Carbs", "\(EatsomeFormat.whole(targets.carbohydrate)) g",
                                 rule: "Whatever energy is left once protein and fat are paid for")
                }
                .padding(.horizontal, 18)
                .wellieSurface()

                WellieCaption(
                    "Salt is not given a reference here. There is no daily figure worth scoring it against, "
                        + "so eatsome shows what a meal contains and leaves it at that."
                )
            }
        } else {
            // Unreachable by construction — the flow does not arrive here until
            // every question is answered — but a screen that would rather say
            // so than print nothing is the point of the whole app.
            VStack(alignment: .leading, spacing: 14) {
                Text("Something is still missing")
                    .font(WellieTheme.font(24, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                WellieProse("Go back and check your age, height, weight, activity and goal.", size: 15)
            }
        }
    }

    /// "Maintenance, as far as we can tell" — or the adjustment, with its size,
    /// because a deficit somebody did not know about is the number they would
    /// most want to have been told.
    private func goalRule(_ targets: DailyTargets) -> String {
        let maintenance = "Maintenance is about \(EatsomeFormat.whole(targets.maintenanceKcal)) kcal"
        let adjustment = Int(targets.goalAdjustmentKcal.rounded())
        if adjustment == 0 { return "\(maintenance), and this matches it" }
        return adjustment < 0
            ? "\(maintenance) — this is \(abs(adjustment)) below it"
            : "\(maintenance) — this is \(adjustment) above it"
    }

    private func referenceRow(_ name: String, _ value: String, rule: String, emphasised: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer(minLength: 8)
                Text(value)
                    .font(WellieTheme.font(emphasised ? 22 : 17, weight: .bold))
                    .foregroundStyle(emphasised ? WellieTheme.accent : WellieTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(rule)
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), about \(value). \(rule).")
    }

    // MARK: - Onward

    private var footer: some View {
        VStack(spacing: 8) {
            switch phase {
            case .health:
                Button {
                    Task { await fillFromHealth() }
                } label: {
                    if readingHealth {
                        ProgressView().tint(WellieTheme.onAccent)
                    } else {
                        Text("Use Health")
                    }
                }
                .buttonStyle(WelliePrimaryButtonStyle())
                .disabled(readingHealth)

                Button("Enter by hand") { forward() }
                    .buttonStyle(WellieQuietButtonStyle())
                    .disabled(readingHealth)

            case .asking(let index):
                let question = questions[safe: index]
                Button("Continue") { forward() }
                    .buttonStyle(WelliePrimaryButtonStyle(enabled: question?.isAnswered(in: store.profile) ?? false))
                    .disabled(!(question?.isAnswered(in: store.profile) ?? false))

            case .reference:
                // Nothing to commit: the profile was saved field by field as
                // each question was answered, so this only says the person has
                // read the figures. That is why the flow is dismissed by a
                // callback rather than by the profile becoming complete —
                // otherwise answering the last question would dismiss the flow
                // and nobody would ever see this screen.
                Button("Start logging", action: onDone)
                    .buttonStyle(WelliePrimaryButtonStyle())
            }
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.bottom, 16)
        .padding(.top, 8)
        .background(WellieTheme.background)
    }
}

// MARK: - The questions

/// The six the arithmetic needs, in the order they are asked.
///
/// Goal first because it is the only one that is a preference rather than a
/// fact, and answering it first makes the rest read as the app working out
/// *your* number rather than interrogating you. The body figures follow in the
/// order a person would say them.
private enum Question: CaseIterable {
    case goal
    case referenceSex
    case age
    case height
    case weight
    case activity

    /// Answered *and* usable. The bounds are `NutritionProfile`'s own: the
    /// published equations begin at 19, and the upper limits keep a slipped
    /// digit from becoming health guidance.
    func isAnswered(in profile: NutritionProfile) -> Bool {
        switch self {
        case .goal: profile.goal != nil
        case .referenceSex: profile.referenceSex != nil
        case .activity: profile.activityLevel != nil
        case .age: profile.ageYears.map { 19...120 ~= $0 } ?? false
        case .height: profile.heightCentimeters.map { 120...230 ~= $0 } ?? false
        case .weight: profile.weightKilograms.map { 35...350 ~= $0 } ?? false
        }
    }

    var title: String {
        switch self {
        case .goal: "What are you after?"
        case .referenceSex: "Which energy equation should we use?"
        case .age: "How old are you?"
        case .height: "How tall are you?"
        case .weight: "What do you weigh?"
        case .activity: "How active is a normal week?"
        }
    }

    var detail: String? {
        switch self {
        case .goal: "It sets where your daily energy sits. You can change it later."
        case .referenceSex:
            "The current adult equations publish two references. This picks which one your estimate uses — it is not a claim about you."
        case .age: "The published equations use it directly."
        case .height: nil
        case .weight: "Roughly is fine. It moves your protein figure as well as your energy."
        case .activity: "Pick the ordinary week, not the busiest one."
        }
    }
}

private extension Array {
    /// The question at an index that a `back` may have left behind.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
