import PhotosUI
import ShamanCore
import SwiftUI

struct MealCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var artifact: RecognitionArtifact?
    @State private var items: [MealReviewItem] = []
    @State private var eatenAt = Date()
    @State private var share = MealShare.whole
    @State private var isRecognizing = false
    @State private var error: String?
    @State private var showingCamera = false
    @State private var otherMealsBelongToUser: Bool?
    @State private var didEditRecognition = false
    /// What the photograph cannot show. Typed before recognition when you know
    /// the dish hides things, or added afterwards to re-read the same photo.
    @State private var note = ""
    @State private var fixText = ""
    @State private var isRefining = false
    @State private var revisionSummary: String?
    @State private var fixError: String?
    /// Rows the last correction touched, highlighted briefly so a delta is
    /// visible without rescanning the list.
    @State private var recentlyChanged: Set<UUID> = []
    @State private var showingDetails = false
    @State private var recipeName = ""
    @State private var savedRecipeID: UUID?
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if items.isEmpty && imageData == nil && !isRecognizing {
                        sourcePicker
                    } else {
                        review
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 32)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { isTyping = false })
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if !items.isEmpty { saveBar }
            }
            .navigationTitle("EATSOME")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPhotoPicker { data in setPhoto(data) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        error = "That photo could not be opened."
                        return
                    }
                    setPhoto(data)
                }
            }
        }
        .wellieScreen()
    }

    private var sourcePicker: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("What did you eat?")
                    .font(WellieTheme.font(30, weight: .bold))
                Text("Take a photo for recognition, choose one from your library, or add food groups manually.")
                    .font(WellieTheme.font(16, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 18)

            Image(systemName: "camera.viewfinder")
                .font(.system(size: 58, weight: .medium, design: .rounded))
                .foregroundStyle(WellieTheme.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(WellieTheme.ice, in: RoundedRectangle(cornerRadius: 30, style: .continuous))

            Button {
                showingCamera = true
            } label: {
                Label("Take a photo", systemImage: "camera.fill")
            }
            .buttonStyle(WelliePrimaryButtonStyle())

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .font(WellieTheme.font(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(WellieTheme.blue)
                    .background(WellieTheme.softBlue, in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius))
            }

            Menu {
                ForEach(FoodGroup.allCases, id: \.self) { group in
                    Button(group.displayName) { items.append(MealReviewItem(manualGroup: group)) }
                }
            } label: {
                Label("Add manually", systemImage: "plus.circle")
                    .font(WellieTheme.font(16, weight: .semibold))
            }

            if !model.recipes.isEmpty { recipesCard }

            DatePicker("Eaten at", selection: $eatenAt)
                .font(WellieTheme.font(15, weight: .medium))
                .wellieCard(color: WellieTheme.card)
        }
    }

    /// Home cooking repeats, and it is the food a camera reads worst. Describe
    /// the dish once and every later log of it starts complete.
    private var recipesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieKicker(text: "Your recipes")

            ForEach(model.recipes.prefix(6)) { recipe in
                Button {
                    load(recipe)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.name)
                                .font(WellieTheme.font(15, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                            Text(recipe.items.prefix(4).map(\.group.displayName).joined(separator: " · "))
                                .font(WellieTheme.font(12, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left.circle.fill")
                            .foregroundStyle(WellieTheme.blue)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete recipe", systemImage: "trash", role: .destructive) {
                        Task { await model.deleteRecipe(recipe) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieCard(color: WellieTheme.card)
    }

    /// Three zones, in the order the data actually flows: what went to the model,
    /// what came back, and the settings you almost never touch.
    ///
    /// It used to be ten cards, each with its own background and padding, with
    /// the correction field below the list it corrects — so typing raised a
    /// keyboard over the very rows you were describing — and no visible save
    /// button at all.
    private var review: some View {
        VStack(spacing: 18) {
            photoHeader

            if isRecognizing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Finding Mediterranean food groups…")
                        .font(WellieTheme.font(15, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .wellieCard(color: WellieTheme.ice)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(WellieTheme.font(14, weight: .medium))
                    .foregroundStyle(WellieTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wellieCard(color: WellieTheme.danger.opacity(0.12))
            }

            if !items.isEmpty {
                if unconfirmedCount > 0 { confirmationBanner }
                if artifact?.recognition.otherMealsVisible == true { otherMealsWarning }

                // The input sits between the photo and the list because it edits
                // both, and above the list because the keyboard must not cover
                // the thing you are describing.
                if artifact != nil { fixCard }

                groupsCard

                detailsSection
            } else if !isRecognizing {
                Menu {
                    ForEach(FoodGroup.allCases, id: \.self) { group in
                        Button(group.displayName) { items.append(MealReviewItem(manualGroup: group)) }
                    }
                } label: {
                    Label("Add food group manually", systemImage: "plus")
                        .font(WellieTheme.font(16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(WellieTheme.softBlue, in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius))
                }
            }
        }
    }

    /// The photo fills its frame rather than fitting inside it: a portrait shot
    /// letterboxed into a landscape box spends two thirds of the width on empty
    /// background. Same pixels, three times the picture.
    ///
    /// The heading is the dish, not an instruction. "Check if everything is
    /// right" is read once in a lifetime and then costs three lines forever.
    private var photoHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            if !items.isEmpty {
                Text(recognitionSummary)
                    .font(WellieTheme.font(22, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isRecognizing {
                Text("Reading your plate")
                    .font(WellieTheme.font(22, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var confirmationBanner: some View {
        Label(
            unconfirmedCount == 1
                ? "One item below needs a tap — it changes your weekly score."
                : "\(unconfirmedCount) items below need a tap — they change your weekly score.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(WellieTheme.font(13, weight: .semibold))
        .foregroundStyle(WellieTheme.warningText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieCard(color: WellieTheme.warning.opacity(0.18))
    }

    private var groupsCard: some View {
        VStack(spacing: 0) {
            WellieKicker(text: "Food groups")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            ForEach($items) { $item in
                MealRecognitionEditorRow(
                    item: $item,
                    isNew: recentlyChanged.contains(item.id),
                    onEdit: { didEditRecognition = true },
                    onDelete: {
                        didEditRecognition = true
                        items.removeAll { $0.id == item.id }
                    }
                )
                if item.id != items.last?.id { Divider() }
            }

            Menu {
                ForEach(FoodGroup.allCases, id: \.self) { group in
                    Button(group.displayName) {
                        didEditRecognition = true
                        items.append(MealReviewItem(manualGroup: group))
                    }
                }
            } label: {
                Label("Add food group", systemImage: "plus")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .padding(.top, 12)
            }
        }
        .wellieCard(color: WellieTheme.card)
    }

    /// Everything you do not change on an ordinary log, folded away. Time is
    /// already right, the plate is usually all yours, and most meals are not
    /// worth saving as a recipe.
    private var detailsSection: some View {
        DisclosureGroup(isExpanded: $showingDetails) {
            VStack(spacing: 16) {
                shareCard
                DatePicker("Eaten at", selection: $eatenAt)
                    .font(WellieTheme.font(15, weight: .medium))
                saveRecipeCard

                if let notes = artifact?.recognition.notes {
                    Text(notes)
                        .font(WellieTheme.font(12, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Details")
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
        }
        .tint(WellieTheme.blue)
        .wellieCard(color: WellieTheme.card)
    }

    /// Pinned, so the one action the screen exists for is never a scroll away.
    private var saveBar: some View {
        Button("Save meal") { Task { await save() } }
            .buttonStyle(WelliePrimaryButtonStyle())
            .disabled(!canSave)
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.bar)
    }

    /// The one text slot, and it lives after the result rather than before it.
    ///
    /// A field before sending asks you to predict what the model will get wrong,
    /// which you cannot do; the one case that seemed to need it — ingredients no
    /// photograph can show — is just as visible once the list is in front of you,
    /// because you cooked the thing. And a saved recipe removes even that on the
    /// second telling.
    ///
    /// It asks for a delta rather than a re-run: by this point you may have fixed
    /// groups and portions by hand, and regenerating the list would throw that
    /// work away.
    private var fixCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            WellieKicker(text: "Missing or wrong?")

            TextField("The toast is missing the eggs and butter", text: $fixText, axis: .vertical)
                .font(WellieTheme.font(15, weight: .medium))
                .focused($isTyping)
                .lineLimit(1...3)
                .padding(12)
                .background(WellieTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let revisionSummary {
                Label(revisionSummary, systemImage: "checkmark.circle.fill")
                    .font(WellieTheme.font(12, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
            }
            if let fixError {
                Text(fixError)
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.danger)
            }

            Button {
                Task { await applyFix() }
            } label: {
                if isRefining {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Update the list", systemImage: "sparkles")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(WellieSecondaryButtonStyle())
            .disabled(fixText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRefining)

            Text("Your other edits are kept — only what you describe changes.")
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
        .wellieCard(color: WellieTheme.card)
    }

    private var saveRecipeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(WellieTheme.blue)
                TextField("Save as a recipe (name it)", text: $recipeName)
                    .font(WellieTheme.font(15, weight: .medium))
                    .focused($isTyping)
                    .submitLabel(.done)
                Button("Save") { saveAsRecipe() }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .disabled(recipeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
            .background(WellieTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(
                savedRecipeID == nil
                    ? "Home cooking repeats. Save it once and the hidden ingredients come back with it."
                    : "Saved. It will be waiting on the first screen next time."
            )
            .font(WellieTheme.font(12, weight: .medium))
            .foregroundStyle(savedRecipeID == nil ? WellieTheme.muted : WellieTheme.blue)
        }
        .wellieCard(color: WellieTheme.card)
    }

    /// A photograph shows the dish, not your serving. A shared platter counted
    /// whole is the single largest way this app can overstate a week.
    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("How much did you eat?", selection: $share) {
                ForEach(MealShare.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(
                share == .whole
                    ? "The whole plate counts toward your week."
                    : "Counted as half — for shared plates and platters."
            )
            .font(WellieTheme.font(12, weight: .medium))
            .foregroundStyle(WellieTheme.muted)
        }
        .wellieCard(color: WellieTheme.card)
    }

    private var otherMealsWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("There’s other food in the frame", systemImage: "exclamationmark.bubble.fill")
                .font(WellieTheme.font(16, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)

            Text("Only the tray closest to the camera was included. Is the other food yours?")
                .font(WellieTheme.font(14, weight: .medium))
                .foregroundStyle(WellieTheme.muted)

            HStack {
                Button("No") { otherMealsBelongToUser = false }
                    .buttonStyle(.bordered)
                    .tint(otherMealsBelongToUser == false ? WellieTheme.blue : WellieTheme.muted)
                // Yes re-reads the photograph with the restriction lifted. The
                // picture already contains those plates; asking you to type out
                // what is visibly in frame is work the model should be doing.
                Button("Yes, all of it") { Task { await includeEverything() } }
                    .buttonStyle(.bordered)
                    .tint(otherMealsBelongToUser == true ? WellieTheme.blue : WellieTheme.muted)
            }

            if otherMealsBelongToUser == true {
                Text("Read again with every plate included.")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieCard(color: WellieTheme.warning.opacity(0.18))
    }

    private var recognitionSummary: String {
        let labels = items.compactMap(\.label).filter { !$0.isEmpty }
        if !labels.isEmpty { return labels.prefix(4).joined(separator: ", ") }
        return items.prefix(4).map(\.group.displayName).joined(separator: ", ")
    }

    private var unconfirmedCount: Int {
        items.count { $0.needsConfirmation }
    }

    private var canSave: Bool {
        !items.isEmpty
            && !isRecognizing
            && unconfirmedCount == 0
            && (artifact?.recognition.otherMealsVisible != true || otherMealsBelongToUser != nil)
    }

    private func setPhoto(_ originalData: Data) {
        let normalized = UIImage(data: originalData)?.jpegData(compressionQuality: 0.82) ?? originalData
        imageData = normalized
        otherMealsBelongToUser = nil
        didEditRecognition = false
        Task { await recognize(normalized) }
    }

    /// Re-reads the same photo with the closest-tray rule lifted, through the
    /// same note slot everything else uses.
    private func includeEverything() async {
        guard let imageData else { return }
        otherMealsBelongToUser = true
        note = [trimmed(note), MealPrompt.everythingIsMine]
            .compactMap { $0 }
            .joined(separator: " ")
        await recognize(imageData)
    }

    private func recognize(_ data: Data) async {
        isRecognizing = true
        error = nil
        artifact = nil
        items = []
        defer { isRecognizing = false }
        do {
            let result = try await model.recognize(imageData: data, note: trimmed(note))
            artifact = result
            let excluded = model.config.medas.excludedItems
            items = result.recognition.items.map {
                MealReviewItem(recognized: $0, excludedMedasItems: excluded)
            }
            if recipeName.isEmpty {
                recipeName = Recipe.suggestedName(for: items.map(\.mealItem))
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sends the list as it stands now — including everything you corrected by
    /// hand — and applies only the delta that comes back.
    private func applyFix() async {
        let text = fixText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isTyping = false
        isRefining = true
        fixError = nil
        revisionSummary = nil
        defer { isRefining = false }

        do {
            let before = items.map(\.mealItem)
            let revision = try await model.refine(imageData: imageData, current: before, note: text)
            let after = revision.applied(to: before)

            // What actually moved, by identity: added rows are ids the previous
            // list never had, changed rows kept theirs. Pressing the button and
            // then hunting for the difference is not feedback.
            let previous = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
            let touched = after.filter { item in
                guard let old = previous[item.id] else { return true }
                return old.group != item.group || old.portion != item.portion
            }

            let excluded = model.config.medas.excludedItems
            items = after.map { MealReviewItem(corrected: $0, excludedMedasItems: excluded) }
            recentlyChanged = Set(touched.map(\.id))
            revisionSummary = revision.summary
            didEditRecognition = true

            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { recentlyChanged = [] }
            }
            // The note is the durable half: it travels with the meal and into
            // the recipe, so the next log of this dish starts complete.
            note = [trimmed(note), text].compactMap { $0 }.joined(separator: ". ")
            fixText = ""
        } catch {
            fixError = error.localizedDescription
        }
    }

    private func load(_ recipe: Recipe) {
        let excluded = model.config.medas.excludedItems
        items = recipe.items.map { MealReviewItem(corrected: $0, excludedMedasItems: excluded) }
        note = recipe.note ?? ""
        recipeName = recipe.name
        savedRecipeID = recipe.id
        didEditRecognition = false
    }

    private func saveAsRecipe() {
        let name = recipeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isTyping = false
        let recipe = Recipe(
            id: savedRecipeID ?? UUIDv7.generate(),
            name: name,
            items: items.map(\.mealItem),
            note: trimmed(note)
        )
        savedRecipeID = recipe.id
        Task { await model.saveRecipe(recipe) }
    }

    private func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func save() async {
        let finalItems = items.map(\.mealItem)
        let recognitionEvidence = artifact.map {
            MealRecognitionEvidence(
                promptVersion: $0.promptVersion,
                rawModelJSON: $0.rawModelJSON,
                initialItems: $0.recognition.asMealItems(),
                otherMealsVisible: $0.recognition.otherMealsVisible
            )
        }
        let source: MealSource = imageData != nil ? .photo : (savedRecipeID != nil ? .recipe : .manual)
        let meal = MealEntry(
            eatenAt: eatenAt.epochMillis,
            items: finalItems,
            source: source,
            // Writing the photo is what makes the hash worth carrying: the meal
            // list can show the food instead of a camera glyph.
            photoHash: imageData.flatMap { PhotoStore.shared.store($0) },
            note: trimmed(note),
            recognitionEvidence: recognitionEvidence,
            share: share,
            wasCorrected: artifact != nil && didEditRecognition
        )
        await model.logMeal(meal)
        // Logging a saved recipe bumps it up the list for next time.
        if let savedRecipeID, let recipe = model.recipes.first(where: { $0.id == savedRecipeID }) {
            await model.saveRecipe(recipe)
        }
        dismiss()
    }

    private func resetCapture() {
        pickerItem = nil
        imageData = nil
        artifact = nil
        items = []
        error = nil
        otherMealsBelongToUser = nil
        didEditRecognition = false
    }
}

private struct MealReviewItem: Identifiable {
    let id: UUID
    let label: String?
    /// What the model answered, before you touched it.
    let suggestedGroup: FoodGroup?
    /// The model's own shortlist of rivals for this item, most likely first.
    let alternatives: [FoodGroup]
    /// The subset of those rivals that would move the MEDAS score in a
    /// different direction. Only these are worth stopping you for.
    let contestedAlternatives: [FoodGroup]
    /// Always populated: the model's answer is prefilled, never left to you.
    var group: FoodGroup
    var portion: Portion
    var isConfirmed: Bool

    init(recognized item: MealRecognition.Item, excludedMedasItems: Set<Int>) {
        id = UUID()
        label = item.label
        suggestedGroup = item.group
        alternatives = Array(
            item.alternatives.filter { $0 != item.group }.prefix(MealPrompt.maxAlternatives)
        )
        contestedAlternatives = item.scoreCriticalAlternatives(excludedItems: excludedMedasItems)
        group = item.group
        portion = item.portion
        isConfirmed = false
    }

    init(manualGroup: FoodGroup) {
        id = UUID()
        label = nil
        suggestedGroup = nil
        alternatives = []
        contestedAlternatives = []
        group = manualGroup
        portion = .medium
        isConfirmed = true
    }

    /// A row that already exists — from a recipe, or from a delta the model just
    /// applied. Its alternatives are still worth showing, but nothing here is
    /// awaiting a first confirmation.
    init(corrected item: MealItem, excludedMedasItems: Set<Int>) {
        // Keeps the stored item's identity so a correction can be shown as a
        // difference from the list that preceded it.
        id = item.id
        label = item.label
        suggestedGroup = item.group
        alternatives = item.modelAlternatives ?? []
        contestedAlternatives = (item.modelAlternatives ?? []).filter {
            Medas.choiceChangesScore(item.group, $0, excludedItems: excludedMedasItems)
        }
        group = item.group
        portion = item.portion
        isConfirmed = true
    }

    /// One tap is owed here: the model named a rival that scores differently,
    /// and guessing wrong bends the week in the wrong direction.
    var needsConfirmation: Bool { !contestedAlternatives.isEmpty && !isConfirmed }

    /// The one-tap choices for this row — the model's answer first, then its
    /// shortlist. The full picker stays available for everything else.
    var choices: [FoodGroup] {
        guard let suggestedGroup else { return [] }
        return [suggestedGroup] + alternatives
    }

    var mealItem: MealItem {
        MealItem(
            group: group,
            portion: portion,
            label: label,
            // Once you have overruled the model, its shortlist was for a
            // different question and should not be stored as evidence here.
            modelAlternatives: group == suggestedGroup ? alternatives : nil
        )
    }
}

private struct MealRecognitionEditorRow: View {
    @Binding var item: MealReviewItem
    var isNew = false
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Menu {
                    ForEach(orderedGroups, id: \.self) { group in
                        Button(group.displayName) { select(group) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label ?? item.group.displayName)
                                .font(WellieTheme.font(16, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)

                            HStack(spacing: 5) {
                                Text(item.group.displayName)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .font(WellieTheme.font(13, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.label ?? "food item")")
            }

            if !item.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if item.needsConfirmation {
                        Label(confirmationPrompt, systemImage: "exclamationmark.triangle.fill")
                            .font(WellieTheme.font(12, weight: .semibold))
                            .foregroundStyle(WellieTheme.warningText)
                    } else if !item.isConfirmed {
                        Text("Could also be")
                            .font(WellieTheme.font(12, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                    }

                    FlowLayout {
                        ForEach(item.choices, id: \.self) { group in
                            choiceChip(group)
                        }
                    }
                }
            }

            Picker(
                "Portion",
                selection: Binding(
                    get: { item.portion },
                    set: {
                        item.portion = $0
                        onEdit()
                    }
                )
            ) {
                Text("Small").tag(Portion.small)
                Text("Medium").tag(Portion.medium)
                Text("Large").tag(Portion.large)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, item.needsConfirmation || isNew ? 10 : 0)
        .background(rowTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.easeOut(duration: 0.25), value: isNew)
    }

    private var rowTint: Color {
        if isNew { return WellieTheme.blue.opacity(0.14) }
        if item.needsConfirmation { return WellieTheme.warning.opacity(0.12) }
        return .clear
    }

    private var confirmationPrompt: String {
        let rivals = item.contestedAlternatives.map(\.displayName).joined(separator: " or ")
        return "Check this one — \(rivals) would score differently"
    }

    private func choiceChip(_ group: FoodGroup) -> some View {
        let isSelected = group == item.group
        return Button {
            select(group)
        } label: {
            Text(group.displayName)
                .font(WellieTheme.font(13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? WellieTheme.onAccent : WellieTheme.blue)
                .background(isSelected ? WellieTheme.blue : WellieTheme.softBlue, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Tapping the group already shown is a confirmation, not an edit: the
    /// saved meal is still exactly what the model produced.
    private func select(_ group: FoodGroup) {
        if item.group != group {
            item.group = group
            onEdit()
        }
        item.isConfirmed = true
    }

    private var orderedGroups: [FoodGroup] {
        let likely = item.choices.isEmpty ? item.group.commonlyConfusedWith : item.choices
        return likely + FoodGroup.allCases.filter { !likely.contains($0) }
    }
}

struct MealItemEditorRow: View {
    @Binding var item: MealItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(orderedGroups, id: \.self) { group in
                        Button(group.displayName) {
                            if item.group != group { item.modelAlternatives = nil }
                            item.group = group
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label ?? item.group.displayName)
                                .font(WellieTheme.font(16, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                            HStack(spacing: 5) {
                                Text(item.group.displayName)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .font(WellieTheme.font(12, weight: .semibold))
                            .foregroundStyle(WellieTheme.blue)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Picker("Portion", selection: $item.portion) {
                Text("Small").tag(Portion.small)
                Text("Medium").tag(Portion.medium)
                Text("Large").tag(Portion.large)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 10)
    }

    /// What the model said this could have been comes first; failing that, the
    /// groups it habitually confuses.
    private var orderedGroups: [FoodGroup] {
        var likely = [item.group] + (item.modelAlternatives ?? [])
        if likely.count == 1 { likely = item.group.commonlyConfusedWith }
        var seen = Set<FoodGroup>()
        let deduped = likely.filter { seen.insert($0).inserted }
        return deduped + FoodGroup.allCases.filter { !deduped.contains($0) }
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
