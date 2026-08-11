import ShamanCore
import SwiftUI

/// A membership-gated table photo. The placeholder is part of the design, not
/// an error state: text-only plates and photos still in flight occupy the same
/// stable grid geometry, so the feed never jumps as images arrive.
struct TableRemotePhoto: View {
    @Environment(AppModel.self) private var model

    let tableID: String
    let postID: String
    let hasPhoto: Bool

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            TablePhotoPlaceholder()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: postID) { await load() }
        .accessibilityHidden(true)
    }

    private func load() async {
        guard hasPhoto, image == nil, let backend = model.currentBackend else { return }
        guard let data = try? await backend.tablePhoto(postID: postID, in: tableID) else { return }
        image = UIImage(data: data)
    }
}
struct TablePhotoPlaceholder: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(WellieTheme.surface))
            var stripes = Path()
            let stride: CGFloat = 22
            var x = -size.height
            while x < size.width {
                stripes.move(to: CGPoint(x: x, y: size.height))
                stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += stride
            }
            context.stroke(stripes, with: .color(WellieTheme.well), lineWidth: 8)
        }
    }
}

struct TableMemberStack: View {
    let members: [TableMember]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(members.prefix(4))) { member in
                Circle()
                    .fill(WellieTheme.raised)
                    .frame(width: 30, height: 30)
                    .overlay {
                        Text(member.isMe ? "You" : member.initial)
                            .font(WellieTheme.font(member.isMe ? 9 : 11, weight: .bold))
                            .foregroundStyle(WellieTheme.muted)
                            .minimumScaleFactor(0.7)
                    }
                    .overlay { Circle().strokeBorder(WellieTheme.background, lineWidth: 2) }
                    .accessibilityLabel(member.isMe ? "You" : member.displayName)
            }
        }
    }
}

struct TableReactionGlyph: View {
    let kind: TableReaction
    var selected = false

    var body: some View {
        Image(systemName: kind == .fire ? "flame.fill" : "fish.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(selected ? WellieTheme.accent : WellieTheme.body)
            .accessibilityHidden(true)
    }
}
