import PhotosUI
import ShamanCore
import SwiftUI

/// Screens `7a`–`7e`. The thread, which is now the app's home.
///
/// Logging is a conversation. You say what you ate — typed, spoken,
/// photographed, or pulled from your own repeats — and send it. Each message is
/// read in the background and becomes a meal card in the same thread, and the
/// composer never waits: the 11 am photo goes up while breakfast is still being
/// read.
///
/// This replaced the Today feed and the tab bar's camera button. The camera
/// stopped being a destination because the composer is always on screen, and a
/// button that opens a screen you then have to come back from is a worse camera
/// than one that is already there. The day's glance survives as the pinned strip
/// above the thread; `My week` is unchanged.
struct LogThreadView: View {
    @Environment(AppModel.self) private var model

    @State private var draft = ""
    /// A photo waiting for its caption.
    ///
    /// It does not send on capture. `7a`'s protein carton goes up as "2 of this
    /// at 11 am" — the words are what makes a photograph of a label into a meal
    /// of a known size, and there is no moment to type them if the shutter is
    /// also the send button. It sits above the composer with an × until you send
    /// it, captioned or not.
    @State private var pendingPhoto: Data?
    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingSettings = false
    @State private var showingDay = false
    @State private var openMeal: MealEntry?
    /// Held while the consent screen is up, so agreeing sends the thing that
    /// prompted it rather than making anyone type it twice.
    @State private var awaitingConsent: Outgoing?
    @State private var voice = VoiceDictation()
    @FocusState private var isTyping: Bool

    private struct Outgoing {
        var said: String?
        var photo: Data?
    }

