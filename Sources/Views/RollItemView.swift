import SwiftUI
import AVKit

/// Full-screen viewer for a stored Credential Roll item: shows the photo/video,
/// its embedded Content Credentials (read back from the file), and Share/Delete.
struct RollItemView: View {
    let item: CredentialRollStore.RollItem
    @ObservedObject var store: CredentialRollStore
    @Environment(\.dismiss) private var dismiss

    @State private var manifestJSON = "{}"
    @State private var showRawJSON = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    media
                    CredentialSummaryCard(manifestJSON: manifestJSON)
                    DisclosureGroup("Raw manifest JSON", isExpanded: $showRawJSON) {
                        Text(manifestJSON)
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
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: item.url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        store.delete(item)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .task(id: item.url) {
                manifestJSON = ManifestReader.json(fileURL: item.url, kind: item.kind) ?? "{}"
            }
        }
    }

    @ViewBuilder
    private var media: some View {
        switch item.kind {
        case .video:
            VideoPlayer(player: AVPlayer(url: item.url))
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .photo:
            if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
