import ShamanCore
import SwiftUI

/// Screen `2i`. Settings, without the machinery.
///
/// Recognition goes through the app-owned backend; provider controls stay in
/// the workshop because they are an evaluation tool, not user configuration.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var habits = DietHabits()
    @State private var versionTaps = 0
    @State private var showingDiets = false
    @State private var showingWorkshop = false
    @State private var showingMethod = false
    @State private var showingPrivacy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    dietCard
                    AccountCard()
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
            .navigationDestination(isPresented: $showingDiets) { DietPickerView() }
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
                .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - What counts

    private var dietCard: some View {
        Button { showingDiets = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("What counts")
                        .font(WellieTheme.font(17, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Spacer(minLength: 8)
                    Text(model.diet.name)
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.blue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }
                WellieProse(
                    "\(model.diet.ruleSummary). Switching re-scores your history — nothing is read again.",
                    size: 14
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wellieCard(color: WellieTheme.ice)
    }

    // MARK: - The answers a photo can't give

    /// Rendered from the active diet's own questions rather than from two
    /// hardcoded booleans. A low-sugar week asks nothing here, and the card
    /// disappears rather than showing two Mediterranean questions that score
    /// nothing.
    @ViewBuilder
    private var habitsCard: some View {
        let questions = model.diet.habits
        if !questions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                WellieSectionTitle(
                    text: questions.count == 1 ? "Your answer" : "Your \(Count.spell(questions.count, capitalized: false)) answers",
                    detail: "The parts a photo can't see"
                )

                ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
                    if index > 0 { WellieRowDivider() }
                    Toggle(question.question, isOn: Binding(
                        get: { habits.answer(question) },
                        set: { habits.set($0, for: question.id) }
                    ))
                    .font(WellieTheme.font(15.5, weight: .semibold))
                }
            }
            .wellieCard()
            .onChange(of: habits) { old, new in
                // The initial load assigns into this state too; writing an event
                // for that would append an identical line on every launch.
                guard old != new else { return }
                Task { await model.updateHabits(new) }
            }
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

            Toggle(isOn: Binding(
                get: { model.hasProteinGoal },
                set: { model.hasProteinGoal = $0 }
            )) {
                Text("Count it as a goal in your olives")
                    .font(WellieTheme.font(15, weight: .semibold))
            }
            .disabled(model.proteinTarget == nil)

            WellieCaption(
                """
                Estimated from what's on your plate, so read the trend rather than the digit. \
                It's the only thing here measured in grams, and the only rule that is estimated \
                rather than counted — which is why it is off unless you ask for it.
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
                in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
            )
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
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
            // "My dishes" is gone with the screen behind it. Dishes were never
            // something anyone curated — the list existed so a home recipe could
            // be described once — and the thread does that job from the log
            // instead: what you repeat surfaces as a chip over the keyboard,
            // ranked by how often and how recently you actually ate it. A
            // screen for maintaining that by hand would be asking someone to
            // keep a list the app can already read.
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
    @State private var confirmingCloudDeletion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your photos have two private copies.")
                            .font(WellieTheme.font(22, weight: .bold))
                        WellieProse(
                            """
                            A meal photo stays on this device and is also stored in eatsome's private \
                            Cloudflare R2 bucket so a failed reading or an explicit retry does not need \
                            another upload. The backend sends it to \(model.provider.displayName) for AI \
                            recognition. It is never public, and deleting the meal removes its cloud \
                            reference and, when no other meal uses it, the cloud photograph.
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
                        Text("You stay in control")
                            .font(WellieTheme.font(17, weight: .bold))
                        WellieProse(
                            "Delete all cloud data to remove your account's stored photos, meal events, recognition results, table content and research-corpus consent. Local meals stay on this phone, and eatsome returns to Apple sign-in.",
                            size: 15
                        )
                        Button("Delete all cloud data", role: .destructive) {
                            confirmingCloudDeletion = true
                        }
                        .buttonStyle(WellieSecondaryButtonStyle())
                        .disabled(model.isDeletingCloudData)
                        if let error = model.cloudError {
                            Text(error)
                                .font(WellieTheme.font(12.5, weight: .medium))
                                .foregroundStyle(WellieTheme.attention)
                        }
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
            .alert("Delete all cloud data?", isPresented: $confirmingCloudDeletion) {
                Button("Delete cloud data", role: .destructive) {
                    Task { await model.revokePhotoProcessingAndDeleteCloudData() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the account's server data and sessions, withdraws photo-processing consent, and returns this phone to Apple sign-in. It cannot be undone.")
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

/// Behind five taps on the version row: provider diagnostics and the bootstrap
/// backend token used by development builds.
struct WorkshopView: View {
    @Environment(AppModel.self) private var model

    @State private var backendToken = ""
    @FocusState private var isEditingKey: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                VStack(alignment: .leading, spacing: 14) {
                    WellieSectionTitle(
                        text: "Recognition",
                        detail: "The phone calls eatsome's backend; only the backend calls a model provider."
                    )

                    Picker("Provider", selection: Binding(
                        get: { model.provider },
                        set: { newValue in
                            backendToken = ""
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

                    SecureField("Backend access token", text: $backendToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(WellieTheme.font(15, weight: .medium))
                        .focused($isEditingKey)
                        .submitLabel(.done)
                        .onSubmit(saveKey)
                        .padding(14)
                        .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))

                    HStack {
                        Label(
                            model.hasBackendAccess ? "Backend access configured" : "No backend token",
                            systemImage: model.hasBackendAccess ? "checkmark.circle.fill" : "circle"
                        )
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(model.hasBackendAccess ? WellieTheme.blue : WellieTheme.muted)
                        Spacer()
                        if model.hasBackendAccess {
                            Button("Remove", role: .destructive) { model.setBackendToken(nil) }
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
                    row("Dishes", "\(model.knownDishCount)")
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

    private var trimmedKey: String { backendToken.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveKey() {
        isEditingKey = false
        guard !trimmedKey.isEmpty else { return }
        model.setBackendToken(trimmedKey)
        backendToken = ""
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
