import EatsomeCore
import SwiftUI

/// The editor behind the three rows of *Your numbers*.
///
/// One sheet, two sections, because the rows are two things: the goal is a
/// choice, and the body is four figures. "Daily reference" is not editable —
/// it is what the other two produce, and a person who wants a different
/// reference changes the inputs, not the output. Tapping it lands here on the
/// body section for that reason.
///
/// Every field is optional and stays optional. An empty field is a fact the
/// screens respond to by printing no denominator, and a default filled in here
/// would be a reference for someone who does not exist.
struct NumbersSheet: View {
    enum Section: String, Identifiable {
        case goal, body
        var id: String { rawValue }
    }

    let section: Section

    @Environment(EatsomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var readingHealth = false
    /// What the last read of Health came to, in words. Nil before anyone asks.
    @State private var healthResult: String?

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(section == .goal ? "Goal" : "Body & activity")
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
            }
            .padding(.top, 16)
            .padding(.horizontal, WellieTheme.screenInset)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch section {
                    case .goal: goal($store.profile)
                    case .body: body($store.profile)
                    }
                    reference
                        .padding(.top, 8)
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .wellieScreen()
    }

    // MARK: Goal

    private func goal(_ profile: Binding<NutritionProfile>) -> some View {
        choices(profile.goal)
    }

    // MARK: Body

    private func body(_ profile: Binding<NutritionProfile>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            card {
                pickerRow("Reference equation") {
                    Picker("Reference equation", selection: profile.referenceSex) {
                        Text("Not set").tag(NutritionProfile.ReferenceSex?.none)
                        ForEach(NutritionProfile.ReferenceSex.allCases, id: \.self) {
                            Text($0.displayName).tag(Optional($0))
                        }
                    }
                }
                WellieRowDivider()
                numberRow("Age", unit: "years", value: profile.ageYears.doubleBinding, range: 19...120, step: 1, decimals: 0)
                WellieRowDivider()
                numberRow("Height", unit: "cm", value: profile.heightCentimeters, range: 120...230, step: 1, decimals: 0)
                WellieRowDivider()
                numberRow("Weight", unit: "kg", value: profile.weightKilograms, range: 35...350, step: 0.5, decimals: 1)
            }
            WellieCaption("The adult 2023 reference equations are sex-specific. This asks which published equation to use; it is not a claim about you.")
                .padding(.horizontal, 6)

            healthRow(profile)

            choices(profile.activityLevel)
                .padding(.top, 8)
        }
    }

    /// Fill the blanks from Health.
    ///
    /// Blanks only, and that is the whole of the rule. A person who typed 74 kg
    /// and then tapped this would not expect it to become 71.4 because a scale
    /// disagrees; a field they clear with its own × is a field they have asked
    /// Health to answer. Non-destructive is also what makes the button safe to
    /// press twice.
    ///
    /// What it says afterwards never claims access was granted. Read
    /// authorization in HealthKit is privacy-preserving on purpose — a refusal
    /// is indistinguishable from somebody who has never owned a scale — so
    /// "nothing to fill in" is the only honest thing to say about an empty
    /// answer, and it is true either way.
    @ViewBuilder
    private func healthRow(_ profile: Binding<NutritionProfile>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await fillFromHealth(profile) }
            } label: {
                HStack(spacing: 10) {
                    if readingHealth {
                        ProgressView().tint(WellieTheme.accent)
                    } else {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text("Fill the blanks from Apple Health")
                        .font(WellieTheme.font(14.5, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(WellieTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .wellieSurface()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(readingHealth)

            WellieCaption(healthResult ?? "Read only, and only about your body: age, height, weight, body fat, and the energy your activity level is inferred from.")
                .padding(.horizontal, 6)
        }
        .padding(.top, 8)
    }

    private func fillFromHealth(_ profile: Binding<NutritionProfile>) async {
        readingHealth = true
        healthResult = nil
        defer { readingHealth = false }
        do {
            try await HealthKitBridge.shared.requestAuthorization()
            let health = try await HealthKitBridge.shared.loadProfile()
            var filled: [String] = []
            func take<T>(_ field: WritableKeyPath<NutritionProfile, T?>, _ value: T?, _ name: String) {
                guard profile.wrappedValue[keyPath: field] == nil, let value else { return }
                profile.wrappedValue[keyPath: field] = value
                filled.append(name)
            }
            take(\.ageYears, health.ageYears, "age")
            take(\.referenceSex, health.referenceSex, "reference equation")
            take(\.heightCentimeters, health.heightCentimeters, "height")
            take(\.weightKilograms, health.weightKilograms, "weight")
            take(\.bodyFatPercentage, health.bodyFatPercentage, "body fat")
            take(\.activityLevel, health.activityLevel, "activity")

            healthResult = filled.isEmpty
                ? "Health had nothing to add. Clear a figure with its × and tap again to let Health answer it."
                : "Filled in \(ListFormatter.localizedString(byJoining: filled)) from Health."
        } catch {
            healthResult = error.localizedDescription
        }
    }

    /// What the inputs produce, live, so the person sees the reference move
    /// as they type rather than discovering it on Today.
    @ViewBuilder
    private var reference: some View {
        if let targets = store.dailyTargets {
            WellieCaption(
                "Daily reference: \(EatsomeFormat.whole(targets.kcal)) kcal, \(EatsomeFormat.whole(targets.protein)) g protein."
            )
            .padding(.horizontal, 6)
        } else {
            WellieCaption("Fill in the four body figures and a goal, and the daily reference appears on Today.")
                .padding(.horizontal, 6)
        }
    }

    // MARK: Rows

    /// A card of choices: one row per case, a name, a line of detail, and a
    /// tick on the one in force.
    ///
    /// Goal and activity were the same list written twice, differing only in
    /// which cases they enumerated and which field they set — and the copies
    /// had already begun to disagree, because only one of them told VoiceOver
    /// which row was selected. One function, and the fact that both enums
    /// answer `displayName` and `detail` is what `ChoiceOption` states.
    private func choices<Option: ChoiceOption>(_ selection: Binding<Option?>) -> some View {
        card {
            ForEach(Array(Option.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 { WellieRowDivider() }
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.displayName)
                                .font(WellieTheme.font(15, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                            Text(option.detail)
                                .font(WellieTheme.font(12.5, weight: .regular))
                                .foregroundStyle(WellieTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if selection.wrappedValue == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(WellieTheme.accent)
                        }
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == option ? [.isSelected] : [])
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .wellieSurface()
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder picker: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer()
            picker()
                .labelsHidden()
                .tint(WellieTheme.accent)
        }
        .padding(.vertical, 8)
    }

    /// A figure with a stepper. `nil` is drawn as "—" and the first tap of the
    /// stepper starts from the bottom of the plausible range rather than from
    /// zero, so an age never passes through 1.
    private func numberRow(
        _ title: String,
        unit: String,
        value: Binding<Double?>,
        range: ClosedRange<Double>,
        step: Double,
        decimals: Int
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            Text(value.wrappedValue.map { "\($0.formatted(.number.precision(.fractionLength(decimals)))) \(unit)" } ?? "—")
                .font(WellieTheme.font(14, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .monospacedDigit()
            Stepper(
                title,
                onIncrement: { value.wrappedValue = min(range.upperBound, (value.wrappedValue ?? range.lowerBound - step) + step) },
                onDecrement: { value.wrappedValue = max(range.lowerBound, (value.wrappedValue ?? range.lowerBound + step) - step) }
            )
            .labelsHidden()
            .tint(WellieTheme.accent)
            if value.wrappedValue != nil {
                Button {
                    value.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(WellieTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .padding(.vertical, 10)
    }
}

/// A profile field that is a choice from a fixed list, drawn as one.
///
/// Declared here rather than in Core because it describes how a row is drawn,
/// not what a profile is: `detail` is a sentence for a person reading a sheet,
/// and nothing computes with it.
protocol ChoiceOption: Hashable, CaseIterable {
    var displayName: String { get }
    var detail: String { get }
}

extension NutritionProfile.Goal: ChoiceOption {}
extension NutritionProfile.ActivityLevel: ChoiceOption {}

private extension Binding where Value == Int? {
    var doubleBinding: Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue.map(Double.init) },
            set: { wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }
}
