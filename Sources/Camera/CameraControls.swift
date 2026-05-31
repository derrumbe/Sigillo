import AVFoundation
import CoreGraphics

/// Photo vs. video capture mode.
enum CaptureMode: String, CaseIterable, Identifiable {
    case photo, video
    var id: String { rawValue }
}

/// Flash / torch behavior.
enum FlashOption: String, CaseIterable, Identifiable {
    case off, auto, on
    var id: String { rawValue }

    var photoFlashMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var torchMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off: return .off
        case .auto: return .auto
        case .on: return .on
        }
    }

    var icon: String {
        switch self {
        case .off: return "bolt.slash.fill"
        case .auto: return "bolt.badge.automatic.fill"
        case .on: return "bolt.fill"
        }
    }
}

/// Output aspect ratio. The sensor is natively 4:3; the others crop the result.
enum AspectRatio: String, CaseIterable, Identifiable {
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"
    var id: String { rawValue }

    /// Long-edge : short-edge ratio used to center-crop the capture, or `nil`
    /// for the native 4:3 (no crop).
    var longToShort: CGFloat? {
        switch self {
        case .fourThree: return nil
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1.0
        }
    }
}

/// Self-timer delay before capture.
enum CaptureTimer: Int, CaseIterable, Identifiable {
    case off = 0
    case three = 3
    case ten = 10
    var id: Int { rawValue }
    var label: String { self == .off ? "off" : "\(rawValue)s" }
}

/// Result of a still capture: the (possibly cropped) JPEG, the camera metadata
/// for the EXIF assertion, and the paired Live Photo movie if one was recorded.
struct PhotoCaptureResult {
    let data: Data
    let metadata: [String: Any]
    let livePhotoMovieURL: URL?
}
