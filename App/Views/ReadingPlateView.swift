import ShamanCore
import SwiftUI

/// Screen `4a·3`. Reading your plate.
///
/// The old thread said "Reading…" in a small pill and let the day carry on
/// around it. That was right for a chat and wrong for a sheet: the sheet is
/// modal, so the pill would have been the only thing on an otherwise empty
/// screen, and a spinner alone gives a person no idea whether to wait.
///
/// So this says three things and stops. What is being read — the photograph and
/// the words, still on screen, because the commonest doubt in the five seconds
/// after sending is *did it get the right picture*. Roughly how long. And that
/// leaving is allowed: the read is a queue entry, not a session, and it lands in
/// Today whether or not anyone is looking at it.
///
/// The skeleton below is a placeholder for the card this becomes and it is
/// deliberately not animated into a fake progress bar. Nothing here knows how
/// far along the model is, and a bar that filled at a made-up rate would be the
/// screen telling its first lie.
struct ReadingPlateView: View {
    @Environment(AppModel.self) private var model
    let message: LogMessage
    let logAnother: () -> Void

    private var state: LogMessageState { model.state(of: message) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            evidence
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 24)

            if case .failed(let reason) = state {
                failure(reason)
            } else {
                working
            }

            Spacer(minLength: 24)

            Text("You can leave this screen — it keeps going and lands in Today when it's done.")
                .font(WellieTheme.font(13, weight: .regular))
                .foregroundStyle(WellieTheme.faint)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Button("Log another while this runs", action: logAnother)
                .buttonStyle(WellieSecondaryButtonStyle())
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 22)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - What is being read

    /// The photograph if there was one, the words if there were words, and
    /// nothing invented when there was only one of the two.
    @ViewBuilder
    private var evidence: some View {
        if let image = PhotoStore.shared.image(for: message.photoHash) {
            // Sized by an empty container, with the image, the scrim and the
            // caption all hung off it as overlays — the same shape as
            // `MealDetailView.banner`. Overlays inherit the container's
            // resolved size, so nothing here depends on what a `ZStack` decides
            // to propose to a gradient that has no size of its own.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .saturation(0.7)
                        .brightness(-0.16)
                }
                .clipped()
                // Weighted to the bottom third rather than ramped evenly: a
                // linear fade sits at roughly 0.5 where the caption is, which
                // darkens a plate of noodles and does not darken a white bowl.
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: WellieTheme.background.opacity(0.1), location: 0),
                            .init(color: WellieTheme.background.opacity(0.35), location: 0.45),
                            .init(color: WellieTheme.background.opacity(0.96), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let said = message.trimmedText {
                            WellieMeta(said, color: WellieTheme.accent)
                                .lineLimit(2)
                        }
                        Text(provenance)
                            .font(WellieTheme.font(13, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    .padding(22)
                }
                .clipShape(RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous))
        } else if let said = message.trimmedText {
            VStack(alignment: .leading, spacing: 8) {
                Text(said)
                    .font(WellieTheme.font(19, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(provenance)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            .wellieCard(radius: WellieTheme.heroRadius)
        }
    }

    private var provenance: String {
        var parts: [String] = []
        if message.photoHash != nil { parts.append("1 photo") }
        if message.trimmedText != nil { parts.append("your note") }
        return parts.joined(separator: " · ")
    }

    // MARK: - In flight

    private var working: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Working it out…")
                    .font(WellieTheme.font(17, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text("Usually five to eight seconds.")
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)

            SkeletonCard()
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 22)
        }
    }

    /// The read did not complete. The message is intact — it is an event in the
    /// log — so this re-sends the one that already exists and never asks anyone
    /// to type it again.
    private func failure(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't read that one.")
                    .font(WellieTheme.font(17, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text(reason)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try again") { model.retry(message) }
                .buttonStyle(WelliePrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }
}

/// The shape of the card this is about to become.
///
/// A placeholder rather than a spinner: it says *a meal with a name and five
/// figures is what arrives*, which is more than a rotating circle says and is
/// true. It shimmers rather than fills, for the reason above — nothing on this
/// device knows how far along the model is.
private struct SkeletonCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            bar(width: 132, height: 13)
            bar(width: 196, height: 24).padding(.top, 14)

            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 9) {
                        bar(width: 38, height: 10)
                        bar(width: 30, height: 16)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 18)
            .overlay(alignment: .top) {
                Rectangle().fill(WellieTheme.hairline).frame(height: 1)
            }
            .padding(.top, 24)
        }
        .wellieCard(padding: 20)
        .opacity(shimmer ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(height > 12 ? WellieTheme.raised : WellieTheme.hairline)
            .frame(width: width, height: height)
    }
}