    private var turns: [ThreadTurn] { model.thread }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.mealsToday().isEmpty { pinnedStrip }
                thread
            }
            .background(WellieTheme.background)
            .navigationTitle("eatsome")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MyWeekView() } label: {
                        Text("My week").font(WellieTheme.font(16, weight: .semibold))
                    }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDay) { DaySheet(day: Date()) }
            .sheet(isPresented: $showingCamera) { CameraPhotoPicker { attach($0) } }
            .sheet(item: $openMeal) { meal in
                NavigationStack { MealDetailView(meal: meal) }
            }
            .sheet(isPresented: consentIsUp) {
                SendConsentView(includesPhoto: awaitingConsent?.photo != nil) {
                    model.acceptPhotoProcessing()
                    if let outgoing = awaitingConsent {
                        awaitingConsent = nil
                        Task { await model.send(said: outgoing.said, photo: outgoing.photo) }
                    }
                } onCancel: {
                    // Nothing is thrown away for declining. The message goes
                    // back into the composer exactly as it was, so agreeing
                    // later is one tap rather than typing it again.
                    if let outgoing = awaitingConsent {
                        if draft.isEmpty, let said = outgoing.said { draft = said }
                        if pendingPhoto == nil { pendingPhoto = outgoing.photo }
                    }
                    awaitingConsent = nil
                }
            }
            .task { voice.configure(model.voiceKeySource) }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { attach(data) }
                    pickerItem = nil
                }
            }
        }
        .wellieScreen()
    }

    private var consentIsUp: Binding<Bool> {
        Binding(get: { awaitingConsent != nil }, set: { if !$0 { awaitingConsent = nil } })
    }

    // MARK: - 7a · The pinned strip

    /// The day's glance, and the only thing above the thread.
    ///
    /// Absent entirely before the first meal — there is nothing to glance at,
    /// and a strip reading "no meals, no olives" is a scolding where a blank is
    /// simply the truth. Tapping it opens `7f`.
    private var pinnedStrip: some View {
        let meals = model.mealsToday()
        return Button { showingDay = true } label: {
            HStack(spacing: 12) {
                Text("Today so far · \(Count.meals(meals.count).lowercased())")
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
                Spacer(minLength: 8)
                if let olives = model.olives() { OliveRow(olives: olives.olives) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WellieTheme.faint)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(WellieTheme.ice)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WellieTheme.hairline).frame(height: 0.5)
        }
    }

    // MARK: - The thread

    private var thread: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if turns.isEmpty {
                        FirstOpenHint().padding(.top, 24)
                    } else {
                        Text("Today")
                            .font(WellieTheme.font(12.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(WellieTheme.ice, in: Capsule())
                            .padding(.top, 8)

                        ForEach(turns) { turn in
                            TurnRow(turn: turn, state: state(of: turn)) { openMeal = turn.meal }
                                retry: { if let message = turn.message { model.retry(message) } }
                                delete: { Task { await model.deleteTurn(turn) } }
                        }
                    }
                    // Anchored so a new message scrolls the thread rather than
                    // the last card, which would leave the bubble half off-screen.
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: turns.count) { _, _ in scrollToBottom(scroller) }
            .onChange(of: model.isReadingAnything) { _, _ in scrollToBottom(scroller) }
            .onAppear { scroller.scrollTo(Self.bottom, anchor: .bottom) }
        }
    }

    private static let bottom = "thread-bottom"

    private func scrollToBottom(_ scroller: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            scroller.scrollTo(Self.bottom, anchor: .bottom)
        }
    }

    private func state(of turn: ThreadTurn) -> LogMessageState {
        guard let message = turn.message else {
            return turn.meal.map { .logged(mealID: $0.id) } ?? .sent
        }
        return model.state(of: message)
    }

    // MARK: - 7d · The composer

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            if voice.isRecording {
                VoiceComposer(voice: voice) { heard in
                    // Voice sends as text: what the transcriber heard is what
                    // gets parsed, so a wrong word is fixed before it goes.
                    draft = heard
                    isTyping = true
                }
            } else {
                if let photo = pendingPhoto { attachment(photo) }
                if isTyping && pendingPhoto == nil { dishChips }
                typingRow
            }
        }
        .background(.bar)
    }

    private func attachment(_ data: Data) -> some View {
        HStack(spacing: 11) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("Add a note, or just send it.")
                .font(WellieTheme.font(13.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
            Spacer(minLength: 0)
            Button { pendingPhoto = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 19))
                    .foregroundStyle(WellieTheme.faint)
            }
            .accessibilityLabel("Remove the photo")
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.top, 10)
    }

    private var dishChips: some View {
        let chips = model.dishSuggestions(typed: draft)
        return Group {
            if chips.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button {
                                // The dish goes into the field rather than
                                // straight into the log: "lentil soup" is often
                                // about to become "lentil soup, small bowl".
                                draft = chip.name
                            } label: {
                                WellieChip(
                                    text: chip.timesLogged > 1
                                        ? "\(chip.name.capitalizedFirst) ×\(chip.timesLogged)"
                                        : chip.name.capitalizedFirst
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.vertical, 9)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var typingRow: some View {
        HStack(spacing: 10) {
            Button { showingCamera = true } label: {
                Image(systemName: "camera.fill").font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(WellieTheme.blue)
            .accessibilityLabel("Take a photo")

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.fill").font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(WellieTheme.blue)
            .accessibilityLabel("Choose a photo")

            TextField("What did you eat?", text: $draft, axis: .vertical)
                .font(WellieTheme.font(16, weight: .medium))
                .focused($isTyping)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(WellieTheme.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(
                        isTyping ? WellieTheme.blue : WellieTheme.outline, lineWidth: 1.5
                    )
                }

            sendOrTalk
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.vertical, 9)
    }

    /// One button doing the two jobs a chat's right-hand button always does.
    /// Empty field: talk. Anything typed: send. That keeps all four inputs —
    /// camera, library, keyboard, mic — without a fifth control on a row that
    /// already has to fit a text field.
    @ViewBuilder
    private var sendOrTalk: some View {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingPhoto == nil {
            Button { voice.start() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(voice.isAvailable ? WellieTheme.blue : WellieTheme.faint)
                    .frame(width: 36, height: 36)
                    .background(WellieTheme.ice, in: Circle())
            }
            .disabled(!voice.isAvailable)
            .accessibilityLabel("Say what you ate")
        } else {
            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WellieTheme.onAccent)
                    .frame(width: 36, height: 36)
                    .background(WellieTheme.blue, in: Circle())
            }
            .accessibilityLabel("Send")
        }
    }

    // MARK: - Sending

    private func sendDraft() {
        let said = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = pendingPhoto
        guard !said.isEmpty || photo != nil else { return }
        draft = ""
        pendingPhoto = nil
        dispatch(Outgoing(said: said.isEmpty ? nil : said, photo: photo))
    }

    /// A captured or chosen photo waits in the composer rather than going
    /// straight up. Anything already typed stays where it is and becomes the
    /// caption when you send.
    private func attach(_ data: Data) {
        pendingPhoto = data
        isTyping = true
    }

    private func dispatch(_ outgoing: Outgoing) {
        guard model.hasAcceptedPhotoProcessing else {
            awaitingConsent = outgoing
            return
        }
        Task { await model.send(said: outgoing.said, photo: outgoing.photo) }
    }
}

// MARK: - 7c · One message, four states

/// One exchange: the bubble, and whatever the app has made of it so far.
private struct TurnRow: View {
    let turn: ThreadTurn
    let state: LogMessageState
    let open: () -> Void
    let retry: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = turn.message, !message.isEmpty {
                MessageBubble(message: message, isPending: isPending)
            }

            switch state {
            case .sent, .reading:
                ReadingPill(hasStarted: isReading)
            case .logged:
                if let meal = turn.meal {
                    ThreadMealCard(meal: meal, open: open)
                }
            case .failed(let reason):
                FailedPill(reason: reason, retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive, action: delete)
        }
    }

    private var isReading: Bool {
        if case .reading = state { return true }
        return false
    }

    /// Sent but not yet picked up — offline, or waiting its turn. The clock is
    /// the only difference on screen, because that is the only difference that
    /// matters: it is written down either way.
    private var isPending: Bool {
        if case .sent = state { return true }
        return false
    }
}

