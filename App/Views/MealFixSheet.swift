import ShamanCore
import SwiftUI

/// Screen `4a·4`, behind `Edit ›`. Everything that is properly a correction.
///
/// The detail screen used to carry six cards: the sentence, the figures, the
/// share switch, a table share, the note, the time, and a delete. Five of them
/// were controls you would touch once a month, sitting permanently above a plate
/// you look at every day, and the effect was that the photograph — the thing the
/// screen is about — was 180 points tall at the top of a form.
///
/// So the split is by frequency rather than by topic. What you check is on the
/// plate; what you change is here.
///
/// The one path in and out of the food list is still words. There is no picker
/// to add an ingredient: you say what was missed and `MealRefiner` returns a
/// *delta* that touches only the rows the model names, so hand edits made on
/// the plate survive a re-read. That is also the only way a quantity is
/// corrected by hand.
struct MealFixSheet: View {
    let meal: MealEntry
    @Binding var draft: MealEntry
    @Binding var dishes: [MealDish]
    /// Called after the meal is removed, so the screen behind this one can
    /// leave too rather than sitting on a meal that no longer exists.
    let onDeleted: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var note: String
    /// The note as it stood when this meal was last read. Whatever was saved
    /// with the meal has already been through the model, so it is where the
    /// comparison starts.
    @State private var readNote: String
    @State private var isRefining = false
    @State private var refineFailure: String?
    @State private var showingDelete = false
    @State private var showingTableShare = false
    @FocusState private var isTyping: Bool

    init(
        meal: MealEntry,
        draft: Binding<MealEntry>,
        dishes: Binding<[MealDish]>,
        onDeleted: @escaping () -> Void
    ) {
        self.meal = meal
        _draft = draft
        _dishes = dishes
        self.onDeleted = onDeleted
        _note = State(initialValue: meal.note ?? "")
        _readNote = State(initialValue: meal.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    noteCard
                    factsCard
                    tableShareCard

                    Button("Remove this meal") { showingDelete = true }
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .wellieColumn()
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isTyping = false })
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .background(WellieTheme.background)
            .navigationTitle("Fix this meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .sheet(isPresented: $showingTableShare) { ShareToTableSheet(meal: meal) }
            .confirmationDialog("Remove this meal?", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task {
                        await model.deleteMeal(meal)
                        dismiss()
                        onDeleted()
                    }
                }
            } message: {
                Text("It leaves your history. The photo goes with it.")
            }
        }
        .wellieScreen()
    }

    // MARK: - In words

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieSectionTitle(
                text: "Missing or wrong?",
                detail: "Say what was missed or what it really was. Only the rows you name change."
            )

            TextField("There was also a coffee", text: $note, axis: .vertical)
                .font(WellieTheme.font(15.5, weight: .regular))
                .foregroundStyle(WellieTheme.ink)
                .tint(WellieTheme.accent)
                .focused($isTyping)
                .lineLimit(2...6)
                .padding(16)
                .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
                        .strokeBorder(isTyping ? WellieTheme.accent : WellieTheme.hairline, lineWidth: 1.5)
                }

            if hasNewNote {
                Button {
                    Task { await reread() }
                } label: {
                    if isRefining {
                        ProgressView().tint(WellieTheme.onAccent).frame(maxWidth: .infinity)
                    } else {
                        Text(draft.items.isEmpty ? "Put this on the list" : "Take this into account")
                    }
                }
                .buttonStyle(WelliePrimaryButtonStyle(enabled: !isRefining))
                .disabled(isRefining)
            }

            if let refineFailure {
                Text(refineFailure)
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wellieCard()
    }

    /// Offering to re-read is only honest while the note says something the
    /// list has not already been through.
    private var hasNewNote: Bool {
        let now = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return !now.isEmpty && now != readNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A delta, not a re-run: the items may have been fixed by hand since, and
    /// regenerating the list would throw that work away.
    private func reread() async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // A revision that changes nothing has to say so. Coming back to a
            // list with no new row in it reads as the app having dropped what
            // you typed.
            guard !revision.isEmpty else {
                refineFailure = "I couldn't tell what to change from that. Try naming the food in a few plain words."
                return
            }
            draft.items = revision.applied(to: draft.items)
            if !dishes.isEmpty {
                let regrouped = MealDish.regrouped(draft.items, keeping: dishes)
                dishes = regrouped
                draft.items = regrouped.flatMap { $0.flattened() }
            }
            draft.note = text
            readNote = text
        } catch {
            refineFailure = error.localizedDescription
        }
    }

    // MARK: - When

    private var factsCard: some View {
        HStack {
            Text("Eaten at")
                .font(WellieTheme.font(15.5, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            DatePicker(
                "",
                selection: Binding(
                    get: { Date(epochMillis: draft.eatenAt) },
                    set: { draft.eatenAt = $0.epochMillis }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, 6)
        .wellieCard(padding: 16)
    }

    /// Sharing this meal with friends, and only when there are friends to share
    /// it with — a button offering to share with nobody is an advert.
    @ViewBuilder
    private var tableShareCard: some View {
        if !model.tables.isEmpty {
            Button { showingTableShare = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Share with a table")
                        .font(WellieTheme.font(15.5, weight: .semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }
                .foregroundStyle(WellieTheme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .wellieCard(padding: 18)
        }
    }
}
