import ShamanCore
import SwiftUI

/// Screen `A` — Settings → "What counts".
///
/// Presets are rule lists, not modes. That distinction is the whole screen: any
/// of them can be forked, a fork says out loud that it is yours, and switching
/// re-scores the history you already have rather than starting a new one.
///
/// Only a spec that reproduces a published instrument carries the validated
/// badge, and it is drawn from `DietSpec.instrument` rather than from the name —
/// a diet assembled from steppers must not be able to claim it by calling itself
/// MEDAS.
struct DietPickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var editing: DietSpec?

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                WellieProse(
                    """
                    Your olives measure how well the week fits the diet you choose. Switching \
                    re-scores your history — nothing is read again.
                    """,
                    size: 14.5
                )
                .padding(.horizontal, 6)

                VStack(spacing: 0) {
                    ForEach(Array(model.projection.availableDiets.enumerated()), id: \.element.id) { index, spec in
                        if index > 0 { WellieRowDivider() }
                        row(spec)
                    }
                    WellieRowDivider()
                    makeYourOwn
                }
                .wellieListCard()
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle("What counts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editing) { DietEditorView(spec: $0) }
        .wellieScreen()
    }

    private func row(_ spec: DietSpec) -> some View {
        let isOn = spec.id == model.diet.id
        return Button {
            Task { await model.selectDiet(spec) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(spec.name)
                            .font(WellieTheme.font(15.5, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                        if let instrument = spec.instrument {
                            badge("Validated · \(instrument)")
                        }
                    }
                    Text(subtitle(spec, isOn: isOn))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(WellieTheme.muted)
                        .textCase(.uppercase)
                }
                Spacer(minLength: 8)
                // A fork is editable in place; a preset opens as a fork the
                // moment anything is changed, which is what keeps a preset a
                // fixed point that can be retuned in a later build.
                Button {
                    editing = spec
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                        .wellieHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(spec.name)")

                // A checkmark or an empty ring — never `WellieMark(isMet:)`,
                // whose unmet state is an exclamation mark. A diet you have not
                // chosen is not a warning.
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(isOn ? WellieTheme.blue : WellieTheme.outline)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(isOn ? WellieTheme.ice : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ spec: DietSpec, isOn: Bool) -> String {
        var parts = [spec.ruleSummary]
        if let from = spec.forkedFrom,
           let origin = DietPresets.preset(id: from)?.name {
            parts.append("forked from \(origin)")
        }
        if isOn { parts.append("your diet now") }
        return parts.joined(separator: " · ")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(WellieTheme.metaFont(8.5))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(WellieTheme.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(WellieTheme.blue.opacity(0.4), lineWidth: 1)
            }
    }

    private var makeYourOwn: some View {
        Button {
            editing = model.diet.forked(as: "My plan")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Make your own")
                    .font(WellieTheme.font(15, weight: .bold))
                Spacer(minLength: 8)
                Text("Fork \(model.diet.name)")
                    .font(WellieTheme.metaFont(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(WellieTheme.muted)
            }
            .foregroundStyle(WellieTheme.blue)
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Screen `B` — the diet editor.
///
/// Two sections, and the split is the point. **Goals** are frequency rules with
/// a stepper, averaged into the olives. **Constraints** are kept or broken and
/// sit in their own section with their own history, never averaged — because
/// "4.5 olives, but there was chicken stock in the soup" is what a vegetarian
/// wants to know and precisely what an average is built to hide.
///
/// No nutrition arithmetic anywhere on this screen. Every control says how
/// often, which is what the app can actually watch.
struct DietEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var spec: DietSpec
    @State private var name: String
    private let original: DietSpec

    init(spec: DietSpec) {
        // Editing a preset forks it on arrival rather than on save: a preset is
        // a compiled constant that a later build may retune, and a copy of one
        // that somebody has changed is a different diet with a different name.
        let editable = DietPresets.isPreset(spec.id) ? spec.forked(as: "My \(spec.name.lowercased())") : spec
        _spec = State(initialValue: editable)
        _name = State(initialValue: editable.name)
        original = editable
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                nameCard
                goalsCard
                constraintsCard
                if let target = model.proteinTarget { proteinCard(target) }
                preview
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle(spec.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    var saved = spec
                    saved.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? original.name : name
                    Task {
                        await model.saveDiet(saved)
                        dismiss()
                    }
                }
                .font(WellieTheme.font(15, weight: .bold))
                .disabled(spec == original && name == original.name)
            }
        }
        .wellieScreen()
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            WellieSectionTitle(text: "Your plan", detail: forkedFrom)
            TextField("Name", text: $name)
                .font(WellieTheme.font(17, weight: .bold))
                .padding(14)
                .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
        }
        .wellieCard()
    }

    private var forkedFrom: String? {
        spec.forkedFrom
            .flatMap { DietPresets.preset(id: $0)?.name }
            .map { "Forked from \($0). It is yours now — it does not claim to be a published screener." }
    }

    // MARK: - Goals

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Goals", detail: "Averaged into your olives")

            ForEach(spec.goals) { goal in
                if goal.id != DietPresets.proteinGoalID {
                    goalRow(goal)
                    if goal.id != spec.goals.last?.id { WellieRowDivider() }
                }
            }
        }
        .wellieCard()
    }

    @ViewBuilder
    private func goalRow(_ goal: DietGoal) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DietCopy.plainTitle(goal, in: spec))
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(direction(goal.shape))
                    .font(WellieTheme.metaFont(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(goal.shape.isUpperBound ? WellieTheme.attention : WellieTheme.blue)
            }
            Spacer(minLength: 8)

            if let cadence = goal.shape.cadence, !goal.shape.isHabitShape {
                stepper(goal, cadence: cadence)
            } else {
                // A habit has no threshold to step: it is a question answered
                // once, and its switch lives with the other questions rather
                // than here, where it would look like something to tune.
                Text(goal.shape.isHabitShape ? "Answered in settings" : "On")
                    .font(WellieTheme.metaFont(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .padding(.vertical, 2)
    }

    private func direction(_ shape: DietGoal.Shape) -> String {
        switch shape {
        case .dailyAtLeast, .weeklyAtLeast, .dailyAtLeastGrams: "At least"
        case .dailyBelow, .weeklyBelow: "Less than"
        case .eachMeal: "Each meal"
        case .habit: "A question, not a photograph"
        }
    }

    private func stepper(_ goal: DietGoal, cadence: DietCadence) -> some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "Fewer", enabled: goal.shape.target > 1) {
                retarget(goal, to: goal.shape.target - 1)
            }
            Text("\(Int(goal.shape.target)) / \(cadence.suffix)")
                .font(WellieTheme.font(13, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .frame(width: 62)
                .padding(.vertical, 7)
                .overlay(alignment: .leading) { divider }
                .overlay(alignment: .trailing) { divider }
            stepButton("plus", label: "More", enabled: goal.shape.target < 14) {
                retarget(goal, to: goal.shape.target + 1)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(WellieTheme.outline, lineWidth: 1)
        }
    }

    private var divider: some View {
        Rectangle().fill(WellieTheme.hairline).frame(width: 1)
    }

    private func stepButton(
        _ icon: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? WellieTheme.ink : WellieTheme.faint)
                .frame(width: 32, height: 30)
                .wellieHitTarget()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func retarget(_ goal: DietGoal, to value: Double) {
        guard let index = spec.goals.firstIndex(where: { $0.id == goal.id }) else { return }
        spec.goals[index].shape = goal.shape.withTarget(value)
        // The hand-written sentence stated the old threshold; a generated one
        // states whatever it is now. Dropping it is the honest move — a title
        // saying "twice a day" over a stepper reading 3 is a screen that lies.
        spec.goals[index].plainTitle = nil
        spec.goals[index].title = DietCopy.plainTitle(spec.goals[index], in: spec)
    }

    // MARK: - Constraints

    private var constraintsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Constraints", detail: "Kept or broken, never averaged")

            if spec.constraints.isEmpty {
                WellieCaption(
                    """
                    Nothing here yet. A constraint is a food you do not eat at all — it never \
                    moves your olives, it just says whether it held, and names the meal when it \
                    did not.
                    """
                )
            }

            ForEach(spec.constraints) { constraint in
                constraintRow(constraint)
                if constraint.id != spec.constraints.last?.id { WellieRowDivider() }
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private func constraintRow(_ constraint: DietConstraint) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(constraint.title)
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(constraint.isEnabled ? WellieTheme.ink : WellieTheme.muted)
                Text(constraintDetail(constraint))
                    .font(WellieTheme.metaFont(9.5))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(constraint.isEnabled ? WellieTheme.danger : WellieTheme.muted)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { constraint.isEnabled },
                set: { value in
                    guard let index = spec.constraints.firstIndex(where: { $0.id == constraint.id })
                    else { return }
                    spec.constraints[index].isEnabled = value
                }
            ))
            .labelsHidden()
        }
    }

    private func constraintDetail(_ constraint: DietConstraint) -> String {
        guard constraint.isEnabled else { return "Off" }
        switch constraint.shape {
        case .never:
            let days = model.daysKept(constraint)
            return days > 0 ? "Never · kept \(days) days" : "Never"
        case .eatingWindow(let start, let end):
            return "Between \(hour(start)) and \(hour(end))"
        }
    }

    private func hour(_ value: Double) -> String {
        let whole = Int(value)
        let minutes = Int((value - Double(whole)) * 60)
        return String(format: "%02d:%02d", whole, minutes)
    }

    // MARK: - Protein

    private func proteinCard(_ target: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieSectionTitle(
                text: "Protein",
                detail: "\(Int(target)) g a day, from your weight in Health"
            )
            Toggle(isOn: Binding(
                get: { model.hasProteinGoal },
                set: { model.hasProteinGoal = $0 }
            )) {
                Text("Count it as a goal")
                    .font(WellieTheme.font(15, weight: .semibold))
            }
            WellieCaption(
                """
                The only figure here measured in grams, and the only one estimated rather than \
                counted. Under target costs the day part of an olive, never all of it.
                """
            )
        }
        .wellieCard()
    }

    // MARK: - Preview

    /// What last week would have scored on this plan, before anything is saved.
    ///
    /// It costs one pass over seven days of stored meals and no model call at
    /// all — which is the claim the whole diet engine rests on, made where
    /// somebody can watch it happen.
    private var preview: some View {
        let result = model.score(with: spec.withProteinTarget(model.hasProteinGoal ? model.proteinTarget : nil))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                OliveRow(olives: Int(result.olives.rounded()), size: 15)
                Text(result.isUnderreported
                     ? "Not enough logged days to preview this plan yet."
                     : "Last week would score \(Count.spell(Int(result.olives.rounded()), capitalized: false)) of five on this plan.")
                    .font(WellieTheme.font(13.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.brokenConstraints.isEmpty {
                Text(brokenLine(result))
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wellieCard()
    }

    private func brokenLine(_ result: DietResult) -> String {
        let count = result.brokenConstraints.reduce(0) { $0 + $1.breaks.count }
        let names = result.brokenConstraints.map(\.title).joined(separator: ", ")
        return "\(Count.spell(count)) meal\(count == 1 ? "" : "s") last week would break it: \(names.lowercased())."
    }
}

private extension DietGoal.Shape {
    var isHabitShape: Bool {
        if case .habit = self { return true }
        return false
    }
}
