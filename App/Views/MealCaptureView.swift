import AVFoundation
import PhotosUI
import ShamanCore
import SwiftUI
import UIKit

/// Everything the camera tab opens: the chooser (`3a`/`3c`), reading (`2d`),
/// the failure that reading can end in (`2d`), and the result (`1b Add meal`).
///
/// Four states in one sheet rather than four pushes, because they are one act.
/// You never go back to the chooser from the result; you retake, which is the
/// same forward motion.
struct MealCaptureView: View {
    /// Preselect the day when the capture was started from an earlier date, so
    /// a meal you forgot on Tuesday lands on Tuesday.
    var day: Date?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private enum Stage { case choosing, reading, failed, reviewing }

    @State private var stage = Stage.choosing
    @State private var imageData: Data?
    @State private var artifact: RecognitionArtifact?
    @State private var items: [MealItem] = []
    @State private var eatenAt = Date()
    @State private var share = MealShare.whole
    @State private var note = ""
    @State private var failure: String?
    @State private var didEdit = false
    @State private var answeredQuestions: Set<UUID> = []
    /// The note as it stood when the photo was read. A note typed afterwards is
    /// new information, and offering to re-read is only honest while it differs.
    @State private var noteAtRecognition = ""
    @State private var isRefining = false
    @State private var sourceRecipeID: UUID?

