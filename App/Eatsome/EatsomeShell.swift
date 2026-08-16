import EatsomeCore
import SwiftUI

/// The app's three durable places, plus one action.
///
/// Three, not four. Tables — the many-person feed — is cut, and with it the
/// question of whether a two-person share should have been a table of two. What
/// is left are the three things a person navigates *to*: the day, the trend,
/// and themselves.
///
/// Logging stays outside the capsule. It opens a task rather than a
/// destination, so treating it as a fourth tab would make selection and back
/// behaviour dishonest. The separate `+` is also modality-neutral: the composer
/// takes a photograph, words, or both, and one field carries the words either
/// way.
struct EatsomeShell: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(EatsomeAccount.self) private var account
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection = Place.today
    @State private var barHeight: CGFloat = 0
    @State private var logging = false
    @State private var confirmingSignOut = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TodayScreen()
                    .layer(.today, selection: selection)

                ProgressScreen(backToToday: { selection = .today })
                    .layer(.progress, selection: selection)

                YouScreen(
                    account: account.isSignedIn
                        ? YouAccount(name: "Your account", provider: "Apple ID")
                        : nil,
                    onSignOut: { confirmingSignOut = true }
                )
                .layer(.you, selection: selection)
            }
            .environment(
                \.mainTabContentClearance,
                barHeight + geometry.safeAreaInsets.bottom + WellieTheme.cardSpacing
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabBar(selection: $selection, log: { logging = true })
                    .background {
                        GeometryReader { bar in
                            Color.clear.preference(
                                key: BarHeightKey.self,
                                value: bar.size.height
                            )
                        }
                    }
            }
        }
        .onPreferenceChange(BarHeightKey.self) { if $0 > 0 { barHeight = $0 } }
        // Full screen rather than a sheet: the composer becomes a reading and
        // then a whole meal to confirm, and a detent that had to grow three
        // times would be arguing with the keyboard the entire way.
        .fullScreenCover(isPresented: $logging) {
            LogComposer()
        }
        .confirmationDialog(
            "Sign out on this phone?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                // The store's, not the account's: it pushes anything still
                // behind the watermark before the session is revoked, which is
                // the last moment that is possible.
                Task { await store.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your meals stay on this phone. The app stays locked until you sign in with Apple again.")
        }
        .wellieScreen()
    }
}

private enum Place: String, CaseIterable, Hashable, Identifiable {
    case today, progress, you

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .progress: "Progress"
        case .you: "You"
        }
    }

    /// The mock drew three plain shapes — a square, a bar chart, a circle —
    /// and on the phone a square and a circle read as two radio buttons rather
    /// than two places. So: pictograms, one per place, outlined at rest and
    /// filled when selected (`symbolVariant` in `TabBar`). A day for Today, a
    /// chart for Progress, a person for You.
    var symbol: String {
        switch self {
        case .today: "calendar"
        case .progress: "chart.bar"
        case .you: "person"
        }
    }
}

private struct TabBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var selection: Place
    let log: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        ForEach(Place.allCases) { place in
                            labelledButton(place)
                        }
                    }
                    .padding(7)
                    .background(WellieTheme.navigationSurface, in: Capsule())
                    logButton(wide: true)
                }
            } else {
                HStack(spacing: 26) {
                    iconButton(.today)
                    iconButton(.progress)
                    logButton(wide: false)
                    iconButton(.you)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(WellieTheme.navigationSurface, in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func iconButton(_ place: Place) -> some View {
        Button { selection = place } label: {
            Image(systemName: place.symbol)
                .symbolVariant(selection == place ? .fill : .none)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    WellieTheme.onNavigation.opacity(selection == place ? 1 : 0.45)
                )
                .frame(width: 22, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(place.title)
        .accessibilityValue(selection == place ? "Selected" : "")
        .accessibilityAddTraits(selection == place ? .isSelected : [])
    }

    private func labelledButton(_ place: Place) -> some View {
        Button { selection = place } label: {
            Label(place.title, systemImage: place.symbol)
                .symbolVariant(selection == place ? .fill : .none)
                .font(WellieTheme.font(13, weight: .semibold))
                .foregroundStyle(
                    WellieTheme.onNavigation.opacity(selection == place ? 1 : 0.62)
                )
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(PressStyle())
        .accessibilityValue(selection == place ? "Selected" : "")
        .accessibilityAddTraits(selection == place ? .isSelected : [])
    }

    @ViewBuilder
    private func logButton(wide: Bool) -> some View {
        Button(action: log) {
            Group {
                if wide {
                    Label("Log", systemImage: "plus")
                        .font(WellieTheme.font(16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(WellieTheme.onAccent)
            .background(WellieTheme.accent, in: wide ? AnyShape(Capsule()) : AnyShape(Circle()))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Log a meal")
        .accessibilityHint("Opens photo and text logging")
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension View {
    /// Keep every place alive while exposing only the selected one. A `TabView`
    /// is not used because it still reserves its native bar on current iOS even
    /// when that bar is visually hidden.
    func layer(_ place: Place, selection: Place) -> some View {
        opacity(selection == place ? 1 : 0)
            .allowsHitTesting(selection == place)
            .accessibilityHidden(selection != place)
            .zIndex(selection == place ? 1 : 0)
    }
}

private struct BarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
