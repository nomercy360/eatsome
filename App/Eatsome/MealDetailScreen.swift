import EatsomeCore
import SwiftUI

/// Screen `13c`. One meal, in one of two states.
///
/// Before it is saved the footer is `[Fix it] [Add to today]`; after, it is
/// "Missing or wrong? Edit ›". Everything above the footer is the same view,
/// which is why it is one view with a mode rather than two screens that would
/// have drifted apart by the second release.
///
/// What the screen is for is correcting without leaving. How much was yours,
/// how many there were, what size, which one — each is a control on the
/// detail that moves a stored, priced value, so the five figures at the top
/// are never a name with the old numbers behind it. Anything a control cannot
/// express — a food that is not on the shortlist, an ingredient the model
/// missed — is a correction in words, behind *Fix it* / *Edit ›*, where the
/// model re-prices what it renames.
struct MealDetailScreen: View {
    enum Mode {
        /// Not yet in the log. `onFix` opens the correction in words; `onAdd`
        /// receives the meal as it stands to be recorded.
        case confirming(onFix: (MealEntry) -> Void, onAdd: (MealEntry) -> Void)
        /// In the log. Changes are recorded as `mealRevised`; `onEdit` opens the
        /// correction in words.
        case saved(onEdit: (MealEntry) -> Void)
    }

    let mode: Mode
    var onBack: (() -> Void)? = nil
    /// The photo path is the logging lane's. Nil hides the row.
    var onAddPhoto: ((MealEntry) -> Void)? = nil

    @Environment(EatsomeStore.self) private var store
    @State private var meal: MealEntry
    /// Rows the person has picked a size or a rival for, before saving. Saving
    /// is never blocked on this: an ignored question is recorded as it stands.
    @State private var resolved: Set<UUID> = []
    @State private var changingPick: MealDish?
    @State private var editingItem: MealDish?
    @State private var editingNote = false

    init(meal: MealEntry, mode: Mode, onBack: (() -> Void)? = nil, onAddPhoto: ((MealEntry) -> Void)? = nil) {
        _meal = State(initialValue: meal)
        self.mode = mode
        self.onBack = onBack
        self.onAddPhoto = onAddPhoto
    }

