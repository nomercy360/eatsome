import AVFoundation
import ShamanCore
import SwiftUI

/// Screen set `2a`. Four screens, each asking for exactly one thing.
///
/// Every ask is skippable. The permission screens explain before iOS does, so a
/// refusal is a decision rather than permanent confusion — an app that fires the
/// system camera prompt cold gets refused by people who would have said yes, and
/// there is no second chance at that dialog.
///
/// The last screen is the two habit questions: the cheapest two of fourteen
/// points in the app, one tap each, and the only two a photograph can never
/// answer.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    @State private var step = 0
    @State private var habits = DietHabits()

    var body: some View {
        Group {
            switch step {
            case 0: welcome
            case 1: cameraAsk
            case 2: healthAsk
            default: habitsAsk
            }
        }
        .animation(.snappy(duration: 0.28), value: step)
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
                // Three plates of different heights. Abstract on purpose: a
                // stock photo of a salad would be a promise about the food, and
                // the promise here is about the week.
                HStack(alignment: .bottom, spacing: 10) {
                    plate(92, opacity: 0.75)
                    plate(126, opacity: 0.9)
                    plate(70, opacity: 0.6)
                }

                Text("Photograph\nwhat you eat.")
                    .font(WellieTheme.font(34, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)

                WellieProse(
                    """
                    eatsome looks for the foods a Mediterranean week is built on — olive oil, \
                    vegetables, fish, beans, nuts — and tells you how yours is going.
                    """,
                    size: 16.5
                )

                VStack(alignment: .leading, spacing: 11) {
                    promise("Every figure traced to a food table")
                    promise("No perfect days to keep up")
                    promise("Private storage you can delete")
                }
            }

            Spacer(minLength: 20)

            VStack(spacing: 12) {
                Button("Start") { step = 1 }
                    .buttonStyle(WelliePrimaryButtonStyle())
                Button("I've used eatsome before") { model.completeOnboarding() }
                    .buttonStyle(WellieQuietButtonStyle())
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.ice.ignoresSafeArea())
    }

    private func plate(_ height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(WellieTheme.surface.opacity(opacity))
            .frame(maxWidth: .infinity)
            .frame(height: height)
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

    // MARK: - 2 · Camera

    private var cameraAsk: some View {
        step(index: 1) {
            VStack(alignment: .leading, spacing: 24) {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .fill(WellieTheme.ice)
                    .frame(height: 230)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(WellieTheme.background)
                            .frame(width: 150, height: 150)
                            .overlay {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 44, weight: .medium))
                                    .foregroundStyle(WellieTheme.blue.opacity(0.35))
                            }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text("Beans · Vegetables · Olive oil")
                            .font(WellieTheme.font(13, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: WellieTheme.ink.opacity(0.1), radius: 9, y: 6)
                            .padding(22)
                    }

                Text("One photo per meal is all it takes.")
                    .font(WellieTheme.font(28, weight: .bold))

                WellieProse(
                    """
                    Point the camera at the plate before you start eating. eatsome names the foods it \
                    can see; you fix anything it gets wrong, or you don't.
                    """,
                    size: 16
                )

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(WellieTheme.blue)
                    WellieProse("Before the first photo is sent, you'll see exactly where it is stored, which AI reads it, and how to delete it.")
                }
                .wellieCard(padding: 17)
            }
        } actions: {
            Button("Allow the camera") {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in step = 2 }
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            Button("I'll use photos I've already taken") { step = 2 }
                .buttonStyle(WellieQuietButtonStyle())
        }
    }

    // MARK: - 3 · Health

    private var healthAsk: some View {
        step(index: 2) {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your watch already knows some of this.")
                    .font(WellieTheme.font(28, weight: .bold))

                WellieProse(
                    """
                    If you let eatsome read Health, three things appear on your Today screen. Nothing is \
                    calculated from them and nothing is written back.
                    """,
                    size: 16
                )

                VStack(spacing: 10) {
                    healthRow("moon.fill", "Sleep", "Last night, and how it compares")
                    healthRow("figure.run", "Workouts", "How many this week")
                    healthRow("scalemass.fill", "Weight", "Also sets your protein target")
                }

                WellieCaption("Read only. eatsome never changes Health data. You can connect this later in Settings.")
            }
        } actions: {
            Button("Connect Apple Health") {
                Task {
                    await model.connectHealth()
                    step = 3
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            Button("Not now") { step = 3 }
                .buttonStyle(WellieQuietButtonStyle())
        }
    }

    private func healthRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - 4 · Two questions

    private var habitsAsk: some View {
        step(index: 3) {
            VStack(alignment: .leading, spacing: 22) {
                Text("Two things a photo can't tell us.")
                    .font(WellieTheme.font(28, weight: .bold))

                WellieProse("Answer once and they count every week from now on. Change them any time.", size: 16)

                question("What do you mostly cook with?",
                         yes: "Olive oil", no: "Butter, or something else",
                         isYes: habits.oliveOilIsMainCulinaryFat) { habits.oliveOilIsMainCulinaryFat = $0 }

                question("Chicken and fish, or beef and pork?",
                         yes: "Mostly chicken and fish", no: "Mostly red meat",
                         isYes: habits.prefersWhiteMeatOverRed) { habits.prefersWhiteMeatOverRed = $0 }
            }
        } actions: {
            Button("Done") {
                Task {
                    await model.updateHabits(habits)
                    model.completeOnboarding()
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle())
        }
    }

    private func question(
        _ title: String,
        yes: String,
        no: String,
        isYes: Bool,
        set: @escaping (Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(WellieTheme.font(19, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 9) {
                answer(yes, isOn: isYes) { set(true) }
                answer(no, isOn: !isYes) { set(false) }
            }
        }
        .wellieCard(padding: 22)
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

    // MARK: - Shared frame

    /// "1 of 3" and a Skip that means it. A step counter with no way out is a
    /// funnel, not an introduction.
    private func step<Body: View, Actions: View>(
        index: Int,
        @ViewBuilder content: () -> Body,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(index) of 3")
                    .font(WellieTheme.font(15, weight: .semibold))
                Spacer()
                Button("Skip") { skip() }
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

    /// Skipping the habits screen still keeps whatever is on it: the defaults
    /// are the two answers most people would give, and leaving them unrecorded
    /// would silently cost two points.
    private func skip() {
        if step >= 3 {
            Task { await model.updateHabits(habits) }
        }
        model.completeOnboarding()
    }
}
