import ShamanCore
import SwiftUI

/// The app's four durable places, plus one action.
///
/// Logging is deliberately outside the tab capsule. It opens a task rather
/// than a destination, so treating it as a fifth tab would make selection and
/// back behavior dishonest. The separate `+` is also modality-neutral: the
/// sheet can take a photograph, words, or voice.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection = MainTab.today
    @State private var showingLog = false
    @State private var showingConsent = false
    @State private var openLogAfterConsent = false
    @State private var tabBarHidden = false

    var body: some View {
        ZStack {
            TodayView()
                .mainTabLayer(.today, selection: selection)

            NavigationStack {
                TablesListView(isTabRoot: true)
            }
            .mainTabLayer(.tables, selection: selection)

            NavigationStack {
                ProgressScreen(isTabRoot: true)
            }
            .mainTabLayer(.progress, selection: selection)

            SettingsView(isTabRoot: true)
                .mainTabLayer(.you, selection: selection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabBarHidden {
                FloatingTabBar(
                    selection: $selection,
                    unreadTables: model.totalUnread,
                    logMeal: beginLogging
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(WellieMotion.step(reduceMotion), value: tabBarHidden)
        .onPreferenceChange(MainTabBarHiddenPreferenceKey.self) {
            tabBarHidden = $0
        }
        .sheet(isPresented: $showingLog) { LogMealSheet() }
        .sheet(isPresented: $showingConsent, onDismiss: {
            guard openLogAfterConsent else { return }
            openLogAfterConsent = false
            showingLog = true
        }) {
            SendConsentView(includesPhoto: true) {
                model.acceptPhotoProcessing()
                openLogAfterConsent = true
                showingConsent = false
            } onCancel: {
                openLogAfterConsent = false
                showingConsent = false
            }
        }
        .wellieScreen()
    }

    /// Straight to the composer, consented or not.
    ///
    /// A wall in front of the first thing anyone does is a wall in front of
    /// finding out whether the app is any good, and on a fresh install it was
    /// worse than that: the gate lived at the point of *sending*, so a first
    /// meal got as far as "Reading your plate" and came back "Couldn't read
    /// that one. Agree before a meal is sent to be read." — an error about a
    /// policy, phrased as a failure to understand the food.
    ///
    /// The composer states what sending does and links to the detail, and
    /// sending is the agreement. Same disclosure, before the same action, minus
    /// the interruption.
    private func beginLogging() { showingLog = true }
}

private enum MainTab: String, CaseIterable, Hashable, Identifiable {
    case today
    case tables
    case progress
    case you

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .tables: "Tables"
        case .progress: "Progress"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .tables: "person.2"
        case .progress: "chart.bar.xaxis"
        case .you: "person.crop.circle"
        }
    }
}

private struct FloatingTabBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var selection: MainTab
    let unreadTables: Int
    let logMeal: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    regularLayout
                    stackedLayout
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var regularLayout: some View {
        HStack(spacing: 10) {
            tabCapsule
                // The four labels fit beside the action on every iPhone that
                // can run iOS 17. A genuinely narrower host uses the stacked
                // alternative below rather than truncating a destination.
                .frame(minWidth: 268)
            roundLogButton
        }
    }

    private var stackedLayout: some View {
        VStack(spacing: 8) {
            Button(action: logMeal) {
                Label("Log a meal", systemImage: "plus")
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background {
                        Capsule()
                            .fill(.ultraThinMaterial)
                        Capsule()
                            .fill(WellieTheme.accent.opacity(0.46))
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(FloatingTabButtonStyle())
            .accessibilityHint("Opens photo, text, and voice logging")

            accessibilityTabGrid
        }
    }

    private var tabCapsule: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(7)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
            Capsule()
                .fill(WellieTheme.raised.opacity(0.56))
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var accessibilityTabGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)],
            spacing: 0
        ) {
            ForEach(MainTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(7)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(WellieTheme.raised.opacity(0.56))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    private func tabButton(_ tab: MainTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 24, height: 23)

                    if tab == .tables, unreadTables > 0 {
                        Circle()
                            .fill(WellieTheme.protein)
                            .frame(width: 7, height: 7)
                            .offset(x: 5, y: -3)
                            .accessibilityHidden(true)
                    }
                }

                Text(tab.title)
                    .font(WellieTheme.font(11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selection == tab ? WellieTheme.ink : WellieTheme.body)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if selection == tab {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(Color.white.opacity(0.13))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .buttonStyle(FloatingTabButtonStyle())
        .accessibilityLabel(tab.title)
        .accessibilityValue(selection == tab ? "Selected" : "")
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    private var roundLogButton: some View {
        Button(action: logMeal) {
            Image(systemName: "plus")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                    Circle()
                        .fill(WellieTheme.accent.opacity(0.46))
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                }
        }
        .buttonStyle(FloatingTabButtonStyle())
        .accessibilityLabel("Log a meal")
        .accessibilityHint("Opens photo, text, and voice logging")
    }
}

private extension View {
    /// Keep every tab's navigation stack alive while exposing only the selected
    /// one. A `TabView` is not used because it still reserves its native bar on
    /// current iOS even when that bar is visually hidden.
    func mainTabLayer(_ tab: MainTab, selection: MainTab) -> some View {
        opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .zIndex(selection == tab ? 1 : 0)
    }
}

private struct FloatingTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MainTabBarHiddenPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Use on a pushed destination whose own bottom controls must take the
    /// safe area. Sheets already cover the tab shell and do not need it.
    func hidesMainTabBar() -> some View {
        preference(key: MainTabBarHiddenPreferenceKey.self, value: true)
    }
}
