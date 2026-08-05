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
                    .background(WellieTheme.danger, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(offset < -8 ? 1 : 0)

            content
                .background(WellieTheme.surface)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            let base = isOpen ? -width : 0
                            offset = min(0, max(-width - 20, base + value.translation.width))
                        }
                        .onEnded { _ in
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
