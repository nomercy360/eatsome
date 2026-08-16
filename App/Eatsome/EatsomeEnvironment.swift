import SwiftUI

/// Space the floating tab shell covers at the bottom of every place.
///
/// It lives here rather than beside the shell that publishes it because three
/// screens read it and only one writes it, and because the writer moved: this
/// key was declared in `App/Views/MainTabView.swift`, which is the old shell
/// and is going. A key declared in the thing being deleted is a compile error
/// waiting for the day the deletion happens.
private struct MainTabContentClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// The height obscured by the tab capsule, including the home indicator and
    /// the card-to-shell breathing room. A scrolling place ends with a spacer
    /// this tall so its last card is not under the glass.
    var mainTabContentClearance: CGFloat {
        get { self[MainTabContentClearanceKey.self] }
        set { self[MainTabContentClearanceKey.self] = newValue }
    }
}
