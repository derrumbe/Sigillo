import Foundation

/// The author/creator identity embedded into each photo's Content Credentials.
///
/// This is surfaced in the C2PA manifest as a `stds.schema-org.CreativeWork`
/// assertion with a schema.org `author`. Because the assertion is part of the
/// signed claim, the attribution is tamper-evident: any change to it invalidates
/// the manifest signature.
struct Creator: Codable, Equatable {
    /// Display name, e.g. "Jane Doe". When empty, no author assertion is added.
    var name: String
    /// Optional identifier — a profile/website URL or social handle.
    var identifier: String

    static let empty = Creator(name: "", identifier: "")

    var isEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Trimmed copy suitable for embedding.
    var normalized: Creator {
        Creator(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

/// Which capture-metadata categories to embed into each photo's `stds.exif`
/// assertion. Each is an independent runtime opt-in.
struct MetadataOptions: Codable, Equatable {
    /// GPS latitude/longitude/altitude (requires location permission).
    var location: Bool
    /// Capture date and time.
    var dateTime: Bool
    /// Camera settings: focal length, aperture, exposure, ISO, lens, etc.
    var cameraSettings: Bool
    /// Device make/model and iOS version.
    var deviceInfo: Bool

    /// Sensible defaults: everything except the privacy-sensitive location.
    static let `default` = MetadataOptions(
        location: false, dateTime: true, cameraSettings: true, deviceInfo: true
    )

    var anyEnabled: Bool { location || dateTime || cameraSettings || deviceInfo }
}

/// Persists the creator identity and metadata options (UserDefaults-backed).
@MainActor
final class CreatorStore: ObservableObject {
    @Published var creator: Creator {
        didSet { persist() }
    }

    /// When enabled, photos also get a CAWG X.509 identity assertion binding the
    /// creator's identity certificate to the author assertion (a "verifiable
    /// credential" in the C2PA/CAWG sense).
    @Published var bindIdentity: Bool {
        didSet { defaults.set(bindIdentity, forKey: identityKey) }
    }

    /// Capture-metadata categories to embed.
    @Published var metadata: MetadataOptions {
        didSet {
            if let data = try? JSONEncoder().encode(metadata) {
                defaults.set(data, forKey: metadataKey)
            }
        }
    }

    /// Automatically save every signed capture to the in-app Credential Roll.
    @Published var autoSaveToRoll: Bool {
        didSet { defaults.set(autoSaveToRoll, forKey: rollKey) }
    }

    private let key = "creator.v1"
    private let identityKey = "creator.bindIdentity.v1"
    private let metadataKey = "creator.metadata.v1"
    private let rollKey = "creator.autoSaveToRoll.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Creator.self, from: data) {
            creator = decoded
        } else {
            creator = .empty
        }
        bindIdentity = defaults.bool(forKey: identityKey)
        if let data = defaults.data(forKey: metadataKey),
           let decoded = try? JSONDecoder().decode(MetadataOptions.self, from: data) {
            metadata = decoded
        } else {
            metadata = .default
        }
        autoSaveToRoll = defaults.object(forKey: rollKey) as? Bool ?? true
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(creator) {
            defaults.set(data, forKey: key)
        }
    }
}
