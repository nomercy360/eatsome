import CryptoKit
import ShamanCore
import UIKit

/// Meal photos on disk, keyed by the same SHA-256 the meal already carries.
///
/// Until now nothing kept them: `photoHash` was a fingerprint, the recognition
/// cache held only JSON, and the picture was gone the moment the sheet closed —
/// which is why a logged meal showed a camera glyph instead of the food.
///
/// The local copy drives the meal UI. The same model-input render may also live
/// in private R2 so failed inference and explicit re-runs do not ask the phone
/// to upload it again; it is never a public image URL.
struct PhotoStore {
    static let shared = PhotoStore()

    /// Long enough to fill a detail view on any phone, small enough that a year
    /// of logging is tens of megabytes rather than hundreds.
    private let maximumDimension: CGFloat = 1280
    private let quality: CGFloat = 0.72

    private let directory: URL?

    private init() {
        directory = (try? EventLog.defaultURL())?
            .deletingLastPathComponent()
            .appendingPathComponent("photos", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    @discardableResult
    func store(_ data: Data) -> String? {
        let hash = ImageDigest.sha256(data)
        guard let url = url(for: hash) else { return nil }
        guard !FileManager.default.fileExists(atPath: url.path) else { return hash }
        guard let downscaled = downscale(data) else { return nil }
        // A failed write must not lose the meal, so this is best effort.
        try? downscaled.write(to: url, options: .atomic)
        return hash
    }

    func image(for hash: String?) -> UIImage? {
        data(for: hash).flatMap(UIImage.init(data:))
    }

    /// The stored bytes themselves, for a correction that wants the model to
    /// look at the plate again rather than only at what was typed.
    func data(for hash: String?) -> Data? {
        guard let hash, let url = url(for: hash) else { return nil }
        return try? Data(contentsOf: url)
    }

    func remove(_ hash: String?) {
        guard let hash, let url = url(for: hash) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func url(for hash: String) -> URL? {
        // The hash is hex from SHA-256; anything else is not ours and has no
        // business becoming a path.
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { return nil }
        return directory?.appendingPathComponent("\(hash).jpg")
    }

    private func downscale(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumDimension else { return image.jpegData(compressionQuality: quality) }

        let scale = maximumDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: quality)
    }
}
