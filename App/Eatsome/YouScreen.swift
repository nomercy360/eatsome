import EatsomeCore
import SwiftUI

/// Who the app thinks is signed in, for the tile at the top of You. Nil is
/// "not signed in", which is a state the screen draws rather than hides.
struct YouAccount: Equatable {
    var name: String
    /// "Apple ID" — the provider, as a person would call it.
    var provider: String
}

/// Screen `13f`. You: your account, your numbers, your sources, your data.
///
/// Shorter than the settings screen it replaces. Reminders and Export are cut
/// and there is no delete-account row; what is left is one tile and three
/// cards, each of which answers a question a person actually opens this screen
/// with. Recognition is something the app does, not something you configure,
/// so there is no provider, no key and no counter here — the version row is
/// the way in for the person who needs those.
struct YouScreen: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(\.mainTabContentClearance) private var clearance

    /// Nil only before the gate has been passed, which this screen cannot be
    /// reached without — it is drawn that way so the tile has something honest
    /// to say if that ever stops being true.
    var account: YouAccount? = nil
    var onSignOut: (() -> Void)? = nil

    @State private var editing: NumbersSheet.Section?
    @State private var showingPrivacy = false

    var body: some View {
        VStack(spacing: 0) {
            titleRow
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    accountTile
                        .padding(.top, 8)
                    section("Your numbers") { numbersCard }
                        .padding(.top, 26)
                    section("Your data") { dataCard }
                        .padding(.top, 22)
                    footer
                        .padding(.top, 14)
                    Color.clear.frame(height: max(20, clearance))
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .sheet(item: $editing) { section in
            NumbersSheet(section: section)
                .environment(store)
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacySheet(fromNewerBuild: store.fromNewerBuild)
        }
        .wellieScreen()
    }

    private var titleRow: some View {
        Text("You")
            .font(WellieTheme.font(16, weight: .bold))
            .foregroundStyle(WellieTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 8)
    }

    // MARK: Account

    private var accountTile: some View {
        HStack(spacing: 14) {
            WellieAvatar(name: account?.name ?? "?", side: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(account?.name ?? "Not signed in")
                    .font(WellieTheme.font(16.5, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text(accountDetail)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Apple ID · logging since 5 Aug". The date is the first thing ever
    /// logged, which the log knows and no profile field has to be told.
    private var accountDetail: String {
        var parts: [String] = []
        if let account { parts.append(account.provider) }
        if let since = loggingSince {
            parts.append("logging since \(since.formatted(.dateTime.day().month(.abbreviated)))")
        } else {
            parts.append("nothing logged yet")
        }
        return parts.joined(separator: " · ")
    }

    /// The first thing ever written down.
    private var loggingSince: Date? {
        store.projection.meals.values.map { Date(epochMillis: $0.eatenAt) }.min()
    }

    // MARK: Cards

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WellieMeta(title, size: 11.5)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            content()
        }
    }

    /// Units sits here rather than under a "Sources" heading of its own. That
    /// card held Apple Health and Units, and with Health no longer read there is
    /// one source left, which is you — so the unit the figures are in belongs
    /// beside the figures.
    private var numbersCard: some View {
        card {
            row("Daily reference", value: dailyReference) { editing = .body }
            WellieRowDivider()
            row("Goal", value: store.profile.goal?.displayName ?? "Not set") { editing = .goal }
            WellieRowDivider()
            row("Body & activity", value: bodyLine) { editing = .body }
            WellieRowDivider()
            row("Units", value: units, chevron: false)
        }
    }

    /// "3,066 kcal · 127 g" — the two references Today measures against, and
    /// the reason the body fields exist. Nothing until the fields do: a
    /// reference invented for an imaginary person is the number the rest of
    /// the app is arranged against.
    private var dailyReference: String {
        guard let targets = store.dailyTargets else { return "Add your numbers" }
        return "\(EatsomeFormat.whole(targets.kcal)) kcal · \(EatsomeFormat.whole(targets.protein)) g"
    }

    private var bodyLine: String {
        let profile = store.profile
        var parts: [String] = []
        if let age = profile.ageYears { parts.append("\(age)") }
        if let height = profile.heightCentimeters { parts.append("\(EatsomeFormat.whole(height)) cm") }
        if let weight = profile.weightKilograms {
            parts.append("\(weight.formatted(.number.precision(.fractionLength(0...1)))) kg")
        }
        if let level = profile.activityLevel, parts.isEmpty { parts.append(level.displayName) }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    private var units: String {
        Locale.current.measurementSystem == .metric ? "Kilograms" : "Pounds"
    }

    private var dataCard: some View {
        card {
            row("Privacy", value: nil) { showingPrivacy = true }
            if account != nil, let onSignOut {
                WellieRowDivider()
                Button(action: onSignOut) {
                    Text("Sign out")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The version, and nothing behind it.
    ///
    /// It used to be a door: five taps opened the workshop, where the provider,
    /// the API key and the call counters lived. There is no workshop — the app
    /// asks Gemini through its own Worker and there is nothing here to
    /// configure — so this is a line of text again.
    private var footer: some View {
        Text("eatsome \(Self.version)")
            .font(WellieTheme.figure(11.5, weight: .regular))
            .foregroundStyle(WellieTheme.muted)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("eatsome version \(Self.version)")
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    // MARK: Pieces

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 18)
            .wellieSurface()
    }

    /// A row that opens something has a chevron and is a button; a row that
    /// only states something has neither, and is plain text rather than a
    /// disabled button — a disabled button dims, and "Not connected" is a
    /// fact, not an unavailable option.
    private func row(_ title: String, value: String?, chevron: Bool = true, action: @escaping () -> Void = {}) -> some View {
        let content = HStack(spacing: 8) {
            Text(title)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(EatsomeFormat.isFigure(value)
                        ? WellieTheme.figure(14, weight: .regular)
                        : WellieTheme.font(14, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WellieTheme.faint)
            }
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        return Group {
            if chevron {
                Button(action: action) { content }.buttonStyle(.plain)
            } else {
                content
            }
        }
    }
}

// MARK: - Privacy

/// What the app does with what it is told. Plain statements, each of which is
/// true by construction rather than by policy, and the one count worth
/// showing: records a newer build wrote that this one carries and cannot read.
private struct PrivacySheet: View {
    let fromNewerBuild: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Privacy")
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer()
                Button("Done") { dismiss() }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
            }
            .padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WellieProse("What you log is written to a file on this phone first, and mirrored to your account so a new phone can have it back. Nothing there is ever rewritten; a correction is a new line.")
                    WellieProse("A photograph is sent to the model once, to be read, and kept privately under your account so a reinstall can recover it. It is never shared.")
                    // Body only, and the distinction is the point. A blanket
                    // "Health is not read" would be false while the old shell's
                    // `AppModel` still bootstraps beside this one and fills in
                    // your height; what is true, and now true everywhere in the
                    // app, is that nothing about your day is read.
                    WellieProse("Apple Health is read, never written, and only about your body — your height, your weight, the energy you burn. Your workouts and your nights are not read at all.")
                    if fromNewerBuild > 0 {
                        WellieCaption(
                            "\(fromNewerBuild) \(fromNewerBuild == 1 ? "entry was" : "entries were") written by a newer version of eatsome. This version keeps them and shows nothing for them; update to see them."
                        )
                    }
                }
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .background(WellieTheme.background)
        .wellieScreen()
    }
}
