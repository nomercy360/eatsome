import ShamanCore
import SwiftUI

/// A table is a gallery, not a conversation. Only plate shares are drawn;
/// legacy message rows remain readable by the API during rollout but never
/// become a second chat surface in the redesigned app.
struct TableFeedView: View {
    @Environment(AppModel.self) private var model

    let table: TableSummary

    @State private var posts: [TablePost] = []
    @State private var loadError: String?
    @State private var openPost: TablePost?
    @State private var showingPicker = false
    @State private var showingInvite = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if let loadError {
                    Text(loadError)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .padding(.horizontal, WellieTheme.screenInset)
                        .padding(.top, 18)
                }

                if groups.isEmpty && loadError == nil { empty }

                ForEach(groups) { group in
                    plateSection(group)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(WellieTheme.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingInvite = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WellieTheme.muted)
                        .wellieHitTarget()
                }
                .accessibilityLabel("Table options")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Post today's plate") { showingPicker = true }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 10)
                .background(WellieTheme.background)
        }
        .navigationDestination(item: $openPost) { post in
            TableDishView(
                table: table,
                post: post,
                react: { kind, on in react(post, kind, on) }
            )
        }
        .sheet(isPresented: $showingPicker, onDismiss: { Task { await load() } }) {
            TableMealPickerSheet(table: table)
        }
        .sheet(isPresented: $showingInvite) {
            NavigationStack {
                TableInviteView(table: table) { showingInvite = false }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showingInvite = false }
                        }
                    }
            }
            .wellieScreen()
        }
        .task { await load() }
        .refreshable { await load() }
        .wellieScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(table.name)
                .font(WellieTheme.font(29, weight: .black))
                .tracking(-0.8)
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TableMemberStack(members: table.members)
                Text("\(table.members.count) people · invite-only")
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            TablePhotoPlaceholder()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("No plates yet")
                .font(WellieTheme.font(17, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Text("The first plate sets the table.")
                .font(WellieTheme.font(13.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var groups: [PlateDay] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: posts.filter(\.isShare)) {
            calendar.startOfDay(for: Date(epochMillis: $0.createdAt))
        }
        return grouped
            .map { PlateDay(day: $0.key, posts: $0.value.sorted { $0.seq > $1.seq }) }
            .sorted { $0.day > $1.day }
    }

    private func plateSection(_ group: PlateDay) -> some View {
        let isToday = Calendar.current.isDateInToday(group.day)
        let count = isToday ? 2 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: count)

        return VStack(alignment: .leading, spacing: 13) {
            WellieMeta(dayLabel(group.day))
                .padding(.horizontal, 4)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(group.posts) { post in
                    Button { openPost = post } label: {
                        TablePlateCell(table: table, post: post, compact: !isToday)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.bottom, 22)
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return DayFormat.long(day)
    }

    private func load() async {
        guard let backend = model.currentBackend else { return }
        do {
            var loaded: [TablePost] = []
            var cursor: Int?
            var visitedCursors: Set<Int> = []
            while true {
                let response = try await backend.feed(
                    tableID: table.id,
                    cursor: cursor,
                    limit: 200
                )
                loaded.append(contentsOf: response.posts)
                guard let next = response.nextCursor,
                      next != cursor,
                      visitedCursors.insert(next).inserted
                else { break }
                cursor = next
            }
            posts = loaded.filter(\.isShare)
            loadError = nil
            if let newest = loaded.map(\.seq).max() {
                await model.markTableRead(table, upTo: newest)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func react(_ post: TablePost, _ kind: TableReaction, _ on: Bool) {
        apply(kind, on: on, to: post.id)
        Task {
            do {
                try await model.currentBackend?.react(
                    postID: post.id,
                    kind: kind,
                    on: on,
                    in: table.id
                )
            } catch {
                apply(kind, on: !on, to: post.id)
            }
        }
    }

    private func apply(_ kind: TableReaction, on: Bool, to postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        posts[index] = posts[index].reacted(kind, on: on)
        if openPost?.id == postID { openPost = posts[index] }
    }
}
private struct PlateDay: Identifiable {
    let day: Date
    let posts: [TablePost]
    var id: Date { day }
}

private struct TablePlateCell: View {
    let table: TableSummary
    let post: TablePost
    let compact: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TableRemotePhoto(tableID: table.id, postID: post.id, hasPhoto: post.hasPhoto)

            LinearGradient(
                colors: [.clear, WellieTheme.background.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text("\(post.mine ? "You" : post.authorName) · \(DayFormat.clock.string(from: Date(epochMillis: post.createdAt)))")
                .font(WellieTheme.font(compact ? 10 : 11.5, weight: .semibold))
                .foregroundStyle(post.hasPhoto ? Color.white : WellieTheme.muted)
                .lineLimit(1)
                .padding(11)

            if reactionCount > 0 {
                Text("\(reactionCount)")
                    .font(WellieTheme.font(10, weight: .bold))
                    .foregroundStyle(WellieTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(WellieTheme.background.opacity(0.82), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(9)
            }
        }
        .frame(height: compact ? 92 : 170)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: compact ? 18 : 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var reactionCount: Int { post.reactions.reduce(0) { $0 + $1.count } }

    private var accessibilityLabel: String {
        let author = post.mine ? "Your plate" : "Plate from \(post.authorName)"
        let title = post.dishName.map { ", \($0)" } ?? ""
        let reactions = reactionCount == 0 ? "" : ", \(reactionCount) reactions"
        return author + title + reactions
    }
}

private struct TableMealPickerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let table: TableSummary

    @State private var selectedMeal: MealEntry?
    @State private var logging = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if meals.isEmpty {
                        VStack(spacing: 10) {
                            Text("Nothing logged today yet.")
                                .font(WellieTheme.font(17, weight: .bold))
                            Text("Log a plate first, then it will be ready to post here.")
                                .font(WellieTheme.font(13.5, weight: .regular))
                                .foregroundStyle(WellieTheme.muted)
                                .multilineTextAlignment(.center)
                            Button("Log a plate") { logging = true }
                                .buttonStyle(WelliePrimaryButtonStyle())
                                .padding(.top, 12)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(meals.reversed()) { meal in
                            Button { selectedMeal = meal } label: {
                                HStack(spacing: 13) {
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
                                            .font(WellieTheme.font(15, weight: .bold))
                                            .foregroundStyle(WellieTheme.ink)
                                            .lineLimit(2)
                                        Text(DayFormat.clock.string(from: Date(epochMillis: meal.eatenAt)))
                                            .font(WellieTheme.font(12, weight: .medium))
                                            .foregroundStyle(WellieTheme.muted)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(WellieTheme.faint)
                                }
                                .padding(14)
                                .background(WellieTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 20)
            }
            .background(WellieTheme.background)
            .navigationTitle("Post today's plate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .sheet(item: $selectedMeal, onDismiss: { dismiss() }) { meal in
            ShareToTableSheet(meal: meal, preselectedTable: table)
        }
        .sheet(isPresented: $logging) { LogMealSheet() }
        .wellieScreen()
    }

    private var meals: [MealEntry] { model.mealsToday() }
}