private struct MessageBubble: View {
    @Environment(AppModel.self) private var model
    let message: LogMessage
    var isPending = false
    @State private var viewingPhoto = false

    // The photo and the caption are separate elements, not one bubble: a shared
    // background pads the narrower of the two with dead colour whenever their
    // widths differ, which on a wide caption drew an L of blue around the
    // image. The photo stands alone in its own rounded clip and the words get
    // their own compact bubble beneath it, trailing-aligned like any sent turn.
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 40)

            if isPending {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WellieTheme.faint)
            }

            VStack(alignment: .trailing, spacing: 6) {
                if let image = PhotoStore.shared.image(for: message.photoHash) {
                    Button {
                        viewingPhoto = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: 230, maxHeight: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("View the photo full screen")
                }
                if let said = message.trimmedText {
                    Text(said)
                        .font(WellieTheme.font(16, weight: .medium))
                        .foregroundStyle(WellieTheme.onAccent)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .frame(maxWidth: 280, alignment: .leading)
                        .background(
                            WellieTheme.blue,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            message.trimmedText.map { "You sent: \($0)" } ?? "You sent a photo"
        )
        .fullScreenCover(isPresented: $viewingPhoto) {
            if let image = PhotoStore.shared.image(for: message.photoHash) {
                PhotoViewer(image: image)
            }
        }
    }
}

/// The photo at full size, on black, dismissed with the close button or a
/// downward drag — the two gestures every photo viewer answers to.
private struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                dismiss()
                            } else {
                                withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                            }
                        }
                )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 8)
            .accessibilityLabel("Close the photo")
        }
        .statusBarHidden()
    }
}

/// State 2. Runs in the background — the composer never locks, and the next
/// message can go while this one is still being read.
private struct ReadingPill: View {
    var hasStarted = true
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(WellieTheme.blue)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * bounce(index))
                }
            }
            Text(hasStarted ? "Reading…" : "Waiting to send…")
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.body)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(WellieTheme.surface, in: Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }

    private func bounce(_ index: Int) -> Double {
        let offset = phase - Double(index) / 3
        let wrapped = offset - offset.rounded(.down)
        return max(0, 1 - abs(wrapped - 0.5) * 3)
    }
}

