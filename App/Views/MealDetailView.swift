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
    /// The names and counts the flat list cannot carry. Empty on every meal
    /// logged before dishes, which is why the sentence falls back to reading
    /// food by food rather than assuming.
    @State private var dishes: [MealDish]
    @State private var openDish: MealDish?
    @State private var editing: EditingFood?
    @State private var showingDelete = false
    @State private var showingRecipeName = false
    @State private var recipeName = ""
    @State private var isRefining = false
    @State private var refineFailure: String?
    /// The note as it stood when this meal was last read. Whatever was saved
    /// with the meal has already been through the model, so it is where the
    /// comparison starts.
    @State private var readNote: String
    @FocusState private var isTyping: Bool

    init(meal: MealEntry) {
        self.meal = meal
        _draft = State(initialValue: meal)
        _dishes = State(initialValue: meal.storedDishes ?? [])
        _readNote = State(initialValue: meal.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                if let photo = PhotoStore.shared.image(for: meal.photoHash) {
                    MealPhotoBanner(image: photo, height: 180)
                }

                sentenceCard
                nutrientCard
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
            // A timestamp is a label, not a control. Without this iOS 26 wraps
            // it in the same glass capsule it gives buttons, and it reads as
            // something you can press.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) { timeLabel }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { timeLabel }
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
        .onChange(of: draft.items) { _, updated in
            guard !dishes.isEmpty else { return }
            dishes = MealDish.regrouped(updated, keeping: dishes)
        }
        .sheet(item: $openDish) { dish in
            DishSheet(
                dish: dish,
                onRename: { name in
                    guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                    dishes[index].name = name
                    draft.items = dishes.flatMap { $0.flattened() }
                },
                onEditIngredient: { editing = EditingFood(id: $0) },
                onAddIngredient: {
                    guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                    let added = MealItem(group: .other)
                    dishes[index].items.append(added)
                    draft.items = dishes.flatMap { $0.flattened() }
                    editing = EditingFood(id: added.id)
                },
                onCount: { count in
                    guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                    // Rewrites the weights rather than multiplying at score time: a
                    // weighed dish already holds every serving that is present, so
                    // "one, not three" has to take two thirds of it back off.
                    dishes[index] = dishes[index].scaled(toCount: count)
                    draft.items = dishes.flatMap { $0.flattened() }
                },
                onRemove: {
                    let members = Set(dish.items.map(\.id))
                    draft.items.removeAll { members.contains($0.id) }
                }
            )
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

    private var timeLabel: some View {
        Text(Date(epochMillis: draft.eatenAt).formatted(date: .omitted, time: .shortened))
            .font(WellieTheme.font(14, weight: .semibold))
            .foregroundStyle(WellieTheme.muted)
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(draft.items.isEmpty ? "Nothing on this meal yet" : "Tap a word to change it")
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Spacer(minLength: 0)
                // Share included, so halving the plate below visibly halves it.
                if !draft.items.isEmpty {
                    Text(model.figure(for: draft).text)
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize()
                }
            }

            if !draft.items.isEmpty {
                FoodSentence(lead: "You had", words: sentenceWords, onTap: { tapWord($0) })
            }
        }
        .wellieCard()
    }

    /// What this meal came to, share included.
    ///
    /// No targets here and no meters: a target is a property of a day, and a
    /// single meal measured against one would say a normal lunch was a third of
    /// a person. This card states what was eaten and stops.
    ///
    /// A figure that rounds to nothing is left out rather than printed as zero.
    /// `PlateFigure` already settled this argument for the headline — "0 g
    /// protein" above a can of Monster is a true sentence that tells a person
    /// nothing they did not know — and a row of five zeros makes the two real
    /// numbers on that can harder to find, not easier. A drink with 4 g of carbs
    /// and 0.4 g of salt should say those two things.
    @ViewBuilder
    private var nutrientCard: some View {
        if !draft.items.isEmpty {
            let total = model.nutrients(in: draft)
            let shown = shownFigures(total)
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This meal")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)

                    HStack(alignment: .top, spacing: 0) {
                        ForEach(shown, id: \.name) { mealFigure($0.name, $0.value, $0.unit) }
                        // Keeps two figures at two-fifths width rather than
                        // stretching them across the card.
                        ForEach(shown.count..<5, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }

                    if !total.isComplete {
                        Text("\(Int(total.unresolvedGrams.rounded())) g here was not recognised. "
                             + "Name it on the fix screen and these figures fill in.")
                            .font(WellieTheme.font(12, weight: .medium))
                            .foregroundStyle(WellieTheme.attention)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .wellieCard()
            }
        }
    }

    /// The figures worth printing, in a fixed order, skipping the ones that
    /// round to nothing.
    private func shownFigures(
        _ total: NutrientTotal
    ) -> [(name: String, value: String, unit: String)] {
        let meal = total.nutrients
        var out: [(name: String, value: String, unit: String)] = []
        func add(_ name: String, _ value: Double, _ unit: String, _ text: String) {
            guard value.rounded() > 0 else { return }
            out.append((name, text, unit))
        }
        add("Energy", meal.kcal, "kcal", "\(Int(meal.kcal.rounded()))")
        add("Protein", meal.protein, "g", "\(Int(meal.protein.rounded()))")
        add("Carbs", meal.carbohydrate, "g", "\(Int(meal.carbohydrate.rounded()))")
        add("Fat", meal.fat, "g", "\(Int(meal.fat.rounded()))")
        // Salt is the one shown to a decimal, because the interesting range is
        // 0.5 to 5 g and whole grams would round most meals to nothing. `≥`
        // only when it was derived: a label that printed 食塩相当量 settled the
        // number, and marking that as a lower bound understates a known fact.
        let salt = meal.saltGrams
        if salt >= 0.05 {
            out.append((
                "Salt",
                (total.saltIsFloor ? "≥ " : "") + String(format: "%.1f", salt),
                "g"
            ))
        }
        return out
    }

    private func mealFigure(_ name: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(WellieTheme.font(11.5, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text(unit)
                    .font(WellieTheme.font(11, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A dish is one word and its ingredients are behind it. A meal saved
    /// before dishes existed has none, and reads food by food as it always did.
    private var sentenceWords: [FoodSentence.Word] {
        guard !dishes.isEmpty else {
            return draft.items.map {
                .init(id: $0.id, text: FoodPhrase.word(for: $0.group, label: $0.label))
            }
        }
        return FoodSentence.words(for: dishes)
    }

    private func tapWord(_ id: UUID) {
        if let dish = dishes.first(where: { $0.id == id }) {
            openDish = dish
        } else {
            editing = EditingFood(id: id)
        }
    }

    /// The one control that exists because sharing genuinely changes the
    /// arithmetic: a platter counted whole is the largest way this app can
    /// overstate a week.
    /// The same one question as the capture screen, worded identically. Two
    /// screens asking the same thing in different words is how a person comes
    /// to believe they are two different things.
    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("How much was yours?")
                    .font(WellieTheme.font(15.5, weight: .semibold))
                Text("Covers sharing too — half a shared bowl counts half")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ShareChips(share: Binding(get: { draft.eaten }, set: { draft.share = $0 }))
        }
        .wellieCard(padding: 20)
    }

    /// The only way food is added or corrected here: say what was missed and the
    /// model returns a delta. There is no picker any more, on purpose — one path
    /// to fix a meal, and it is the one that also teaches the prompt something.
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Missing or wrong?")
                .font(WellieTheme.font(15.5, weight: .semibold))
            TextField(
                "There was also a coffee",
                text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0.isEmpty ? nil : $0 }),
                axis: .vertical
            )
            .font(WellieTheme.font(15, weight: .medium))
            .focused($isTyping)
            .lineLimit(1...5)
            .padding(14)
            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if hasNewNote {
                Button {
                    Task { await reread() }
                } label: {
                    if isRefining {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(
                            draft.items.isEmpty ? "Put this on the list" : "Take this into account",
                            systemImage: "sparkles"
                        )
                        .font(WellieTheme.font(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WellieSecondaryButtonStyle())
                .disabled(isRefining)
            }

            if let refineFailure {
                Text(refineFailure)
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
            }

            WellieCaption("Kept with this meal. Save it as a dish and it comes back next time.")
        }
        .wellieCard(padding: 20)
    }

    /// Offering to re-read is only honest while the note says something the list
    /// has not already been through.
    private var hasNewNote: Bool {
        let now = (draft.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !now.isEmpty && now != readNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A delta, not a re-run: the items may have been fixed by hand since, and
    /// regenerating the list would throw that work away.
    private func reread() async {
        let text = (draft.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTyping = false
        isRefining = true
        refineFailure = nil
        defer { isRefining = false }
        do {
            let revision = try await model.refine(
                imageData: PhotoStore.shared.data(for: meal.photoHash),
                current: draft.items,
                note: text
            )
            draft.items = revision.applied(to: draft.items)
            readNote = text
        } catch {
            refineFailure = error.localizedDescription
        }
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
                var revised = draft
                if !dishes.isEmpty {
                    let regrouped = MealDish.regrouped(draft.items, keeping: dishes)
                    revised.storedDishes = regrouped
                    revised.items = regrouped.flatMap { $0.flattened() }
                }
                await model.reviseMeal(revised)
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
