import ShamanCore
import SwiftUI

/// Screen `7b`. Tap the mic, talk, watch the words appear.
///
/// It replaces the typing row rather than floating over it, so the thread never
/// moves while you speak. What you accept goes into the composer as text and is
/// sent like anything else — the words are the message, so a misheard one is
/// fixed before it goes rather than argued with afterwards.
struct VoiceComposer: View {
    @Bindable var voice: VoiceDictation
    /// Called with the transcript when the tick is tapped.
    let accept: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let error = voice.error {
                    Text(error)
                        .font(WellieTheme.font(14.5, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                } else if voice.isPreparing {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 9) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(WellieTheme.accent)
                            Text("Getting microphone ready…")
                                .font(WellieTheme.font(17, weight: .medium))
                                .foregroundStyle(WellieTheme.ink)
                        }
                        Text("Wait for “Start talking” before you speak.")
                            .font(WellieTheme.font(12.5, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                    }
                } else if voice.heard.isEmpty {
                    Text("Start talking…")
                        .font(WellieTheme.font(17, weight: .medium))
                        .foregroundStyle(WellieTheme.accent)
                } else {
                    Text(voice.heard)
                        .font(WellieTheme.font(17, weight: .medium))
                        .foregroundStyle(WellieTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .animation(.easeOut(duration: 0.15), value: voice.heard)
            .animation(.easeOut(duration: 0.15), value: voice.phase)

            HStack(spacing: 14) {
                Button { voice.cancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WellieTheme.body)
                        .frame(width: 38, height: 38)
                        .wellieHitTarget()
                        .background(WellieTheme.ice, in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous))
                }
                .accessibilityLabel("Discard")

                if voice.isPreparing {
                    Text("Connecting securely…")
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Waveform(levels: voice.levels)
                        .frame(maxWidth: .infinity)

                    Text(timer)
                        .font(WellieTheme.font(14, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                        .monospacedDigit()
                }

                Button { accept(voice.accept()) } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WellieTheme.onAccent)
                        .frame(width: 38, height: 38)
                        .background(canAccept ? WellieTheme.blue : WellieTheme.faint, in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous))
                }
                .disabled(!canAccept)
                .accessibilityLabel("Use these words")
            }
        }
        .padding(18)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.vertical, 10)
    }

    private var canAccept: Bool {
        voice.isListening
            && !voice.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var timer: String {
        let seconds = Int(voice.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Input level over the last few seconds.
///
/// Not decoration. Silence and a dead microphone look identical on a screen
/// showing no words yet, and this is the one thing that tells them apart while
/// there is still time to do something about it.
private struct Waveform: View {
    let levels: [Float]

    private let bars = 22

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                    .fill(WellieTheme.blue.opacity(0.35 + 0.65 * Double(height(index))))
                    .frame(width: 3, height: 4 + CGFloat(height(index)) * 22)
            }
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.12), value: levels.count)
        .accessibilityHidden(true)
    }

    /// Newest on the right, so the trace runs the way the words do.
    private func height(_ index: Int) -> Float {
        let offset = bars - index
        guard levels.count >= offset else { return 0.05 }
        return max(0.05, levels[levels.count - offset])
    }
}