/// State 3. The message became a meal — and the card, not the bubble, is what
/// opens `2e`.
private struct ThreadMealCard: View {
    @Environment(AppModel.self) private var model
    let meal: MealEntry
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                HStack(spacing: 12) {
                    MealThumbnail(meal: meal, side: 44, radius: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MealDisplay.title(meal))
                            .font(WellieTheme.font(16.5, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .lineLimit(1)
                        Text(MealDisplay.whenAndWhat(meal))
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WellieTheme.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The olives alone. The card also carried the counted-groups
            // phrase, but in a thread the dish name above already says what
            // this was, and "Beans, something else, red meat and more" beside
            // it read as noise, not information — the full reading lives one
            // tap away on the meal detail.
            OliveRow(olives: model.olives(for: meal).olives)

            if let question = ambiguity {
                NeedsYouPill(meal: meal, item: question.item, rivals: question.rivals)
            }
        }
        .wellieCard(padding: 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 24)
    }

    /// State 4, and the only one that ever asks. At most one per meal: a card
    /// that raises three questions is a form, and this is a thread.
    private var ambiguity: (item: MealItem, rivals: [FoodGroup])? {
        let excluded = model.config.medas.excludedItems
        guard let item = meal.items.first(where: {
            !$0.scoreCriticalAlternatives(excludedItems: excluded).isEmpty
        }) else { return nil }
        return (item, item.scoreCriticalAlternatives(excludedItems: excluded))
    }
}

private extension MealItem {
    func scoreCriticalAlternatives(excludedItems: Set<Int>) -> [FoodGroup] {
        (modelAlternatives ?? []).filter {
            Medas.choiceChangesScore(group, $0, excludedItems: excludedItems)
        }
    }
}

/// Never blocks the thread. The meal is already saved with the model's best
/// guess and marked as one; this is an offer, not a gate.
///
/// The answer is the tap: the fork arrives as structured data — a group and
/// its rivals — so the choices sit right in the pill, and picking one rewrites
/// the item without a sheet, a keyboard, or a model round-trip. A structured
/// answer is also the only kind the don't-ask-again habit can ever learn from;
/// a typed note cannot feed that lookup.
private struct NeedsYouPill: View {
    @Environment(AppModel.self) private var model
    let meal: MealEntry
    let item: MealItem
    let rivals: [FoodGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(WellieTheme.attention).frame(width: 6, height: 6)
                Text(question)
                    .font(WellieTheme.font(13.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
            }
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        Task { await answer(choice) }
                    } label: {
                        Text(choice.shortName)
                            .font(WellieTheme.font(13.5, weight: .bold))
                            .foregroundStyle(WellieTheme.attention)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(WellieTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            WellieTheme.attentionSurface,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var question: String {
        let name = item.label?.capitalizedFirst ?? item.group.shortName
        return "\(name) — or \(rivals[0].sentenceName)?"
    }

    /// The model's guess first, then its rivals: confirming what it said is as
    /// real an answer as overturning it, and both retire the question.
    private var choices: [FoodGroup] {
        [item.group] + rivals
    }

    /// A direct edit, exactly the shape the detail screen's save produces:
    /// rewrite the one item, re-sync the dishes it flattened from, record the
    /// revision. Clearing the item's rivals is what retires the question — the
    /// original shortlist survives untouched in `recognitionEvidence`.
    private func answer(_ chosen: FoodGroup) async {
        var revised = meal
        guard let index = revised.items.firstIndex(where: { $0.id == item.id }) else { return }
        revised.items[index].group = chosen
        revised.items[index].modelAlternatives = []
        if let dishes = revised.storedDishes, !dishes.isEmpty {
            let regrouped = MealDish.regrouped(revised.items, keeping: dishes)
            revised.storedDishes = regrouped
            revised.items = regrouped.flatMap { $0.flattened() }
        }
        await model.reviseMeal(revised)
    }
}

/// The read did not complete. The message is intact, so this re-sends it and
/// never asks anyone to type it again.
private struct FailedPill: View {
    let reason: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WellieTheme.attention)
            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn't read that one.")
                    .font(WellieTheme.font(14.5, weight: .bold))
                Text(reason)
                    .font(WellieTheme.font(12.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button("Retry", action: retry)
                .font(WellieTheme.font(14, weight: .bold))
                .foregroundStyle(WellieTheme.blue)
        }
        .padding(14)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.trailing, 24)
    }
}

// MARK: - 7e · First open

/// Straight after onboarding: no pinned strip, because there is nothing to
/// glance at, and no tour. One message from the app, written like a person,
/// showing the three ways in. It scrolls away forever after the first log.
private struct FirstOpenHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What have you eaten today? Tell me like you'd tell a friend — I'll sort out the rest.")
                .font(WellieTheme.font(16, weight: .medium))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                hint("mic.fill", "say it")
                hint("camera.fill", "snap it, or a photo you already took")
                hint("text.bubble.fill", "even “half a kebab at 2 am” counts")
            }
        }
        .padding(17)
        .frame(maxWidth: 320, alignment: .leading)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WellieTheme.blue)
                .frame(width: 16)
            Text(text)
                .font(WellieTheme.font(14, weight: .medium))
                .foregroundStyle(WellieTheme.body)
        }
    }
}
