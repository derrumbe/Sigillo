import SwiftUI

/// Shows the freshly captured photo, a human-readable summary of its embedded
/// Content Credentials, and the raw manifest JSON for inspection.
struct PhotoReviewView: View {
    let photo: CameraViewModel.CapturedPhoto
    @ObservedObject var model: CameraViewModel

    @State private var showRawJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    credentialSummary

                    if let confirmation = model.saveConfirmation {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    DisclosureGroup("Raw manifest JSON", isExpanded: $showRawJSON) {
                        Text(photo.manifestJSON)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 4)
                }
                .padding()
            }
            .navigationTitle("Content Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { model.dismissReview() }
                }
                // Share/AirDrop the signed file directly. This transfers the exact
                // signed bytes, so the embedded Content Credentials are preserved —
                // unlike exporting the "original" from the Photos app, which can
                // re-encode and strip the manifest.
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: photo.fileURL,
                        preview: SharePreview("C2PA Photo", image: Image(uiImage: photo.image))
                    ) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        model.saveToLibrary()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
    }

    private var credentialSummary: some View {
        let info = ManifestSummary(json: photo.manifestJSON)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Signed Content Credential embedded", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if photo.identityBound {
                Label("Verifiable identity bound (CAWG X.509)", systemImage: "person.badge.shield.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if photo.identityRequested {
                Label("Identity not bound — basic author only", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            summaryRow("Author", info.author)
            summaryRow("Produced by", info.claimGenerator)
            summaryRow("Action", info.action)
            summaryRow("Source type", info.digitalSourceType)
            summaryRow("Signed by", info.issuer)
            summaryRow("Signed at", info.signedAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func summaryRow(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
        }
    }
}

/// Pulls a few friendly fields out of the manifest-store JSON returned by the
/// C2PA `Reader` so we can show them without dumping raw JSON at the user.
private struct ManifestSummary {
    let author: String?
    let claimGenerator: String?
    let action: String?
    let digitalSourceType: String?
    let issuer: String?
    let signedAt: String?

    init(json: String) {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            author = nil; claimGenerator = nil; action = nil
            digitalSourceType = nil; issuer = nil; signedAt = nil
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

        let signatureInfo = active?["signature_info"] as? [String: Any]
        issuer = signatureInfo?["issuer"] as? String
        signedAt = signatureInfo?["time"] as? String
    }
}
