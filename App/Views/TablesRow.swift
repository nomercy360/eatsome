import CoreImage.CIFilterBuiltins
import ShamanCore
import SwiftUI
import UIKit

/// The quiet route from Today into the private plate groups.
struct TablesRow: View {
    @Environment(AppModel.self) private var model

    let open: (TableSummary?) -> Void

    var body: some View {
        Button { open(model.tables.count == 1 ? model.loudestTable : nil) } label: {
            HStack(spacing: 11) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tables.count > 1 ? "Tables · \(model.tables.count)" : model.loudestTable?.name ?? "Tables")
                        .font(WellieTheme.font(14, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .lineLimit(1)
                    Text(model.loudestTable?.previewLine ?? "Private groups, plates only")
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if model.totalUnread > 0 {
                    Text("\(model.totalUnread)")
                        .font(WellieTheme.metaFont(10))
                        .foregroundStyle(WellieTheme.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(WellieTheme.accent, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WellieTheme.faint)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tables list

struct TablesListView: View {
    @Environment(AppModel.self) private var model

    var isTabRoot = false

    @State private var creating = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Small groups of people you know. Plates only — no messages.")
                    .font(WellieTheme.font(14.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(4)
                    .padding(.bottom, 10)

                ForEach(ordered) { table in
                    NavigationLink {
                        TableFeedView(table: table)
                            .hidesMainTabBar()
                    } label: {
                        TableListCard(table: table)
                    }
                    .buttonStyle(.plain)
                }

                if ordered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(WellieTheme.faint)
                        Text("Your first table starts with a name and a link.")
                            .font(WellieTheme.font(14, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                }
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(WellieTheme.background)
        .navigationTitle("Tables")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New table") { creating = true }
                        .font(WellieTheme.font(14, weight: .semibold))
                        .foregroundStyle(WellieTheme.accent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !isTabRoot {
                Button("New table") { creating = true }
                    .buttonStyle(WelliePrimaryButtonStyle())
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.vertical, 10)
                    .background(WellieTheme.background)
            }
        }
        .refreshable { await model.refreshTables() }
        .sheet(isPresented: $creating) { TableCreateFlow() }
        .task { await model.refreshTables() }
        .wellieBackSwipe()
        .wellieScreen()
    }

    private var ordered: [TableSummary] {
        model.tables.sorted {
            ($0.latest?.createdAt ?? 0) > ($1.latest?.createdAt ?? 0)
        }
    }
}

private struct TableListCard: View {
    let table: TableSummary

    private var plates: [TablePlatePreview] { table.recentPlates ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            if !plates.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(plates.prefix(3))) { plate in
                        TableRemotePhoto(
                            tableID: table.id,
                            postID: plate.id,
                            hasPhoto: plate.hasPhoto
                        )
                        .frame(maxWidth: .infinity)
                    }
                    ForEach(plates.count..<3, id: \.self) { _ in
                        TablePhotoPlaceholder().frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 110)
            }

            HStack(spacing: 14) {
                if plates.isEmpty {
                    WellieAvatar(name: table.name, side: 52)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(table.name)
                            .font(WellieTheme.font(17, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(table.members.count) people")
                            .font(WellieTheme.font(12.5, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    Text(detail)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .lineLimit(1)
                }
                if plates.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }
            }
            .padding(17)
        }
        .background(WellieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(WellieTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let latest = table.latest else { return "No plates yet" }
        let count = table.platesToday ?? table.cookedToday ?? 0
        let plateLine = count == 0 ? "Quiet today" : "\(count) plate\(count == 1 ? "" : "s") today"
        return "\(plateLine) · \(latest.authorName) posted \(relative(latest.createdAt))"
    }

    private func relative(_ millis: EpochMillis) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(Date(epochMillis: millis))))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60) min ago" }
        if seconds < 86_400 { return "\(seconds / 3_600) hr ago" }
        return "\(seconds / 86_400)d ago"
    }
}

// MARK: - Create and invite

private struct TableCreateFlow: View {
    @Environment(\.dismiss) private var dismiss

    @State private var createdTable: TableSummary?

    var body: some View {
        NavigationStack {
            TableCreateView { createdTable = $0 }
                .navigationDestination(item: $createdTable) { table in
                    TableInviteView(table: table) { dismiss() }
                }
        }
        .wellieScreen()
    }
}

private struct TableCreateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let created: (TableSummary) -> Void

    @State private var name = ""
    @State private var showsPhotos = true
    @State private var showsNutrition = false
    @State private var working = false
    @State private var error: String?

    private let suggestions = ["Family", "Gym crew", "Office lunch"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                WellieMeta("Name it")
                    .padding(.horizontal, 4)

                TextField("Flat dinners", text: $name)
                    .font(WellieTheme.font(18, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .background(WellieTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(WellieTheme.accent, lineWidth: 1.5)
                    }
                    .padding(.top, 14)

                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { name = suggestion }
                            .font(WellieTheme.font(12.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .frame(minHeight: 44)
                            .background(WellieTheme.surface, in: Capsule())
                            .overlay { Capsule().strokeBorder(WellieTheme.hairline, lineWidth: 1) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)

                WellieMeta("What they see")
                    .padding(.horizontal, 4)
                    .padding(.top, 32)

                VStack(spacing: 0) {
                    visibilityToggle("Photos of what you post", isOn: $showsPhotos)
                    WellieRowDivider()
                    visibilityToggle("What's in it and portions", isOn: $showsNutrition)
                    WellieRowDivider()
                    privateVisibilityRow("Your weight and goals")
                }
                .padding(.horizontal, 18)
                .background(WellieTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                }
                .padding(.top, 14)

                Text("Numbers stay private by default. You post a plate, not a report.")
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(3)
                    .padding(.horizontal, 4)
                    .padding(.top, 14)

                if let error {
                    Text(error)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(WellieTheme.background)
        .navigationTitle("New table")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(WellieTheme.font(14, weight: .semibold))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Create and invite", action: submit)
                .buttonStyle(WelliePrimaryButtonStyle(enabled: isReady && !working))
                .disabled(!isReady || working)
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 10)
                .background(WellieTheme.background)
        }
    }

    private var isReady: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func visibilityToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(WellieTheme.font(14.5, weight: .medium))
                .foregroundStyle(isOn.wrappedValue ? WellieTheme.ink : WellieTheme.muted)
        }
        .tint(WellieTheme.accent)
        .padding(.vertical, 13)
    }

    private func submit() {
        guard isReady else { return }
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                let table = try await model.createTable(
                    named: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    visibility: TableVisibility(
                        photos: showsPhotos,
                        nutrition: showsNutrition,
                        bodyAndGoals: false
                    )
                )
                created(table)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func privateVisibilityRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(WellieTheme.font(14.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
            Spacer()
            Label("Private", systemImage: "lock.fill")
                .font(WellieTheme.font(11, weight: .semibold))
                .foregroundStyle(WellieTheme.faint)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), always private")
    }
}

struct TableInviteView: View {
    @Environment(AppModel.self) private var model

    let table: TableSummary
    let onDone: () -> Void

    @State private var copied = false
    @State private var inviteCode: String
    @State private var inviteExpiresAt: EpochMillis?
    @State private var inviteError: String?

    init(table: TableSummary, onDone: @escaping () -> Void) {
        self.table = table
        self.onDone = onDone
        _inviteCode = State(initialValue: table.inviteCode)
        _inviteExpiresAt = State(initialValue: table.inviteExpiresAt)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Send the link.\nThat's the whole thing.")
                    .font(WellieTheme.font(25, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No usernames, no search. Nobody finds you — you invite them.")
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(4)
                    .padding(.top, 10)

                HStack(spacing: 12) {
                    Text(inviteURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                        .font(WellieTheme.font(13.5, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.url = inviteURL
                        copied = true
                    }
                    .font(WellieTheme.font(12.5, weight: .bold))
                    .foregroundStyle(WellieTheme.onAccent)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .background(WellieTheme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(17)
                .background(WellieTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                }
                .padding(.top, 24)

                HStack(spacing: 10) {
                    inviteButton("Messages") { openMessages() }
                    inviteButton("WhatsApp") { openWhatsApp() }
                    ShareLink(item: inviteURL) { Text("More") }
                        .buttonStyle(TableInviteButtonStyle())
                }
                .padding(.top, 10)

                HStack(spacing: 12) {
                    Rectangle().fill(WellieTheme.hairline).frame(height: 1)
                    WellieMeta("Or in person")
                    Rectangle().fill(WellieTheme.hairline).frame(height: 1)
                }
                .padding(.horizontal, 4)
                .padding(.top, 26)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .padding(22)
                        .background(WellieTheme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                        .accessibilityLabel("QR code for the invite link")
                }

                Text(expiryLine)
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                if let inviteError {
                    Text(inviteError)
                        .font(WellieTheme.font(12, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 28)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(WellieTheme.background)
        .navigationTitle("Invite to \(table.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await renewIfExpired() }
        .safeAreaInset(edge: .bottom) {
            Button("Skip — invite later", action: onDone)
                .buttonStyle(WellieSecondaryButtonStyle())
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 10)
                .background(WellieTheme.background)
        }
    }

    private var expiryLine: String {
        "Let them point a camera at this. Link expires in 24 hours."
    }

    private var inviteURL: URL {
        URL(string: "eatsome://table/\(inviteCode.lowercased())")!
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(inviteURL.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else {
            return nil
        }
        let context = CIContext()
        guard let image = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }

    private func inviteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(TableInviteButtonStyle())
    }

    private func openMessages() {
        var components = URLComponents()
        components.scheme = "sms"
        components.queryItems = [URLQueryItem(name: "body", value: inviteURL.absoluteString)]
        if let url = components.url { UIApplication.shared.open(url) }
    }

    private func openWhatsApp() {
        var components = URLComponents(string: "https://wa.me/")
        components?.queryItems = [URLQueryItem(name: "text", value: inviteURL.absoluteString)]
        if let url = components?.url { UIApplication.shared.open(url) }
    }

    private func renewIfExpired() async {
        guard let inviteExpiresAt, inviteExpiresAt <= Date().epochMillis else { return }
        guard let backend = model.currentBackend else { return }
        do {
            let renewed = try await backend.rotateTableInvite(tableID: table.id)
            inviteCode = renewed.inviteCode
            self.inviteExpiresAt = renewed.inviteExpiresAt ?? Date().epochMillis + 86_400_000
            inviteError = nil
        } catch {
            inviteError = "Could not renew this invite yet."
        }
    }
}

/// The receiving end of an invite link. Confirmation is deliberate: a QR code
/// or link can bring the app here, but cannot silently add an account to a
/// private group.
struct TableInviteJoinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let inviteCode: String

    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Join this table?")
                    .font(WellieTheme.font(27, weight: .bold))
                    .tracking(-0.7)
                    .foregroundStyle(WellieTheme.ink)

                Text("Tables are invite-only. Joining lets the group see only the plates and details you choose to post.")
                    .font(WellieTheme.font(14, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(4)

                HStack {
                    WellieMeta("Invite code")
                    Spacer()
                    Text(inviteCode)
                        .font(WellieTheme.font(15, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(WellieTheme.ink)
                }
                .padding(17)
                .background(WellieTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                }

                if let error {
                    Text(error)
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                }

                Spacer()

                Button("Join table", action: join)
                    .buttonStyle(WelliePrimaryButtonStyle(enabled: !working))
                    .disabled(working)
            }
            .padding(WellieTheme.screenInset)
            .background(WellieTheme.background)
            .navigationTitle("Table invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") {
                        model.clearPendingTableInvite()
                        dismiss()
                    }
                }
            }
        }
        .wellieScreen()
    }

    private func join() {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await model.joinTable(code: inviteCode, as: "You")
                model.clearPendingTableInvite()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct TableInviteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(12.5, weight: .semibold))
            .foregroundStyle(WellieTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(WellieTheme.surface.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }
}
