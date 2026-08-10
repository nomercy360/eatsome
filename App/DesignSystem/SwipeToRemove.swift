import SwiftUI

/// Swipe-to-remove for a row that lives in a card rather than in a `List`.
///
/// The redesign puts meals and dishes inside white 28pt cards, which rules out
/// `List` and its free `swipeActions`. The gesture is still the right one —
/// removing a meal is a rare, reversible-by-relogging action that should not
/// cost a button on every row — so it is rebuilt here.
///
/// Deliberately a plain `.gesture`, not a high-priority one: the vertical
/// scroll must always win, because scrolling past a list is what you do a
/// hundred times more often than deleting from it.
struct SwipeToRemove<Content: View>: View {
    let onRemove: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    /// Decided once, on the first movement of a drag, and held until it ends.
    /// Judging direction on every update lets a diagonal drag flicker between
    /// scrolling and swiping; a finger that started downward stays scrolling.
    @State private var isHorizontal: Bool?

    private let width: CGFloat = 92

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                close()
                onRemove()
            } label: {
                Text("Remove")
                    .font(WellieTheme.font(14, weight: .bold))
                    .foregroundStyle(WellieTheme.onAccent)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(WellieTheme.danger, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            content
                .background(WellieTheme.surface)
                .offset(x: offset)
                // Simultaneous, and it has to be all three of those words.
                //
                // A plain `.gesture` loses outright: the row wraps a
                // NavigationLink, whose press handling claims the touch and
                // cancels the drag before it starts, which is why swiping did
                // nothing at all. `.highPriorityGesture` fixes that and breaks
                // something worse — it takes the touch ahead of the enclosing
                // ScrollView, so every drag beginning on a meal row is swallowed
                // and the whole of Today stops scrolling. Refusing to move the
                // row is not the same as declining the gesture.
                //
                // Simultaneous lets the scroll view keep its pan while this
                // watches the same finger, and the axis latch below is what
                // decides which of them is being asked for.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            if isHorizontal == nil {
                                isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                            }
                            guard isHorizontal == true else { return }
                            let base = isOpen ? -width : 0
                            offset = min(0, max(-width - 20, base + value.translation.width))
                        }
                        .onEnded { _ in
                            let wasHorizontal = isHorizontal == true
                            isHorizontal = nil
                            guard wasHorizontal else { return }
                            withAnimation(.snappy(duration: 0.22)) {
                                isOpen = offset < -width / 2
                                offset = isOpen ? -width : 0
                            }
                        }
                )
        }
        .accessibilityAction(named: "Remove") { onRemove() }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.22)) {
            isOpen = false
            offset = 0
        }
    }
}
