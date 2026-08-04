import PhotosUI
import ShamanCore
import SwiftUI

struct MealCaptureView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var recognition: MealRecognition?
    @State private var items: [MealItem] = []
    @State private var eatenAt = Date()
    @State private var isRecognizing = false
    @State private var error: String?
    @State private var showingCamera = false

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
                    Button(group.displayName) { items.append(MealItem(group: group, portion: .medium)) }
                }
            } label: {
                Label("Add manually", systemImage: "plus.circle")
                    .font(WellieTheme.font(16, weight: .semibold))
            }

            DatePicker("Eaten at", selection: $eatenAt)
                .font(WellieTheme.font(15, weight: .medium))
                .wellieCard(color: WellieTheme.card)
        }
    }

    private var review: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                Capsule().fill(WellieTheme.blue).frame(width: 34, height: 5)
                Capsule().fill(WellieTheme.blue).frame(width: 34, height: 5)
                Capsule().fill(WellieTheme.softBlue).frame(width: 34, height: 5)
            }
            .padding(.top, 8)

            Text(isRecognizing ? "Reading your plate" : "Check if everything is right")
                .font(WellieTheme.font(28, weight: .bold))
                .multilineTextAlignment(.center)

            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }

            if isRecognizing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Finding Mediterranean food groups…")
                        .font(WellieTheme.font(15, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
                .wellieCard(color: WellieTheme.ice)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(WellieTheme.font(14, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wellieCard(color: Color.red.opacity(0.07))
            }

            if !items.isEmpty {
                Text(recognitionSummary)
                    .font(WellieTheme.font(21, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)

                VStack(spacing: 0) {
                    HStack {
                        WellieKicker(text: "Food groups")
                        Spacer()
                        if let recognition {
                            Text("\(Int(recognition.confidence * 100))% confidence")
                                .font(WellieTheme.font(12, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                        }
                    }
                    .padding(.bottom, 8)

                    ForEach(Array(items.indices), id: \.self) { index in
                        MealItemEditorRow(item: $items[index])
                        if index < items.count - 1 { Divider() }
                    }

                    Menu {
                        ForEach(FoodGroup.allCases, id: \.self) { group in
                            Button(group.displayName) {
                                items.append(MealItem(group: group, portion: .medium))
                            }
                        }
                    } label: {
                        Label("Add food group", systemImage: "plus")
                            .font(WellieTheme.font(15, weight: .semibold))
                            .padding(.top, 12)
                    }
                }
                .wellieCard(color: WellieTheme.card)

                DatePicker("Eaten at", selection: $eatenAt)
                    .font(WellieTheme.font(15, weight: .medium))
                    .wellieCard(color: WellieTheme.card)

                if let notes = recognition?.notes {
                    Text(notes)
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("Save meal") { Task { await save() } }
                    .buttonStyle(WelliePrimaryButtonStyle())
                    .disabled(items.isEmpty || isRecognizing)
            } else if !isRecognizing {
                Menu {
                    ForEach(FoodGroup.allCases, id: \.self) { group in
                        Button(group.displayName) { items.append(MealItem(group: group, portion: .medium)) }
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

    private var recognitionSummary: String {
        let labels = items.compactMap(\.label).filter { !$0.isEmpty }
        if !labels.isEmpty { return labels.prefix(4).joined(separator: ", ") }
        return items.prefix(4).map(\.group.displayName).joined(separator: ", ")
    }

    private func setPhoto(_ originalData: Data) {
        let normalized = UIImage(data: originalData)?.jpegData(compressionQuality: 0.82) ?? originalData
        imageData = normalized
        Task { await recognize(normalized) }
    }

    private func recognize(_ data: Data) async {
        isRecognizing = true
        error = nil
        recognition = nil
        items = []
        defer { isRecognizing = false }
        do {
            let result = try await model.recognize(imageData: data)
            recognition = result
            items = result.asMealItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        let originalGroups = recognition?.items.map(\.group)
        let meal = MealEntry(
            eatenAt: eatenAt.epochMillis,
            items: items,
            source: imageData == nil ? .manual : .photo,
            photoHash: imageData.map(ImageDigest.sha256),
            modelConfidence: recognition?.confidence,
            wasCorrected: originalGroups != nil && originalGroups != items.map(\.group)
        )
        await model.logMeal(meal)
        dismiss()
    }
}

struct MealItemEditorRow: View {
    @Binding var item: MealItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Menu {
                    ForEach(orderedGroups, id: \.self) { group in
                        Button(group.displayName) { item.group = group }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label ?? item.group.displayName)
                            .font(WellieTheme.font(16, weight: .semibold))
                            .foregroundStyle(WellieTheme.ink)
                        if item.label != nil {
                            Text(item.group.displayName)
                                .font(WellieTheme.font(12, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                        }
                    }
                }
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

    private var orderedGroups: [FoodGroup] {
        let likely = item.group.commonlyConfusedWith
        return likely + FoodGroup.allCases.filter { !likely.contains($0) }
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
