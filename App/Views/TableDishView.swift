import ShamanCore
import SwiftUI

/// Screen `9c`. A friend's dish, opened like a gallery page.
///
/// Full-bleed photo, big grotesque title, ingredients as hairline chips, one
/// dark save button. Replies keep the feed's quiet register.
///
/// What is *not* here is the point of the screen: there are no olives, no
/// score, no week. The person who shared this is not being marked, and there
/// is nowhere on this page a judgement of their eating could be drawn even by
/// accident — the post never carried one. "What's in it" is present only when
/// they switched it on, and its absence is the redaction rather than a gap.
struct TableDishView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let table: TableSummary
    let post: TablePost
    let react: (TableReaction, Bool) -> Void

    @State private var photo: UIImage?
    @State private var saving = false
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let photo {
                    WelliePhoto(image: photo, height: 320)
                }

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.dishName ?? "A meal")
                            .font(WellieTheme.font(28, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        WellieMeta(byline)
                    }

                    if let caption = post.caption, !caption.isEmpty {
                        Text(caption)
                            .font(WellieTheme.font(15.5, weight: .medium))
                            .foregroundStyle(WellieTheme.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    reactions

                    ingredients

                    save
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .background(WellieTheme.background)
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhoto() }
        .wellieScreen()
    }

    private var byline: String {
        let time = DayTimeline.clock.string(from: Date(epochMillis: post.createdAt))
        return "\(post.authorName) · \(time)"
    }

    private var reactions: some View {
        HStack(spacing: 18) {
            ForEach(TableReaction.allCases, id: \.self) { kind in
                let state = post.reaction(kind)
                Button { react(kind, !(state?.mine ?? false)) } label: {
                    HStack(spacing: 6) {
                        switch kind {
                        case .olive:
                            OliveMark().frame(width: 15, height: 15)
                                .opacity(state?.mine == true ? 1 : 0.3)
                        case .heart:
                            Image(systemName: state?.mine == true ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(state?.mine == true ? WellieTheme.heart : WellieTheme.muted)
                        }
                        if let count = state?.count, count > 0 {
                            Text("\(count)")
                                .font(WellieTheme.metaFont(11))
                                .foregroundStyle(WellieTheme.muted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    /// Hairline chips, and only when the sharer said yes.
    ///
    /// Weights are shown when they travelled, because "180 g" is what makes a
    /// friend's portion useful rather than decorative — but they are the
    /// sharer's weights, not a target, and nothing on this page turns them into
    /// a figure about the reader.
    @ViewBuilder
    private var ingredients: some View {
        if let rows = post.ingredients, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                WellieMeta("What's in it · from \(post.authorName)'s log")
                FlowLayout(spacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        chip(row)
                    }
                }
            }
        } else {
            WellieCaption(
                "\(post.authorName) shared the dish but not what's in it. That's theirs to switch on."
            )
        }
    }

    private func chip(_ row: PostIngredient) -> some View {
        let name = row.label?.isEmpty == false ? row.label! : row.group.shortName
        let weight = row.grams.map { " · \(Int($0.rounded())) g" } ?? ""
        return Text(name + weight)
            .font(WellieTheme.font(13, weight: .medium))
            .foregroundStyle(WellieTheme.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }

    /// One dark button, and it saves into *your* log as a meal you can then
    /// correct — not a copy of their entry. What arrives is what they chose to
    /// share, which is why the button is disabled without ingredients: a meal
    /// with a name and no food in it would score as nothing and read as a bug.
    @ViewBuilder
    private var save: some View {
        if let rows = post.ingredients, !rows.isEmpty {
            Button {
                saving = true
                Task {
                    await model.saveSharedDish(post, ingredients: rows)
                    saving = false
                    saved = true
                }
            } label: {
                Text(saved ? "Saved to your log" : "Save to my collections")
                    .font(WellieTheme.font(16, weight: .bold))
                    // Olive stays dark in both schemes, so white reads on it;
                    // `inkSurface` inverts, so its foreground has to as well.
                    .foregroundStyle(saved ? WellieTheme.onAccent : WellieTheme.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        saved ? WellieTheme.olive : WellieTheme.inkSurface,
                        in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(saving || saved)
        }
    }

    private func loadPhoto() async {
        guard post.hasPhoto, photo == nil, let backend = model.currentBackend else { return }
        guard let data = try? await backend.tablePhoto(postID: post.id, in: table.id) else { return }
        photo = UIImage(data: data)
    }
}

/// The share sheet. Two switches and a caption, and one of them is not offered.
///
/// The olives are absent by construction rather than defaulted off: there is no
/// control here that would make a score travel, because a score is a judgement
/// of somebody's week and handing that to a feed is the one thing this app will
/// not do. The line saying so is on the sheet, because a promise nobody can
/// read is not a promise.
struct ShareToTableSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let meal: MealEntry

    @State private var selected: TableSummary?
    @State private var caption = ""
    @State private var showsIngredients = true
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    tables
                    what
                    privacy
                    if let error {
                        Text(error)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.attention)
                    }
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share", action: share)
                        .font(WellieTheme.font(15, weight: .bold))
                        .disabled(selected == nil || working)
                }
            }
            .onAppear { selected = selected ?? model.loudestTable }
        }
        .wellieScreen()
    }

    private var tables: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.tables.enumerated()), id: \.element.id) { index, table in
                if index > 0 { WellieRowDivider() }
                Button { selected = table } label: {
                    HStack(spacing: 11) {
                        WellieAvatar(name: table.name, side: 26)
                        Text(table.name)
                            .font(WellieTheme.font(15, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                        Spacer(minLength: 8)
                        Image(systemName: selected?.id == table.id ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(selected?.id == table.id ? WellieTheme.blue : WellieTheme.outline)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .wellieListCard()
    }

    private var what: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let image = PhotoStore.shared.thumbnail(for: meal.photoHash, side: 52) {
                    WelliePhoto(image: image, inCard: true).frame(width: 52, height: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(MealDisplay.title(meal))
                        .font(WellieTheme.font(16, weight: .bold))
                    WellieMeta(DayTimeline.clock.string(from: Date(epochMillis: meal.eatenAt)))
                }
                Spacer(minLength: 0)
            }
            TextField("Say something about it", text: $caption, axis: .vertical)
                .font(WellieTheme.font(15, weight: .medium))
                .lineLimit(1...4)
                .padding(12)
                .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
        }
        .wellieCard()
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $showsIngredients) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show what's in it")
                        .font(WellieTheme.font(15.5, weight: .semibold))
                    WellieMeta("\(ingredientCount) ingredients, with weights")
                }
            }

            WellieRowDivider()

            HStack(spacing: 10) {
                OliveRow(olives: model.olives(for: meal).olives, size: 13)
                Spacer(minLength: 8)
                WellieMeta("Never shared")
            }
            WellieCaption(
                """
                Your olives stay yours. There is no switch for them — a score is about your \
                week, not about this plate, and it is not something to hand to a feed.
                """
            )
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private var ingredientCount: Int { meal.items.count }

    private func share() {
        guard let table = selected else { return }
        working = true
        Task {
            do {
                try await model.share(meal, to: table, caption: caption, showingIngredients: showsIngredients)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
