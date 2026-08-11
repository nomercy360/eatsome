import ShamanCore
import SwiftUI

/// Screen `2i`. Settings, without the machinery.
///
/// Recognition goes through the app-owned backend; provider controls stay in
/// the workshop because they are an evaluation tool, not user configuration.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var isTabRoot = false

    @State private var versionTaps = 0
    @State private var showingWorkshop = false
    @State private var showingPrivacy = false
    @State private var showingNutritionProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    AccountCard()
                    healthCard
                    dailyReferenceCard
                    listCard
                    version
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle(isTabRoot ? "You" : "Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTabRoot {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .font(WellieTheme.font(15, weight: .semibold))
                    }
                }
            }
            .navigationDestination(isPresented: $showingWorkshop) { WorkshopView() }
            .sheet(isPresented: $showingPrivacy) { PrivacyView() }
            .sheet(isPresented: $showingNutritionProfile) { NutritionProfileSettingsView() }
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
            return "Health can fill age, height, weight, body fat and activity, and show sleep and workouts. Read only — eatsome never changes Health data."
        }
        let checked = model.healthLastRefreshedAt
            .map { "Last checked at \($0.formatted(date: .omitted, time: .shortened))." } ?? ""
        // Refusal and an empty store look identical to an app; saying
        // "connected" for both would be the app claiming to know which.
        let caveat = model.healthIsEmpty
            ? " Nothing has come back yet — either nothing is recorded, or access was declined."
            : ""
        return "Reading body profile, energy, sleep and workouts. \(checked) eatsome never changes Health data.\(caveat)"
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

    // MARK: - Daily reference

    private var dailyReferenceCard: some View {
        Button { showingNutritionProfile = true } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Text("Daily reference")
                        .font(WellieTheme.font(17, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }

                if let targets = model.dailyTargets {
                    Text("~\(Int(targets.kcal)) kcal · \(Int(targets.protein)) g protein")
                        .font(WellieTheme.font(20, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    HStack(spacing: 7) {
                        WellieChip(text: "Carbs \(range(targets.carbohydrateRange)) g", style: .outline, size: 12.5)
                        WellieChip(text: "Fat \(range(targets.fatRange)) g", style: .outline, size: 12.5)
                    }
                    WellieCaption(
                        "\(model.nutritionProfile.goal?.displayName ?? "Personal") · maintenance ~\(Int(targets.maintenanceKcal)) kcal"
                    )
                } else {
                    WellieProse("Add age, height, weight, activity and a goal to calculate it.", size: 14)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .wellieCard(color: WellieTheme.ice)
    }

    private func range(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound))–\(Int(range.upperBound))"
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
                            Age, sex reference, height, weight, body fat, energy, sleep and workouts are \
                            read when the app opens and are never copied into the meal log or written back. \
                            Your goal and any manually entered profile fields stay on this device. iOS does \
                            not tell an app whether a refused read \
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
