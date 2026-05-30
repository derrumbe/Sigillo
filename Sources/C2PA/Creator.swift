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

/// Persists the creator identity across launches (UserDefaults-backed).
@MainActor
final class CreatorStore: ObservableObject {
    @Published var creator: Creator {
        didSet { persist() }
    }

    private let key = "creator.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Creator.self, from: data) {
            creator = decoded
        } else {
            creator = .empty
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(creator) {
            defaults.set(data, forKey: key)
        }
    }
}
