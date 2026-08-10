import ShamanCore
import SwiftUI

/// Screen `9a`. The table as a gallery feed.
///
/// Photos run edge to edge, posts separate with hairlines rather than cards,
/// and reactions are quiet text buttons. The composer stays: this is still a
/// place you talk, not only a place you scroll.
///
/// One dark object per exchange, which is the rule the whole screen rests on —
/// your own sent messages are ink, and everything else (avatars, captions,
/// photo posts) stays light. Twenty messages in a day then read as a gallery
/// rather than a wall.
struct TableFeedView: View {
    @Environment(AppModel.self) private var model

    let table: TableSummary

    @State private var posts: [TablePost] = []
    @State private var asOf: EpochMillis?
    @State private var draft = ""
    @State private var replyTo: TablePost?
    @State private var loadError: String?
    @State private var openPost: TablePost?
    @FocusState private var isTyping: Bool

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header
                ForEach(posts) { post in
                    TablePostRow(
                        table: table,
                        post: post,
                        reply: { replyTo = post; isTyping = true },
                        open: { if post.isShare { openPost = post } },
                        react: { kind, on in react(post, kind, on) }
                    )
                    Rectangle().fill(WellieTheme.hairline).frame(height: 0.5)
                }
                if posts.isEmpty { empty }
            }
        }
        .background(WellieTheme.background)
        .navigationTitle(table.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .navigationDestination(item: $openPost) { post in
            TableDishView(table: table, post: post, react: { kind, on in react(post, kind, on) })
        }
        .task { await load() }
        .refreshable { await load() }
        .wellieScreen()
    }

    // MARK: - Who is here

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: -6) {
                ForEach(table.members) { member in
                    WellieAvatar(name: member.displayName, side: 26)
                }
                Spacer(minLength: 10)
            }
            HStack(spacing: 8) {
                WellieMeta(membersLine)
                Spacer(minLength: 0)
                if let asOf, staleness(asOf) != nil {
                    WellieMeta(staleness(asOf)!)
                }
            }
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WellieTheme.hairline).frame(height: 0.5)
        }
    }

    /// "6 friends · 3 cooked today". `cookedToday` is nil when this client did
    /// not tell the server where its day starts, and nil is not zero — a table
    /// where nobody cooked and a table whose day boundary is unknown are
    /// different facts and must not read the same.
    private var membersLine: String {
        let people = "\(table.members.count) friend\(table.members.count == 1 ? "" : "s")"
        guard let cooked = table.cookedToday else { return people }
        return "\(people) · \(cooked) cooked today"
    }

    private func staleness(_ asOf: EpochMillis) -> String? {
        let minutes = Int((Date().epochMillis - asOf) / 60_000)
        guard minutes >= 2 else { return nil }
        return minutes < 60 ? "as of \(minutes)m ago" : "as of \(minutes / 60)h ago"
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(WellieTheme.font(17, weight: .bold))
            WellieProse("Share a meal from your day, or just say something.", size: 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
        .multilineTextAlignment(.center)
    }

    // MARK: - Talking

    private var composer: some View {
        VStack(spacing: 0) {
            if let replyTo {
                HStack(spacing: 8) {
                    WellieMeta("Replying to \(replyTo.authorName)")
                    Spacer(minLength: 8)
                    Button { self.replyTo = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WellieTheme.muted)
                            .wellieHitTarget()
                    }
                    .accessibilityLabel("Stop replying")
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 7)
            }
            HStack(spacing: 10) {
                TextField("Message \(table.name)", text: $draft, axis: .vertical)
                    .font(WellieTheme.font(15.5, weight: .medium))
                    .focused($isTyping)
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                            .strokeBorder(WellieTheme.outline, lineWidth: 1)
                    }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WellieTheme.onInk)
                        .frame(width: 34, height: 34)
                        .background(
                            canSend ? WellieTheme.inkSurface : WellieTheme.faint,
                            in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
                        )
                        .wellieHitTarget()
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let parent = replyTo?.id
        draft = ""
        replyTo = nil
        Task {
            try? await model.currentBackend?.post(
                .message(id: UUIDv7.generate().uuidString, text: text, replyToPostId: parent),
                to: table.id
            )
            await load()
        }
    }

    // MARK: - Reading

    private func load() async {
        guard let backend = model.currentBackend else { return }
        do {
            let response = try await backend.feed(tableID: table.id)
            posts = response.posts
            asOf = response.asOf
            loadError = nil
            // Read up to what was actually rendered, never to `latestSeq` —
            // marking a page read that the person has not seen is how a badge
            // becomes a lie in the other direction.
            if let top = response.posts.map(\.seq).max() {
                await model.markTableRead(table, upTo: top)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Optimistic, because the toggle is idempotent both ways on the server —
    /// a double tap is one state rather than an error, so drawing it before the
    /// call returns can only ever be early, never wrong.
    ///
    /// And it stays local. This used to refetch the whole paged feed after every
    /// heart, which bought nothing the optimistic draw had not already shown and
    /// cost a round trip per tap on the one interaction people do fastest.
    private func react(_ post: TablePost, _ kind: TableReaction, _ on: Bool) {
        apply(kind, on: on, to: post.id)
        Task {
            do {
                try await model.currentBackend?.react(
                    postID: post.id, kind: kind, on: on, in: table.id
                )
            } catch {
                // Put it back. A reaction that silently fails leaves the person
                // believing they said something they did not.
                apply(kind, on: !on, to: post.id)
            }
        }
    }

    private func apply(_ kind: TableReaction, on: Bool, to postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index] = posts[index].reacted(kind, on: on)
    }
}

// MARK: - One post

private struct TablePostRow: View {
    @Environment(AppModel.self) private var model

    let table: TableSummary
    let post: TablePost
    let reply: () -> Void
    let open: () -> Void
    let react: (TableReaction, Bool) -> Void

    @State private var photo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                WellieAvatar(name: post.authorName, side: 24)
                Text(post.authorName)
                    .font(WellieTheme.font(13.5, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                WellieMeta(DayTimeline.clock.string(from: Date(epochMillis: post.createdAt)), size: 9)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 14)

            if post.isShare {
                share
            } else {
                message
            }

            reactions
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 12)
        }
        .task { await loadPhoto() }
    }

    // MARK: - A shared meal

    @ViewBuilder
    private var share: some View {
        if let caption = post.caption, !caption.isEmpty {
            Text(caption)
                .font(WellieTheme.font(15.5, weight: .medium))
                .foregroundStyle(WellieTheme.body)
                .padding(.horizontal, WellieTheme.screenInset)
        }

        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                if let photo {
                    // Full-bleed, no radius. `9d`: a photo inside a card squares
                    // to 8, a photo in the feed runs to the edge of the screen.
                    WelliePhoto(image: photo, height: 260)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.dishName ?? "A meal")
                        .font(WellieTheme.font(17, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .multilineTextAlignment(.leading)
                    if post.ingredients != nil {
                        WellieMeta("What's in it · \(post.ingredientLine)")
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Words

    @ViewBuilder
    private var message: some View {
        if let text = post.text {
            Text(text)
                .font(WellieTheme.font(15.5, weight: post.mine ? .medium : .regular))
                .foregroundStyle(post.mine ? WellieTheme.onInk : WellieTheme.ink)
                .padding(.horizontal, post.mine ? 13 : 0)
                .padding(.vertical, post.mine ? 9 : 0)
                .background {
                    // Ink, and only for what you sent. One dark object per
                    // exchange is what keeps a busy table readable.
                    if post.mine {
                        RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                            .fill(WellieTheme.inkSurface)
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Quiet buttons

    private var reactions: some View {
        HStack(spacing: 16) {
            ForEach(TableReaction.allCases, id: \.self) { kind in
                let state = post.reaction(kind)
                Button { react(kind, !(state?.mine ?? false)) } label: {
                    HStack(spacing: 5) {
                        icon(kind, filled: state?.mine ?? false)
                        if let count = state?.count, count > 0 {
                            Text("\(count)")
                                .font(WellieTheme.metaFont(10))
                                .foregroundStyle(WellieTheme.muted)
                        }
                    }
                    .wellieHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(reactionLabel(kind, state))
                .accessibilityAddTraits(state?.mine == true ? [.isSelected] : [])
            }

            Button("Reply", action: reply)
                .font(WellieTheme.font(12.5, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)

            Spacer(minLength: 0)
        }
    }

    /// What VoiceOver says for a reaction, count included.
    ///
    /// The count is part of the label rather than a separate element, because
    /// a screen reader reaching "olive, button" and then "4" as unrelated text
    /// has to be pieced back together by the listener.
    private func reactionLabel(_ kind: TableReaction, _ state: PostReactions?) -> String {
        let name = kind == .olive ? "Olive" : "Heart"
        let count = state?.count ?? 0
        let mine = state?.mine == true
        switch (count, mine) {
        case (0, _): return "\(name), none yet"
        case (1, true): return "\(name), just you"
        case (_, true): return "\(name), you and \(count - 1) more"
        default: return "\(name), \(count)"
        }
    }

    @ViewBuilder
    private func icon(_ kind: TableReaction, filled: Bool) -> some View {
        switch kind {
        case .olive:
            OliveMark()
                .frame(width: 13, height: 13)
                .opacity(filled ? 1 : 0.3)
        case .heart:
            Image(systemName: filled ? "heart.fill" : "heart")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? WellieTheme.heart : WellieTheme.muted)
        }
    }

    /// Asked for only when the post says there is one — `hasPhoto` exists so a
    /// text meal does not cost a round trip per row.
    private func loadPhoto() async {
        guard post.hasPhoto, photo == nil, let backend = model.currentBackend else { return }
        guard let data = try? await backend.tablePhoto(postID: post.id, in: table.id) else { return }
        photo = UIImage(data: data)
    }
}
