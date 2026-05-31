import Foundation
import C2PA

/// Reads the embedded C2PA manifest store from a file as JSON, without needing
/// signing credentials (verification/inspection only).
enum ManifestReader {
    static func json(fileURL: URL, kind: MediaKind) -> String? {
        let format = kind == .photo ? "image/jpeg" : "video/quicktime"
        guard
            let stream = try? Stream(readFrom: fileURL),
            let reader = try? Reader(format: format, stream: stream)
        else { return nil }
        return try? reader.json()
    }
}
