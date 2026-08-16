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
    private var hasPhoto: Bool { PhotoStore.shared.image(for: meal.photoHash) != nil }
    private var singleDish: MealDish? { meal.dishes.count == 1 ? meal.dishes.first : nil }
    private var singleItem: MealItem? { singleDish.flatMap { $0.items.count == 1 ? $0.items.first : nil } }
    /// Frame 2: a menu item with a decision pending, before saving.
    private var pendingPick: Bool {
        guard !isSaved, let item = singleItem else { return false }
        return MealDetailModel.needsPick(item) && !resolved.contains(item.id)
    }

    var body: some View {
        // The photograph scrolls with the page. It is the background of the
        // scroll *content*, not of the screen: a fixed backdrop under a moving
        // card read as the card sliding over a poster, and the plate is part
        // of the record, not wallpaper. The scroll view runs to the top edge
        // so the photo can too, and the nav row floats over it.
        GeometryReader { geometry in
        let topInset = geometry.safeAreaInsets.top
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                    if !hasPhoto { plainHeading.padding(.top, 30 + navRowHeight + topInset) }
                    card.padding(.top, hasPhoto ? 186 + navRowHeight + topInset : 22)
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
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        if hasPhoto { photoBackdrop(width: geometry.size.width) }
                    }
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                footer.background(WellieTheme.background)
            }
            navRow.padding(.top, topInset).ignoresSafeArea(edges: .top)
        }
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
                .foregroundStyle(WellieTheme.ink)
                .padding(.horizontal, hasPhoto ? 14 : 0)
                .padding(.vertical, hasPhoto ? 9 : 0)
                .background {
                    if hasPhoto { Capsule().fill(.ultraThinMaterial) }
                }
                .overlay {
                    if hasPhoto { Capsule().strokeBorder(WellieTheme.glassStroke, lineWidth: 1) }
                }
            }
            .buttonStyle(.plain)
            .disabled(onBack == nil)
            .accessibilityLabel("Back to Today")
            Spacer()
            Text(navSubtitle)
                .font(WellieTheme.figure(14, weight: .regular))
                .foregroundStyle(hasPhoto ? WellieTheme.body : WellieTheme.muted)
                .padding(.horizontal, hasPhoto ? 14 : 0)
                .padding(.vertical, hasPhoto ? 9 : 0)
                .background {
                    if hasPhoto { Capsule().fill(.ultraThinMaterial) }
                }
                .overlay {
                    if hasPhoto { Capsule().strokeBorder(WellieTheme.glassStroke, lineWidth: 1) }
                }
        }
        .padding(.horizontal, hasPhoto ? 20 : 26)
        .padding(.top, 12)
    }

    // MARK: The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasPhoto {
                title
                Text(summarySubtitle)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.body)
                    .padding(.top, 5)
            }
            figures.padding(.top, hasPhoto ? 18 : 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if hasPhoto {
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(WellieTheme.surface.opacity(0.78))
            } else {
                RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
                    .fill(WellieTheme.surface)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: hasPhoto ? WellieTheme.heroRadius : WellieTheme.controlRadius, style: .continuous)
                .strokeBorder(hasPhoto ? WellieTheme.glassStroke : WellieTheme.hairline, lineWidth: 1)
        }
    }

    private var plainHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            title
            Text(summarySubtitle)
                .font(WellieTheme.font(13))
                .foregroundStyle(WellieTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// The height the floating nav row occupies over the photograph, which the
    /// scroll content pads for so nothing starts underneath it.
    private let navRowHeight: CGFloat = 60

    @ViewBuilder
    private func photoBackdrop(width: CGFloat) -> some View {
        if let image = PhotoStore.shared.image(for: meal.photoHash) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: 400)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, WellieTheme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 80)
                }
                .accessibilityHidden(true)
        }
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
        if let dish = singleDish, let item = singleItem, MealDetailModel.hasPick(item), !pendingPick {
            Button { changingPick = dish } label: { text.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint("Change what this is or which one it was")
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
        if let item = singleItem, MealDetailModel.hasPick(item) {
            return "Tap a word to change it"
        }
        return meal.eaten == .whole ? "As logged" : "\(meal.eaten.chipName) of it"
    }

    private var summarySubtitle: String {
        if meal.wasCorrected {
            return "\(meal.eaten.chipName) of it · corrected by you"
        }
        let source = meal.source == .text ? "as you wrote it" : "Estimated"
        return "\(subtitle) · \(source)"
    }

    private var figures: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // The halo is a soft ellipse behind the figure, not clipped to
                // the figure's box — a glow with an edge is a green rectangle.
                // Same construction as Today's, at the size of a 34 pt number.
                Text(EatsomeFormat.whole(meal.nutrients.kcal))
                    .font(WellieTheme.figure(34, weight: .heavy))
                    .tracking(-1)
                    .foregroundStyle(WellieTheme.ink)
                    .frame(height: 40)
                    .background {
                        RadialGradient(
                            colors: [WellieTheme.accent.opacity(0.5), WellieTheme.accent.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(x: 0.7, y: 0.5)
                        .offset(y: 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                Text("kcal")
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Text("Salt \(meal.nutrients.saltGrams.formatted(.number.precision(.fractionLength(0...1)))) g")
                    .font(WellieTheme.figure(12))
                    .foregroundStyle(WellieTheme.muted)
            }
            WellieRowDivider().padding(.top, 16)
            HStack(spacing: 0) {
                macro(.protein, "Protein", meal.nutrients.protein)
                macro(.carbs, "Carbs", meal.nutrients.carbohydrate)
                macro(.fat, "Fat", meal.nutrients.fat)
            }
            .padding(.top, 16)
        }
    }

    private func macro(_ kind: NutrientKind, _ name: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                NutrientIcon(kind: kind, size: 14)
                Text(name)
                    .font(WellieTheme.font(11, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
            }
            Text("\(EatsomeFormat.whole(value)) g")
                .font(WellieTheme.figure(17, weight: .heavy))
                .foregroundStyle(WellieTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var provenance: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(MealDetailModel.provenanceLine(meal, resolved: !pendingPick))
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !pendingPick, let dish = singleDish, let item = singleItem, MealDetailModel.hasPick(item) {
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
///
/// One question: the widest open fork (`MealDetailModel.askedFork`), or the
/// rivals when no fork is open. Answering commits and resolves the row; the
/// sheet behind Change offers the rest.
private struct InlinePick: View {
    let dish: MealDish
    let item: MealItem
    let onPick: (MealDish) -> Void

    @State private var pick: MealDetailModel.ForkPick?
    @State private var alternative: FoodAlternative?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let fork = MealDetailModel.askedFork(item) {
                ForkChips(fork: fork, selection: $pick)
            } else if !item.alternatives.isEmpty {
                WhichOneChips(current: item.label, alternatives: item.alternatives, selection: $alternative)
            }
        }
        .onChange(of: pick) { _, _ in commit() }
        .onChange(of: alternative) { _, _ in commit() }
    }

    private func commit() {
        onPick(MealDetailModel.applying(count: dish.count, pick: pick, alternative: alternative, to: dish))
    }
}