    private var isSaved: Bool { if case .saved = mode { return true } else { return false } }
    private var singleDish: MealDish? { meal.dishes.count == 1 ? meal.dishes.first : nil }
    private var singleItem: MealItem? { singleDish.flatMap { $0.items.count == 1 ? $0.items.first : nil } }
    /// Frame 2: a menu item with a decision pending, before saving.
    private var pendingPick: Bool {
        guard !isSaved, let item = singleItem else { return false }
        return MealDetailModel.needsPick(item) && !resolved.contains(item.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            navRow
            ScrollView {
                VStack(spacing: 0) {
                    card.padding(.top, 22)
                    if pendingPick, let dish = singleDish, let item = singleItem {
                        InlinePick(dish: dish, item: item) { picked in
                            commit(MealDetailModel.replacing(picked, in: meal))
                            resolved.insert(picked.items.first?.id ?? item.id)
                        }
                        .padding(.top, 14)
                    } else if let dish = singleDish {
                        amountBlock(dish).padding(.top, 20)
                    } else {
                        itemsBlock.padding(.top, 22)
                    }
                    if !pendingPick {
                        MealNoteRow(note: meal.personalNote) { editingNote = true }
                            .padding(.top, 12)
                    }
                    if meal.photoHash == nil, let onAddPhoto, !isSaved {
                        addPhotoRow { onAddPhoto(meal) }.padding(.top, 12)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .scrollIndicators(.hidden)
            footer.background(WellieTheme.background)
        }
        .background(WellieTheme.background)
        .sheet(item: $changingPick) { dish in
            ChangePickSheet(dish: dish) { picked, _ in
                commit(MealDetailModel.replacing(picked, in: meal))
            }
        }
        .sheet(item: $editingItem) { dish in
            ChangePickSheet(dish: dish, showsAmount: true, share: dish.share) { picked, share in
                var next = picked
                next.share = share == .whole ? nil : share
                commit(MealDetailModel.replacing(next, in: meal))
            }
        }
        .fullScreenCover(isPresented: $editingNote) {
            MealNoteEditor(title: navSubtitle, text: meal.personalNote ?? "") { note in
                var next = meal
                next.personalNote = note
                commit(next, corrected: false)
            }
        }
        .wellieScreen()
    }

    // MARK: Committing

    /// One place a change lands. Before saving it is the working copy; after,
    /// it is a `mealRevised` event, because a correction is a new line and
    /// never a mutation. A note is not a correction and does not flip
    /// `wasCorrected` — a person writing "lovely" about their soup has not
    /// disputed the soup.
    private func commit(_ next: MealEntry, corrected: Bool = true) {
        var updated = next
        if corrected { updated.wasCorrected = true }
        meal = updated
        if isSaved {
            Task { await store.record(.mealRevised(updated), occurredAt: updated.eatenAt) }
        }
    }

    // MARK: Nav

    private var navSubtitle: String {
        "\(EatsomeFormat.time(meal.eatenAt)) · \(Daypart(at: meal.eatenAt).displayName)"
    }

    private var navRow: some View {
        HStack {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Today")
                }
                .font(WellieTheme.font(14, weight: .semibold))
                .foregroundStyle(WellieTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(onBack == nil)
            .accessibilityLabel("Back to Today")
            Spacer()
            Text(navSubtitle)
                .font(WellieTheme.font(14, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            photograph
            VStack(alignment: .leading, spacing: 0) {
                title
                Text(subtitle)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 8)
                figures
                    .padding(.top, 18)
                    .overlay(alignment: .top) { Rectangle().fill(WellieTheme.hairline).frame(height: 1) }
                    .padding(.top, 22)
                provenance
                    .padding(.top, 14)
                    .overlay(alignment: .top) { Rectangle().fill(WellieTheme.hairline).frame(height: 1) }
                    .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Clipped before the surface is drawn, so the photograph's top corners
        // are the card's corners. `wellieSurface` paints its background inside
        // the same shape and strokes its border over the top, so neither is
        // eaten by the clip.
        .clipShape(RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous))
        .wellieSurface(radius: WellieTheme.controlRadius)
    }

    /// The plate, at the top of its own card.
    ///
    /// The full stored JPEG rather than a thumbnail: this is 190 points tall
    /// and the width of the screen, where the 36 pt version on Today would be
    /// visibly soft. `PhotoStore` caches the decode, so the cost is paid once
    /// and not on every redraw of a screen whose chips move the figures.
    ///
    /// Absent means absent — no frame, no placeholder glyph. A meal typed in
    /// has no photograph and never will, and a grey square standing in for one
    /// is an empty slot inviting a person to wonder what is missing. The
    /// composer draws the fork-and-knife stand-in because there a picture is
    /// still expected; here it is not.
    @ViewBuilder
    private var photograph: some View {
        if let image = PhotoStore.shared.image(for: meal.photoHash) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 190)
                .frame(maxWidth: .infinity)
                .clipped()
                .accessibilityElement()
                .accessibilityLabel("Photograph of this meal")
        }
    }

    /// The title is the dish sentence. On a one-item meal with rivals it is
    /// also the way in to *which one?* — "tap a word to change it" — and the
    /// whole title is the tap target rather than each word, because a title
    /// is one food here and splitting it into words would offer to change
    /// "B.M.T." on its own.
    @ViewBuilder
    private var title: some View {
        let text = Text(MealTitle.of(meal))
            .font(WellieTheme.font(25, weight: .bold))
            .foregroundStyle(WellieTheme.ink)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        if let dish = singleDish, let item = singleItem, !item.alternatives.isEmpty || item.sizes.count > 1, !pendingPick {
            Button { changingPick = dish } label: { text.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Change what this is or what size it was")
        } else {
            text
        }
    }

    private var subtitle: String {
        if meal.dishes.count > 1 { return "\(meal.dishes.count) items together" }
        if let dish = singleDish, dish.count > 1 {
            // "4 cartons · 103 kcal each" in the mock. Nothing stores a
            // vessel, so the count is of servings.
            return "\(dish.count) servings · \(EatsomeFormat.whole(MealDetailModel.perServingKcal(dish))) kcal each"
        }
        if let item = singleItem, !item.alternatives.isEmpty || item.sizes.count > 1 {
            return "Tap a word to change it"
        }
        return meal.eaten == .whole ? "As logged" : "\(meal.eaten.chipName) of it"
    }

    private var figures: some View {
        let list = MealFigure.figures(meal.nutrients)
        return HStack(alignment: .top, spacing: 6) {
            ForEach(list) { figure in
                VStack(alignment: .leading, spacing: 5) {
                    Text(figure.name)
                        .font(WellieTheme.font(12, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                    Text(figure.text)
                        .font(WellieTheme.font(18, weight: .bold))
                        // A displayed zero keeps its column and stops competing.
                        .foregroundStyle(figure.isZero ? WellieTheme.muted : WellieTheme.ink)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(figure.spoken)
            }
        }
    }

    private var provenance: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MealDetailModel.provenanceLine(meal, resolved: !pendingPick))
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !pendingPick, let dish = singleDish, let item = singleItem, item.sizes.count > 1 || !item.alternatives.isEmpty {
                Button("Change") { changingPick = dish }
                    .font(WellieTheme.font(12.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
                    .fixedSize()
            }
        }
    }

    // MARK: One dish

    private func amountBlock(_ dish: MealDish) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How much was yours?")
                .font(WellieTheme.font(13, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            ShareAndCountRow(
                share: Binding(
                    get: { meal.share },
                    set: { share in
                        var next = meal
                        next.share = share == .whole ? nil : share
                        commit(next)
                    }
                ),
                count: Binding(
                    get: { dish.count },
                    set: { count in commit(MealDetailModel.replacing(dish.scaled(toCount: count), in: meal)) }
                )
            )
            .padding(.top, 12)
            Text(dish.count > 1
                 ? "The numbers above already count all \(ProgressData.number(dish.count).lowercased())."
                 : "Had more than one? Each + adds a whole one.")
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .padding(.top, 10)
        }
    }

    // MARK: Several things

    private var itemsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            WellieMeta("What's in it", size: 11.5)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(meal.dishes.enumerated()), id: \.element.id) { index, dish in
                    if index > 0 { Rectangle().fill(WellieTheme.hairline).frame(height: 1) }
                    itemRow(dish)
                }
            }
            .padding(.horizontal, 16)
            .wellieSurface(radius: WellieTheme.innerRadius)
            .padding(.top, 12)
            Text("Tap an item for its own amount, size and kind. Counts change the totals above.")
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .padding(.horizontal, 4)
                .padding(.top, 10)
            addItemRow.padding(.top, 12)
        }
    }

    private func itemRow(_ dish: MealDish) -> some View {
        HStack(spacing: 12) {
            Button { editingItem = dish } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dish.name.map(EatsomeFormat.capitalizedFirst) ?? EatsomeFormat.capitalizedFirst(dish.items.first?.label ?? "Item"))
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(EatsomeFormat.whole(MealDetailModel.perServingKcal(dish))) kcal each")
                        if let item = dish.items.first, !item.alternatives.isEmpty {
                            Text("·")
                            Text("\(item.alternatives.count) more option\(item.alternatives.count == 1 ? "" : "s")")
                                .foregroundStyle(WellieTheme.accent)
                                .fontWeight(.semibold)
                        }
                    }
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RowStepper(count: Binding(
                get: { dish.count },
                set: { count in commit(MealDetailModel.replacing(dish.scaled(toCount: count), in: meal)) }
            ))
            Button { editingItem = dish } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WellieTheme.faint)
                    .frame(width: 24, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change \(dish.name ?? "item")")
        }
        .padding(.vertical, 13)
    }

