import AVFoundation
import UIKit

/// Drives an `AVCaptureSession` for stills, Live Photos, and video, and exposes
/// the manual controls (zoom, flash, exposure, night mode, aspect, timer, mode).
///
/// AVFoundation work runs on a private session queue; published state is updated
/// on the main actor for SwiftUI.
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status { case unconfigured, configured, unauthorized, failed }

    @Published private(set) var status: Status = .unconfigured

    // Live control state (bound by the UI).
    @Published var captureMode: CaptureMode = .photo
    @Published var flashOption: FlashOption = .off
    @Published var aspect: AspectRatio = .fourThree
    @Published var timer: CaptureTimer = .off
    @Published var isLivePhotoEnabled = false
    @Published private(set) var isLivePhotoSupported = false
    @Published var nightModeEnabled = false
    @Published private(set) var nightModeSupported = false
    @Published private(set) var isRecording = false

    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var canSwitchCamera = false

    @Published var zoomFactor: CGFloat = 1.0
    @Published private(set) var minZoomFactor: CGFloat = 1.0
    @Published private(set) var maxZoomFactor: CGFloat = 8.0
    @Published var exposureBias: Float = 0
    @Published private(set) var minExposureBias: Float = -2
    @Published private(set) var maxExposureBias: Float = 2

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "org.contentauth.example.Sigillo.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoInput: AVCaptureDeviceInput?

    private var photoContinuation: CheckedContinuation<PhotoCaptureResult, Error>?
    private var videoContinuation: CheckedContinuation<URL, Error>?
    private var pendingData: Data?
    private var pendingMetadata: [String: Any] = [:]
    private var pendingLiveURL: URL?

    // MARK: - Lifecycle

    func start() {
        Task {
            guard await requestAuthorization() else { status = .unauthorized; return }
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
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureSession() {
        guard status == .unconfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = Self.bestCamera(for: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            Task { @MainActor in self.status = .failed }
            return
        }
        session.addInput(input)
        self.videoInput = input

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            Task { @MainActor in self.status = .failed }
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported

        session.commitConfiguration()
        refreshDeviceCapabilities(device)
    }

    private static func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .front
            ? [.builtInTrueDepthCamera, .builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        for t in types {
            if let d = AVCaptureDevice.default(t, for: .video, position: position) { return d }
        }
        // Last resort: any available camera (only meaningful for the back case).
        return position == .back ? AVCaptureDevice.default(for: .video) : nil
    }

    private func refreshDeviceCapabilities(_ device: AVCaptureDevice) {
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10)
        let minExp = device.minExposureTargetBias
        let maxExp = device.maxExposureTargetBias
        let liveSupported = photoOutput.isLivePhotoCaptureSupported
        let lowLight = device.isLowLightBoostSupported
        let canSwitch = Self.bestCamera(for: .front) != nil && Self.bestCamera(for: .back) != nil
        Task { @MainActor in
            self.minZoomFactor = minZoom
            self.maxZoomFactor = maxZoom
            self.minExposureBias = minExp
            self.maxExposureBias = maxExp
            self.isLivePhotoSupported = liveSupported
            self.nightModeSupported = lowLight
            self.canSwitchCamera = canSwitch
            self.status = .configured
        }
    }

    // MARK: - Controls

    func setCaptureMode(_ mode: CaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode
        sessionQueue.async { [weak self] in self?.reconfigureForMode(mode) }
    }

    private func reconfigureForMode(_ mode: CaptureMode) {
        session.beginConfiguration()
        switch mode {
        case .photo:
            if let mo = movieOutput, session.outputs.contains(mo) { session.removeOutput(mo) }
            session.sessionPreset = .photo
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        case .video:
            if session.outputs.contains(photoOutput) { session.removeOutput(photoOutput) }
            let mo = movieOutput ?? AVCaptureMovieFileOutput()
            movieOutput = mo
            if !session.outputs.contains(mo), session.canAddOutput(mo) { session.addOutput(mo) }
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        }
        session.commitConfiguration()
    }

    /// Flip between the back and front (selfie) camera. Ignored while recording,
    /// since swapping the input mid-recording would interrupt the movie.
    func switchCamera() {
        guard canSwitchCamera, !isRecording else { return }
        let target: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in self?.reconfigureCamera(to: target) }
    }

    private func reconfigureCamera(to position: AVCaptureDevice.Position) {
        guard let newDevice = Self.bestCamera(for: position),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

        session.beginConfiguration()
        if let current = videoInput { session.removeInput(current) }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        } else if let current = videoInput {
            session.addInput(current)            // revert if the new input is rejected
            session.commitConfiguration()
            return
        }
        session.commitConfiguration()

        Task { @MainActor in
            self.cameraPosition = position
            // The new device starts at its own defaults; reset the published
            // control state so the UI matches what the hardware is doing.
            self.zoomFactor = 1
            self.exposureBias = 0
        }
        refreshDeviceCapabilities(newDevice)
    }

    func setZoom(_ factor: CGFloat) {
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        zoomFactor = clamped
        configureDevice { $0.videoZoomFactor = clamped }
    }

    func setExposureBias(_ bias: Float) {
        let clamped = max(minExposureBias, min(bias, maxExposureBias))
        exposureBias = clamped
        configureDevice { $0.setExposureTargetBias(clamped, completionHandler: nil) }
    }

    func setNightMode(_ on: Bool) {
        nightModeEnabled = on
        configureDevice { device in
            if device.isLowLightBoostSupported {
                device.automaticallyEnablesLowLightBoostWhenAvailable = on
            }
        }
    }

    func focusAndExpose(at point: CGPoint) {
        // `point` is in normalized (0–1) device coordinates.
        configureDevice { device in
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
        }
    }

    private func configureDevice(_ block: @escaping (AVCaptureDevice) -> Void) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                block(device)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Still capture

    func capturePhoto() async throws -> PhotoCaptureResult {
        let flash = flashOption.photoFlashMode
        let wantLive = isLivePhotoEnabled && photoOutput.isLivePhotoCaptureEnabled
        return try await withCheckedThrowingContinuation { cont in
            self.photoContinuation = cont
            self.pendingData = nil
            self.pendingMetadata = [:]
            self.pendingLiveURL = nil
            sessionQueue.async { [weak self] in
                guard let self else { return }
                let settings: AVCapturePhotoSettings
                if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                } else {
                    settings = AVCapturePhotoSettings()
                }
                settings.flashMode = flash
                settings.photoQualityPrioritization = .quality
                if wantLive {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                    settings.livePhotoMovieFileURL = url
                }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Video recording

    func startRecording() {
        guard captureMode == .video, let movieOutput, !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let torch = flashOption == .on
        configureDevice { device in
            if device.hasTorch, device.isTorchModeSupported(torch ? .on : .off) {
                device.torchMode = torch ? .on : .off
            }
        }
        isRecording = true
        sessionQueue.async { movieOutput.startRecording(to: url, recordingDelegate: self) }
    }

    func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.videoContinuation = cont
            sessionQueue.async { [weak self] in self?.movieOutput?.stopRecording() }
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
        let data = photo.fileDataRepresentation()
        let metadata = photo.metadata
        Task { @MainActor in
            self.pendingData = data
            self.pendingMetadata = metadata
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL,
        duration: CMTime,
        photoDisplayTime: CMTime,
        resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        let url = error == nil ? outputFileURL : nil
        Task { @MainActor in self.pendingLiveURL = url }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        Task { @MainActor in
            guard let cont = self.photoContinuation else { return }
            self.photoContinuation = nil
            if let error {
                cont.resume(throwing: error)
            } else if let data = self.pendingData {
                cont.resume(returning: PhotoCaptureResult(
                    data: data, metadata: self.pendingMetadata, livePhotoMovieURL: self.pendingLiveURL
                ))
            } else {
                cont.resume(throwing: CameraError.noImageData)
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            self.configureDevice { device in
                if device.hasTorch, device.torchMode != .off { device.torchMode = .off }
            }
            guard let cont = self.videoContinuation else { return }
            self.videoContinuation = nil
            // A non-nil error can still accompany a usable file (e.g. reached a
            // limit), so treat a present file as success.
            if FileManager.default.fileExists(atPath: outputFileURL.path) {
                cont.resume(returning: outputFileURL)
            } else if let error {
                cont.resume(throwing: error)
            } else {
                cont.resume(throwing: CameraError.noImageData)
            }
        }
    }
}

enum CameraError: LocalizedError {
    case noImageData
    var errorDescription: String? {
        switch self {
        case .noImageData: return "The camera did not return any media data."
        }
    }
}
