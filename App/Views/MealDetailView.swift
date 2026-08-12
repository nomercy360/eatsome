import ShamanCore
import SwiftUI

/// Screen `4a·4`. A meal you already saved.
///
/// The photograph is the page here, not an object on it — it runs to the top
/// edge under a gradient and the card floats on it. That is the one place in the
/// app a photo behaves that way, and the reason is that this screen is the only
/// one whose subject is a single plate: everywhere else a photo is one of
/// several things in a list.
///
/// What is on the card is what you would want to check without deciding to edit
/// anything: when, what it was, and the five figures. The meal reads as a
/// sentence and every word in it is tappable, which is the same gesture and the
/// same words as the capture screen — editing later uses the muscle you already
/// have. Everything that is properly an *edit* — a correction in words, the
/// time, sharing, removing it — moved behind `Edit ›` into `MealFixSheet`, so
/// this screen has one question on it ("how much of that was yours?") instead
/// of six cards of controls.
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
    @State private var showingFix = false
    /// The same destination as `showingFix`, in the other presentation slot.
    ///
    /// A dish sheet is already up when this one is asked for, and a second
    /// `.sheet` on the same view cannot present over the first — it silently
    /// does nothing. A `fullScreenCover` is a separate slot, so the fix screen
    /// opens over the dish and the dish is still there underneath when it
    /// closes. That is also how the add-ingredient screen behaved before.
    @State private var addingFromDish = false

    init(meal: MealEntry) {
        self.meal = meal
        _draft = State(initialValue: meal)
        _dishes = State(initialValue: meal.storedDishes ?? [])
    }

    private var photo: UIImage? { PhotoStore.shared.image(for: meal.photoHash) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if let photo { banner(photo) }
                    VStack(spacing: 0) {
                        Color.clear.frame(height: photo == nil ? 8 : 208)
                        plateCard
                            .padding(.horizontal, 18)
                    }
                }

                shareSection
                    .padding(.horizontal, 18)
                    .padding(.top, 24)

                Button { showingFix = true } label: {
                    HStack(spacing: 8) {
                        Text("Missing or wrong?")
                            .font(WellieTheme.font(14, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                        Spacer(minLength: 8)
                        Text("Edit")
                            .font(WellieTheme.font(14, weight: .semibold))
                            .foregroundStyle(WellieTheme.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WellieTheme.accent)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: photo == nil ? [] : .top)
        .background(WellieTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .wellieBackSwipe()
        .overlay(alignment: .topLeading) { backButton }
        .safeAreaInset(edge: .bottom) { if draft != meal { saveBar } }
        .sheet(isPresented: $showingFix) {
            MealFixSheet(meal: meal, draft: $draft, dishes: $dishes) { dismiss() }
        }
        .fullScreenCover(isPresented: $addingFromDish) {
            MealFixSheet(meal: meal, draft: $draft, dishes: $dishes) { dismiss() }
        }
        .sheet(item: $editing) { target in
            if let index = draft.items.firstIndex(where: { $0.id == target.id }) {
                FoodEditSheet(
                    item: $draft.items[index],
                    onRemove: { draft.items.removeAll { $0.id == target.id } }
                )
            }
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
                // an ingredient with no way to name one. Words are the one way
                // in, which is what the fix screen is.
                onAddIngredient: { addingFromDish = true },
                onCount: { count in
                    guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                    // Rewrites the weights rather than multiplying when read: a
                    // weighed dish already holds every serving that is present,
                    // so "one, not three" has to take two thirds of it back off.
                    dishes[index] = dishes[index].scaled(toCount: count)
                    draft.items = dishes.flatMap { $0.flattened() }
                },
                onRemove: {
                    let members = Set(dish.items.map(\.id))
                    draft.items.removeAll { members.contains($0.id) }
                }
            )
        }
        .onChange(of: draft.items) { _, updated in
            guard !dishes.isEmpty else { return }
            dishes = MealDish.regrouped(updated, keeping: dishes)
        }
        .wellieScreen()
    }

    // MARK: - The photograph

    /// The photograph, filling the width at a fixed height.
    ///
    /// Sized by an empty container with the image as an *overlay* rather than
    /// by hanging two frames off the image. `scaledToFill` fills whatever size
    /// it is proposed, and stacked `.frame(height:)` / `.frame(maxWidth:)`
    /// modifiers make the order they were written in load-bearing — which is
    /// the kind of detail that survives until someone reorders them tidily.
    /// `Color.clear` settles the size first and the overlay has one thing to
    /// fill.
    private func banner(_ image: UIImage) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                // Dark at the top so the back button reads on a bright plate,
                // dark at the bottom so the card has something to sit on.
                LinearGradient(
                    stops: [
                        .init(color: WellieTheme.background.opacity(0.55), location: 0),
                        .init(color: WellieTheme.background.opacity(0), location: 0.4),
                        .init(color: WellieTheme.background.opacity(0.9), location: 0.92),
                        .init(color: WellieTheme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, alignment: .top)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                Text("Today")
            }
            .font(WellieTheme.font(14, weight: .semibold))
            .foregroundStyle(photo == nil ? WellieTheme.accent : .white)
            .padding(.horizontal, 22)
            .wellieHitTarget()
        }
        .buttonStyle(.plain)
    }

    // MARK: - The plate

    /// The card that floats on the photograph.
    ///
    /// Translucent rather than solid, and it is the one translucent surface in
    /// the app: what is behind it is the plate this card describes, so letting a
    /// little of it through is information rather than decoration.
    private var plateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            WellieMeta(
                "\(DayFormat.time(draft.eatenAt)) · \(MealDisplay.partOfDay(draft))",
                color: WellieTheme.accent
            )

            if draft.items.isEmpty {
                Text("Nothing on this meal yet")
                    .font(WellieTheme.font(24, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .padding(.top, 10)
            } else {
                FoodSentence(
                    lead: "",
                    words: sentenceWords,
                    size: 24,
                    punctuates: false,
                    onTap: { tapWord($0) }
                )
                .padding(.top, 10)
                Text("Tap a word to change it")
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 8)
            }

            figures
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(WellieTheme.surface.opacity(photo == nil ? 1 : 0.72))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        }
    }

    /// What this meal came to, share included.
    ///
    /// No targets and no meters: a target is a property of a day, and a single
    /// meal measured against one would say a normal lunch was a third of a
    /// person. This states what was eaten and stops.
    @ViewBuilder
    private var figures: some View {
        if !draft.items.isEmpty {
            let total = model.nutrients(in: draft)
            let shown = shownFigures(total)
            if !shown.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(shown, id: \.name) { figure($0.name, $0.value, $0.unit) }
                    // Keeps two figures at two-fifths width rather than
                    // stretching them across the card.
                    ForEach(shown.count..<5, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 18)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.09)).frame(height: 1)
                }
                .padding(.top, 22)

                if let attention = total.foodMatchAttention {
                    Text(attention + " Tap the highlighted food to name it more precisely.")
                        .font(WellieTheme.font(12, weight: .regular))
                        .foregroundStyle(WellieTheme.attention)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                }
            }
        }
    }

    /// The figures worth printing, in a fixed order, skipping the ones that
    /// round to nothing.
    ///
    /// A figure that rounds to nothing is left out rather than printed as zero:
    /// "0 g protein" above a can of Monster is a true sentence that tells a
    /// person nothing they did not know, and a row of five zeros makes the two
    /// real numbers on that can harder to find rather than easier.
    private func shownFigures(
        _ total: NutrientTotal
    ) -> [(name: String, value: String, unit: String)] {
        let meal = total.nutrients
        var out: [(name: String, value: String, unit: String)] = []
        func add(_ name: String, _ value: Double, _ unit: String) {
            guard value.rounded() > 0 else { return }
            out.append((name, "\(Int(value.rounded()))", unit))
        }
        add("Energy", meal.kcal, "kcal")
        add("Protein", meal.protein, "g")
        add("Carbs", meal.carbohydrate, "g")
        add("Fat", meal.fat, "g")
        // Salt is the one shown to a decimal, because the interesting range is
        // 0.5 to 5 g and whole grams would round most meals to nothing. `≥` only
        // when it was derived: a label that printed 食塩相当量 settled the number,
        // and marking that as a lower bound understates a known fact. There is
        // deliberately no daily ceiling beside it — see `Nutrients.saltGrams`.
        let salt = meal.saltGrams
        if salt >= 0.05 {
            out.append((
                "Salt",
                (total.saltIsFloor ? "≥" : "") + String(format: "%.1f", salt),
                "g"
            ))
        }
        return out
    }

    private func figure(_ name: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(WellieTheme.font(12, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(WellieTheme.font(17, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                if unit != "kcal" {
                    Text(" \(unit)")
                        .font(WellieTheme.font(12, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(value) \(unit)")
    }

    /// A dish is one word and its ingredients are behind it. A meal saved
    /// before dishes existed has none, and reads food by food as it always did.
    ///
    /// The first word takes a capital because there is no lead any more: the
    /// capture screen says "You had *salmon and tuna don*", where this card puts
    /// the sentence where a title goes and "salmon and tuna don" alone reads as
    /// a typo rather than as a style.
    private var sentenceWords: [FoodSentence.Word] {
        let unresolved = Set(draft.items.compactMap { item -> UUID? in
            guard item.resolution?.status == .unresolved
                    || (item.resolution == nil
                        && model.config.nutrientsPerGram?.food(for: item) == nil)
            else { return nil }
            return item.id
        })
        var words = dishes.isEmpty
            ? draft.items.map {
                FoodSentence.Word(
                    id: $0.id,
                    text: FoodPhrase.word(for: $0.kind, label: $0.label),
                    isUncertain: unresolved.contains($0.id)
                )
            }
            : FoodSentence.words(for: dishes, uncertain: unresolved)
        if let first = words.first {
            words[0] = FoodSentence.Word(
                id: first.id,
                text: first.text.capitalizedFirst,
                isUncertain: first.isUncertain,
                isPending: first.isPending
            )
        }
        return words
    }

    private func tapWord(_ id: UUID) {
        if let dish = dishes.first(where: { $0.id == id }) {
            openDish = dish
        } else {
            editing = EditingFood(id: id)
        }
    }

    // MARK: - How much was yours

    /// The one control that exists because sharing genuinely changes the
    /// arithmetic: a platter counted whole is the largest way this app can
    /// overstate what you ate. Worded exactly as the capture screen words it —
    /// two screens asking the same thing in different words is how a person
    /// comes to believe they are two different questions.
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How much was yours?")
                .font(WellieTheme.font(13, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            WellieChipRow(
                options: MealShare.allCases,
                selection: Binding(get: { draft.eaten }, set: { draft.share = $0 }),
                title: \.chipName,
                fills: true
            )
        }
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
