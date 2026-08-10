import ShamanCore
import SwiftUI

/// The road to your tables: one slim row under the day's header, and it never
/// costs more than one row.
///
/// With one table the row names it and shows the last thing said in it. With
/// several it reads "Tables · 4" with the combined unread, and tapping opens
/// the plain list (`10d`). Nothing else on the day page changes either way —
/// which is the constraint the whole social surface is built under: the day is
/// yours, and the friends live one tap off it.
///
/// Absent entirely when you are in no tables. A row saying "no tables yet" is
/// an advert on a screen about your lunch.
struct TablesRow: View {
    @Environment(AppModel.self) private var model

    let open: (TableSummary?) -> Void

    var body: some View {
        if let table = model.loudestTable {
            Button { open(model.tables.count == 1 ? table : nil) } label: {
                HStack(spacing: 10) {
                    avatars(of: table)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(table))
                            .font(WellieTheme.font(14, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .lineLimit(1)
                        if let preview = table.previewLine {
                            Text(preview)
                                .font(WellieTheme.font(12.5, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if model.totalUnread > 0 { badge }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(WellieTheme.background)
            .overlay(alignment: .bottom) {
                Rectangle().fill(WellieTheme.hairline).frame(height: 0.5)
            }
        }
    }

    private func title(_ table: TableSummary) -> String {
        model.tables.count == 1 ? table.name : "Tables · \(model.tables.count)"
    }

    /// Up to three square avatars, overlapped. Squares because `9d` says so,
    /// and because a row of circles reads as a contact list where these are
    /// the people whose food you are about to look at.
    private func avatars(of table: TableSummary) -> some View {
        let members = Array(table.members.prefix(3))
        return HStack(spacing: -6) {
            ForEach(members) { member in
                WellieAvatar(name: member.displayName, side: 22)
            }
        }
    }

    /// The count, with its age.
    ///
    /// Polling means the number is a snapshot; `asOf` says when it was taken.
    /// Below a couple of minutes it is close enough to now that saying so is
    /// noise, and past that the row admits it rather than implying live.
    private var badge: some View {
        HStack(spacing: 6) {
            if let age = staleness {
                WellieMeta(age)
            }
            Text("\(model.totalUnread)")
                .font(WellieTheme.metaFont(10))
                .foregroundStyle(WellieTheme.onAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WellieTheme.blue, in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous))
        }
    }

    private var staleness: String? {
        guard let asOf = model.tablesAsOf else { return nil }
        let minutes = Int((Date().epochMillis - asOf) / 60_000)
        guard minutes >= 2 else { return nil }
        return minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago"
    }
}

/// Screen `10d`. The plain list, reached only when there is more than one
/// table — ordered by unread, then by the last thing posted.
struct TablesListView: View {
    @Environment(AppModel.self) private var model

    @State private var joining = false
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, table in
                        if index > 0 { WellieRowDivider() }
                        NavigationLink { TableFeedView(table: table) } label: { row(table) }
                            .buttonStyle(.plain)
                    }
                }
                .wellieListCard()

                VStack(spacing: 0) {
                    Button { creating = true } label: {
                        action("New table", detail: "Invite by link", icon: "plus")
                    }
                    .buttonStyle(.plain)
                    WellieRowDivider()
                    Button { joining = true } label: {
                        action("Join with a code", detail: nil, icon: "arrow.right.to.line")
                    }
                    .buttonStyle(.plain)
                }
                .wellieListCard()

                if let asOf = model.tablesAsOf {
                    WellieMeta("Counted \(DayTimeline.clock.string(from: Date(epochMillis: asOf)))")
                        .frame(maxWidth: .infinity)
                }
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle("Tables")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshTables() }
        .sheet(isPresented: $creating) { TableSetupSheet(mode: .create) }
        .sheet(isPresented: $joining) { TableSetupSheet(mode: .join) }
        .wellieScreen()
    }

    private var ordered: [TableSummary] {
        model.tables.sorted {
            $0.unreadCount == $1.unreadCount
                ? ($0.latest?.createdAt ?? 0) > ($1.latest?.createdAt ?? 0)
                : $0.unreadCount > $1.unreadCount
        }
    }

    private func row(_ table: TableSummary) -> some View {
        HStack(spacing: 12) {
            WellieAvatar(name: table.name, side: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(table.name)
                    .font(WellieTheme.font(15.5, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                if let preview = table.previewLine {
                    Text(preview)
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let latest = table.latest {
                WellieMeta(DayTimeline.clock.string(from: Date(epochMillis: latest.createdAt)), size: 9)
            }
            if table.hasUnread {
                Text("\(table.unreadCount)")
                    .font(WellieTheme.metaFont(10))
                    .foregroundStyle(WellieTheme.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WellieTheme.blue, in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous))
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func action(_ title: String, detail: String?, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(WellieTheme.font(15, weight: .bold))
            Spacer(minLength: 8)
            if let detail { WellieMeta(detail) }
        }
        .foregroundStyle(WellieTheme.blue)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}

/// Making one, or joining one. Two fields at most, and the display name is
/// asked here because there is no profile to read it from — being per-table
/// means nobody has to build a profile system before six friends can share a
/// week of dinners.
struct TableSetupSheet: View {
    enum Mode { case create, join }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    @State private var name = ""
    @State private var code = ""
    @State private var displayName = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 12) {
                        if mode == .create {
                            field("Table name", text: $name, placeholder: "Sunday table")
                        } else {
                            field("Invite code", text: $code, placeholder: "ABCD234XYZ")
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                        WellieRowDivider()
                        field("What friends call you", text: $displayName, placeholder: "Anya")
                    }
                    .wellieCard()

                    WellieCaption(
                        mode == .create
                            ? "Anyone at the table can invite. Your olives never travel — what you share is a dish, a photo, and only the ingredients you switch on."
                            : "Codes are read out loud, so they carry no I, L, O, 0 or 1. Lower case is fine."
                    )

                    if let error {
                        Text(error)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.attention)
                    }
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle(mode == .create ? "New table" : "Join a table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(mode == .create ? "Create" : "Join", action: submit)
                        .font(WellieTheme.font(15, weight: .bold))
                        .disabled(!isReady || working)
                }
            }
        }
        .wellieScreen()
    }

    private var isReady: Bool {
        let named = !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return named && !(mode == .create ? name : code).trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            WellieMeta(label)
            TextField(placeholder, text: text)
                .font(WellieTheme.font(16, weight: .semibold))
        }
    }

    private func submit() {
        working = true
        Task {
            do {
                switch mode {
                case .create: try await model.createTable(named: name, as: displayName)
                case .join: try await model.joinTable(code: code, as: displayName)
                }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
