import SwiftUI
import Photos
import AVFoundation

/// Orchestrates the capture/record → sign → review flow and exposes UI state.
@MainActor
final class CameraViewModel: ObservableObject {

    /// The signed item currently presented for review, if any.
    @Published var captured: CapturedItem?
    @Published var isBusy = false
    @Published var countdown: Int?
    @Published var errorMessage: String?
    @Published var saveConfirmation: String?

    let camera = CameraController()
    let creatorStore = CreatorStore()
    let locationProvider = LocationProvider()
    let rollStore = CredentialRollStore()
    private let signer: ContentCredentialSigner?
    private let signerInitError: String?

    struct CapturedItem: Identifiable {
        let id = UUID()
        let kind: MediaKind
        /// Still image, or a poster frame for video.
        let image: UIImage?
        /// Signed JPEG bytes (photo only).
        let signedData: Data?
        /// On-disk signed asset for Share/AirDrop (exact signed bytes).
        let fileURL: URL
        let manifestJSON: String
        let identityRequested: Bool
        let identityBound: Bool
        /// Original (unsigned) Live Photo movie, kept so the pairing survives a
        /// save to Photos. The still carries the credential.
        let livePhotoMovieURL: URL?
        /// Whether this capture was stored in the Credential Roll.
        var savedToRoll: Bool
    }

    init() {
        do {
            self.signer = try ContentCredentialSigner()
            self.signerInitError = nil
        } catch {
            self.signer = nil
            self.signerInitError = error.localizedDescription
        }
    }

    func onAppear() {
        camera.start()
        if creatorStore.metadata.location { locationProvider.start() }
        if let signerInitError { errorMessage = signerInitError }
    }

    func onDisappear() {
        camera.stop()
    }

    func enableLocation() {
        locationProvider.start()
    }

    // MARK: - Shutter

    /// Shutter action: capture a photo, or start/stop recording in video mode.
    func shutter() {
        switch camera.captureMode {
        case .photo: capturePhoto()
        case .video: camera.isRecording ? stopRecording() : startRecording()
        }
    }

    private var wantsIdentity: Bool {
        creatorStore.bindIdentity && !creatorStore.creator.isEmpty
    }

    private func capturePhoto() {
        guard !isBusy, !camera.isRecording else { return }
        guard let signer else { errorMessage = signerInitError ?? "Signer unavailable."; return }
        isBusy = true
        Task {
            defer { isBusy = false }
            await runCountdown()
            do {
                let capture = try await camera.capturePhoto()
                let croppedData = ImageCrop.crop(capture.data, to: camera.aspect)

                var builder = CaptureMetadataBuilder(options: creatorStore.metadata)
                let exif = builder.build(properties: capture.metadata,
                                         location: locationProvider.currentLocation)

                let result = try signer.sign(
                    jpegData: croppedData,
                    creator: creatorStore.creator,
                    bindIdentity: creatorStore.bindIdentity,
                    exif: exif
                )
                guard let image = UIImage(data: result.signedImageData) else {
                    throw CameraError.noImageData
                }
                cleanupCurrentItem()
                let fileURL = try writeTempFile(result.signedImageData, ext: "jpg")
                let saved = creatorStore.autoSaveToRoll && rollStore.add(from: fileURL, kind: .photo) != nil
                captured = CapturedItem(
                    kind: .photo,
                    image: image,
                    signedData: result.signedImageData,
                    fileURL: fileURL,
                    manifestJSON: result.manifestJSON,
                    identityRequested: wantsIdentity,
                    identityBound: result.identityBound,
                    livePhotoMovieURL: capture.livePhotoMovieURL,
                    savedToRoll: saved
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startRecording() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await runCountdown()
            isBusy = false
            camera.startRecording()
        }
    }

    private func stopRecording() {
        guard let signer else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let rawURL = try await camera.stopRecording()
                let result = try signer.signVideo(
                    at: rawURL,
                    creator: creatorStore.creator,
                    bindIdentity: creatorStore.bindIdentity
                )
                try? FileManager.default.removeItem(at: rawURL)

                cleanupCurrentItem()
                let shareURL = try moveToTempFile(result.signedVideoURL, ext: "mov")
                let saved = creatorStore.autoSaveToRoll && rollStore.add(from: shareURL, kind: .video) != nil
                captured = CapturedItem(
                    kind: .video,
                    image: Self.posterFrame(for: shareURL),
                    signedData: nil,
                    fileURL: shareURL,
                    manifestJSON: result.manifestJSON,
                    identityRequested: wantsIdentity,
                    identityBound: result.identityBound,
                    livePhotoMovieURL: nil,
                    savedToRoll: saved
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runCountdown() async {
        let seconds = camera.timer.rawValue
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            countdown = remaining
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdown = nil
    }

    func dismissReview() {
        cleanupCurrentItem()
        captured = nil
        saveConfirmation = nil
    }

    /// Manually store the current capture in the Credential Roll.
    func addCurrentToRoll() {
        guard var item = captured, !item.savedToRoll else { return }
        if rollStore.add(from: item.fileURL, kind: item.kind) != nil {
            item.savedToRoll = true
            captured = item
            saveConfirmation = "Added to Credential Roll."
        }
    }

    // MARK: - Save to Photos

    func saveToLibrary() {
        guard let captured else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                errorMessage = "Photo library access was denied."
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    switch captured.kind {
                    case .photo:
                        if let data = captured.signedData {
                            request.addResource(with: .photo, data: data, options: nil)
                        }
                        if let movie = captured.livePhotoMovieURL {
                            let opts = PHAssetResourceCreationOptions()
                            opts.shouldMoveFile = false
                            request.addResource(with: .pairedVideo, fileURL: movie, options: opts)
                        }
                    case .video:
                        request.addResource(with: .video, fileURL: captured.fileURL, options: nil)
                    }
                }
                saveConfirmation = captured.kind == .photo
                    ? "Saved to Photos with Content Credentials."
                    : "Saved video to Photos with Content Credentials."
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Temp files

    private func writeTempFile(_ data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigillo \(Self.fileTimestamp).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func moveToTempFile(_ source: URL, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sigillo \(Self.fileTimestamp).\(ext)")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: source, to: url)
        return url
    }

    private func cleanupCurrentItem() {
        if let url = captured?.fileURL { try? FileManager.default.removeItem(at: url) }
        if let movie = captured?.livePhotoMovieURL { try? FileManager.default.removeItem(at: movie) }
    }

    private static var fileTimestamp: String {
        ISO8601DateFormatter.string(
            from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]
        ).replacingOccurrences(of: ":", with: ".")
    }

    private static func posterFrame(for url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}
