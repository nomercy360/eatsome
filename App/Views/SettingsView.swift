import ShamanCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var apiKey = ""
    @State private var habits = DietHabits()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Settings")
                            .font(WellieTheme.font(32, weight: .bold))
                        Text("Everything eatsome reads, generates, and stores.")
                            .font(WellieTheme.font(15, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)

                    recognitionCard
                    healthCard
                    habitsCard
                    diagnosticsCard
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 32)
            }
            .navigationTitle("EATSOME")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { habits = model.projection.habits }
        }
        .wellieScreen()
    }

    private var recognitionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieKicker(text: "Recognition")
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .foregroundStyle(WellieTheme.blue)
                SecureField("OpenAI API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(WellieTheme.font(15, weight: .medium))
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack {
                Label(
                    model.hasAPIKey ? "Key stored securely" : "No key stored",
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

            Button("Save key") {
                model.setAPIKey(apiKey)
                apiKey = ""
            }
            .buttonStyle(WelliePrimaryButtonStyle())
            .disabled(apiKey.isEmpty)

            Text("Stored in Keychain and sent only to api.openai.com. Meal photos are uploaded for recognition.")
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
        .wellieCard(color: WellieTheme.softBlue)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                WellieKicker(text: "Apple Health")
                Spacer()
                Image(systemName: model.hasRequestedHealthAccess ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.hasRequestedHealthAccess ? WellieTheme.blue : WellieTheme.muted)
            }

            SettingValueRow(label: "Access", value: "Workouts, sleep, weight")
            SettingValueRow(
                label: "Last refresh",
                value: model.healthLastRefreshedAt?.formatted(date: .omitted, time: .shortened) ?? "Never"
            )

            Button(model.hasRequestedHealthAccess ? "Review Health access" : "Connect Apple Health") {
                Task { await model.connectHealth() }
            }
            .buttonStyle(WellieSecondaryButtonStyle())

            Button("Refresh now") { Task { await model.refreshHealth() } }
                .font(WellieTheme.font(14, weight: .semibold))
                .disabled(model.isLoadingHealth)

            Text("Read only. eatsome never changes Health data.")
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)

            if let error = model.healthError {
                Text(error).font(WellieTheme.font(12, weight: .medium)).foregroundStyle(.orange)
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private var habitsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            WellieKicker(text: "Mediterranean habits")
                .padding(.bottom, 8)
            Toggle("Olive oil is my main culinary fat", isOn: $habits.oliveOilIsMainCulinaryFat)
                .font(WellieTheme.font(15, weight: .semibold))
                .padding(.vertical, 8)
            Divider()
            Toggle("I prefer white meat to red", isOn: $habits.prefersWhiteMeatOverRed)
                .font(WellieTheme.font(15, weight: .semibold))
                .padding(.vertical, 8)
            Text("These are the two MEDAS items a photograph cannot answer.")
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .padding(.top, 4)
        }
        .wellieCard(color: WellieTheme.card)
        .onChange(of: habits) { _, new in Task { await model.updateHabits(new) } }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieKicker(text: "Diagnostics")
            SettingValueRow(label: "Model", value: model.config.recognition.model)
            SettingValueRow(label: "Config", value: model.configSource.rawValue)
            SettingValueRow(label: "Meals", value: "\(model.projection.meals.count)")
            SettingValueRow(label: "Health workouts", value: "\(model.healthSnapshot.workouts.count)")
            SettingValueRow(label: "Sleep sessions", value: "\(model.healthSnapshot.sleep.count)")
            SettingValueRow(label: "Weight readings", value: "\(model.healthSnapshot.weights.count)")
            if model.skippedLogLines > 0 {
                SettingValueRow(label: "Unreadable log lines", value: "\(model.skippedLogLines)", warning: true)
            }
        }
        .wellieCard(color: WellieTheme.card)
    }
}

private struct SettingValueRow: View {
    let label: String
    let value: String
    var warning = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(WellieTheme.font(15, weight: .semibold))
            Spacer()
            Text(value)
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(warning ? .orange : WellieTheme.muted)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}
