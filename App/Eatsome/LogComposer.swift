import EatsomeCore
import PhotosUI
import SwiftUI

/// Logging a meal, from the `+` to a line in the log.
///
/// One modal with four stages rather than a stack of pushed screens, because
/// the whole thing is a single act and the back button between its halves would
/// be a lie: there is nothing to go back *to* between saying what you ate and
/// seeing what it was.
///
/// The order is the discipline, and it is the one thing here worth defending:
///
/// **The input is written down before it is read.** `messageSent` is appended
/// the instant the send happens, and recognition runs after. That is what makes
/// a failed reading retryable rather than retypeable, and it is why a photograph
/// taken at a restaurant with no signal is not lost. The meal is a *second*
/// event, so an uncorrected model answer and the words that produced it are two
/// records rather than one — which is the difference that lets recognition
/// quality be measured later at all.
///
/// **A late answer may not resurrect a cancelled send.** Cancelling appends
/// `messageDeleted` and removes the local photograph; every path back from the
/// Worker re-checks that the message is still in the projection before it does
/// anything with the answer. Without that check, cancelling a slow read leaves a
/// meal appearing on Today thirty seconds later, from a screen that was closed.
struct LogComposer: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(EatsomeAccount.self) private var account
    @Environment(\.dismiss) private var dismiss

    /// Where the one send has got to. The message travels with every stage
    /// after the first because it is what the stage is *about* — a screen that
    /// watched "whether anything is being read" would show the wrong meal the
    /// moment two sends overlapped.
    private enum Stage {
        case composing
        case reading(LogMessage)
        case confirming(MealEntry, LogMessage)
        case failed(LogMessage, String)
    }

    @State private var stage = Stage.composing
    @State private var said = ""
    /// The original bytes as they came off the camera or out of the library.
    /// `ModelInputImage` renders the one JPEG that is hashed, sent and stored,
    /// and it does it at send time so a re-pick costs nothing.
    @State private var photo: Data?
    @State private var when = Date()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingConsent = false
    @State private var fixing = false
    @State private var fixFailure: String?
    @State private var isFixing = false

    var body: some View {
        Group {
            switch stage {
            case .composing:
                composer
            case .reading(let message):
                ReadingState(said: message.said, photoHash: message.photoHash) {
                    Task { await cancel(message) }
                }
            case .confirming(let meal, let message):
                MealDetailScreen(
                    meal: meal,
                    mode: .confirming(
                        onFix: { _ in fixing = true },
                        onAdd: { confirmed in Task { await add(confirmed, for: message) } }
                    ),
                    onBack: { Task { await cancel(message) } },
                    onAddPhoto: { _ in showingCamera = true }
                )
            case .failed(let message, let reason):
                FailedState(message: message, reason: reason) {
                    Task { await reread(message) }
                } onCancel: {
                    Task { await cancel(message) }
                }
            }
        }
        .background(WellieTheme.background)
        .sheet(isPresented: $showingCamera) {
            CameraPhoto { data in
                photo = data
                if case .confirming = stage { Task { await rereadWithPhoto() } }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingConsent) {
            SendConsentSheet(includesPhoto: photo != nil) {
                account.agreeToSend()
                showingConsent = false
                Task { await send() }
            } onCancel: {
                showingConsent = false
            }
        }
        .fullScreenCover(isPresented: $fixing) {
            if case .confirming(let meal, _) = stage {
                FixInWords(
                    subject: MealTitle.of(meal),
                    isWorking: isFixing,
                    failure: fixFailure,
                    onSubmit: { note in Task { await fix(note, on: meal) } },
                    onCancel: { fixing = false; fixFailure = nil }
                )
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photo = data
                    if case .confirming = stage { await rereadWithPhoto() }
                }
                pickerItem = nil
            }
        }
        .wellieScreen()
    }

    // MARK: - Saying what it was

    private var composer: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(WellieTheme.font(14.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Text("Log a meal")
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer()
                // Balances the title against Cancel without a second control.
                Color.clear.frame(width: 52, height: 1)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let photo, let image = UIImage(data: photo) {
                        attachedPhoto(image)
                            .padding(.horizontal, WellieTheme.screenInset)
                            .padding(.top, 20)
                    }

                    Text(photo == nil ? "What did you eat?" : "Anything the photo can't show")
                        .font(WellieTheme.font(25, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(WellieTheme.ink)
                        .padding(.horizontal, 24)
                        .padding(.top, photo == nil ? 28 : 20)

                    words
                        .padding(.horizontal, WellieTheme.screenInset)
                        .padding(.top, 16)

                    Text("Write it, photograph it, or both.")
                        .font(WellieTheme.font(12.5))
                        .foregroundStyle(WellieTheme.muted)
                        .padding(.horizontal, 26)
                        .padding(.top, 10)

                    if photo == nil {
                        RecentPhotosStrip(
                            pickerItem: $pickerItem,
                            onCamera: { showingCamera = true },
                            onPick: { photo = $0 }
                        )
                        .padding(.top, 24)
                    }

                    whenRow
                        .padding(.horizontal, WellieTheme.screenInset)
                        .padding(.top, 22)

                    Color.clear.frame(height: 20)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            footer
        }
    }

    private func attachedPhoto(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { photo = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WellieTheme.onInk)
                        .frame(width: 28, height: 28)
                        .background(WellieTheme.inkSurface.opacity(0.85), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Remove the photo")
            }
    }

    /// One field, and its label changes with what is attached.
    ///
    /// Not two — a "what you ate" box and a separate "note for the model" box
    /// would be the same sentence going to the same place under two names. The
    /// Worker decides whether these words caption a picture or are the entire
    /// account of the meal, and it can only decide that because it is told
    /// which it received.
    private var words: some View {
        TextField(
            photo == nil ? "Two eggs on sourdough, flat white" : "Fried in butter, two eggs in the batter",
            text: $said,
            axis: .vertical
        )
        .font(WellieTheme.font(17, weight: .regular))
        .foregroundStyle(WellieTheme.ink)
        .lineLimit(3...6)
        .padding(20)
        .frame(minHeight: 116, alignment: .top)
        .wellieSurface()
    }

    /// Backdating, as a plain date picker rather than a sentence the model
    /// parses. "Half a kebab at 2 am" used to be read out of the words, which
    /// works until it does not and then silently files dinner under the wrong
    /// day; a control cannot misread itself.
    private var whenRow: some View {
        HStack {
            Text("When")
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            DatePicker("When", selection: $when, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, 6)
    }

    private var canSend: Bool {
        photo != nil || !said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button("Read this") {
                Task { await sendOrAsk() }
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: canSend))
            .disabled(!canSend)
            Text("activates once there’s a photo or words")
                .font(WellieTheme.font(10.5))
                .foregroundStyle(WellieTheme.muted)
                .padding(.top, 6)
            if let error = account.error {
                Text(error)
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(WellieTheme.background)
    }

    // MARK: - Sending

    private func sendOrAsk() async {
        guard account.hasAgreedToSend else {
            showingConsent = true
            return
        }
        await send()
    }

    /// Write it down, then read it. In that order, always.
    private func send() async {
        let rendered = photo.flatMap(ModelInputImage.render)
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = LogMessage(
            sentAt: when.epochMillis,
            said: text.isEmpty ? nil : text,
            photoHash: rendered.flatMap { PhotoStore.shared.store($0) }
        )
        guard !message.isEmpty else { return }

        await store.record(.messageSent(message), occurredAt: message.sentAt)
        stage = .reading(message)
        await read(message, bytes: rendered)
    }

    private func reread(_ message: LogMessage) async {
        stage = .reading(message)
        // The composer's own bytes win over the stored ones. A photograph
        // attached at the confirmation step is not on the message — the
        // message was written before it existed — so reading only by
        // `message.photoHash` would retry the picture-less version of a send
        // the person had just added a picture to.
        let bytes = photo.flatMap(ModelInputImage.render)
            ?? PhotoStore.shared.data(for: message.photoHash)
        await read(message, bytes: bytes)
    }

    /// Re-read the same words with a photograph now attached. This is what the
    /// *Add a photo* row on the confirmation actually does: attaching a picture
    /// to figures that never saw it would be a photograph of a different claim.
    private func rereadWithPhoto() async {
        guard case .confirming(_, let message) = stage,
              let rendered = photo.flatMap(ModelInputImage.render)
        else { return }
        PhotoStore.shared.store(rendered)
        stage = .reading(message)
        await read(message, bytes: rendered)
    }

    private func read(_ message: LogMessage, bytes: Data?) async {
        guard let session = account.session else {
            stage = .failed(message, "This build cannot reach the eatsome service.")
            return
        }
        do {
            let answer = try await session.recognize(
                said: message.said,
                image: bytes.map { (data: $0, mimeType: "image/jpeg") }
            )
            // Cancel may have removed the message while this was in flight.
            guard store.projection.messages[message.id] != nil else { return }
            guard let meal = answer.recognition.mealEntry(
                eatenAt: message.sentAt,
                // A photo with a caption is still a photograph: the picture is
                // the stronger evidence and the words are what it could not
                // show.
                source: bytes == nil ? .text : .photo,
                photoHash: answer.photoHash ?? message.photoHash,
                messageID: message.id
            ) else {
                stage = .failed(message, "Nothing in that looked like food. Try naming what you ate.")
                return
            }
            stage = .confirming(meal, message)
        } catch {
            guard store.projection.messages[message.id] != nil else { return }
            stage = .failed(message, error.localizedDescription)
        }
    }

    // MARK: - Landing

    private func add(_ meal: MealEntry, for message: LogMessage) async {
        guard store.projection.meals[meal.id] == nil else { return }
        await store.record(.mealLogged(meal), occurredAt: meal.eatenAt)
        dismiss()
    }

    private func fix(_ note: String, on meal: MealEntry) async {
        isFixing = true
        fixFailure = nil
        defer { isFixing = false }
        switch await MealRefinement.apply(note, to: meal, using: account.session) {
        case .success(let corrected):
            guard case .confirming(_, let message) = stage else { return }
            stage = .confirming(corrected, message)
            fixing = false
        case .failure(let reason):
            fixFailure = reason
        }
    }

    /// The message and its private local photograph leave together, and the
    /// late answer above is ignored because of it.
    private func cancel(_ message: LogMessage) async {
        PhotoStore.shared.remove(message.photoHash)
        await store.record(.messageDeleted(messageID: message.id), occurredAt: message.sentAt)
        dismiss()
    }
}

// MARK: - Waiting

/// What a reading looks like while it happens.
///
/// It says roughly how long rather than drawing a bar, because there is no
/// progress to report: the Worker answers when the model does. A stated
/// expectation is the honest version of a bar that would have to be invented.
private struct ReadingState: View {
    let said: String?
    let photoHash: String?
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack(alignment: .top) {
            if photoHash != nil { ReadingPhotoBackdrop(hash: photoHash) }

            VStack(spacing: 0) {
                HStack {
                    Button(action: onCancel) {
                        Label("Cancel", systemImage: "xmark")
                            .font(WellieTheme.font(14, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay { Capsule().strokeBorder(WellieTheme.glassStroke, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 12)

                if photoHash == nil, let said, !said.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("“")
                            .font(WellieTheme.font(34, weight: .heavy))
                            .foregroundStyle(WellieTheme.accent)
                        Text(said)
                            .font(WellieTheme.font(27, weight: .heavy))
                            .tracking(-0.7)
                            .foregroundStyle(WellieTheme.ink)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 104)
                }

                ReadingSkeleton(
                    title: photoHash == nil ? "Reading your meal" : "Reading your plate",
                    overPhoto: photoHash != nil
                )
                    .scaleEffect(pulsing ? 0.985 : 1)
                    .opacity(pulsing ? 0.84 : 1)
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.top, photoHash == nil ? 50 : 186)

                if photoHash != nil, let said, !said.isEmpty {
                    Text("“\(said)”")
                        .font(WellieTheme.font(13))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .padding(.top, 22)
                }

                Spacer(minLength: 20)

                Button("Cancel this reading", action: onCancel)
                    .font(WellieTheme.font(15, weight: .bold))
                    .foregroundStyle(WellieTheme.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .wellieSurface(radius: WellieTheme.controlRadius, border: WellieTheme.outline)
                    .buttonStyle(.plain)
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulsing = true }
        }
    }
}

private struct ReadingPhotoBackdrop: View {
    let hash: String?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = PhotoStore.shared.image(for: hash) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    WellieTheme.raised
                }
            }
            .frame(width: geometry.size.width, height: 400)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, WellieTheme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }
        }
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }
}

