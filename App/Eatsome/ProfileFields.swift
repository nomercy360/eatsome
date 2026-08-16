import EatsomeCore
import SwiftUI

// The controls the profile is given in, shared by the two places that ask for
// it: `Onboarding`, which asks once and only for what is missing, and
// `NumbersSheet`, where any of it can be changed later. One vocabulary, so
// changing your height afterwards looks like giving it in the first place.

/// A profile field that is a choice from a fixed list, drawn as one.
///
/// Declared here rather than in Core because it describes how a row is drawn,
/// not what a profile is: `detail` is a sentence for a person reading a screen,
/// and nothing computes with it.
protocol ChoiceOption: Hashable, CaseIterable {
    var displayName: String { get }
    var detail: String { get }
}

extension NutritionProfile.Goal: ChoiceOption {}
extension NutritionProfile.ActivityLevel: ChoiceOption {}

/// The reference sex's detail is written here rather than in Core because it
/// is the sentence that keeps the question honest — the field selects a
/// published equation and is not a claim about anybody. Core states the same
/// thing in a doc comment; this is the version a person reads.
extension NutritionProfile.ReferenceSex: ChoiceOption {
    var detail: String {
        switch self {
        case .female: "Uses the published adult female equation"
        case .male: "Uses the published adult male equation"
        }
    }
}

/// The container every group of profile rows sits in.
struct ProfileCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 18)
            .wellieSurface()
    }
}

/// A card of choices: one row per case, a name, a line of detail, and a tick on
/// the one in force.
///
/// Goal and activity were the same list written twice, differing only in which
/// cases they enumerated and which field they set — and the copies had already
/// begun to disagree, because only one of them told VoiceOver which row was
/// selected. One view, and the fact that all three enums answer `displayName`
/// and `detail` is what `ChoiceOption` states.
struct ChoiceRows<Option: ChoiceOption>: View {
    @Binding var selection: Option?

    var body: some View {
        ProfileCard {
            ForEach(Array(Option.allCases.enumerated()), id: \.element) { index, option in
                if index > 0 { WellieRowDivider() }
                Button {
                    selection = option
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
                        if selection == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(WellieTheme.onAccent)
                                .frame(width: 18, height: 18)
                                .background(WellieTheme.accent, in: Circle())
                        }
                    }
                    .padding(.vertical, 14)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
    }
}

/// A figure with a stepper, for **changing** one.
///
/// `nil` draws as "—", and the first tap starts from the bottom of the
/// plausible range rather than from zero so an age never passes through 1. It
/// is the right control for a list of figures a person is revisiting and the
/// wrong one for giving a figure for the first time — see `ProfileWheel`.
struct NumberRow: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            Text(value.map { "\($0.formatted(.number.precision(.fractionLength(decimals)))) \(unit)" } ?? "—")
                .font(WellieTheme.figure(14, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .monospacedDigit()
            Stepper(
                title,
                onIncrement: { value = min(range.upperBound, (value ?? range.lowerBound - step) + step) },
                onDecrement: { value = max(range.lowerBound, (value ?? range.lowerBound + step) - step) }
            )
            .labelsHidden()
            .tint(WellieTheme.accent)
            if value != nil {
                Button {
                    value = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(WellieTheme.faint)
                }
                .buttonStyle(.plain)
                .wellieHitTarget(36)
                .accessibilityLabel("Clear \(title)")
            }
        }
        .padding(.vertical, 10)
    }
}

/// A figure on a wheel, for **giving** one.
///
/// The stepper above moves by one and is exactly right for correcting a height
/// by a centimetre. It is exactly wrong for meeting somebody: a `±1` control
/// starting at the bottom of the range asks a forty-five-year-old for
/// twenty-six taps to say how old they are, and asks for eighty-five to give a
/// weight. A wheel is one gesture and the standard iOS answer to "a number
/// from a bounded range", so onboarding uses it and You keeps the stepper.
///
/// **The wheel's position is not the answer until it is moved.** A wheel cannot
/// draw "nothing selected", so it has to open somewhere — and writing that
/// somewhere straight into the profile would hand a stranger's height to
/// anybody who tapped Continue without looking. So the position is local state,
/// the profile stays nil until the person actually turns it, and the step they
/// are on cannot be passed in the meantime. A value that is already known —
/// from Health, or from going back a screen — opens under the marker and counts
/// immediately, because that one really was answered.
struct ProfileWheel: View {
    let title: String
    let unit: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let decimals: Int
    /// Where the wheel opens when nothing is known yet.
    let start: Double

    /// Where the wheel is pointing, which is only the same thing as `value`
    /// once it has been turned.
    @State private var position: Double

    init(
        title: String,
        unit: String,
        value: Binding<Double?>,
        range: ClosedRange<Double>,
        step: Double,
        decimals: Int,
        start: Double
    ) {
        self.title = title
        self.unit = unit
        _value = value
        self.range = range
        self.step = step
        self.decimals = decimals
        self.start = start
        _position = State(initialValue: value.wrappedValue ?? start)
    }

    private var options: [Double] {
        stride(from: range.lowerBound, through: range.upperBound, by: step).map { $0 }
    }

    private func text(_ option: Double) -> String {
        "\(option.formatted(.number.precision(.fractionLength(decimals)))) \(unit)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(title, selection: $position) {
                ForEach(options, id: \.self) { option in
                    Text(text(option))
                        .font(WellieTheme.figure(17, weight: .regular))
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue(value.map(text) ?? "Not set")
            .onChange(of: position) { _, moved in value = moved }

            if value == nil {
                Text("Scroll to your \(title.lowercased())")
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.bottom, 12)
            }
        }
    }
}

extension Binding where Value == Int? {
    var doubleBinding: Binding<Double?> {
        Binding<Double?>(
            get: { wrappedValue.map(Double.init) },
            set: { wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }
}
