import SwiftUI
import AVFoundation
import AVKit

/// A SwiftUI wrapper around an `AVCaptureVideoPreviewLayer` that renders the
/// live camera feed.
///
/// On devices with the hardware **Camera Control** (iPhone 16 family) — and via
/// the volume buttons — a full press fires `onPrimaryCapture`, wired to the same
/// action as the on-screen shutter. Handled through `AVCaptureEventInteraction`
/// (iOS 17.2+); older devices, which have no Camera Control, just don't install
/// the interaction.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onPrimaryCapture: () -> Void = {}

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onPrimaryCapture = onPrimaryCapture
        view.installCaptureEventInteraction()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.onPrimaryCapture = onPrimaryCapture
    }

    /// A `UIView` whose backing layer is an `AVCaptureVideoPreviewLayer`.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Safe: `layerClass` guarantees the type.
            layer as! AVCaptureVideoPreviewLayer
        }

        /// Invoked on a hardware-button full press (Camera Control / volume).
        var onPrimaryCapture: (() -> Void)?

        func installCaptureEventInteraction() {
            guard #available(iOS 17.2, *) else { return }
            // Fire on `.ended` (button released) so a press-and-hold doesn't
            // trigger early; `[weak self]` avoids the view ⇄ interaction cycle.
            let interaction = AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended { self?.onPrimaryCapture?() }
            }
            addInteraction(interaction)
        }
    }
}
