import AVFoundation
import CoreMedia
import ImageIO
import UIKit

/// A dedicated, app-private gallery of signed assets.
///
/// Files are stored verbatim in the app's Application Support directory, so the
/// embedded C2PA manifest is preserved exactly — unlike the system Photos
/// pipeline, which re-encodes (and strips credentials) on many export paths.
@MainActor
final class CredentialRollStore: ObservableObject {

    struct RollItem: Identifiable, Hashable {
        let url: URL
        let kind: MediaKind
        let date: Date
        var id: URL { url }
    }

    @Published private(set) var items: [RollItem] = []

    private let directory: URL
    private var thumbnailCache: [URL: UIImage] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("CredentialRoll", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        items = urls.compactMap { url -> RollItem? in
            guard let kind = Self.kind(for: url) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return RollItem(url: url, kind: kind, date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// Copies a signed asset into the roll. Returns the stored item.
    @discardableResult
    func add(from source: URL, kind: MediaKind) -> RollItem? {
        let ext = kind == .photo ? "jpg" : "mov"
        let dest = directory.appendingPathComponent("Sigillo \(Self.timestamp).\(ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: source, to: dest)
        } catch {
            return nil
        }
        reload()
        return items.first { $0.url == dest }
    }

    func delete(_ item: RollItem) {
        try? FileManager.default.removeItem(at: item.url)
        thumbnailCache[item.url] = nil
        reload()
    }

    /// Returns a cached thumbnail, generating it off the main actor on first use.
    func thumbnail(for item: RollItem) async -> UIImage? {
        if let cached = thumbnailCache[item.url] { return cached }
        let url = item.url
        let kind = item.kind
        let image = await Task.detached(priority: .utility) {
            kind == .photo ? RollThumbnailer.image(url) : RollThumbnailer.video(url)
        }.value
        if let image { thumbnailCache[item.url] = image }
        return image
    }

    private static func kind(for url: URL) -> MediaKind? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "heic": return .photo
        case "mov", "mp4": return .video
        default: return nil
        }
    }

    private static var timestamp: String {
        ISO8601DateFormatter.string(
            from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]
        ).replacingOccurrences(of: ":", with: ".")
    }
}

/// Off-actor thumbnail generation.
enum RollThumbnailer {
    static func image(_ url: URL, maxPixel: CGFloat = 600) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    static func video(_ url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cg = try? generator.copyCGImage(
            at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil
        ) else { return nil }
        return UIImage(cgImage: cg)
    }
}
