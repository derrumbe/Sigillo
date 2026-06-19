import UIKit

/// Rotates JPEG data by 90° and re-encodes it, baking the rotation into the
/// pixels (orientation reset to `.up`) at full resolution.
///
/// Re-encoding changes the bytes, which invalidates the original C2PA signature,
/// so the rotated output is always re-signed with a `c2pa.orientation` credential
/// that links the original as a parent ingredient. See `ContentCredentialSigner`.
enum ImageRotate {
    static func rotated90(_ data: Data, clockwise: Bool = true) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size                       // already orientation-adjusted
        guard size.width > 0, size.height > 0 else { return nil }
        let newSize = CGSize(width: size.height, height: size.width)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale                  // keep native pixel resolution
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let rotated = renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: clockwise ? .pi / 2 : -.pi / 2)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2,
                                  width: size.width, height: size.height))
        }
        return rotated.jpegData(compressionQuality: 0.95)
    }
}
