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
            Form {
                Section {
                    if let imageData, let image = UIImage(data: imageData) {
                        Image(uiImage: image)
                            .resizable().scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take a photo", systemImage: "camera")
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose from library", systemImage: "photo")
                    }
                }

                if isRecognizing {
                    Section { HStack { ProgressView(); Text("Reading the plate…").padding(.leading, 8) } }
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if !items.isEmpty || imageData != nil {
                    Section {
                        ForEach($items) { $item in
                            MealItemRow(item: $item)
                        }
                        .onDelete { items.remove(atOffsets: $0) }

                        Menu {
                            ForEach(FoodGroup.allCases, id: \.self) { group in
                                Button(group.displayName) {
                                    items.append(MealItem(group: group, portion: .medium))
                                }
                            }
                        } label: {
                            Label("Add a group", systemImage: "plus")
                        }
                    } header: {
                        Text("What's on the plate")
                    } footer: {
                        if let recognition {
                            Text(footerText(for: recognition))
                        }
                    }
                }

                Section {
                    DatePicker("Eaten at", selection: $eatenAt)
                }
            }
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(items.isEmpty)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPhotoPicker { data in
                    imageData = data
                    Task { await recognize(data) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    imageData = data
                    await recognize(data)
                }
            }
        }
    }

    private func footerText(for recognition: MealRecognition) -> String {
        var parts = ["Model confidence \(Int(recognition.confidence * 100))%."]
        if let notes = recognition.notes { parts.append(notes) }
        if recognition.confidence < model.config.recognition.autoConfirmConfidence {
            parts.append("Worth a look before saving.")
        }
        return parts.joined(separator: " ")
    }

    private func recognize(_ data: Data) async {
        isRecognizing = true
        error = nil
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

/// One tap to fix a group, one to fix a portion. The model confuses fish with
/// white meat and misses olive oil; both are a second's work to correct here,
/// and correcting is what turns a guess into a record.
struct MealItemRow: View {
    @Binding var item: MealItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Menu {
                    ForEach(orderedGroups, id: \.self) { group in
                        Button(group.displayName) { item.group = group }
                    }
                } label: {
                    Text(item.group.displayName)
                        .font(.body)
                }
                if let label = item.label {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: $item.portion) {
                ForEach(Portion.allCases, id: \.self) { portion in
                    Text(portion.rawValue.capitalized).tag(portion)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    /// Likely confusions first, then everything else.
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
            // 0.8 JPEG at native size: the request sends it at `detail: low`
            // anyway, so anything larger is bandwidth for nothing.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
