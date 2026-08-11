import Photos
import PhotosUI
import ShamanCore
import SwiftUI

/// Screen `4a·2`. Log a meal.
///
/// Four ways in, and the mock's own sentence for why there are four: *type it,
/// say it, or add a photo — one is enough*. The composer used to live
/// permanently at the bottom of the thread, which made it free to reach and
/// impossible to explain; as a sheet it gets a heading, and the heading is what
/// tells a new person that a photograph is optional.
///
/// Sending does not close it. It becomes `ReadingPlateView`, in place, so the
/// photograph you just sent stays on screen while it is read and "log another"
/// is one tap rather than a re-entry. The sheet closes itself when the read
/// lands — or you can leave, and it lands in Today either way.
struct LogMealSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    /// A photo waiting for its caption.
    ///
    /// It does not send on capture. A photograph of a protein carton goes up as
    /// "2 of these at 11 am" — the words are what turn a picture of a label into
    /// a meal of a known size, and there is no moment to type them if the
    /// shutter is also the send button.
    @State private var pendingPhoto: Data?
    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    /// The message being read. Non-nil is the whole of the reading phase.
    @State private var reading: LogMessage?
    @State private var voice = VoiceDictation()
    @FocusState private var isTyping: Bool

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            if let reading {
                ReadingPlateView(message: reading, logAnother: { logAnother() })
            } else {
                compose
            }
        }
        .background(WellieTheme.background)
        .wellieScreen()
        .presentationDragIndicator(.hidden)
        .task { voice.configure(model.voiceKeySource) }
        .sheet(isPresented: $showingCamera) { CameraPhotoPicker { attach($0) } }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { attach(data) }
                pickerItem = nil
            }
        }
        // The sheet's own job is finished the moment the meal exists. Leaving
        // it up on a saved meal would make the person dismiss a screen that is
        // no longer about anything.
        .onChange(of: readingState) { _, state in
            if case .logged = state { dismiss() }
        }
    }

    private var readingState: LogMessageState? {
        reading.map { model.state(of: $0) }
    }

    // MARK: - Chrome

    private var sheetHeader: some View {
        ZStack {
            Text(reading == nil ? "Log a meal" : "Reading your plate")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        Text("Cancel")
                    }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
                    .wellieHitTarget()
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    // MARK: - Composing

    private var compose: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What did you eat?")
                        .font(WellieTheme.font(25, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Type it, say it, or add a photo. One is enough.")
                        .font(WellieTheme.font(14, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)

                if voice.isRecording {
                    VoiceComposer(voice: voice) { heard in
                        // Voice sends as text: what the transcriber heard is
                        // what gets parsed, so a wrong word is fixed before it
                        // goes rather than after it is a meal.
                        draft = heard
                        isTyping = true
                    }
                    .padding(.top, 20)
                } else {
                    inputCard.padding(.top, 22)
                    sourceButtons.padding(.top, 12)
                }

                RecentPhotosStrip { attach($0) }
                    .padding(.top, 26)

                repeats.padding(.top, 26)
            }
            .padding(.bottom, 32)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isTyping = false })
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    /// The field, with the mic and the send arrow tucked under it.
    ///
    /// Under, not beside: the row is 44 pt of controls and a growing text field,
    /// and putting them on one line is what forced the old composer's field down
    /// to a single visible line. Here the sentence gets the full width and the
    /// controls get their own row, which is also where an attached photo shows
    /// itself.
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pendingPhoto, let image = UIImage(data: pendingPhoto) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous))
                    .accessibilityLabel("Selected meal photo")
                    .overlay(alignment: .topTrailing) {
                        Button { self.pendingPhoto = nil } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(WellieTheme.ink)
                                .frame(width: 30, height: 30)
                                .background(WellieTheme.background.opacity(0.94), in: Circle())
                                .overlay {
                                    Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove the photo")
                        .offset(x: 10, y: -10)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 10)
            }

            TextField(
                "Salmon and tuna don, half a bowl…",
                text: $draft,
                axis: .vertical
            )
            .font(WellieTheme.font(17, weight: .regular))
            .foregroundStyle(WellieTheme.ink)
            .tint(WellieTheme.accent)
            .focused($isTyping)
            .lineLimit(1...6)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button { voice.start() } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(voice.isAvailable ? WellieTheme.accent : WellieTheme.faint)
                        .frame(width: 44, height: 44)
                        .background(WellieTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!voice.isAvailable)
                .accessibilityLabel("Say what you ate")

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSend ? WellieTheme.onAccent : WellieTheme.faint)
                        .frame(width: 44, height: 44)
                        .background(canSend ? WellieTheme.accent : WellieTheme.raised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(18)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                .strokeBorder(isTyping ? WellieTheme.accent : WellieTheme.hairline, lineWidth: 1.5)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .animation(.easeOut(duration: 0.15), value: isTyping)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingPhoto != nil
    }

    private var sourceButtons: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                SourceLabel(icon: "photo.on.rectangle", text: "From gallery")
            }
            .buttonStyle(.plain)

            Button { showingCamera = true } label: {
                SourceLabel(icon: "camera.fill", text: "Camera")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WellieTheme.screenInset)
    }

    /// What you are most likely about to type, for this time of day.
    ///
    /// The chip fills the field rather than logging straight away: "lentil
    /// soup" is very often about to become "lentil soup, small bowl". Sent from
    /// the field it also takes the no-model path in `AppModel.send(dish:)` —
    /// the ingredients and their weights are already known from the last time,
    /// and asking a model to describe lentil soup again spends money to be told
    /// the same thing less reliably.
    @ViewBuilder
    private var repeats: some View {
        let chips = model.dishSuggestions(typed: draft)
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                WellieMeta("Again?", color: WellieTheme.faint)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(chips) { chip in
                        Button { draft = chip.name.capitalizedFirst } label: {
                            WellieChip(text: chip.name.capitalizedFirst)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Sending

    private func attach(_ data: Data) {
        pendingPhoto = data
        isTyping = true
    }

    private func send() {
        let said = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = pendingPhoto
        guard !said.isEmpty || photo != nil else { return }
        isTyping = false
        Task {
            reading = await model.send(said: said.isEmpty ? nil : said, photo: photo)
            // Cleared only once the message exists, so a failed write leaves
            // the words where they were rather than swallowing them.
            draft = ""
            pendingPhoto = nil
        }
    }

    /// Back to an empty composer while the last one is still being read. The
    /// reading does not pause and does not need this screen — it is a queue.
    private func logAnother() {
        reading = nil
        isTyping = true
    }
}

/// One of the two source buttons.
///
/// A view rather than a method on the sheet: `PhotosPicker`'s label builder is
/// not main-actor isolated, so a `some View` returned from a method on the
/// enclosing view cannot cross into it.
private struct SourceLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WellieTheme.accent)
            Text(text)
                .font(WellieTheme.font(14, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
                .strokeBorder(WellieTheme.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Recent photos

/// The last few pictures on the phone, so lunch you photographed at one o'clock
/// is one tap at nine in the evening.
///
/// The strip asks for read access when the meal logger opens. That is the first
/// screen where the app visibly needs the library, so the request is contextual
/// without becoming a launch-time interruption. The system `PhotosPicker`
/// remains available even when this broader access is declined.
private struct RecentPhotosStrip: View {
    @Environment(\.scenePhase) private var scenePhase

    let onPick: (Data) -> Void

    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var recent: [Recent] = []

    private struct Recent: Identifiable {
        let id: String
        let asset: PHAsset
        let thumbnail: UIImage
    }

    private var isAllowed: Bool { status == .authorized || status == .limited }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieMeta("Recent photos", color: WellieTheme.faint)
            HStack(spacing: 10) {
                if isAllowed && !recent.isEmpty {
                    ForEach(recent) { item in
                        Button { pick(item.asset) } label: {
                            Image(uiImage: item.thumbnail)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 78, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: WellieTheme.photoRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("A recent photo")
                    }
                } else {
                    ForEach(0..<4, id: \.self) { _ in
                        Button(action: request) {
                            RoundedRectangle(cornerRadius: WellieTheme.photoRadius, style: .continuous)
                                .fill(WellieTheme.surface)
                                .frame(width: 78, height: 78)
                                .overlay {
                                    RoundedRectangle(cornerRadius: WellieTheme.photoRadius, style: .continuous)
                                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: isAllowed ? .contain : .ignore)
            .accessibilityLabel(isAllowed ? "" : "Show recent photos")
            .accessibilityAddTraits(isAllowed ? [] : .isButton)

            if isAllowed && recent.isEmpty {
                Text("No photos on this phone yet.")
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            } else if !isAllowed {
                Text(photoAccessMessage)
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .padding(.horizontal, 24)
        .task { preparePhotoLibrary() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPhotoLibrary()
        }
    }

    private var photoAccessMessage: String {
        switch status {
        case .notDetermined:
            "Allow photo access to show your latest pictures here."
        case .denied:
            "Photo access is off. Pick above, or tap here to change it in Settings."
        case .restricted:
            "Photo access is restricted on this device."
        default:
            "Recent photos are unavailable."
        }
    }

    private func preparePhotoLibrary() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        status = current
        switch current {
        case .notDetermined:
            request()
        case .authorized, .limited:
            load()
        default:
            recent = []
        }
    }

    private func refreshPhotoLibrary() {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        status = current
        if current == .authorized || current == .limited {
            load()
        } else {
            recent = []
        }
    }

    private func request() {
        // Already refused: iOS will not ask again, and a button that silently
        // does nothing is worse than one that sends you where the answer can be
        // changed.
        guard status == .notDetermined else {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { granted in
            Task { @MainActor in
                status = granted
                if granted == .authorized || granted == .limited { load() }
            }
        }
    }

    private func load() {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 4
        let assets = PHAsset.fetchAssets(with: options)
        // Thumbnails come back in whatever order they decode, which on a mixed
        // library is not the order they were taken in. The fetch order is the
        // newest-first order the strip promises, so it is captured up front and
        // the arrivals are sorted into it.
        let order = (0..<assets.count).map { assets.object(at: $0).localIdentifier }

        let manager = PHImageManager.default()
        let request = PHImageRequestOptions()
        request.deliveryMode = .highQualityFormat
        request.resizeMode = .exact
        request.isNetworkAccessAllowed = true

        assets.enumerateObjects { asset, _, _ in
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 234, height: 234),
                contentMode: .aspectFill,
                options: request
            ) { image, _ in
                guard let image else { return }
                Task { @MainActor in
                    // `requestImage` can call back twice — a degraded thumbnail
                    // and then the real one — so replace by identifier rather
                    // than append, or the strip grows to eight tiles.
                    let entry = Recent(id: asset.localIdentifier, asset: asset, thumbnail: image)
                    if let index = recent.firstIndex(where: { $0.id == entry.id }) {
                        recent[index] = entry
                    } else {
                        recent.append(entry)
                        recent.sort {
                            (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
                        }
                    }
                }
            }
        }
    }

    private func pick(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data else { return }
            Task { @MainActor in onPick(data) }
        }
    }
}
