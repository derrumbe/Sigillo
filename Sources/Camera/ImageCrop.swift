import UIKit

/// Center-crops captured JPEG data to a chosen aspect ratio, preserving the
/// image's orientation and full resolution. (EXIF/camera metadata is captured
/// separately from `AVCapturePhoto.metadata`, so re-encoding here is harmless.)
enum ImageCrop {
    static func crop(_ data: Data, to aspect: AspectRatio) -> Data {
        // 4:3 is the native sensor ratio — no crop, keep original bytes.
        guard aspect.longToShort != nil, let image = UIImage(data: data) else { return data }

        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return data }

        let portrait = h >= w
        let targetWH: CGFloat
        switch aspect {
        case .square:
            targetWH = 1
        case .sixteenNine:
            targetWH = portrait ? 9.0 / 16.0 : 16.0 / 9.0
        case .fourThree:
            return data
        }

        let currentWH = w / h
        var cropW = w
        var cropH = h
        if currentWH > targetWH {
            cropW = h * targetWH      // too wide → trim width
        } else {
            cropH = w / targetWH      // too tall → trim height
        }
        let x = (w - cropW) / 2
        let y = (h - cropH) / 2

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale     // keep native pixel resolution (no upscaling)
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: cropW, height: cropH), format: format
        )
        let cropped = renderer.image { _ in
            image.draw(at: CGPoint(x: -x, y: -y))
        }
        return cropped.jpegData(compressionQuality: 0.95) ?? data
    }
}
