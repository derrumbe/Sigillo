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
    @AppStorage("showRollCredentials") private var showCredentials = true

    var body: some View {
        NavigationStack {
            Group {
                if showCredentials {
                    ScrollView {
                        VStack(spacing: 16) {
                            mediaView(fill: false)
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
                } else {
                    // Credentials hidden: let the media fill the screen.
                    mediaView(fill: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }
            .navigationTitle("Content Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCredentials.toggle()
                    } label: {
                        Label(showCredentials ? "Hide Credentials" : "Show Credentials",
                              systemImage: showCredentials ? "eye.slash" : "eye")
                    }
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

    /// Renders the photo/video. When `fill` is true (credentials hidden) the
    /// media expands to fill the available space; otherwise it sits at its
    /// natural size within the scrolling credential layout.
    @ViewBuilder
    private func mediaView(fill: Bool) -> some View {
        switch item.kind {
        case .video:
            VideoPlayer(player: AVPlayer(url: item.url))
                .frame(height: fill ? nil : 300)
                .frame(maxHeight: fill ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: fill ? 0 : 12))
        case .photo:
            if let image = UIImage(contentsOfFile: item.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: fill ? 0 : 12))
            }
        }
    }
}