    @State private var showingCamera = false
    @State private var showingDetails = false
    @State private var showingAddFood = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var editing: EditingFood?
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .choosing: chooser
                case .reading: reading
                case .failed: failureScreen
                case .reviewing: review
                }
            }
            .background(WellieTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPhotoPicker { setPhoto($0) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showingAddFood) {
                FoodGroupPicker { group in
                    items.append(MealItem(group: group, portion: .medium))
                    didEdit = true
                }
            }
            .sheet(item: $editing) { target in
                if let index = items.firstIndex(where: { $0.id == target.id }) {
                    FoodEditSheet(
                        item: $items[index],
                        onRemove: { items.removeAll { $0.id == target.id } },
                        onChange: {
                            didEdit = true
                            answeredQuestions.insert(target.id)
                        }
                    )
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        // Reworded on 2d's pattern: what happened, and that
                        // nothing was lost.
                        failure = "That photo wouldn't open. Nothing is lost — try another one."
                        stage = .failed
                        return
                    }
                    setPhoto(data)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
        .onAppear { if let day { eatenAt = startOfCapture(day) } }
        .wellieScreen()
    }

    // MARK: - 3a / 3c · Add a meal

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add a meal")
                        .font(WellieTheme.font(27, weight: .bold))
                    Text(chooserSubtitle)
                        .font(WellieTheme.font(15.5, weight: .medium))
                        .foregroundStyle(WellieTheme.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)

                // Without the camera the order flips: the route that works is
                // the one at the top, and the one that does not stays visible
                // with a reason rather than vanishing.
                if cameraIsAvailable {
                    takePhotoRow
                    choosePhotoRow
                } else {
                    choosePhotoRow
                    takePhotoRow
                }

                if !model.recipes.isEmpty { dishesCard }

                Button("Add it by hand instead") { addByHand() }
                    .buttonStyle(WellieQuietButtonStyle())
                    .font(WellieTheme.font(15, weight: .semibold))
                    .padding(.top, 2)
            }
            .wellieColumn()
        }
    }

    private var chooserSubtitle: String {
        cameraIsAvailable
            ? "A photo is quickest. Everything after this is optional."
            : "The camera is switched off for eatsome, so a photo you already took is the quickest way."
    }

    private var cameraIsAvailable: Bool {
        cameraStatus != .denied && cameraStatus != .restricted
            && UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var takePhotoRow: some View {
        Button {
            if cameraIsAvailable {
                showingCamera = true
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            CaptureRouteRow(
                icon: "camera.fill",
                title: "Take a photo",
                subtitle: cameraIsAvailable ? "Point at the plate before you start" : "Needs camera access",
                action: cameraIsAvailable ? .chevron : .text("Turn on"),
                isDimmed: !cameraIsAvailable
            )
        }
        .buttonStyle(.plain)
    }

    private var choosePhotoRow: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            CaptureRouteRow(
                icon: "photo.on.rectangle",
                title: "Choose a photo",
                subtitle: "One you already took",
                action: .chevron
            )
        }
        .buttonStyle(.plain)
    }

    /// Home cooking repeats, and it is the food a camera reads worst. The dish
    /// you cooked most is the one you are most likely cooking now.
    private var dishesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Or a dish you cook often")
                .font(WellieTheme.font(15, weight: .bold))

            ForEach(model.recipes.prefix(3)) { recipe in
                Button { load(recipe) } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(WellieTheme.ice)
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "text.book.closed.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(WellieTheme.blue)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.name)
                                .font(WellieTheme.font(15.5, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                            Text(timesLoggedText(recipe))
                                .font(WellieTheme.font(12.5, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WellieTheme.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .wellieCard()
    }

    private func timesLoggedText(_ recipe: Recipe) -> String {
        let count = model.timesLogged(recipe)
        return count == 0 ? "Not logged yet" : "Logged \(count) time\(count == 1 ? "" : "s")"
    }

    // MARK: - 2d · Reading

    private var reading: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                MealPhotoBanner(image: imageData.flatMap(UIImage.init(data:)))

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Reading your plate")
                            .font(WellieTheme.font(15, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                    }

                    // The sentence assembling itself. A spinner alone says
                    // "wait"; this says what is being made while you wait.
                    VStack(alignment: .leading, spacing: 11) {
                        skeleton(0.82, tone: WellieTheme.ice)
                        skeleton(0.64, tone: WellieTheme.ice)
                        skeleton(0.44, tone: WellieTheme.ice.opacity(0.6))
                    }

                    WellieProse("A few seconds. You can put the phone down — it'll be here when you come back.")
                }
                .wellieCard()

                noteCard(caption: "Type it now and it'll be taken into account.")
            }
            .wellieColumn()
        }
    }

    private func skeleton(_ fraction: Double, tone: Color) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tone)
                .frame(width: proxy.size.width * fraction)
        }
        .frame(height: 22)
    }

    // MARK: - 2d · Couldn't read it

    private var failureScreen: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                MealPhotoBanner(image: imageData.flatMap(UIImage.init(data:)))

                VStack(alignment: .leading, spacing: 16) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(WellieTheme.attentionSurface)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(WellieTheme.attention)
                        }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("I couldn't read this one.")
                            .font(WellieTheme.font(22, weight: .bold))
                        WellieProse(failure ?? "Something went wrong on the way there.", size: 15)
                    }

                    VStack(spacing: 10) {
                        Button("Try reading it again") {
                            guard let imageData else { return }
                            Task { await recognize(imageData) }
                        }
                        .buttonStyle(WelliePrimaryButtonStyle())
                        .disabled(imageData == nil)

                        Button("Tell me what it was") {
                            stage = .reviewing
                            showingAddFood = true
                        }
                        .buttonStyle(WellieSecondaryButtonStyle())
                    }

                    // The photo is already on the phone; losing the meal
                    // because the network dropped would be the app's fault
                    // charged to the person.
                    Button("Keep the photo, sort it later") { Task { await save() } }
                        .buttonStyle(WellieQuietButtonStyle())
                }
                .wellieCard()
            }
            .wellieColumn()
        }
    }

    // MARK: - 1b · The result

    private var review: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                if imageData != nil {
                    MealPhotoBanner(
                        image: imageData.flatMap(UIImage.init(data:)),
                        trailing: AnyView(
                            Button("Retake") { showingCamera = true }
                                .font(WellieTheme.font(13, weight: .semibold))
                                .foregroundStyle(WellieTheme.blue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule())
                        )
                    )
                }

                sentenceCard
                noteCard(caption: "Optional. It stays with the meal, so next time this dish starts complete.")
                detailsRow
            }
            .wellieColumn()
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { isTyping = false })
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(items.isEmpty ? "Nothing on the list yet" : "Tap a word to change it")
                .font(WellieTheme.font(13, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)

            if items.isEmpty {
                WellieProse("Add what you ate and it counts the same as a photo would.")
            } else {
                FoodSentence(
                    lead: artifact == nil ? "You had" : "Looks like",
                    words: items.map { item in
                        .init(
                            id: item.id,
                            text: FoodPhrase.word(for: item.group, label: item.label),
                            isUncertain: item.id == openQuestion?.id
                        )
                    },
                    onTap: { editing = EditingFood(id: $0) }
                )
            }

            if let question = openQuestion { uncertainty(question) }

            Button { showingAddFood = true } label: {
                Label(items.isEmpty ? "Add a food" : "Add something", systemImage: "plus")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
            }
            .padding(.top, 2)
        }
        .wellieCard()
    }

    /// One question, never a queue of them.
    ///
    /// Every ambiguity the model reports could be asked about, and asking about
    /// all of them turns a confirmation into a form. Only score-critical rivals
    /// qualify, and only the first: the rest are still one tap away in the
    /// sentence, and saving is never blocked on any of them.
    private var openQuestion: MealItem? {
        let excluded = model.config.medas.excludedItems
        return items.first { item in
            guard !answeredQuestions.contains(item.id),
                  let rivals = item.modelAlternatives, !rivals.isEmpty
            else { return false }
            return rivals.contains { Medas.choiceChangesScore(item.group, $0, excludedItems: excluded) }
        }
    }

    private func uncertainty(_ item: MealItem) -> some View {
        let excluded = model.config.medas.excludedItems
        let rivals = (item.modelAlternatives ?? []).filter {
            Medas.choiceChangesScore(item.group, $0, excludedItems: excluded)
        }
        return VStack(alignment: .leading, spacing: 10) {
            WellieRowDivider().padding(.vertical, 2)
            Text("One thing I'm unsure about")
                .font(WellieTheme.font(15, weight: .semibold))
            WellieProse(
                """
                Is \(FoodPhrase.word(for: item.group, label: item.label)) closer to \
                \(item.group.sentenceName), or to \(rivals.first?.sentenceName ?? "something else")? \
                It changes your week either way, so it's worth a tap — but you can skip it.
                """,
                size: 14.5
            )
            FlowLayout(spacing: 7, lineSpacing: 7) {
                Button { answer(item, as: item.group) } label: {
                    WellieChip(text: item.group.plainName, style: .selected, size: 14)
                }
                .buttonStyle(.plain)
                ForEach(rivals, id: \.self) { rival in
                    Button { answer(item, as: rival) } label: {
                        WellieChip(text: rival.plainName, style: .soft, size: 14)
                    }
                    .buttonStyle(.plain)
                }
                Button { answeredQuestions.insert(item.id) } label: {
                    WellieChip(text: "Skip", style: .outline, size: 14)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Tapping the group already shown is a confirmation, not an edit: the
    /// saved meal is still exactly what the model produced.
    private func answer(_ item: MealItem, as group: FoodGroup) {
        answeredQuestions.insert(item.id)
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index].group != group else { return }
        items[index].group = group
        items[index].modelAlternatives = nil
        didEdit = true
    }

    private func noteCard(caption: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anything the photo can't show?")
                .font(WellieTheme.font(15, weight: .semibold))

            TextField("Fried in butter, two eggs in the batter…", text: $note, axis: .vertical)
                .font(WellieTheme.font(15, weight: .medium))
                .focused($isTyping)
                .lineLimit(1...4)
                .padding(14)
                .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // A re-read only makes sense once the note says something the model
            // did not already have, and it applies a delta so hand edits stay.
            if stage == .reviewing, artifact != nil, hasNewNote {
                Button {
                    Task { await reread() }
                } label: {
                    if isRefining {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Take this into account", systemImage: "sparkles")
                            .font(WellieTheme.font(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(WellieSecondaryButtonStyle())
                .disabled(isRefining)
            }

            WellieCaption(caption)
        }
        .wellieCard()
    }

    private var hasNewNote: Bool {
        let now = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return !now.isEmpty && now != noteAtRecognition.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything you do not change on an ordinary log, folded away. The time is
    /// already right and the plate is usually all yours.
    private var detailsRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy(duration: 0.2)) { showingDetails.toggle() } } label: {
                HStack(spacing: 7) {
                    Spacer()
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                    Text("Time, portions, sharing")
                        .font(WellieTheme.font(14, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(WellieTheme.muted)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingDetails {
                VStack(alignment: .leading, spacing: 16) {
                    DatePicker("Eaten at", selection: $eatenAt)
                        .font(WellieTheme.font(15.5, weight: .semibold))

                    WellieRowDivider()

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("How much did you eat?")
                                .font(WellieTheme.font(15.5, weight: .semibold))
                            Text("Half counts as half toward your week")
                                .font(WellieTheme.font(13, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                        }
                        Spacer(minLength: 8)
                        ShareChips(share: $share)
                    }
                }
                .wellieCard()
                .padding(.top, 10)
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(saveTitle) { Task { await save() } }
                .buttonStyle(WelliePrimaryButtonStyle(enabled: !items.isEmpty))
                .disabled(items.isEmpty)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(WellieTheme.background)
    }

    /// "Looks right" is the honest label when a model produced the list and you
    /// changed nothing. Once you have edited it, it is simply yours.
    private var saveTitle: String {
        guard artifact != nil else { return "Save this meal" }
        return didEdit ? "Save this meal" : "Looks right — save it"
    }

    // MARK: - Flow

    private func setPhoto(_ original: Data) {
        guard let normalized = ModelInputImage.render(original) else {
            failure = "That photo wouldn't open. Nothing is lost — try another one."
            stage = .failed
            return
        }
        imageData = normalized
        items = []
        artifact = nil
        answeredQuestions = []
        didEdit = false
        Task { await recognize(normalized) }
    }

    private func recognize(_ data: Data) async {
        stage = .reading
        failure = nil
        let sent = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await model.recognize(imageData: data, note: sent.isEmpty ? nil : sent)
            artifact = result
            items = result.recognition.asMealItems()
            noteAtRecognition = sent
            stage = .reviewing
        } catch {
            failure = error.localizedDescription
            stage = .failed
        }
    }

    /// A delta, not a re-run: by this point groups and portions may have been
    /// fixed by hand, and regenerating the list would throw that work away.
    private func reread() async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTyping = false
        isRefining = true
        defer { isRefining = false }
        do {
            let revision = try await model.refine(imageData: imageData, current: items, note: text)
            items = revision.applied(to: items)
            noteAtRecognition = text
            didEdit = true
        } catch {
            failure = error.localizedDescription
        }
    }

    private func load(_ recipe: Recipe) {
        items = recipe.items.map {
            MealItem(group: $0.group, portion: $0.portion, label: $0.label)
        }
        note = recipe.note ?? ""
        sourceRecipeID = recipe.id
        stage = .reviewing
    }

    private func addByHand() {
        stage = .reviewing
        showingAddFood = true
    }

    /// A meal logged for an earlier day lands at midday on that day rather than
    /// at this instant, which would put Tuesday's lunch on Thursday.
    private func startOfCapture(_ day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Date() }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func save() async {
        let evidence = artifact.map {
            MealRecognitionEvidence(
                promptVersion: $0.promptVersion,
                rawModelJSON: $0.rawModelJSON,
                initialItems: $0.recognition.asMealItems(),
                otherMealsVisible: $0.recognition.otherMealsVisible
            )
        }
        let source: MealSource = imageData != nil ? .photo : (sourceRecipeID != nil ? .recipe : .manual)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        let meal = MealEntry(
            eatenAt: eatenAt.epochMillis,
            items: items,
            source: source,
            photoHash: imageData.flatMap { PhotoStore.shared.store($0) },
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            recognitionEvidence: evidence,
            share: share,
            wasCorrected: artifact != nil && didEdit,
            recipeID: sourceRecipeID
        )
        await model.logMeal(meal)
        // Logging a saved dish bumps it up the list for next time.
        if let sourceRecipeID, let recipe = model.recipes.first(where: { $0.id == sourceRecipeID }) {
            await model.saveRecipe(recipe)
        }
        dismiss()
    }
}

/// The two routes on `3a`, and the greyed one on `3c`.
struct CaptureRouteRow: View {
    enum Action {
        case chevron
        case text(String)
    }

    let icon: String
    let title: String
    let subtitle: String
    var action: Action = .chevron
    var isDimmed = false

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(isDimmed ? WellieTheme.well : WellieTheme.ice)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isDimmed ? WellieTheme.faint : WellieTheme.blue)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WellieTheme.font(18, weight: .bold))
                    .foregroundStyle(isDimmed ? WellieTheme.muted : WellieTheme.ink)
                Text(subtitle)
                    .font(WellieTheme.font(13.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }

            Spacer(minLength: 0)

            switch action {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WellieTheme.faint)
            case .text(let label):
                Text(label)
                    .font(WellieTheme.font(14, weight: .bold))
                    .foregroundStyle(WellieTheme.blue)
            }
        }
        .wellieCard()
        .contentShape(Rectangle())
    }
}

/// All / Half, as two chips rather than a segmented control — it is a fact
/// about this plate, not a mode the screen is in.
struct ShareChips: View {
    @Binding var share: MealShare

    var body: some View {
        HStack(spacing: 6) {
            chip("All", value: .whole)
            chip("Half", value: .part)
        }
    }

    private func chip(_ text: String, value: MealShare) -> some View {
        Button { share = value } label: {
            WellieChip(text: text, style: share == value ? .selected : .soft)
        }
        .buttonStyle(.plain)
    }
}

struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPhotoPicker
        init(_ parent: CameraPhotoPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
