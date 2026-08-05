import ShamanCore
import SwiftUI

/// Screen `2g`. Dishes you cook often.
///
/// This exists because photographs have a ceiling no model clears: home cooking
/// hides its ingredients. French toast is two eggs, milk, and the butter it was
/// fried in, and none of that is in the frame. Describe it once and every later
/// log of it starts complete.
struct RecipesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: Recipe?
    @State private var creating = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Home cooking hides its ingredients.")
                        .font(WellieTheme.font(16, weight: .bold))
                    WellieProse(
                        """
                        A camera can't see the eggs in French toast or the oil in a stew. Describe a \
                        dish once and every later log of it starts complete.
                        """,
                        size: 14.5
                    )
                }
                .wellieCard(padding: 20)

                ForEach(model.recipes) { recipe in
                    SwipeToRemove {
                        Task { await model.deleteRecipe(recipe) }
                    } content: {
                        Button { editing = recipe } label: { row(recipe) }
                            .buttonStyle(.plain)
                    }
                }

                Button { creating = true } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(WellieTheme.ice)
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(WellieTheme.blue)
                            }
                        Text("Describe a new dish")
                            .font(WellieTheme.font(16.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                        Spacer(minLength: 0)
                    }
                    .wellieCard(padding: 20)
                }
                .buttonStyle(.plain)

                WellieCaption("Swipe a dish to remove it. Removing a dish doesn't change meals you've already logged.")
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle("My dishes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { RecipeEditor(recipe: $0) }
        .sheet(isPresented: $creating) { RecipeEditor(recipe: nil) }
        .wellieScreen()
    }

    private func row(_ recipe: Recipe) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WellieTheme.ice)
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: "text.book.closed.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WellieTheme.blue)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(WellieTheme.font(16.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                Text(subtitle(recipe))
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WellieTheme.faint)
        }
        .wellieCard(padding: 20)
        .contentShape(Rectangle())
    }

    private func subtitle(_ recipe: Recipe) -> String {
        var seen = Set<FoodGroup>()
        let foods = recipe.items.map(\.group)
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map(\.sentenceName)
            .joined(separator: ", ")
        let count = model.timesLogged(recipe)
        guard count > 0 else { return foods.isEmpty ? "Nothing in it yet" : foods }
        return "\(foods) · \(count) time\(count == 1 ? "" : "s")"
    }
}

/// Describing a dish: a name, the foods in it, and the line about what a
/// photograph could never show.
struct RecipeEditor: View {
    let recipe: Recipe?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var items: [MealItem] = []
    @State private var note = ""
    @State private var editing: EditingFood?
    @State private var showingAddFood = false
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What do you call it?")
                            .font(WellieTheme.font(15.5, weight: .semibold))
                        TextField("Lentil soup", text: $name)
                            .font(WellieTheme.font(17, weight: .semibold))
                            .focused($isTyping)
                            .submitLabel(.done)
                            .padding(14)
                            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .wellieCard(padding: 20)

                    VStack(alignment: .leading, spacing: 14) {
                        Text(items.isEmpty ? "What goes in it?" : "Tap a word to change it")
                            .font(WellieTheme.font(13, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)

                        if items.isEmpty {
                            WellieProse("Everything, including what a photo can't see — the eggs, the oil, the butter.")
                        } else {
                            FoodSentence(
                                lead: "It has",
                                words: items.map {
                                    .init(id: $0.id, text: FoodPhrase.word(for: $0.group, label: $0.label))
                                },
                                size: 21,
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

                    VStack(alignment: .leading, spacing: 10) {
                        Text("A note for next time")
                            .font(WellieTheme.font(15.5, weight: .semibold))
                        TextField("Fried in butter, two eggs in the batter…", text: $note, axis: .vertical)
                            .font(WellieTheme.font(15, weight: .medium))
                            .focused($isTyping)
                            .lineLimit(1...4)
                            .padding(14)
                            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        WellieCaption("Sent with the photo whenever you log this dish, so the read starts complete.")
                    }
                    .wellieCard(padding: 20)
                }
                .wellieColumn()
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isTyping = false })
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WellieTheme.background)
            .navigationTitle(recipe == nil ? "A new dish" : "Edit dish")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Save this dish") { save() }
                    .buttonStyle(WelliePrimaryButtonStyle(enabled: canSave))
                    .disabled(!canSave)
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(WellieTheme.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $editing) { target in
                if let index = items.firstIndex(where: { $0.id == target.id }) {
                    FoodEditSheet(
                        item: $items[index],
                        onRemove: { items.removeAll { $0.id == target.id } }
                    )
                }
            }
            .sheet(isPresented: $showingAddFood) {
                FoodGroupPicker { items.append(MealItem(group: $0, portion: .medium)) }
            }
            .onAppear(perform: load)
        }
        .wellieScreen()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !items.isEmpty
    }

    private func load() {
        guard let recipe, name.isEmpty else { return }
        name = recipe.name
        items = recipe.items
        note = recipe.note ?? ""
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = Recipe(
            // Keeping the id makes this an edit rather than a second dish with
            // the same name, and the log supersedes the old one.
            id: recipe?.id ?? UUIDv7.generate(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            items: items,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        Task { await model.saveRecipe(saved) }
        dismiss()
    }
}
