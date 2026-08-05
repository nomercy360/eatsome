import ShamanCore
import SwiftUI

/// Screen `2e`. A meal you already saved.
///
/// The same sentence as the capture screen, so editing later uses the muscle
/// you already have. Save appears only once something has changed — a button
/// that is always there teaches you to press it out of superstition. Delete is
/// text, at the bottom, where destructive things belong.
struct MealDetailView: View {
    let meal: MealEntry

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: MealEntry
    @State private var editing: EditingFood?
    @State private var showingAddFood = false
    @State private var showingDelete = false
    @State private var showingRecipeName = false
    @State private var recipeName = ""
    @FocusState private var isTyping: Bool

    init(meal: MealEntry) {
        self.meal = meal
        _draft = State(initialValue: meal)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                if let photo = PhotoStore.shared.image(for: meal.photoHash) {
                    MealPhotoBanner(image: photo, height: 180)
                }

                sentenceCard
                shareCard
                noteCard
                factsCard

                Button("Remove this meal") { showingDelete = true }
                    .font(WellieTheme.font(15.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .wellieColumn()
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isTyping = false })
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WellieTheme.background)
        .navigationTitle(DayFormat.title(Date(epochMillis: draft.eatenAt)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(Date(epochMillis: draft.eatenAt).formatted(date: .omitted, time: .shortened))
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        // Only once something has actually moved. Comparing the whole entry
        // rather than tracking a flag means undoing an edit hides it again.
        .safeAreaInset(edge: .bottom) { if draft != meal { saveBar } }
        .sheet(item: $editing) { target in
            if let index = draft.items.firstIndex(where: { $0.id == target.id }) {
                FoodEditSheet(
                    item: $draft.items[index],
                    onRemove: { draft.items.removeAll { $0.id == target.id } }
                )
            }
        }
        .sheet(isPresented: $showingAddFood) {
            FoodGroupPicker { draft.items.append(MealItem(group: $0, portion: .medium)) }
        }
        .alert("Save as a dish", isPresented: $showingRecipeName) {
            TextField("Lentil soup", text: $recipeName)
            Button("Save") { saveAsRecipe() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Described once, it comes back complete — including what the camera can't see.")
        }
        .confirmationDialog("Remove this meal?", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await model.deleteMeal(meal)
                    dismiss()
                }
            }
        } message: {
            Text("It comes off your week. The photo goes with it.")
        }
        .wellieScreen()
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.items.isEmpty ? "Nothing on this meal yet" : "Tap a word to change it")
                .font(WellieTheme.font(13, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)

            if !draft.items.isEmpty {
                FoodSentence(
                    lead: "You had",
                    words: draft.items.map {
                        .init(id: $0.id, text: FoodPhrase.word(for: $0.group, label: $0.label))
                    },
                    onTap: { editing = EditingFood(id: $0) }
                )
            }

            Button { showingAddFood = true } label: {
                Label("Add something", systemImage: "plus")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
            }
            .padding(.top, 2)
        }
        .wellieCard()
    }

    /// The one control that exists because sharing genuinely changes the
    /// arithmetic: a platter counted whole is the largest way this app can
    /// overstate a week.
    private var shareCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("How much did you eat?")
                    .font(WellieTheme.font(15.5, weight: .semibold))
                Text("Half counts as half toward your week")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
            Spacer(minLength: 8)
            ShareChips(share: Binding(get: { draft.eaten }, set: { draft.share = $0 }))
        }
        .wellieCard(padding: 20)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your note")
                .font(WellieTheme.font(15.5, weight: .semibold))
            TextField(
                "What the photo couldn't show",
                text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0.isEmpty ? nil : $0 }),
                axis: .vertical
            )
            .font(WellieTheme.font(15, weight: .medium))
            .focused($isTyping)
            .lineLimit(1...5)
            .padding(14)
            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            WellieCaption("Kept with this meal. Save it as a dish and it comes back next time.")
        }
        .wellieCard(padding: 20)
    }

    private var factsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Eaten at")
                    .font(WellieTheme.font(15.5, weight: .semibold))
                Spacer()
                DatePicker(
                    "",
                    selection: Binding(
                        get: { Date(epochMillis: draft.eatenAt) },
                        set: { draft.eatenAt = $0.epochMillis }
                    )
                )
                .labelsHidden()
            }
            .padding(.vertical, 12)

            WellieRowDivider()

            Button {
                recipeName = Recipe.suggestedName(for: draft.items)
                showingRecipeName = true
            } label: {
                WellieChevronRow(title: "Save as a dish")
            }
            .buttonStyle(.plain)
        }
        .wellieListCard()
    }

    private var saveBar: some View {
        Button("Save changes") {
            Task {
                await model.reviseMeal(draft)
                dismiss()
            }
        }
        .buttonStyle(WelliePrimaryButtonStyle())
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(WellieTheme.background)
    }

    private func saveAsRecipe() {
        let name = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await model.saveRecipe(
                Recipe(name: name, items: draft.items, note: draft.note)
            )
        }
    }
}
