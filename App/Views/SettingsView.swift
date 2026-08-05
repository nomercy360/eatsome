import ShamanCore
import SwiftUI

/// Screen `2i`. Settings, without the machinery.
///
/// The provider switch, the model name and the seven diagnostic rows are gone
/// from the interface: recognition is something the app does, not something the
/// user configures. What is left is Health, the two habit answers, the protein
/// target, and the honest privacy statement.
///
/// Diagnostics — and the key the recognizer still needs until it talks to a
/// server of ours — stay reachable by tapping the version row five times. That
/// keeps them for the person who built this without handing them to anyone else.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var habits = DietHabits()
    @State private var versionTaps = 0
    @State private var showingWorkshop = false
    @State private var showingMethod = false
    @State private var showingPrivacy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    healthCard
                    habitsCard
                    proteinCard
                    listCard
                    version
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .navigationDestination(isPresented: $showingWorkshop) { WorkshopView() }
            .sheet(isPresented: $showingMethod) { ScoreMethodView() }
            .sheet(isPresented: $showingPrivacy) { PrivacyView() }
            .onAppear { habits = model.projection.habits }
        }
        .wellieScreen()
    }

    // MARK: - Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Apple Health")
                    .font(WellieTheme.font(17, weight: .bold))
                Spacer()
                if model.hasRequestedHealthAccess {
                    HStack(spacing: 6) {
                        WellieMark(size: 17)
                        Text(model.healthIsEmpty ? "No samples" : "Connected")
                            .font(WellieTheme.font(13.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                    }
                }
            }

            WellieProse(healthLine, size: 14.5)

            if model.hasRequestedHealthAccess {
                HStack(spacing: 9) {
                    inlineButton("Review access") { Task { await model.connectHealth() } }
                    inlineButton("Refresh now") { Task { await model.refreshHealth() } }
                }
            } else {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .buttonStyle(WellieSecondaryButtonStyle())
            }

            if let error = model.healthError {
                Text(error)
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private var healthLine: String {
        guard model.hasRequestedHealthAccess else {
            return "Sleep, workouts and weight can appear on Today. Read only — eatsome never changes Health data."
        }
        let checked = model.healthLastRefreshedAt
            .map { "Last checked at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
        // Refusal and an empty store look identical to an app; saying
        // "connected" for both would be the app claiming to know which.
        let caveat = model.healthIsEmpty
            ? " Nothing has come back yet — either nothing is recorded, or access was declined."
            : ""
        return "Reading sleep, workouts and weight. \(checked) eatsome never changes Health data.\(caveat)"
    }

    private func inlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(WellieTheme.font(15, weight: .bold))
                .foregroundStyle(WellieTheme.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The two answers

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            WellieSectionTitle(text: "Your two answers", detail: "The parts a photo can't see")

            Toggle("You cook with olive oil", isOn: $habits.oliveOilIsMainCulinaryFat)
                .font(WellieTheme.font(15.5, weight: .semibold))
            WellieRowDivider()
            Toggle("You choose chicken and fish over red meat", isOn: $habits.prefersWhiteMeatOverRed)
                .font(WellieTheme.font(15.5, weight: .semibold))
        }
        .wellieCard()
        .onChange(of: habits) { old, new in
            // The initial load assigns into this state too; writing an event
            // for that would append an identical line on every launch.
            guard old != new else { return }
            Task { await model.updateHabits(new) }
        }
    }

    // MARK: - Protein

    private var proteinCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            WellieSectionTitle(text: "Protein", detail: proteinDetail)

            VStack(spacing: 9) {
                ForEach(Protein.Intent.allCases, id: \.self) { intent in
                    intentRow(intent)
                }
            }

            WellieCaption(
                """
                Estimated from what's on your plate, so read the trend rather than the digit. \
                It's the only thing here measured in grams.
                """
            )
        }
        .wellieCard()
    }

    private var proteinDetail: String {
        guard let target = model.proteinTarget else {
            return "Health has no weight yet, so there is no daily number."
        }
        return "\(Int(target)) g a day, from your weight in Health"
    }

    private func intentRow(_ intent: Protein.Intent) -> some View {
        let isOn = model.proteinIntent == intent
        return Button { model.proteinIntent = intent } label: {
            HStack(spacing: 12) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WellieTheme.onAccent)
                }
                Text(intentName(intent))
                    .font(WellieTheme.font(15.5, weight: isOn ? .bold : .semibold))
                    .foregroundStyle(isOn ? WellieTheme.onAccent : WellieTheme.body)
                Spacer(minLength: 8)
                Text("\(intent.gramsPerKilogram.formatted(.number.precision(.fractionLength(1)))) g/kg")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(isOn ? WellieTheme.onAccent.opacity(0.7) : WellieTheme.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                isOn ? WellieTheme.blue : WellieTheme.well,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(WellieTheme.outline, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The stored names are training vocabulary; these are what a person would
    /// say they were doing.
    private func intentName(_ intent: Protein.Intent) -> String {
        switch intent {
        case .maintain: "Staying as I am"
        case .active: "Active"
        case .building: "Building muscle"
        }
    }

    // MARK: - The rest

    private var listCard: some View {
        VStack(spacing: 0) {
            NavigationLink { RecipesView() } label: {
                WellieChevronRow(title: "My dishes", value: "\(model.recipes.count)")
            }
            .buttonStyle(.plain)

            WellieRowDivider()
            WellieChevronRow(title: "Units", value: WeightFormat.unitName)
                .foregroundStyle(WellieTheme.ink)

            WellieRowDivider()
            Button { showingMethod = true } label: {
                WellieChevronRow(title: "How the score works")
            }
            .buttonStyle(.plain)

            WellieRowDivider()
            Button { showingPrivacy = true } label: {
                WellieChevronRow(title: "Your photos and data")
            }
            .buttonStyle(.plain)
        }
        .wellieListCard()
    }

    private var version: some View {
        VStack(spacing: 8) {
            Button {
                versionTaps += 1
                if versionTaps >= 5 {
                    versionTaps = 0
                    showingWorkshop = true
                }
            } label: {
                Text("eatsome \(appVersion)")
                    .font(WellieTheme.font(13.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// What the app does with a photograph, said plainly and in one place.
struct PrivacyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your photos stay on your phone.")
                            .font(WellieTheme.font(22, weight: .bold))
                        WellieProse(
                            """
                            A meal photo is sent once, to \(model.provider.host), to be read. It is not \
                            stored there by us and it is not posted anywhere. The copy that stays is the \
                            one on this device, and deleting a meal deletes its photograph with it.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard(color: WellieTheme.ice)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nothing is overwritten")
                            .font(WellieTheme.font(17, weight: .bold))
                        WellieProse(
                            """
                            Every meal, correction and answer is appended to a log on this device. A \
                            correction is a new line, not an edit — which is why the app can tell you \
                            later what it originally thought, and why nothing you have written can be \
                            silently lost.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Health is read only")
                            .font(WellieTheme.font(17, weight: .bold))
                        WellieProse(
                            """
                            Sleep, workouts and weight are read when the app opens and are never copied \
                            into the log or written back. iOS does not tell an app whether a refused read \
                            and an empty store are the same thing, so eatsome says both rather than \
                            guessing.
                            """,
                            size: 15
                        )
                    }
                    .wellieCard()
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("Your photos and data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
        }
        .wellieScreen()
    }
}

/// Behind five taps on the version row: the provider switch, the key, and the
/// counters. Everything the redesign took off the settings screen, kept for the
/// one person who needs it and shown to nobody else.
struct WorkshopView: View {
    @Environment(AppModel.self) private var model

    @State private var apiKey = ""
    @FocusState private var isEditingKey: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    WellieSectionTitle(
                        text: "Recognition",
                        detail: "Per device, not per account — the point is to run both against your own plates."
                    )

                    Picker("Provider", selection: Binding(
                        get: { model.provider },
                        set: { newValue in
                            apiKey = ""
                            isEditingKey = false
                            model.setProvider(newValue)
                        }
                    )) {
                        ForEach(RecognitionProvider.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)

                    row("Model", model.activeModel)

                    SecureField("\(model.provider.displayName) API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(WellieTheme.font(15, weight: .medium))
                        .focused($isEditingKey)
                        .submitLabel(.done)
                        .onSubmit(saveKey)
                        .padding(14)
                        .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack {
                        Label(
                            model.hasAPIKey ? "Key stored in Keychain" : "No key stored",
                            systemImage: model.hasAPIKey ? "checkmark.circle.fill" : "circle"
                        )
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(model.hasAPIKey ? WellieTheme.blue : WellieTheme.muted)
                        Spacer()
                        if model.hasAPIKey {
                            Button("Remove", role: .destructive) { model.setAPIKey(nil) }
                                .font(WellieTheme.font(13, weight: .semibold))
                        }
                    }

                    Button("Save key", action: saveKey)
                        .buttonStyle(WelliePrimaryButtonStyle(enabled: !trimmedKey.isEmpty))
                        .disabled(trimmedKey.isEmpty)
                }
                .wellieCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Counters")
                        .font(WellieTheme.font(17, weight: .bold))
                    row("Config", model.configSource.rawValue)
                    row("Meals", "\(model.projection.meals.count)")
                    row("Dishes", "\(model.recipes.count)")
                    row("Health workouts", "\(model.healthSnapshot.workouts.count)")
                    row("Sleep sessions", "\(model.healthSnapshot.sleep.count)")
                    row("Weight readings", "\(model.healthSnapshot.weights.count)")
                    if model.skippedLogLines > 0 {
                        // A silently skipped line is how you lose trust in your
                        // own data six months later.
                        row("Unreadable log lines", "\(model.skippedLogLines)", warning: true)
                    }
                }
                .wellieCard()
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle("Workshop")
        .navigationBarTitleDisplayMode(.inline)
        .wellieScreen()
    }

    private var trimmedKey: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveKey() {
        isEditingKey = false
        guard !trimmedKey.isEmpty else { return }
        model.setAPIKey(trimmedKey)
        apiKey = ""
    }

    private func row(_ label: String, _ value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(WellieTheme.font(15, weight: .semibold))
            Spacer()
            Text(value)
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(warning ? WellieTheme.attention : WellieTheme.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}
