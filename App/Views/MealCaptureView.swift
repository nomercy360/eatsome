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
    /// The names, counts and sizes the flat list cannot carry. `items` stays
    /// the edit surface — the refiner returns a delta against it — and this is
    /// rebuilt from it, so the two never drift.
    @State private var dishes: [MealDish] = []
    @State private var openDish: MealDish?
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
    @State private var showingFix = false
    /// The line under the spinner. Starts on the plain one so the first thing
    /// read is what is actually happening, then wanders.
    @State private var chatter = PlateChatter.phrases[0]
    @State private var sourceRecipeID: UUID?

    @State private var showingCamera = false
    @State private var showingDetails = false
    @State private var showingPhotoConsent = false
    @State private var pendingConsentImage: Data?
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
            .sheet(isPresented: $showingPhotoConsent) {
                PhotoProcessingConsentView {
                    model.acceptPhotoProcessing()
                    if let pendingConsentImage {
                        self.pendingConsentImage = nil
                        Task { await recognize(pendingConsentImage) }
                    }
                } onCancel: {
                    pendingConsentImage = nil
                    imageData = nil
                    stage = .choosing
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
            .onChange(of: items) { _, updated in
                guard !dishes.isEmpty else { return }
                dishes = MealDish.regrouped(updated, keeping: dishes)
            }
            // Full screen, not a sheet: the keyboard and a detent cannot agree
            // on a height, and the argument happens in front of the reader.
            .fullScreenCover(isPresented: $showingFix) {
                FixScreen(text: $note) { Task { await reread() } }
            }
            .sheet(item: $openDish) { dish in
                DishSheet(
                    dish: dish,
                    onRename: { name in
                        guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                        dishes[index].name = name
                        items = dishes.flatMap { $0.flattened() }
                        didEdit = true
                    },
                    onEditIngredient: { editing = EditingFood(id: $0) },
                    onAddIngredient: {
                        guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                        let added = MealItem(group: .other, portion: .medium)
                        dishes[index].items.append(added)
                        items = dishes.flatMap { $0.flattened() }
                        didEdit = true
                        // Straight into the picker: a row reading "something
                        // else, normal" is not an ingredient, it is a promise
                        // to name one.
                        editing = EditingFood(id: added.id)
                    },
                    onCount: { count in
                        guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                        // Rewrites the weights rather than multiplying at score time: a
                        // weighed dish already holds every serving that is present, so
                        // "one, not three" has to take two thirds of it back off.
                        dishes[index] = dishes[index].scaled(toCount: count)
                        items = dishes.flatMap { $0.flattened() }
                        didEdit = true
                    },
                    onSize: { size in
                        guard let index = dishes.firstIndex(where: { $0.id == dish.id }) else { return }
                        dishes[index].size = size
                        items = dishes.flatMap { $0.flattened() }
                        didEdit = true
                    },
                    onRemove: {
                        let names = Set(dish.items.map(\.id))
                        items.removeAll { names.contains($0.id) }
                        didEdit = true
                    }
                )
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

                if !model.suggestedRecipes.isEmpty { dishesCard }

                Button("Add it by hand instead") { addByHand() }
                    .buttonStyle(WellieQuietButtonStyle())
                    .font(WellieTheme.font(15, weight: .semibold))
                    .padding(.top, 2)
            }
            .wellieColumn()
        }
    }

    /// The figure above the sentence, which has to be the one the meal will
    /// read once it is saved — the same inputs `PlateFigure.forMeal` will see
    /// for the `MealEntry` this screen writes.
    ///
    /// `items` is the flattened list and carries no nutrition panel, so a
    /// labelled drink read from it is worth its food group now and its label a
    /// tap later — a tester watched a Monster go from 2 g to 0 g on save. The
    /// share is applied for the same reason: it is applied after saving.
    /// Dishes are empty only for a meal typed by hand, which has no panels.
    private var figureForThisMeal: PlateFigure {
        dishes.isEmpty
            ? .protein(grams: model.protein(in: items) * share.factor)
            : model.figure(for: dishes, share: share)
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
            Text(hasFrequentlyLoggedDish ? "Or a dish you cook often" : "Or a dish you saved recently")
                .font(WellieTheme.font(15, weight: .bold))

            ForEach(model.suggestedRecipes) { recipe in
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

    private var hasFrequentlyLoggedDish: Bool {
        model.suggestedRecipes.contains { model.timesLogged($0) > 0 }
    }

    private func timesLoggedText(_ recipe: Recipe) -> String {
        let count = model.timesLogged(recipe)
        return count == 0 ? "Saved recently" : "Logged \(count) time\(count == 1 ? "" : "s")"
    }

    // MARK: - 2d · Reading

    private var reading: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                MealPhotoBanner(image: imageData.flatMap(UIImage.init(data:)))

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(chatter)
                            .font(WellieTheme.font(15, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                            .contentTransition(.opacity)
                            .animation(.easeInOut(duration: 0.28), value: chatter)
                            // The line changes under the reader; announcing
                            // every one would talk over them. VoiceOver hears
                            // the state once and the phrases stay decorative.
                            .accessibilityLabel("Reading your plate")
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
                .task { await runChatter() }
            }
            .wellieColumn()
        }
    }

    /// One line, not a text box.
    ///
    /// A field here puts a keyboard over the sentence it is asking about, and
    /// most meals need no correction at all — an open box asks every one of
    /// them a question. The row says a fix is possible and gets out of the way;
    /// the sheet is where the typing happens, over the top, with the sentence
    /// still in place behind it.
    private var fixRow: some View {
        Button { showingFix = true } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WellieTheme.ice)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(savedNote.isEmpty ? "Something wrong or missing?" : "What you told me")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    Text(
                        savedNote.isEmpty
                            ? "Say it in a sentence — everything else stays as you set it"
                            : savedNote
                    )
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Both inside the label, and in this order: applied outside the
            // button the card is only decoration around it, and the tap target
            // shrinks to the glyphs — a row-sized thing that answers to a
            // word-sized press.
            .wellieCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefining)
    }

    private var savedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs for as long as the reading card is on screen; SwiftUI cancels it
    /// when the stage changes, so nothing has to stop it.
    private func runChatter() async {
        var generator = SystemRandomNumberGenerator()
        for phrase in PlateChatter.order(using: &generator) {
            chatter = phrase
            try? await Task.sleep(for: .seconds(PlateChatter.interval))
            if Task.isCancelled { return }
        }
        // A read slow enough to exhaust the list holds on the last line. Going
        // back to the top would read as the app having started over.
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
                        // The reassurance first, because it is the question
                        // being asked; the reason second, because it is the
                        // one thing that tells you which route below to take.
                        WellieProse(
                            "The photo is saved, so nothing is lost. "
                                + (failure ?? "Something went wrong on the way there."),
                            size: 15
                        )
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
                            isTyping = true
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
                // With nothing on the list, typing is not a correction — it is
                // the only way food gets onto the meal at all, so it stays an
                // open field. Once there is a sentence to read, the correction
                // is a row: a keyboard over the thing you are checking is the
                // one layout that cannot work.
                if items.isEmpty {
                    noteCard(caption: "What you type is read into the list, and stays with the meal.")
                } else {
                    fixRow
                }
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(sentenceCardHeading)
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(isRefining ? WellieTheme.blue : WellieTheme.muted)
                Spacer(minLength: 0)
                if !items.isEmpty {
                    // Dimmed rather than blanked: the figure it is showing is
                    // still the true one for the list as it stands, and a
                    // number that vanishes reads as a number that was wrong.
                    Text(figureForThisMeal.text)
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                        .opacity(isRefining ? 0.4 : 1)
                        .fixedSize()
                }
            }

            if items.isEmpty {
                WellieProse("Say what you ate below and it counts the same as a photo would.")
            } else {
                FoodSentence(
                    lead: artifact == nil ? "You had" : "Looks like",
                    words: sentenceWords,
                    onTap: { tapWord($0) }
                )
            }

            // The fix is quoted back verbatim while it is being worked in, so
            // the wait is attached to the words that caused it. The promise
            // that nothing else moves is the reassurance worth repeating.
            if isRefining, !noteAtRecognition.isEmpty || hasNewNote {
                WellieCaption("Your fix: “\(fixInFlight)” — everything else stays as you set it.")
            } else if let question = openQuestion {
                uncertainty(question)
            }
        }
        .wellieCard()
        .animation(.easeInOut(duration: 0.2), value: isRefining)
    }

    private var sentenceCardHeading: String {
        if isRefining { return "Working your fix in…" }
        return items.isEmpty ? "Nothing on the list yet" : "Tap a word to change it"
    }

    private var fixInFlight: String {
        let typed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? noteAtRecognition : typed
    }

    /// A dish is one word — "2 plates of fried rice" — and its ingredients are
    /// behind it. Without dishes the sentence still reads food by food, which
    /// is every meal logged before this and everything added by hand.
    private var sentenceWords: [FoodSentence.Word] {
        var words: [FoodSentence.Word]
        if dishes.isEmpty {
            words = items.map { item in
                .init(
                    id: item.id,
                    text: FoodPhrase.word(for: item.group, label: item.label),
                    isUncertain: item.id == openQuestion?.id
                )
            }
        } else {
            words = FoodSentence.words(for: dishes, uncertain: openQuestion?.id)
        }
        // Everything already on the list keeps its place and its wording; the
        // ghost is appended, so the fix reads as an addition to a sentence you
        // still recognise rather than a sentence being rewritten.
        if isRefining { words.append(.init(id: Self.ghostWordID, text: "…", isPending: true)) }
        return words
    }

    /// Stable, so the ghost is one view being animated rather than a new view
    /// appearing on every redraw.
    private static let ghostWordID = UUID()

    private func tapWord(_ id: UUID) {
        if let dish = dishes.first(where: { $0.id == id }) {
            openDish = dish
        } else {
            editing = EditingFood(id: id)
        }
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
            // With nothing on the list this box is not an addendum, it is the
            // meal: typing is the only way food gets onto it. That covers a meal
            // entered by hand and a photograph that could not be read.
            Text(items.isEmpty ? "What did you eat?" : "Anything the photo can't show?")
                .font(WellieTheme.font(15, weight: .semibold))

            TextField(
                items.isEmpty
                    ? "Two eggs, toast, and a coffee…"
                    : "Fried in butter, two eggs in the batter…",
                text: $note,
                axis: .vertical
            )
                .font(WellieTheme.font(15, weight: .medium))
                .focused($isTyping)
                .lineLimit(1...4)
                .padding(14)
                .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            // A re-read only makes sense once the note says something the model
            // did not already have, and it applies a delta so hand edits stay.
            // No photograph is not a reason to withhold it — the words alone are
            // enough, and for a hand-entered meal they are the only input there
            // is going to be.
            if stage == .reviewing, hasNewNote {
                Button {
                    Task { await reread() }
                } label: {
                    if isRefining {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(
                            items.isEmpty ? "Put this on the list" : "Take this into account",
                            systemImage: "sparkles"
                        )
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
                    // Not "sharing": it used to promise a control that was not
                    // in the panel. Sharing is now folded into the one portion
                    // question, so the label names what is actually in there.
                    Text("Time & portions")
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
                    EatenAtRow(eatenAt: $eatenAt)

                    WellieRowDivider()

                    // One question, not two. "How much did you eat" and "did
                    // you share it" are the same fact asked twice — what
                    // fraction of the plate was yours — and answering both
                    // invites answering them inconsistently.
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("How much was yours?")
                                .font(WellieTheme.font(15.5, weight: .semibold))
                            Text("Covers sharing too — half a shared bowl counts half")
                                .font(WellieTheme.font(13, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
            // Disabled for the few seconds a fix is being worked in, and for
            // no other reason: saving mid-revision would store a list the
            // person has already told the app is wrong.
            Button(saveTitle) { Task { await save() } }
                .buttonStyle(WelliePrimaryButtonStyle(enabled: !items.isEmpty && !isRefining))
                .disabled(items.isEmpty || isRefining)
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
        dishes = []
        artifact = nil
        answeredQuestions = []
        didEdit = false
        if model.hasAcceptedPhotoProcessing {
            Task { await recognize(normalized) }
        } else {
            pendingConsentImage = normalized
            showingPhotoConsent = true
        }
    }

    private func recognize(_ data: Data) async {
        stage = .reading
        failure = nil
        let sent = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await model.recognize(imageData: data, note: sent.isEmpty ? nil : sent)
            artifact = result
            dishes = result.recognition.asMealDishes() ?? []
            items = dishes.isEmpty ? result.recognition.asMealItems() : dishes.flatMap { $0.flattened() }
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
            dishes = MealDish.regrouped(items, keeping: dishes)
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
        isTyping = true
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

        // One writer for both representations, so they cannot disagree.
        let saved = dishes.isEmpty ? [] : MealDish.regrouped(items, keeping: dishes)
        let meal = MealEntry(
            eatenAt: eatenAt.epochMillis,
            items: saved.isEmpty ? items : saved.flatMap { $0.flattened() },
            source: source,
            photoHash: imageData.flatMap { PhotoStore.shared.store($0) },
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            recognitionEvidence: evidence,
            share: share,
            wasCorrected: artifact != nil && didEdit,
            recipeID: sourceRecipeID,
            storedDishes: saved.isEmpty ? nil : saved
        )
        await model.logMeal(meal)
        // Logging a saved dish bumps it up the list for next time.
        if let sourceRecipeID, let recipe = model.recipes.first(where: { $0.id == sourceRecipeID }) {
            await model.saveRecipe(recipe)
        }
        dismiss()
    }
}

/// Explicit permission before the first photo leaves the phone. This is kept
/// separate from camera authorization: access to a sensor is not consent to
/// cloud storage or disclosure to a third-party AI provider.
private struct PhotoProcessingConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Before this photo is read")
                        .font(WellieTheme.font(26, weight: .bold))
                    WellieProse(
                        "eatsome will store the 2048-pixel meal image in its private Cloudflare R2 bucket and send it to \(model.provider.displayName) to identify foods.",
                        size: 16
                    )
                    VStack(alignment: .leading, spacing: 12) {
                        consentPoint("Stored for retries", "The private cloud copy lets you retry recognition without uploading again.")
                        consentPoint("Kept to this phone", "The cloud copy is filed under this install's own id, so no other tester's app can reach it.")
                        consentPoint("Delete whenever you want", "Deleting a meal removes its cloud copy when no other meal uses it; Settings can erase all cloud data and withdraw consent.")
                        consentPoint("Research use is separate", "eatsome does not add the image to its research corpus unless you separately opt in.")
                    }
                    .wellieCard(color: WellieTheme.ice)
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Agree and send this photo") {
                        onAgree()
                        dismiss()
                    }
                    .buttonStyle(WelliePrimaryButtonStyle())
                    Button("Not now") {
                        onCancel()
                        dismiss()
                    }
                    .buttonStyle(WellieQuietButtonStyle())
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 12)
                .background(WellieTheme.background)
            }
        }
        .interactiveDismissDisabled()
        .wellieScreen()
    }

    private func consentPoint(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(WellieTheme.font(15.5, weight: .bold))
            Text(detail)
                .font(WellieTheme.font(13.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
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
/// The date as a word where there is one. "Aug 6, 2026" is how a database
/// writes today; nobody back-logs a meal by ISO date, and the system picker's
/// own label cannot be changed — hence the pill and the popover behind it.
struct EatenAtRow: View {
    @Binding var eatenAt: Date

    @State private var showingDay = false
    @State private var showingTime = false

    var body: some View {
        HStack(spacing: 8) {
            Text("Eaten")
                .font(WellieTheme.font(15.5, weight: .semibold))
            Spacer(minLength: 8)

            // Both pills are ours. Leaving the time to the system picker meant
            // two badges side by side in two different fills and two different
            // corner radii, because a compact `DatePicker` styles itself and
            // will not be told otherwise.
            pill(DayFormat.title(eatenAt)) { showingDay = true }
                .popover(isPresented: $showingDay) {
                    // A graphical picker given no width is squeezed to whatever
                    // the popover guesses, which clipped the month header to
                    // "026 >". It needs about this much.
                    DatePicker("", selection: $eatenAt, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .frame(width: 320)
                        .padding(10)
                        .presentationCompactAdaptation(.popover)
                }

            pill(eatenAt.formatted(date: .omitted, time: .shortened)) { showingTime = true }
                .popover(isPresented: $showingTime) {
                    DatePicker("", selection: $eatenAt, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(width: 260, height: 180)
                        .padding(.horizontal, 10)
                        .presentationCompactAdaptation(.popover)
                }
        }
    }

    private func pill(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(WellieTheme.ice, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct ShareChips: View {
    @Binding var share: MealShare

    var body: some View {
        // Equal thirds rather than intrinsic widths: three chips sized to their
        // own text leave a ragged row, and the widest of them is the one that
        // wraps first when the type size goes up.
        HStack(spacing: 12) {
            ForEach(MealShare.allCases, id: \.self) { value in
                Button { share = value } label: {
                    WellieChip(
                        text: value.chipName,
                        style: share == value ? .selected : .soft,
                        size: 14.5,
                        fills: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
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
