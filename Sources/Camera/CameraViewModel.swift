import SwiftUI
import Photos

/// Orchestrates the capture → sign → review flow and exposes UI state.
@MainActor
final class CameraViewModel: ObservableObject {

    /// The signed photo currently presented for review, if any.
    @Published var captured: CapturedPhoto?
    @Published var isBusy = false
    @Published var errorMessage: String?
    @Published var saveConfirmation: String?

    let camera = CameraController()
    private let signer: ContentCredentialSigner?
    private let signerInitError: String?

    struct CapturedPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
        let signedData: Data
        let manifestJSON: String
        /// On-disk copy of the signed JPEG, used for Share/AirDrop so the exact
        /// signed bytes (with the embedded manifest) are transferred unchanged.
        let fileURL: URL
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
        if let signerInitError { errorMessage = signerInitError }
    }

    func onDisappear() {
        camera.stop()
    }

    /// Captures a photo and embeds Content Credentials before presenting it.
    func capture() {
        guard !isBusy else { return }
        guard let signer else {
            errorMessage = signerInitError ?? "Signer unavailable."
            return
        }

        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let jpeg = try await camera.capturePhoto()
                let result = try signer.sign(jpegData: jpeg)
                guard let image = UIImage(data: result.signedImageData) else {
                    throw CameraError.noImageData
                }
                cleanupCurrentTempFile()
                let fileURL = try writeTempFile(result.signedImageData)
                captured = CapturedPhoto(
                    image: image,
                    signedData: result.signedImageData,
                    manifestJSON: result.manifestJSON,
                    fileURL: fileURL
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissReview() {
        cleanupCurrentTempFile()
        captured = nil
        saveConfirmation = nil
    }

    /// Writes the signed bytes to a uniquely-named file in the temporary
    /// directory so a `ShareLink` can transfer it (e.g. via AirDrop) verbatim.
    /// The filename becomes the name the recipient sees.
    private func writeTempFile(_ data: Data) throws -> URL {
        let name = "C2PA Camera \(Self.fileTimestamp).jpg"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func cleanupCurrentTempFile() {
        if let url = captured?.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static var fileTimestamp: String {
        ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withInternetDateTime]
        )
        .replacingOccurrences(of: ":", with: ".")
    }

    /// Saves the signed asset to the photo library, preserving the embedded
    /// C2PA manifest (we add the original file data, not a re-encoded UIImage).
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
                    request.addResource(with: .photo, data: captured.signedData, options: nil)
                }
                saveConfirmation = "Saved to Photos with Content Credentials."
            } catch {
                errorMessage = "Could not save: \(error.localizedDescription)"
            }
        }
    }
}
