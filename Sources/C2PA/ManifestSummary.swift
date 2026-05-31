import SwiftUI

/// Pulls a few friendly fields out of the manifest-store JSON returned by the
/// C2PA `Reader` so we can show them without dumping raw JSON at the user.
struct ManifestSummary {
    let author: String?
    let claimGenerator: String?
    let action: String?
    let digitalSourceType: String?
    let issuer: String?
    let signedAt: String?
    let hasIdentityAssertion: Bool
    // Capture metadata (from the stds.exif assertion).
    let device: String?
    let captureTime: String?
    let cameraSummary: String?
    let location: String?

    init(json: String) {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            author = nil; claimGenerator = nil; action = nil
            digitalSourceType = nil; issuer = nil; signedAt = nil
            hasIdentityAssertion = false
            device = nil; captureTime = nil; cameraSummary = nil; location = nil
            return
        }

        let activeLabel = root["active_manifest"] as? String
        let manifests = root["manifests"] as? [String: Any]
        let active = (manifests?[activeLabel ?? ""] as? [String: Any])
            ?? manifests?.values.first as? [String: Any]

        claimGenerator = (active?["claim_generator_info"] as? [[String: Any]])?
            .first?["name"] as? String
            ?? active?["claim_generator"] as? String

        let assertions = active?["assertions"] as? [[String: Any]]
        let actionsAssertion = assertions?.first {
            ($0["label"] as? String)?.hasPrefix("c2pa.actions") ?? false
        }
        let firstAction = ((actionsAssertion?["data"] as? [String: Any])?["actions"]
            as? [[String: Any]])?.first
        action = firstAction?["action"] as? String
        digitalSourceType = firstAction?["digitalSourceType"] as? String
            ?? firstAction?["digital_source_type"] as? String

        // schema.org CreativeWork author assertion (the creator credential).
        let creativeWork = assertions?.first {
            ($0["label"] as? String)?.hasPrefix("stds.schema-org.CreativeWork") ?? false
        }
        let authors = (creativeWork?["data"] as? [String: Any])?["author"] as? [[String: Any]]
        author = authors?.compactMap { person -> String? in
            guard let name = person["name"] as? String else { return nil }
            if let id = person["identifier"] as? String, !id.isEmpty {
                return "\(name) (\(id))"
            }
            return name
        }.joined(separator: ", ")

        hasIdentityAssertion = assertions?.contains {
            ($0["label"] as? String)?.hasPrefix("cawg.identity") ?? false
        } ?? false

        let signatureInfo = active?["signature_info"] as? [String: Any]
        issuer = signatureInfo?["issuer"] as? String
        signedAt = signatureInfo?["time"] as? String

        // EXIF capture-metadata assertion.
        let exif = (assertions?.first { ($0["label"] as? String) == "stds.exif" }?["data"])
            as? [String: Any]
        func ex(_ key: String) -> String? { exif?["exif:\(key)"] as? String }

        if let model = ex("Model") {
            device = [model, ex("Software")].compactMap { $0 }.joined(separator: " · ")
        } else {
            device = nil
        }
        captureTime = ex("DateTimeOriginal")

        let camera = [
            ex("FNumber").map { "ƒ/\($0)" },
            ex("ExposureTime").map { "\($0)s" },
            ex("ISOSpeedRatings").map { "ISO \($0)" },
            ex("FocalLength").map { "\($0)mm" },
            ex("LensModel"),
        ].compactMap { $0 }
        cameraSummary = camera.isEmpty ? nil : camera.joined(separator: " · ")

        if let lat = ex("GPSLatitude"), let lon = ex("GPSLongitude") {
            location = "\(lat), \(lon)"
        } else {
            location = nil
        }
    }
}

/// Reusable card that renders a `ManifestSummary` (used by the roll item viewer;
/// the capture review screen renders its own variant with live identity state).
struct CredentialSummaryCard: View {
    let manifestJSON: String

    var body: some View {
        let info = ManifestSummary(json: manifestJSON)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Signed Content Credential", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if info.hasIdentityAssertion {
                Label("Verifiable identity (CAWG X.509)", systemImage: "person.badge.shield.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }

            row("Author", info.author)
            row("Produced by", info.claimGenerator)
            row("Action", info.action)
            row("Device", info.device)
            row("Camera", info.cameraSummary)
            row("Captured", info.captureTime)
            row("Location", info.location)
            row("Signed by", info.issuer)
            row("Signed at", info.signedAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                Text(value).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
        }
    }
}
