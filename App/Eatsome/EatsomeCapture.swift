import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Getting a photograph into the composer: the camera, and the pictures already
/// on the phone.
///
/// Two ways in rather than one, because they answer different situations.
/// The camera is for food in front of you; the strip is for lunch you
/// photographed at one o'clock and are logging at nine in the evening, which is
/// most of the time.

/// The system camera, or the library on a device without one.
struct CameraPhoto: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPhoto
        init(_ parent: CameraPhoto) { self.parent = parent }

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

/// The last dozen pictures on the phone, plus a way into all of them.
///
/// Read access is asked for when the composer opens: that is the first screen
/// where the app visibly needs the library, so the request is contextual
/// without becoming a launch-time interruption. The system `PhotosPicker` in
/// the first tile still works when the broader access is declined, which is why
/// it is first and not last.
struct RecentPhotosStrip: View {
    @Environment(\.scenePhase) private var scenePhase

    @Binding var pickerItem: PhotosPickerItem?
    let onPick: (Data) -> Void

    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var recent: [Recent] = []
    @State private var loadID = UUID()

    private struct Recent: Identifiable {
        let id: String
        let asset: PHAsset
        let thumbnail: UIImage
    }

    private var isAllowed: Bool { status == .authorized || status == .limited }
    static let tile: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieMeta("Recent photos", size: 11.5)
                .padding(.horizontal, WellieTheme.screenInset)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) { GalleryTile() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose from all photos")

                    if isAllowed, !recent.isEmpty {
                        ForEach(recent) { item in
                            Button { pick(item.asset) } label: {
                                Image(uiImage: item.thumbnail)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: Self.tile, height: Self.tile)
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: WellieTheme.photoRadius,
                                            style: .continuous
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("A recent photo")
                        }
                    } else {
                        ForEach(0..<4, id: \.self) { index in
                            Button(action: request) { emptyTile }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show recent photos")
                                .accessibilityHidden(index > 0)
                        }
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .scrollIndicators(.hidden)

            if let note = accessNote {
                Text(note)
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.horizontal, WellieTheme.screenInset)
            }
        }
        .task { prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
    }

    /// The way into the whole library. A type rather than a computed property
    /// on the strip: `PhotosPicker`'s label closure is `Sendable`, and a
    /// main-actor property read from inside it is a concurrency warning that
    /// would be silenced rather than answered.
    private struct GalleryTile: View {
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WellieTheme.accent)
                Text("All photos")
                    .font(WellieTheme.font(11.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
            }
            .frame(width: RecentPhotosStrip.tile, height: RecentPhotosStrip.tile)
            .wellieSurface(radius: WellieTheme.photoRadius)
        }
    }

    private var emptyTile: some View {
        Color.clear
            .frame(width: Self.tile, height: Self.tile)
            .wellieSurface(radius: WellieTheme.photoRadius)
    }

    private var accessNote: String? {
        if isAllowed { return recent.isEmpty ? "No photos on this phone yet." : nil }
        switch status {
        case .notDetermined: return "Allow photo access to show your latest pictures here."
        case .denied: return "Photo access is off. Pick above, or tap a tile to change it in Settings."
        case .restricted: return "Photo access is restricted on this device."
        default: return "Recent photos are unavailable."
        }
    }

    // MARK: Authorization

    private func prepare() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .notDetermined: request()
        case .authorized, .limited: load()
        default: clear()
        }
    }

    private func refresh() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if isAllowed { load() } else { clear() }
    }

    private func clear() {
        loadID = UUID()
        recent = []
    }

    private func request() {
        // Already refused: iOS will not ask a second time, and a button that
        // silently does nothing is worse than one that goes where the answer
        // can actually be changed.
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

    // MARK: Loading

    private func load() {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 12
        let assets = PHAsset.fetchAssets(with: options)
        // Thumbnails arrive in whatever order they decode, which on a mixed
        // library is not the order they were taken in. The fetch order is the
        // newest-first order the strip promises, so it is captured up front and
        // the arrivals are sorted into it.
        let order = (0..<assets.count).map { assets.object(at: $0).localIdentifier }
        let currentLoad = UUID()
        loadID = currentLoad
        recent.removeAll { !order.contains($0.id) }

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
                    guard loadID == currentLoad else { return }
                    // `requestImage` can call back twice — a degraded thumbnail
                    // and then the real one — so replace by identifier rather
                    // than append, or the strip grows to twice its length.
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

/// A stored meal photograph, drawn at the size it is asked for.
///
/// The decode happens in `PhotoStore`, which caches it — this is called from a
/// row body, so it runs on every render of every meal in the day.
struct MealPhoto: View {
    let hash: String?
    var side: CGFloat
    var radius: CGFloat

    var body: some View {
        Group {
            if let image = PhotoStore.shared.thumbnail(for: hash, side: side) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // A stand-in that does not pretend to be a photograph: this is
                // a meal with no picture, or one whose picture has not come
                // back from the account yet.
                WellieTheme.raised.overlay {
                    Image(systemName: "fork.knife")
                        .font(.system(size: side * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(WellieTheme.accent)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
}
