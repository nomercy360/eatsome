import CryptoKit
import EatsomeCore
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
/// `@unchecked Sendable` for exactly one reason: `NSCache` is documented as
/// thread-safe — "You can add, remove, and query items in the cache from
/// different threads without having to lock the cache yourself" — but it is not
/// marked `Sendable`, and every other stored property here is a `let`. The
/// checker cannot see the guarantee, so it is asserted here with its source
/// rather than worked around with an actor this type does not need.
struct PhotoStore: @unchecked Sendable {
    static let shared = PhotoStore()

    /// Long enough to fill a detail view on any phone, small enough that a year
    /// of logging is tens of megabytes rather than hundreds.
    private let maximumDimension: CGFloat = 1280
    private let quality: CGFloat = 0.72

    private let directory: URL?

    /// Decoded images, held in memory.
    ///
    /// `image(for:)` is called from a view body, so it runs on every render of
    /// every row that has a photograph — a day with four photographed meals was
    /// reading four files off disk and decoding four JPEGs each time the
    /// composer's text changed. `NSCache` because it is the one cache iOS will
    /// empty for us under pressure rather than letting a long day of logging
    /// grow without a ceiling.
    private let decoded = NSCache<NSString, UIImage>()

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
        guard let hash else { return nil }
        if let hit = decoded.object(forKey: hash as NSString) { return hit }
        guard let image = data(for: hash).flatMap(UIImage.init(data:)) else { return nil }
        decoded.setObject(image, forKey: hash as NSString)
        return image
    }

    /// A thumbnail at the size it will actually be drawn.
    ///
    /// The timeline draws a 56 pt square and the share sheet a 52 pt one, and
    /// both were being handed a 1280 px decode. `preparingThumbnail(of:)` does
    /// the downsample in ImageIO rather than by drawing the full bitmap first,
    /// which is the difference that matters when a day has six of them.
    func thumbnail(for hash: String?, side: CGFloat, scale: CGFloat = 3) -> UIImage? {
        guard let hash else { return nil }
        let key = "\(hash)@\(Int(side))" as NSString
        if let hit = decoded.object(forKey: key) { return hit }
        guard let full = image(for: hash) else { return nil }
        let pixels = CGSize(width: side * scale, height: side * scale)
        guard let small = full.preparingThumbnail(of: pixels) else { return full }
        decoded.setObject(small, forKey: key)
        return small
    }

    /// The stored bytes themselves, for a correction that wants the model to
    /// look at the plate again rather than only at what was typed.
    func data(for hash: String?) -> Data? {
        guard let hash, let url = url(for: hash) else { return nil }
        return try? Data(contentsOf: url)
    }

    func contains(_ hash: String?) -> Bool {
        guard let hash, let url = url(for: hash.lowercased()) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Rebuild a missing local cache entry from the account's private server
    /// copy. Verify the content address before allowing remote bytes to choose a
    /// local filename; the on-disk JPEG may then be resized independently.
    @discardableResult
    func restore(_ data: Data, for hash: String) -> Bool {
        let hash = hash.lowercased()
        guard ImageDigest.sha256(data) == hash, let url = url(for: hash) else { return false }
        if FileManager.default.fileExists(atPath: url.path) { return true }
        guard let downscaled = downscale(data) else { return false }
        do {
            try downscaled.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func remove(_ hash: String?) {
        guard let hash, let url = url(for: hash) else { return }
        decoded.removeObject(forKey: hash as NSString)
        try? FileManager.default.removeItem(at: url)
    }

    /// Every picture, gone, and the directory left in place and empty.
    ///
    /// For one caller: a different account signing in on this phone. The
    /// directory is recreated rather than left missing because `init` is the
    /// only other place that makes it, and this type is a singleton that will
    /// not be initialised again in this process.
    func removeAll() {
        decoded.removeAllObjects()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
