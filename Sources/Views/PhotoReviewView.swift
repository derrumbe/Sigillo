import SwiftUI

/// Shows the freshly captured photo/video, a human-readable summary of its
/// embedded Content Credentials, and the raw manifest JSON for inspection.
struct PhotoReviewView: View {
    let item: CameraViewModel.CapturedItem
    @ObservedObject var model: CameraViewModel

    @State private var showRawJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    preview

                    credentialSummary

                    if let confirmation = model.saveConfirmation {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }

                    if item.savedToRoll {
                        Label("Saved to Credential Roll", systemImage: "checkmark.seal.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            model.addCurrentToRoll()
                        } label: {
                            Label("Add to Credential Roll", systemImage: "square.stack.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    DisclosureGroup("Raw manifest JSON", isExpanded: $showRawJSON) {
                        Text(item.manifestJSON)
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
                    ShareLink(item: item.fileURL) {
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

    @ViewBuilder
    private var preview: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.3))
                    .frame(height: 220)
                    .overlay(Image(systemName: "video.fill").font(.largeTitle).foregroundStyle(.white))
            }
            if item.kind == .video {
                Label("Video", systemImage: "video.fill")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
    }

    private var credentialSummary: some View {
        let info = ManifestSummary(json: item.manifestJSON)
        return VStack(alignment: .leading, spacing: 10) {
            Label("Signed Content Credential embedded", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if item.identityBound {
                Label("Verifiable identity bound (CAWG X.509)", systemImage: "person.badge.shield.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            } else if item.identityRequested {
                Label("Identity not bound — basic author only", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            summaryRow("Author", info.author)
            summaryRow("Produced by", info.claimGenerator)
            summaryRow("Action", info.action)
            summaryRow("Source type", info.digitalSourceType)
            summaryRow("Device", info.device)
            summaryRow("Camera", info.cameraSummary)
            summaryRow("Captured", info.captureTime)
            summaryRow("Location", info.location)
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
