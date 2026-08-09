import ShamanCore
import SwiftUI
import UIKit

/// Two controls that outlived the capture screen they were written for.
///
/// `MealCaptureView` is gone — logging is a thread now — but the meal detail
/// screen still asks how much of a shared plate was yours, and the composer
/// still needs a camera. They were the only two things in that 1,200-line file
/// with a life of their own.

/// How much of the plate was yours, as three chips on one row.
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

/// The system camera, or the library on a device without one.
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
