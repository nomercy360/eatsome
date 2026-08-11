import SwiftUI

/// Swipe-to-remove for a row that lives in a card rather than in a `List`.
///
/// The redesign puts meals inside rounded surface cards, which rules out
/// `List` and its free `swipeActions`. The gesture is still the right one —
/// removing a meal is a rare, reversible-by-relogging action that should not
/// cost a button on every row — so it is rebuilt here.
struct SwipeToRemove<Content: View>: View {
    let onTap: () -> Void
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
            .accessibilityHidden(!isOpen)

            content
                .offset(x: offset)
                // A real tap gesture fails as soon as the finger travels far
                // enough to become the horizontal drag below. A nested Button
                // can still commit its action after a simultaneous drag, which
                // is how a delete swipe used to open the meal instead.
                .onTapGesture(perform: handleTap)
                // Simultaneous, and it has to be all three of those words.
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
        .background(
            WellieTheme.surface,
            in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
        .accessibilityAction(named: "Remove") { onRemove() }
    }

    private func handleTap() {
        if isOpen {
            close()
        } else {
            onTap()
        }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.22)) {
            isOpen = false
            offset = 0
        }
    }
}
