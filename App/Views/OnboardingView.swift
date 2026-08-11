import ShamanCore
import SwiftUI

/// Health-first setup for the redesigned daily nutrition reference.
///
/// Apple Health supplies whatever it already knows. The flow then asks only
/// for missing body inputs, confirms activity, asks for a goal and leaves body
/// fat optional. Each missing value gets one screen so the setup never turns
/// into a form.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var route = Route.health
    @State private var profile = NutritionProfile()
    @State private var loadedProfile = false
    @State private var connectingHealth = false
    @State private var returnAfterEdit: Route?
    @State private var healthOverrides: Set<AppModel.NutritionProfileField> = []
    @State private var showingFirstMealLog = false

    private enum Route: Hashable {
        case health
        case healthReview
        case age
        case referenceSex
        case height
        case weight
        case activity
        case goal
        case bodyFat
        case summary
    }

    var body: some View {
        Group {
            switch route {
            case .health: healthAsk
            case .healthReview: healthReview
            case .age: ageAsk
            case .referenceSex: referenceSexAsk
            case .height: heightAsk
            case .weight: weightAsk
            case .activity: activityAsk
            case .goal: goalAsk
            case .bodyFat: bodyFatAsk
            case .summary: summary
            }
        }
        .id(route)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .animation(WellieMotion.step(reduceMotion), value: route)
        .onAppear {
            guard !loadedProfile else { return }
            profile = model.nutritionProfile
            healthOverrides = model.nutritionProfileHealthOverrides
            loadedProfile = true
        }
        .sheet(isPresented: $showingFirstMealLog, onDismiss: finishOnboarding) {
            LogMealSheet()
        }
        .wellieScreen()
    }

    // MARK: - Health

    private var healthAsk: some View {
        onboardingPage(progress: 1) {
            VStack(alignment: .leading, spacing: 0) {
                onboardingTitle(
                    "Connect Apple Health?",
                    detail: "If you do, we read what's already there and skip those questions."
                )

                VStack(spacing: 0) {
                    permissionRow("Date of birth")
                    WellieRowDivider()
                    permissionRow("Height & weight")
                    WellieRowDivider()
                    permissionRow("Body fat, if measured")
                    WellieRowDivider()
                    permissionRow("Workouts & sleep")
                }
                .wellieListCard()
                .padding(.top, 28)

                WellieCaption(
                    "We never write to Health, and nothing leaves your phone unless you log it."
                )
                .padding(.horizontal, 10)
                .padding(.top, 18)

                if let error = model.healthError {
                    Text(error)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } actions: {
            Button {
                connectingHealth = true
                Task {
                    await model.connectHealth()
                    connectingHealth = false
                    guard model.healthError == nil else { return }
                    profile = model.nutritionProfile
                    if healthFilledCount > 0 {
                        navigate(to: .healthReview)
                    } else {
                        navigate(to: firstMissingBodyRoute)
                    }
                }
            } label: {
                if connectingHealth {
                    ProgressView()
                        .tint(WellieTheme.onAccent)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect Health")
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: !connectingHealth))
            .disabled(connectingHealth)

            Button("I'll enter it myself") {
                navigate(to: firstMissingBodyRoute)
            }
            .buttonStyle(WellieQuietButtonStyle())
        }
    }

    private func permissionRow(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(WellieTheme.font(14.5, weight: .medium))
                .foregroundStyle(WellieTheme.ink)
            Spacer()
            Text("read")
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
        }
        .padding(.vertical, 14)
    }

    private var healthReview: some View {
        onboardingPage(progress: 2) {
            VStack(alignment: .leading, spacing: 0) {
                onboardingTitle(
                    "Health filled \(healthCountWord) in.",
                    detail: "Check them and we'll move on. Tap any to change."
                )

                VStack(spacing: 10) {
                    if let age = rawHealth.ageYears {
                        reviewRow(
                            title: "Age",
                            value: "\(age)",
                            destination: .age
                        )
                    }
                    if let height = rawHealth.heightCentimeters {
                        reviewRow(
                            title: "Height",
                            value: "\(height.formatted(.number.precision(.fractionLength(0)))) cm",
                            destination: .height
                        )
                    }
                    if let weight = rawHealth.weightKilograms {
                        reviewRow(
                            title: "Weight",
                            value: "\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg",
                            destination: .weight
                        )
                    }
                    if let bodyFat = rawHealth.bodyFatPercentage {
                        reviewRow(
                            title: "Body fat",
                            value: "\(bodyFat.formatted(.number.precision(.fractionLength(0...1))))%",
                            destination: .bodyFat
                        )
                    } else {
                        missingReviewRow
                    }
                }
                .padding(.top, 28)
            }
        } actions: {
            Button("Looks right") {
                model.saveNutritionProfile(profile, overridingHealthFields: healthOverrides)
                navigate(to: firstMissingBodyRoute)
            }
            .buttonStyle(WelliePrimaryButtonStyle())
        }
    }

    private func reviewRow(
        title: String,
        value: String,
        destination: Route
    ) -> some View {
        Button {
            returnAfterEdit = .healthReview
            navigate(to: destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(WellieTheme.onAccent)
                    .frame(width: 23, height: 23)
                    .background(WellieTheme.protein, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(WellieTheme.font(12.5, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                    Text(value)
                        .font(WellieTheme.font(19, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                }

                Spacer(minLength: 8)

                Text("Change")
                    .font(WellieTheme.font(12.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                WellieTheme.surface,
                in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Uses a manual value instead of the value from Health")
    }

    private var missingReviewRow: some View {
        HStack(spacing: 14) {
            Circle()
                .strokeBorder(WellieTheme.outline, lineWidth: 2)
                .frame(width: 23, height: 23)
            VStack(alignment: .leading, spacing: 3) {
                Text("Body fat")
                    .font(WellieTheme.font(12.5))
                    .foregroundStyle(WellieTheme.muted)
                Text("Not in Health — we'll ask")
                    .font(WellieTheme.font(14, weight: .medium))
                    .foregroundStyle(WellieTheme.body)
            }
            Spacer()
        }
        .padding(18)
        .background(
            WellieTheme.well,
            in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                .strokeBorder(WellieTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    // MARK: - Missing body inputs

    private var ageAsk: some View {
        numberPage(
            progress: 2,
            title: "Your age?",
            value: Binding(
                get: { profile.ageYears ?? 34 },
                set: { profile.ageYears = $0 }
            ),
            range: 19...120,
            display: String.init,
            unit: "years"
        ) {
            commit(.age, next: nextAfterBodyField(.age))
        }
    }

    private var referenceSexAsk: some View {
        onboardingPage(progress: 2) {
            VStack(alignment: .leading, spacing: 0) {
                requiredTitle("Which energy equation should we use?")

                VStack(spacing: 12) {
                    ForEach(NutritionProfile.ReferenceSex.allCases, id: \.self) { reference in
                        choiceCard(
                            title: reference.displayName,
                            detail: reference == .female
                                ? "Uses the published adult female reference"
                                : "Uses the published adult male reference",
                            selected: profile.referenceSex == reference
                        ) {
                            profile.referenceSex = reference
                        }
                    }
                }
                .padding(.top, 34)

                WellieCaption(
                    "The current adult energy equations publish two references. Choose the one your daily estimate should use."
                )
                .padding(.horizontal, 8)
                .padding(.top, 18)
            }
        } actions: {
            let enabled = profile.referenceSex != nil
            Button("Continue") {
                commit(.referenceSex, next: nextAfterBodyField(.referenceSex))
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: enabled))
            .disabled(!enabled)
        }
    }

    private var heightAsk: some View {
        numberPage(
            progress: 2,
            title: "Your height?",
            value: Binding(
                get: { Int((profile.heightCentimeters ?? 170).rounded()) },
                set: { profile.heightCentimeters = Double($0) }
            ),
            range: 120...230,
            display: String.init,
            unit: "cm"
        ) {
            commit(.height, next: nextAfterBodyField(.height))
        }
    }

    private var weightAsk: some View {
        numberPage(
            progress: 2,
            title: "Your weight?",
            value: Binding(
                get: { Int(((profile.weightKilograms ?? 70) * 10).rounded()) },
                set: { profile.weightKilograms = Double($0) / 10 }
            ),
            range: 350...3500,
            display: { scaled in
                (Double(scaled) / 10).formatted(.number.precision(.fractionLength(1)))
            },
            unit: "kg"
        ) {
            commit(.weight, next: nextAfterBodyField(.weight))
        }
    }

    private func numberPage(
        progress: Int,
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        display: @escaping (Int) -> String,
        unit: String,
        continueAction: @escaping () -> Void
    ) -> some View {
        onboardingPage(progress: progress) {
            VStack(alignment: .leading, spacing: 0) {
                requiredTitle(title)

                VStack(spacing: 8) {
                    Text(display(value.wrappedValue))
                        .font(WellieTheme.font(78, weight: .black))
                        .tracking(-3)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(unit)
                        .font(WellieTheme.font(14, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)

                HorizontalNumberPicker(
                    selection: value,
                    values: range,
                    display: display
                )
                .padding(.top, 34)
            }
        } actions: {
            Button("Continue", action: continueAction)
                .buttonStyle(WelliePrimaryButtonStyle())
        }
    }

    // MARK: - Activity and goal

    private var activityAsk: some View {
        onboardingPage(progress: 3) {
            VStack(alignment: .leading, spacing: 0) {
                onboardingTitle(
                    "How active is a normal week?",
                    detail: activityDetail
                )

                VStack(spacing: 10) {
                    ForEach(NutritionProfile.ActivityLevel.allCases, id: \.self) { level in
                        activityCard(level)
                    }
                }
                .padding(.top, 28)
            }
        } actions: {
            let enabled = profile.activityLevel != nil
            Button("Continue") {
                commit(.activity, next: .goal)
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: enabled))
            .disabled(!enabled)
        }
    }

    private var activityDetail: String {
        if let value = rawHealth.activityLevel {
            return "Health suggests \(activityName(value).lowercased()) — pick what feels true."
        }
        return "Pick the ordinary week, not the busiest one."
    }

    private func activityCard(_ level: NutritionProfile.ActivityLevel) -> some View {
        let selected = profile.activityLevel == level
        let fromHealth = rawHealth.activityLevel == level

        return Button {
            profile.activityLevel = level
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activityName(level))
                        .font(WellieTheme.font(16, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Text(activityDescription(level))
                        .font(WellieTheme.font(12.5, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WellieTheme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(WellieTheme.accent, in: Circle())
                }

                if fromHealth {
                    WellieMeta("From Health", size: 11, color: WellieTheme.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WellieTheme.raised, in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .selectionCard(selected: selected)
        }
        .buttonStyle(.plain)
    }

    private var goalAsk: some View {
        onboardingPage(progress: 4) {
            VStack(alignment: .leading, spacing: 0) {
                onboardingTitle("What are you after?")

                VStack(spacing: 12) {
                    goalCard(.loseWeight, symbol: "arrow.down")
                    goalCard(.gainMuscle, symbol: "arrow.up")
                    goalCard(.maintain, symbol: "equal")
                }
                .padding(.top, 32)
            }
        } actions: {
            let enabled = profile.goal != nil
            Button("Continue") {
                model.saveNutritionProfile(profile, overridingHealthFields: healthOverrides)
                navigate(to: profile.bodyFatPercentage == nil ? .bodyFat : .summary)
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: enabled))
            .disabled(!enabled)
        }
    }

    private func goalCard(_ goal: NutritionProfile.Goal, symbol: String) -> some View {
        let selected = profile.goal == goal

        return Button {
            profile.goal = goal
        } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(selected ? WellieTheme.onAccent : WellieTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(selected ? WellieTheme.accent : WellieTheme.raised, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(goalName(goal))
                        .font(WellieTheme.font(18, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Text(goalDescription(goal))
                        .font(WellieTheme.font(12.5))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(WellieTheme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(WellieTheme.accent, in: Circle())
                }
            }
            .selectionCard(selected: selected, verticalPadding: 20)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Optional body fat

    private var bodyFatAsk: some View {
        onboardingPage(progress: 5) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    WellieMeta(rawHealth.bodyFatPercentage == nil ? "Not in Health · Optional" : "Manual override · Optional")
                    Text("Roughly what's your body fat?")
                        .font(WellieTheme.font(31, weight: .black))
                        .tracking(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 1) {
                        Text(Int((profile.bodyFatPercentage ?? 18).rounded()).formatted())
                            .font(WellieTheme.font(70, weight: .black))
                            .tracking(-3)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(WellieTheme.font(32, weight: .bold))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    Text(bodyFatDescription)
                        .font(WellieTheme.font(14, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 38)

                Slider(value: bodyFatBinding, in: 5...50, step: 1)
                    .tint(WellieTheme.accent)
                    .padding(.top, 26)

                HStack {
                    Text("5%")
                    Spacer()
                    Text("25%")
                    Spacer()
                    Text("50%+")
                }
                .font(WellieTheme.font(11.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .padding(.top, 4)

                HStack(spacing: 10) {
                    ForEach(Array(bodyFatRanges.enumerated()), id: \.offset) { index, label in
                        bodyFatRangeCard(label, selected: bodyFatRangeIndex == index)
                    }
                }
                .padding(.top, 28)
            }
        } actions: {
            Button("Continue") {
                commit(.bodyFat, next: .summary)
            }
            .buttonStyle(WelliePrimaryButtonStyle())

            Button("Not sure — skip this") {
                profile.bodyFatPercentage = nil
                commit(.bodyFat, next: .summary)
            }
            .buttonStyle(WellieQuietButtonStyle())
        }
    }

    private var bodyFatBinding: Binding<Double> {
        Binding(
            get: { profile.bodyFatPercentage ?? 18 },
            set: { profile.bodyFatPercentage = $0 }
        )
    }

    private var bodyFatDescription: String {
        let value = profile.bodyFatPercentage ?? 18
        return switch value {
        case ..<14: "Lean estimate"
        case ..<21: "Athletic, some definition"
        case ..<29: "Around the middle range"
        default: "Above the middle range"
        }
    }

    private var bodyFatRanges: [String] {
        switch profile.referenceSex {
        case .female: ["18–24%", "25–31%", "32–38%"]
        case .male: ["10–14%", "15–20%", "21–27%"]
        case nil: ["10–19%", "20–29%", "30–39%"]
        }
    }

    private var bodyFatRangeIndex: Int {
        let value = profile.bodyFatPercentage ?? 18
        return switch profile.referenceSex {
        case .female:
            value < 25 ? 0 : (value < 32 ? 1 : 2)
        case .male:
            value < 15 ? 0 : (value < 21 ? 1 : 2)
        case nil:
            value < 20 ? 0 : (value < 30 ? 1 : 2)
        }
    }

    private func bodyFatRangeCard(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(WellieTheme.font(11, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? WellieTheme.accent : WellieTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(12)
            .frame(height: 112)
            .background(
                selected ? WellieTheme.accent.opacity(0.08) : WellieTheme.well,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? WellieTheme.accent : WellieTheme.hairline, lineWidth: selected ? 1.5 : 1)
            }
    }

    // MARK: - Targets

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    WellieMeta("Your daily targets")
                        .padding(.top, 28)

                    if let targets = DailyTargets.forProfile(profile) {
                        Text("\(Int(targets.kcal).formatted()) kcal,\n\(Int(targets.protein).formatted()) g protein.")
                            .font(WellieTheme.font(33, weight: .black))
                            .tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)

                        Text(summarySentence)
                            .font(WellieTheme.font(14, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 14)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            TargetTile(
                                label: "Energy",
                                value: Int(targets.kcal).formatted(),
                                detail: "kcal / day"
                            )
                            TargetTile(
                                label: "Protein",
                                value: "\(Int(targets.protein)) g",
                                detail: proteinRatio(targets)
                            )
                            TargetTile(label: "Carbs", value: "\(displayCarbs(targets)) g")
                            TargetTile(label: "Fat", value: "\(displayFat(targets)) g")
                        }
                        .padding(.top, 28)
                    } else {
                        Text("A required detail is still missing.")
                            .font(WellieTheme.font(24, weight: .bold))
                            .padding(.top, 14)
                        WellieCaption("Review age, energy equation, height, weight, activity and goal.")
                            .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
            }

            if DailyTargets.forProfile(profile) != nil {
                Button("Log my first meal") {
                    model.saveNutritionProfile(profile, overridingHealthFields: healthOverrides)
                    showingFirstMealLog = true
                }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            } else {
                Button("Review missing details") {
                    navigate(to: firstMissingBodyRoute)
                }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.background.ignoresSafeArea())
    }

    // MARK: - Shared layout

    private func onboardingPage<Content: View, Actions: View>(
        progress: Int,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            OnboardingProgress(current: progress)
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 36)

            ScrollView {
                content()
                    .padding(.horizontal, 30)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 6) {
                actions()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WellieTheme.background.ignoresSafeArea())
    }

    private func onboardingTitle(_ title: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(WellieTheme.font(31, weight: .black))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(WellieTheme.font(15, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requiredTitle(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieMeta("Not in Health · Required")
            Text(title)
                .font(WellieTheme.font(31, weight: .black))
                .tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choiceCard(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(WellieTheme.font(17, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Text(detail)
                        .font(WellieTheme.font(12.5))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected ? WellieTheme.accent : WellieTheme.outline)
            }
            .selectionCard(selected: selected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Routing and persistence

    private var rawHealth: HealthProfileSnapshot { model.healthSnapshot.profile }

    private var healthFilledCount: Int {
        [
            rawHealth.ageYears != nil,
            rawHealth.heightCentimeters != nil,
            rawHealth.weightKilograms != nil,
            rawHealth.bodyFatPercentage != nil
        ]
        .filter { $0 }
        .count
    }

    private var healthCountWord: String {
        switch healthFilledCount {
        case 1: "one"
        case 2: "two"
        case 3: "three"
        case 4: "four"
        default: "\(healthFilledCount)"
        }
    }

    private var firstMissingBodyRoute: Route {
        if profile.ageYears == nil { return .age }
        if profile.referenceSex == nil { return .referenceSex }
        if profile.heightCentimeters == nil { return .height }
        if profile.weightKilograms == nil { return .weight }
        return .activity
    }

    private func nextAfterBodyField(_ field: AppModel.NutritionProfileField) -> Route {
        switch field {
        case .age:
            if profile.referenceSex == nil { return .referenceSex }
            if profile.heightCentimeters == nil { return .height }
            if profile.weightKilograms == nil { return .weight }
        case .referenceSex:
            if profile.heightCentimeters == nil { return .height }
            if profile.weightKilograms == nil { return .weight }
        case .height:
            if profile.weightKilograms == nil { return .weight }
        case .weight, .bodyFat, .activity:
            break
        }
        return .activity
    }

    private func navigate(to destination: Route) {
        prepare(destination)
        withAnimation(WellieMotion.step(reduceMotion)) {
            route = destination
        }
    }

    private func prepare(_ destination: Route) {
        switch destination {
        case .age:
            profile.ageYears = profile.ageYears ?? 34
        case .height:
            profile.heightCentimeters = profile.heightCentimeters ?? 170
        case .weight:
            profile.weightKilograms = profile.weightKilograms ?? 70
        case .bodyFat:
            profile.bodyFatPercentage = profile.bodyFatPercentage ?? 18
        default:
            break
        }
    }

    private func commit(_ field: AppModel.NutritionProfileField, next: Route) {
        if returnAfterEdit != nil || healthValueExists(for: field) && differsFromHealth(field) {
            healthOverrides.insert(field)
        }
        model.saveNutritionProfile(profile, overridingHealthFields: healthOverrides)

        if let destination = returnAfterEdit {
            returnAfterEdit = nil
            navigate(to: destination)
        } else {
            navigate(to: next)
        }
    }

    private func finishOnboarding() {
        model.saveNutritionProfile(profile, overridingHealthFields: healthOverrides)
        model.completeOnboarding()
    }

    private func healthValueExists(for field: AppModel.NutritionProfileField) -> Bool {
        switch field {
        case .age: rawHealth.ageYears != nil
        case .referenceSex: rawHealth.referenceSex != nil
        case .height: rawHealth.heightCentimeters != nil
        case .weight: rawHealth.weightKilograms != nil
        case .bodyFat: rawHealth.bodyFatPercentage != nil
        case .activity: rawHealth.activityLevel != nil
        }
    }

    private func differsFromHealth(_ field: AppModel.NutritionProfileField) -> Bool {
        switch field {
        case .age: profile.ageYears != rawHealth.ageYears
        case .referenceSex: profile.referenceSex != rawHealth.referenceSex
        case .height: profile.heightCentimeters != rawHealth.heightCentimeters
        case .weight: profile.weightKilograms != rawHealth.weightKilograms
        case .bodyFat: profile.bodyFatPercentage != rawHealth.bodyFatPercentage
        case .activity: profile.activityLevel != rawHealth.activityLevel
        }
    }

    // MARK: - Copy and target presentation

    private func activityName(_ level: NutritionProfile.ActivityLevel) -> String {
        switch level {
        case .inactive: "Mostly sitting"
        case .lowActive: "Lightly active"
        case .active: "Active"
        case .veryActive: "Very active"
        }
    }

    private func activityDescription(_ level: NutritionProfile.ActivityLevel) -> String {
        switch level {
        case .inactive: "Desk work, little walking"
        case .lowActive: "On your feet, a walk most days"
        case .active: "Training two to four times a week"
        case .veryActive: "Hard training or physical job"
        }
    }

    private func goalName(_ goal: NutritionProfile.Goal) -> String {
        switch goal {
        case .loseWeight: "Lose weight"
        case .gainMuscle: "Gain muscle"
        case .maintain: "Stay where I am"
        }
    }

    private func goalDescription(_ goal: NutritionProfile.Goal) -> String {
        switch goal {
        case .loseWeight: "Slight deficit, protein kept high"
        case .gainMuscle: "Small surplus, protein kept high"
        case .maintain: "Eat around maintenance"
        }
    }

    private var summarySentence: String {
        let age = profile.ageYears.map(String.init) ?? "your age"
        let height = profile.heightCentimeters
            .map { "\(Int($0.rounded())) cm" }
            ?? "your height"
        let weight = profile.weightKilograms
            .map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) kg" }
            ?? "your weight"
        let activity = profile.activityLevel.map { activityName($0).lowercased() } ?? "your activity"
        let goal = profile.goal.map {
            switch $0 {
            case .loseWeight: "losing weight"
            case .gainMuscle: "gaining muscle"
            case .maintain: "maintaining"
            }
        } ?? "your goal"
        return "Built from \(age), \(height), \(weight), \(activity), \(goal). Change any of it in settings."
    }

    private func proteinRatio(_ targets: DailyTargets) -> String? {
        guard let weight = profile.weightKilograms, weight > 0 else { return nil }
        let ratio = targets.protein / weight
        return "\(ratio.formatted(.number.precision(.fractionLength(1)))) g per kg"
    }

    private func displayFat(_ targets: DailyTargets) -> Int {
        let candidate = (targets.kcal * 0.30 / 9).rounded()
        return Int(min(max(candidate, targets.fatRange.lowerBound), targets.fatRange.upperBound))
    }

    private func displayCarbs(_ targets: DailyTargets) -> Int {
        let remaining = (targets.kcal - targets.protein * 4 - Double(displayFat(targets)) * 9) / 4
        return Int(min(max(remaining.rounded(), targets.carbohydrateRange.lowerBound), targets.carbohydrateRange.upperBound))
    }
}

private struct OnboardingProgress: View {
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? WellieTheme.accent : WellieTheme.hairline)
                    .frame(height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current) of 5")
    }
}

private struct HorizontalNumberPicker: View {
    @Binding var selection: Int
    let values: ClosedRange<Int>
    let display: (Int) -> String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(values), id: \.self) { value in
                        Button {
                            selection = value
                        } label: {
                            Text(display(value))
                                .font(
                                    WellieTheme.font(
                                        value == selection ? 29 : nearbySize(value),
                                        weight: value == selection ? .black : .semibold
                                    )
                                )
                                .foregroundStyle(valueColor(value))
                                .frame(minWidth: value == selection ? 70 : 42)
                                .frame(height: 54)
                                .background(
                                    value == selection ? WellieTheme.accent.opacity(0.08) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay {
                                    if value == selection {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(WellieTheme.accent, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(value)
                    }
                }
                .padding(.horizontal, 120)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, value in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
        .frame(height: 58)
        .accessibilityRepresentation {
            Stepper(
                "Selected value: \(display(selection))",
                value: $selection,
                in: values
            )
        }
    }

    private func nearbySize(_ value: Int) -> CGFloat {
        let distance = abs(value - selection)
        if distance <= 1 { return 23 }
        if distance <= 2 { return 19 }
        return 15
    }

    private func valueColor(_ value: Int) -> Color {
        let distance = abs(value - selection)
        if distance == 0 { return WellieTheme.ink }
        if distance <= 1 { return WellieTheme.body }
        return WellieTheme.muted
    }
}

private struct TargetTile: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(WellieTheme.font(12.5))
                .foregroundStyle(WellieTheme.muted)
            Text(value)
                .font(WellieTheme.font(25, weight: .black))
                .foregroundStyle(WellieTheme.ink)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(WellieTheme.font(11.5, weight: .medium))
                    .foregroundStyle(WellieTheme.body)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            WellieTheme.surface,
            in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                .strokeBorder(WellieTheme.hairline, lineWidth: 1)
        }
    }
}

private extension View {
    func selectionCard(selected: Bool, verticalPadding: CGFloat = 17) -> some View {
        padding(.horizontal, 20)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? WellieTheme.accent.opacity(0.08) : WellieTheme.surface,
                in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(selected ? WellieTheme.accent : WellieTheme.hairline, lineWidth: selected ? 1.5 : 1)
            }
    }
}
