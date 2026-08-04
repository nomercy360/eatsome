import ShamanCore
import SwiftUI

struct MealDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let meal: MealEntry
    @State private var draft: MealEntry
    @State private var showingDeleteConfirmation = false

    init(meal: MealEntry) {
        self.meal = meal
        _draft = State(initialValue: meal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    Image(systemName: meal.source == .photo ? "camera.fill" : "fork.knife")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(WellieTheme.blue)
                        .frame(width: 76, height: 76)
                        .background(WellieTheme.softBlue, in: Circle())

                    Text(MealDisplay.title(draft))
                        .font(WellieTheme.font(28, weight: .bold))
                        .multilineTextAlignment(.center)

                    Text(MealDisplay.subtitle(draft))
                        .font(WellieTheme.font(16, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        ForEach(uniqueGroups.prefix(4), id: \.self) { WellieChip(text: $0.displayName) }
                    }
                }
                .frame(maxWidth: .infinity)
                .wellieCard(color: WellieTheme.ice, padding: 24)

                VStack(spacing: 0) {
                    HStack {
                        WellieKicker(text: "Meal breakdown")
                        Spacer()
                        if let confidence = draft.modelConfidence {
                            Text("\(Int(confidence * 100))% confidence")
                                .font(WellieTheme.font(12, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                        }
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(draft.items.indices), id: \.self) { index in
                        VStack(alignment: .trailing, spacing: 0) {
                            MealItemEditorRow(item: $draft.items[index])
                            Button(role: .destructive) {
                                draft.items.remove(at: index)
                            } label: {
                                Label("Remove", systemImage: "trash")
                                    .font(WellieTheme.font(12, weight: .medium))
                            }
                            .disabled(draft.items.count == 1)
                            .padding(.bottom, 8)
                        }
                        if index < draft.items.count - 1 { Divider() }
                    }

                    Menu {
                        ForEach(FoodGroup.allCases, id: \.self) { group in
                            Button(group.displayName) {
                                draft.items.append(MealItem(group: group, portion: .medium))
                            }
                        }
                    } label: {
                        Label("Add food group", systemImage: "plus")
                            .font(WellieTheme.font(15, weight: .semibold))
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .wellieCard(color: WellieTheme.card)

                DatePicker(
                    "Eaten at",
                    selection: Binding(
                        get: { Date(epochMillis: draft.eatenAt) },
                        set: { draft.eatenAt = $0.epochMillis }
                    )
                )
                .font(WellieTheme.font(15, weight: .medium))
                .wellieCard(color: WellieTheme.card)

                Button("Save changes") {
                    Task {
                        await model.reviseMeal(draft)
                        dismiss()
                    }
                }
                .buttonStyle(WelliePrimaryButtonStyle())
                .disabled(draft.items.isEmpty || draft == meal)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.bottom, 32)
        }
        .navigationTitle("MEAL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Delete meal", systemImage: "trash", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this meal?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteMeal(meal)
                    dismiss()
                }
            }
        }
        .wellieScreen()
    }

    private var uniqueGroups: [FoodGroup] {
        var seen = Set<FoodGroup>()
        return draft.items.map(\.group).filter { seen.insert($0).inserted }
    }
}
