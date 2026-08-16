import UIKit

/// Produces the single JPEG representation used for recognition, hashing, and
/// remote media storage. Keeping this boundary in one place prevents an eval
/// from replaying a different render than the model originally saw.
enum ModelInputImage {
    /// The whole frame, never a crop — the long edge is scaled and both sides
    /// follow, so nothing leaves the picture.
    ///
    /// 2048 rather than 1024 because printed packaging is food too: a nutrition
    /// panel or a product name is often the only thing in the frame that
    /// settles what a carton actually is, and it is the first thing a downscale
    /// destroys.
    static let maximumDimension: CGFloat = 2048
    static let compressionQuality: CGFloat = 0.82

    static func render(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, maximumDimension / longest)
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: compressionQuality)
    }
}
