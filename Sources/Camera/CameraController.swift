import AVFoundation
import UIKit

/// Drives an `AVCaptureSession` for still-photo capture.
///
/// This is a thin, focused wrapper around AVFoundation: it configures a single
/// back-camera input and a photo output, exposes the session for live preview,
/// and returns the captured JPEG as `Data` so it can be fed straight into the
/// C2PA signing pipeline.
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status {
        case unconfigured
        case configured
        case unauthorized
        case failed
    }

    @Published private(set) var status: Status = .unconfigured

    /// The session backing the live preview layer.
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "org.contentauth.example.C2PACamera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    // MARK: - Lifecycle

    /// Requests camera permission, configures the session, and starts it running.
    func start() {
        Task {
            guard await requestAuthorization() else {
                status = .unauthorized
                return
            }
            sessionQueue.async { [weak self] in
                self?.configureSession()
                self?.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configureSession() {
        guard status == .unconfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            DispatchQueue.main.async { self.status = .failed }
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else {
            DispatchQueue.main.async { self.status = .failed }
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality

        DispatchQueue.main.async { self.status = .configured }
    }

    // MARK: - Capture

    /// Captures a single photo and returns its JPEG-encoded bytes.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .quality

            sessionQueue.async { [weak self] in
                self?.photoOutput.capturePhoto(with: settings, delegate: self!)
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        Task { @MainActor in
            defer { self.photoContinuation = nil }

            if let error {
                self.photoContinuation?.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                self.photoContinuation?.resume(throwing: CameraError.noImageData)
                return
            }
            self.photoContinuation?.resume(returning: data)
        }
    }
}

enum CameraError: LocalizedError {
    case noImageData

    var errorDescription: String? {
        switch self {
        case .noImageData: return "The camera did not return any image data."
        }
    }
}
