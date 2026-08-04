import ShamanCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var apiKey = ""
    @State private var habits = DietHabits()
    @State private var healthAuthorized: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        model.setAPIKey(apiKey)
                        apiKey = ""
                    }
                    .disabled(apiKey.isEmpty)
                    if model.hasAPIKey {
                        Label("A key is stored", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                        Button("Remove key", role: .destructive) { model.setAPIKey(nil) }
                    }
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("""
                    Stored in the Keychain, sent only to api.openai.com. \
                    Photos are uploaded for recognition; nothing else leaves the phone.
                    """)
                }

                Section {
                    Toggle("Olive oil is my main culinary fat", isOn: $habits.oliveOilIsMainCulinaryFat)
                    Toggle("I prefer white meat to red", isOn: $habits.prefersWhiteMeatOverRed)
                } header: {
                    Text("Habits")
                } footer: {
                    Text("Two MEDAS items a photo cannot answer.")
                }
                .onChange(of: habits) { _, new in
                    Task { await model.updateHabits(new) }
                }

                Section("Health") {
                    Button("Allow writing workouts to Health") {
                        Task { healthAuthorized = await HealthKitBridge.shared.requestAuthorization() }
                    }
                    if let healthAuthorized {
                        Text(healthAuthorized ? "Granted" : "Not granted")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Diagnostics") {
                    LabeledContent("Model", value: model.config.recognition.model)
                    LabeledContent("Config source", value: model.configSource.rawValue)
                    LabeledContent("Meals logged", value: "\(model.projection.meals.count)")
                    LabeledContent("Sets logged", value: "\(model.projection.sets.count)")
                    if model.skippedLogLines > 0 {
                        LabeledContent("Unreadable log lines", value: "\(model.skippedLogLines)")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { habits = model.projection.habits }
        }
    }
}
