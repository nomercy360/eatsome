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
    @State private var showingTableShare = false
    @State private var isRefining = false
    @State private var refineFailure: String?
    /// The dish a new ingredient is being named for, the words being typed for
    /// it, and — while the model is weighing them — the words to quote back.
    /// Kept apart from the note: an addition is spent on the row it produces.
    @State private var adding: AddingIngredient?
    @State private var addText = ""
    @State private var addInFlight: String?
    /// Shown by the sentence rather than in the note card, which is where the
    /// re-read reports and is several cards further down.
    @State private var addFailure: String?
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
                tableShareCard
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
        .sheet(isPresented: $showingTableShare) { ShareToTableSheet(meal: meal) }
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
                // Never the ingredient sheet: it is pickers only, and a row
                // appended as `.other` to open it in gave the person "Something
                // else / Something else" and "Not weighed" — a promise to name
                // an ingredient with no way to name one.
                onAddIngredient: { adding = AddingIngredient(id: dish.id, dish: dish.name) },
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
        // The fix screen with the fix screen's words swapped out. Full screen
        // for the reason it is full screen there: a keyboard and a detent
        // cannot agree on a height.
        .fullScreenCover(item: $adding) { target in
            FixScreen(purpose: .add, text: $addText) {
                Task { await addIngredient(to: target.dish) }
            }
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
                Text(sentenceHeading)
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(addInFlight == nil ? WellieTheme.muted : WellieTheme.blue)
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

            if let addInFlight {
                WellieCaption("Adding “\(addInFlight)” — everything else stays as you set it.")
            } else if let addFailure {
                Text(addFailure)
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wellieCard()
        .animation(.easeInOut(duration: 0.2), value: addInFlight)
    }

    private var sentenceHeading: String {
        if addInFlight != nil { return "Adding it to the list…" }
        return draft.items.isEmpty ? "Nothing on this meal yet" : "Tap a word to change it"
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
    /// Sharing this meal with friends, and only when there are friends to share
    /// it with. `shareCard` above is a different question with an unfortunately
    /// similar name — that one asks how much of the plate was yours.
    ///
    /// Absent when you are in no tables, for the same reason the row on the day
    /// page is: a button offering to share with nobody is an advert.
    @ViewBuilder
    private var tableShareCard: some View {
        if !model.tables.isEmpty {
            Button { showingTableShare = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Share with a table")
                        .font(WellieTheme.font(15.5, weight: .bold))
                    Spacer(minLength: 8)
                    WellieMeta("Your olives stay yours")
                }
                .foregroundStyle(WellieTheme.blue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wellieCard()
        }
    }

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
            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))

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

    /// A named ingredient, weighed by the model and filed under the dish it was
    /// added from.
    ///
    /// The same delta as a fix, because it is the same act: the person supplies
    /// words, the model supplies the weight. The words are not appended to the
    /// note — the note is what is still to be taken into account, and these have
    /// been. The row on the list is the record.
    ///
    /// The dish is written on afterwards rather than asked for: the refiner is
    /// handed a flat list and knows nothing about dishes, so every row it adds
    /// comes back unfiled. Coming from a dish sheet there is nothing to guess.
    private func addIngredient(to dish: String) async {
        let text = addText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        addText = ""
        addInFlight = text
        isRefining = true
        addFailure = nil
        defer {
            isRefining = false
            addInFlight = nil
        }
        do {
            let existing = Set(draft.items.map(\.id))
            let revision = try await model.refine(
                imageData: PhotoStore.shared.data(for: meal.photoHash),
                current: draft.items,
                note: text
            )
            // A revision that changes nothing has to say so. Returning to a
            // sentence with no new word in it reads as the app having dropped
            // what you typed.
            guard !revision.isEmpty else {
                addFailure = "I couldn't tell what “\(text)” was. Try naming it in a few plain words."
                return
            }
            var updated = revision.applied(to: draft.items)
            for index in updated.indices where !existing.contains(updated[index].id) {
                updated[index].dish = dish
            }
            draft.items = updated
        } catch {
            addFailure = error.localizedDescription
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

            // "Save as a dish" was here, and it is gone with the screen that
            // listed them. What it existed for still happens, automatically:
            // home cooking hides its ingredients, so you correct a dish once —
            // the eggs in the French toast, the oil in the stew — and the next
            // time you log it from a chip it comes back with those corrections,
            // because the chip repeats the most recent logging rather than a
            // separately curated recipe. Naming it a second time was a list to
            // keep, and the log already knows.
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

}
