import ShamanCore
import SwiftUI

/// One plate, opened like a gallery page. The only social actions are light
/// reactions; the only words are the author's editable note.
struct TableDishView: View {
    @Environment(AppModel.self) private var model

    let table: TableSummary
    let post: TablePost
    let react: (TableReaction, Bool) -> Void

    @State private var visiblePost: TablePost
    @State private var photo: UIImage?
    @State private var editingNote = false

    init(
        table: TableSummary,
        post: TablePost,
        react: @escaping (TableReaction, Bool) -> Void
    ) {
        self.table = table
        self.post = post
        self.react = react
        _visiblePost = State(initialValue: post)
    }

    var body: some View {
        ZStack(alignment: .top) {
            hero

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 286)

                    WellieMeta(byline)

                    Text(visiblePost.dishName ?? "A meal")
                        .font(WellieTheme.font(22, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 7)

                    if let caption = visiblePost.caption, !caption.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            Capsule()
                                .fill(WellieTheme.accent)
                                .frame(width: 2)
                            Text(caption)
                                .font(WellieTheme.font(15.5, weight: .medium))
                                .foregroundStyle(WellieTheme.body)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 16)
                    }

                    if !visiblePost.ingredientLine.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            WellieMeta("What's in it")
                            Text(visiblePost.ingredientLine)
                                .font(WellieTheme.font(13.5, weight: .medium))
                                .foregroundStyle(WellieTheme.body)
                                .lineSpacing(3)
                        }
                        .padding(.top, 18)
                    }

                    reactions
                        .padding(.top, 22)

                    if visiblePost.mine {
                        Button { editingNote = true } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "quote.opening")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(WellieTheme.accent)
                                    .frame(width: 30, height: 30)
                                    .background(WellieTheme.hairline, in: Circle())
                                Text(visiblePost.caption?.isEmpty == false
                                     ? "Your note — edit or remove any time"
                                     : "Add a one-line note")
                                    .font(WellieTheme.font(13, weight: .medium))
                                    .foregroundStyle(WellieTheme.muted)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text("Edit")
                                    .font(WellieTheme.font(12.5, weight: .semibold))
                                    .foregroundStyle(WellieTheme.accent)
                            }
                            .padding(16)
                            .background(WellieTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 22)
                    }

                    Text(privacyLine)
                        .font(WellieTheme.font(12.5, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                        .lineSpacing(3)
                        .padding(.top, 112)
                        .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $editingNote) {
            TableNoteEditor(note: visiblePost.caption ?? "") { note in
                let saved = try await model.updateTableNote(note, for: visiblePost, in: table)
                visiblePost = visiblePost.withCaption(saved)
            }
        }
        .task { await loadPhoto() }
        .wellieScreen()
    }

    private var hero: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                TablePhotoPlaceholder()
            }

            LinearGradient(
                stops: [
                    .init(color: WellieTheme.background.opacity(0.62), location: 0),
                    .init(color: .clear, location: 0.42),
                    .init(color: WellieTheme.background.opacity(0.96), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: 390)
        .clipped()
        .accessibilityHidden(true)
    }

    private var byline: String {
        let author = visiblePost.mine ? "You" : visiblePost.authorName
        return "\(author) · \(DayFormat.clock.string(from: Date(epochMillis: visiblePost.createdAt)))"
    }

    private var privacyLine: String {
        visiblePost.ingredientLine.isEmpty
            ? "The photo and this line are all they see. Numbers stay on your side."
            : "The photo, this line, and the listed food are all they see. Your calories, weight, goals, and rating stay on your side."
    }

    private var reactions: some View {
        HStack(spacing: 8) {
            ForEach(TableReaction.allCases, id: \.self) { kind in
                let state = visiblePost.reaction(kind)
                reactionChip(kind, state: state)
            }

            Menu {
                ForEach(TableReaction.allCases, id: \.self) { kind in
                    Button(reactionName(kind)) {
                        toggle(kind)
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WellieTheme.muted)
                    .frame(width: 44, height: 44)
                    .background(WellieTheme.surface, in: Circle())
                    .overlay { Circle().strokeBorder(WellieTheme.hairline, lineWidth: 1) }
            }

            Spacer(minLength: 0)
        }
    }

    private func reactionChip(_ kind: TableReaction, state: PostReactions?) -> some View {
        let selected = state?.mine == true
        return Button { toggle(kind) } label: {
            HStack(spacing: 7) {
                TableReactionGlyph(kind: kind, selected: selected)
                Text("\(state?.count ?? 0)")
                    .font(WellieTheme.font(12.5, weight: .bold))
                    .foregroundStyle(selected ? WellieTheme.accent : WellieTheme.muted)
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(WellieTheme.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(selected ? WellieTheme.accent : WellieTheme.hairline, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(reactionName(kind)), \(state?.count ?? 0)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggle(_ kind: TableReaction) {
        let on = !(visiblePost.reaction(kind)?.mine ?? false)
        visiblePost = visiblePost.reacted(kind, on: on)
        react(kind, on)
    }

    private func reactionName(_ kind: TableReaction) -> String {
        kind == .fire ? "Fire" : "Looks delicious"
    }

    private func loadPhoto() async {
        guard visiblePost.hasPhoto, photo == nil, let backend = model.currentBackend else { return }
        guard let data = try? await backend.tablePhoto(postID: visiblePost.id, in: table.id) else { return }
        photo = UIImage(data: data)
    }
}
private struct TableNoteEditor: View {
    @Environment(\.dismiss) private var dismiss

    let save: (String?) async throws -> Void

    @State private var note: String
    @State private var working = false
    @State private var error: String?

    init(note: String, save: @escaping (String?) async throws -> Void) {
        self.save = save
        _note = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                WellieMeta("One line, no replies")
                TextEditor(text: $note)
                    .font(WellieTheme.font(15.5, weight: .medium))
                    .foregroundStyle(WellieTheme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(minHeight: 130)
                    .background(WellieTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                    }
                Text("This note sits under the photo. It never starts a thread.")
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                if let error {
                    Text(error)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                }
                Spacer()
                if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Remove note", role: .destructive) { submit(nil) }
                        .font(WellieTheme.font(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(WellieTheme.screenInset)
            .background(WellieTheme.background)
            .navigationTitle("Your note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { submit(note) }
                        .font(WellieTheme.font(14, weight: .bold))
                        .disabled(working)
                }
            }
        }
        .wellieScreen()
    }

    private func submit(_ value: String?) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await save(value)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - Share a logged plate

struct ShareToTableSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let meal: MealEntry
    let preselectedTable: TableSummary?

    @State private var selected: TableSummary?
    @State private var caption = ""
    @State private var working = false
    @State private var error: String?

    init(meal: MealEntry, preselectedTable: TableSummary? = nil) {
        self.meal = meal
        self.preselectedTable = preselectedTable
        _selected = State(initialValue: preselectedTable)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    tableChoice
                    plate
                    privacy
                    if let error {
                        Text(error)
                            .font(WellieTheme.font(12.5, weight: .medium))
                            .foregroundStyle(WellieTheme.attention)
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(WellieTheme.background)
            .navigationTitle("Post plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Post to table", action: share)
                    .buttonStyle(WelliePrimaryButtonStyle(enabled: selected != nil && !working))
                    .disabled(selected == nil || working)
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.vertical, 10)
                    .background(WellieTheme.background)
            }
            .onAppear { selected = selected ?? model.loudestTable }
        }
        .wellieScreen()
    }

    @ViewBuilder
    private var tableChoice: some View {
        if let preselectedTable {
            HStack(spacing: 10) {
                WellieAvatar(name: preselectedTable.name, side: 32)
                Text(preselectedTable.name)
                    .font(WellieTheme.font(15, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer()
                WellieMeta("Invite-only")
            }
            .padding(15)
            .background(WellieTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.tables.enumerated()), id: \.element.id) { index, table in
                    if index > 0 { WellieRowDivider() }
                    Button { selected = table } label: {
                        HStack(spacing: 11) {
                            WellieAvatar(name: table.name, side: 28)
                            Text(table.name)
                                .font(WellieTheme.font(14.5, weight: .bold))
                                .foregroundStyle(WellieTheme.ink)
                            Spacer()
                            Image(systemName: selected?.id == table.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected?.id == table.id ? WellieTheme.accent : WellieTheme.outline)
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
            .background(WellieTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var plate: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                if let image = PhotoStore.shared.thumbnail(for: meal.photoHash, side: 58) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    TablePhotoPlaceholder()
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(MealDisplay.title(meal))
                        .font(WellieTheme.font(15.5, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                    Text(DayFormat.clock.string(from: Date(epochMillis: meal.eatenAt)))
                        .font(WellieTheme.font(12, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
            }

            TextField("Add a one-line note", text: $caption, axis: .vertical)
                .font(WellieTheme.font(14.5, weight: .medium))
                .lineLimit(1...3)
                .padding(13)
                .background(WellieTheme.well)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .background(WellieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(WellieTheme.hairline, lineWidth: 1)
        }
    }

    private var privacy: some View {
        Text(selected.map { model.tableVisibility(for: $0).nutrition } == true
             ? "This table also receives the foods and portions in the plate. Calories, weight, goals, and your meal rating stay on your side."
             : "The photo and this line are all they see. Calories, macros, weight, goals, and your meal rating stay on your side.")
            .font(WellieTheme.font(12.5, weight: .regular))
            .foregroundStyle(WellieTheme.muted)
            .lineSpacing(3)
            .padding(.horizontal, 4)
    }

    private func share() {
        guard let table = selected else { return }
        working = true
        Task {
            defer { working = false }
            do {
                try await model.share(
                    meal,
                    to: table,
                    caption: caption,
                    showingIngredients: model.tableVisibility(for: table).nutrition
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