    /// "Add an item" is a correction in words — there is no picker for a food
    /// the model did not name — so it goes where words go.
    private var addItemRow: some View {
        Button { openWords() } label: {
            HStack {
                Text("Add an item")
                    .font(WellieTheme.font(14.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
                    .strokeBorder(WellieTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addPhotoRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(WellieTheme.raised)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "camera")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WellieTheme.accent)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a photo")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    // "Sharpens the estimate, and the table sees it" in the
                    // mock; Tables is cut, and the first half stands alone.
                    Text("Sharpens the estimate")
                        .font(WellieTheme.font(12.5, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.outline, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private func openWords() {
        switch mode {
        case .confirming(let onFix, _): onFix(meal)
        case .saved(let onEdit): onEdit(meal)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .confirming(let onFix, let onAdd):
            // 1 : 1.35, as the mock draws it — the primary action is the wider
            // one, and a plain `HStack` would split the row in half.
            GeometryReader { geometry in
                let gap: CGFloat = 10
                let unit = (geometry.size.width - gap) / 2.35
                HStack(spacing: gap) {
                    Button { onFix(meal) } label: {
                        Text("Fix it")
                            .font(WellieTheme.font(15, weight: .bold))
                            .foregroundStyle(WellieTheme.body)
                            .frame(width: unit)
                            .padding(.vertical, 16)
                            .wellieSurface(radius: 22, border: WellieTheme.outline)
                    }
                    .buttonStyle(.plain)
                    Button { onAdd(meal) } label: {
                        Text("Add to today")
                            .font(WellieTheme.font(15, weight: .bold))
                            .foregroundStyle(WellieTheme.onAccent)
                            .frame(width: unit * 1.35)
                            .padding(.vertical, 16)
                            .background(WellieTheme.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(height: 54)
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.bottom, 20)
        case .saved(let onEdit):
            HStack {
                Text("Missing or wrong?")
                    .font(WellieTheme.font(14, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Button { onEdit(meal) } label: {
                    HStack(spacing: 2) {
                        Text("Edit")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }
}

// MARK: - Frame 2

/// The pickers inline on the detail, before a decision is made. Same chips as
/// the sheet; the difference is that here they commit on tap, because there is
/// no "Use this" — the card above is the preview.
private struct InlinePick: View {
    let dish: MealDish
    let item: MealItem
    let onPick: (MealDish) -> Void

    @State private var size: FoodSize?
    @State private var alternative: FoodAlternative?

    init(dish: MealDish, item: MealItem, onPick: @escaping (MealDish) -> Void) {
        self.dish = dish
        self.item = item
        self.onPick = onPick
        // The size that is already priced is shown selected: the card above
        // is a preview of it, and a row of chips with none chosen would say
        // the figures came from nowhere.
        _size = State(initialValue: MealDetailModel.chosenSize(of: item, count: dish.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if item.sizes.count > 1 {
                SizeChips(sizes: item.sizes, selection: $size)
            }
            if !item.alternatives.isEmpty {
                WhichOneChips(current: item.label, alternatives: item.alternatives, selection: $alternative)
            }
        }
        .onChange(of: size) { _, _ in commit() }
        .onChange(of: alternative) { _, _ in commit() }
    }

    private func commit() {
        onPick(MealDetailModel.applying(count: dish.count, size: size, alternative: alternative, to: dish))
    }
}
