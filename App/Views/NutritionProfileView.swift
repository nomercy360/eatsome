import ShamanCore
import SwiftUI

/// The body inputs the adult DRI energy equations actually use. Health-filled
/// fields are read-only here so there is one source of truth; they can be edited
/// in the Health app.
struct NutritionBodyEditor: View {
    @Binding var profile: NutritionProfile
    let health: HealthProfileSnapshot

    var body: some View {
        VStack(spacing: 0) {
            ageRow
            WellieRowDivider()
            referenceRow
            WellieRowDivider()
            decimalRow(
                title: "Height",
                unit: "cm",
                value: $profile.heightCentimeters,
                healthValue: health.heightCentimeters,
                decimals: 0
            )
            WellieRowDivider()
            decimalRow(
                title: "Weight",
                unit: "kg",
                value: $profile.weightKilograms,
                healthValue: health.weightKilograms,
                decimals: 1
            )
            WellieRowDivider()
            decimalRow(
                title: "Body fat",
                unit: "% · optional",
                value: $profile.bodyFatPercentage,
                healthValue: health.bodyFatPercentage,
                decimals: 1
            )
        }
        .wellieListCard()
    }

    private var ageRow: some View {
        HStack(spacing: 12) {
            fieldLabel("Age", fromHealth: health.ageYears != nil)
            Spacer(minLength: 12)
            TextField(
                "—",
                text: Binding(
                    get: { profile.ageYears.map(String.init) ?? "" },
                    set: { profile.ageYears = Int($0.filter(\.isNumber)) }
                )
            )
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .disabled(health.ageYears != nil)
            .frame(width: 72)
            Text("years")
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
        .profileRow()
    }

    private var referenceRow: some View {
        HStack(spacing: 12) {
            fieldLabel("Energy equation", fromHealth: health.referenceSex != nil)
            Spacer(minLength: 10)
            if let reference = health.referenceSex {
                Text(reference.displayName)
                    .font(WellieTheme.font(14.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
            } else {
                Picker("Energy equation", selection: $profile.referenceSex) {
                    Text("Choose").tag(nil as NutritionProfile.ReferenceSex?)
                    ForEach(NutritionProfile.ReferenceSex.allCases, id: \.self) { reference in
                        Text(reference.displayName).tag(reference as NutritionProfile.ReferenceSex?)
                    }
                }
                .labelsHidden()
            }
        }
        .profileRow()
    }

    private func decimalRow(
        title: String,
        unit: String,
        value: Binding<Double?>,
        healthValue: Double?,
        decimals: Int
    ) -> some View {
        HStack(spacing: 12) {
            fieldLabel(title, fromHealth: healthValue != nil)
            Spacer(minLength: 12)
            TextField(
                "—",
                text: Binding(
                    get: { value.wrappedValue.map { format($0, decimals: decimals) } ?? "" },
                    set: { value.wrappedValue = Double($0.replacingOccurrences(of: ",", with: ".")) }
                )
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .disabled(healthValue != nil)
            .frame(width: 72)
            Text(unit)
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .frame(minWidth: 30, alignment: .leading)
        }
        .profileRow()
    }

    private func fieldLabel(_ title: String, fromHealth: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            if fromHealth { WellieMeta("From Health") }
        }
    }

    private func format(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...decimals)))
    }
}

struct NutritionActivityPicker: View {
    @Binding var selection: NutritionProfile.ActivityLevel?
    var healthValue: NutritionProfile.ActivityLevel?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(NutritionProfile.ActivityLevel.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { WellieRowDivider() }
                Button {
                    guard healthValue == nil else { return }
                    selection = level
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(level.displayName)
                                    .font(WellieTheme.font(15.5, weight: .semibold))
                                if healthValue == level { WellieMeta("From Health") }
                            }
                            Text(level.detail)
                                .font(WellieTheme.font(12.5, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selection == level ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(selection == level ? WellieTheme.blue : WellieTheme.outline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .wellieListCard()
    }
}

struct NutritionGoalPicker: View {
    @Binding var selection: NutritionProfile.Goal?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(NutritionProfile.Goal.allCases.enumerated()), id: \.element) { index, goal in
                if index > 0 { WellieRowDivider() }
                Button { selection = goal } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(goal.displayName)
                                .font(WellieTheme.font(15.5, weight: .semibold))
                            Text(goal.detail)
                                .font(WellieTheme.font(12.5, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: selection == goal ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(selection == goal ? WellieTheme.blue : WellieTheme.outline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .wellieListCard()
    }
}

struct DailyReferenceSummary: View {
    let profile: NutritionProfile
    let targets: DailyTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    WellieMeta("Daily energy")
                    Text("~\(Int(targets.kcal)) kcal")
                        .font(WellieTheme.font(25, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                }
                Spacer(minLength: 12)
                if targets.goalAdjustmentKcal != 0 {
                    Text(adjustment)
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(targets.goalAdjustmentKcal < 0 ? WellieTheme.attention : WellieTheme.blue)
                }
            }

            FlowLayout(spacing: 7, lineSpacing: 7) {
                WellieChip(text: "Protein \(Int(targets.protein)) g", style: .outline)
                WellieChip(text: "Carbs \(range(targets.carbohydrateRange)) g", style: .outline)
                WellieChip(text: "Fat \(range(targets.fatRange)) g", style: .outline)
            }

            if let leanMass = profile.leanMassKilograms {
                WellieMeta("Approx. lean mass \(leanMass.formatted(.number.precision(.fractionLength(1)))) kg")
            }

            WellieCaption(
                "Maintenance is ~\(Int(targets.maintenanceKcal)) kcal. Based on the 2023 adult Dietary Reference Intakes; real needs vary, so use the trend in body weight to adjust it."
            )

            if profile.goal == .loseWeight,
               profile.bodyMassIndex.map({ $0 < 18.5 }) == true {
                WellieCaption("No deficit was applied because the entered BMI is below the adult reference range.")
            }
        }
    }

    private var adjustment: String {
        let value = Int(abs(targets.goalAdjustmentKcal))
        return targets.goalAdjustmentKcal < 0 ? "−\(value) from maintenance" : "+\(value) over maintenance"
    }

    private func range(_ value: ClosedRange<Double>) -> String {
        "\(Int(value.lowerBound))–\(Int(value.upperBound))"
    }
}

struct NutritionProfileSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NutritionProfile()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    WellieSectionTitle(text: "Your profile", detail: "Health fills what it can")
                    NutritionBodyEditor(profile: $draft, health: model.editableHealthProfile)

                    WellieSectionTitle(text: "Activity", detail: "Usual, not your best day")
                    NutritionActivityPicker(
                        selection: $draft.activityLevel,
                        healthValue: model.editableHealthProfile.activityLevel
                    )

                    WellieSectionTitle(text: "Goal")
                    NutritionGoalPicker(selection: $draft.goal)

                    if let targets = DailyTargets.forProfile(draft) {
                        DailyReferenceSummary(profile: draft, targets: targets)
                            .wellieCard(color: WellieTheme.ice)
                    } else {
                        WellieCaption("Age 19+, equation reference, height, weight, activity and goal are required. Body fat is optional.")
                    }

                    WellieCaption("This is a planning reference for healthy adults, not medical nutrition guidance or a pregnancy/breastfeeding equation.")
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("Daily reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.saveNutritionProfile(draft)
                        dismiss()
                    }
                    .font(WellieTheme.font(15, weight: .bold))
                }
            }
            .onAppear { draft = model.nutritionProfile }
        }
        .wellieScreen()
    }
}

private extension View {
    func profileRow() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}