private struct ReadingSkeleton: View {
    let title: String
    let overPhoto: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(WellieTheme.font(24, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(WellieTheme.ink)
            Text("Usually five to eight seconds")
                .font(WellieTheme.font(13.5))
                .foregroundStyle(WellieTheme.body)
                .padding(.top, 6)
            WellieRowDivider().padding(.top, 20)
            HStack(spacing: 10) {
                Capsule().fill(WellieTheme.raised).frame(height: 14)
                Capsule().fill(WellieTheme.raised).frame(width: 86, height: 14)
            }
            .padding(.top, 16)
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(WellieTheme.raised).frame(height: 14) }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .background {
            if overPhoto {
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                            .fill(WellieTheme.glassFill)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                            .strokeBorder(WellieTheme.glassStroke, lineWidth: 1)
                    }
            } else {
                RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                    .fill(WellieTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous)
                            .strokeBorder(WellieTheme.outline, lineWidth: 1)
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A reading that did not work. The words are still written down, so the offer
/// is to try again rather than to type it out a second time.
private struct FailedState: View {
    let message: LogMessage
    let reason: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if message.photoHash != nil { ReadingPhotoBackdrop(hash: message.photoHash) }
            VStack(spacing: 0) {
            HStack {
                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                        .font(WellieTheme.font(14, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .wellieSurface(radius: WellieTheme.rowRadius)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 12)

            Spacer(minLength: message.photoHash == nil ? 80 : 186)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(WellieTheme.attention)
                        .frame(width: 30, height: 30)
                        .background(WellieTheme.attentionSurface, in: Circle())
                    Text("That reading didn't work")
                        .font(WellieTheme.font(22, weight: .heavy))
                        .foregroundStyle(WellieTheme.ink)
                }
                Text(reason)
                    .font(WellieTheme.font(13.5))
                    .foregroundStyle(WellieTheme.body)
                    .lineSpacing(3)
            }
            .padding(22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous))
            .background(WellieTheme.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: WellieTheme.heroRadius, style: .continuous).strokeBorder(WellieTheme.glassStroke, lineWidth: 1) }
            .padding(.horizontal, WellieTheme.screenInset)

            if let said = message.said, !said.isEmpty {
                Text("“\(said)”")
                    .font(WellieTheme.font(13))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
                    .padding(.top, 22)
            }

            VStack(spacing: 8) {
                Button("Try again", action: onRetry)
                    .buttonStyle(WelliePrimaryButtonStyle())
                Button("Discard it", action: onCancel)
                    .buttonStyle(WellieQuietButtonStyle())
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.bottom, 16)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
