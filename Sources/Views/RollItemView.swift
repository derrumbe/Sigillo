import SwiftUI
import AVKit

/// Full-screen viewer for a stored Credential Roll item: shows the photo/video,
/// its embedded Content Credentials (read back from the file), and Share/Rotate/
/// Delete. Rotating re-signs the photo, so `current` tracks the replacement item.
struct RollItemView: View {
    @ObservedObject var store: CredentialRollStore
    /// Rotate + re-sign a photo, returning the replacement item.
    var onRotate: ((CredentialRollStore.RollItem) async -> CredentialRollStore.RollItem?)?

    @State private var current: CredentialRollStore.RollItem
    @Environment(\.dismiss) private var dismiss

    @State private var manifestJSON = "{}"
    @State private var showRawJSON = false
    @State private var isRotating = false
    @AppStorage("showRollCredentials") private var showCredentials = true

    init(item: CredentialRollStore.RollItem,
         store: CredentialRollStore,
         onRotate: ((CredentialRollStore.RollItem) async -> CredentialRollStore.RollItem?)? = nil) {
        self._store = ObservedObject(wrappedValue: store)
        self._current = State(initialValue: item)
        self.onRotate = onRotate
    }

    private var canRotate: Bool { onRotate != nil && current.kind == .photo }

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
            .overlay {
                if isRotating {
                    ProgressView("Re-signing…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                if canRotate {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: rotate) {
                            Label("Rotate", systemImage: "rotate.right")
                        }
                        .disabled(isRotating)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: current.url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(role: .destructive) {
                        store.delete(current)
                        dismiss()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .task(id: current.url) {
                manifestJSON = ManifestReader.json(fileURL: current.url, kind: current.kind) ?? "{}"
            }
        }
    }

    private func rotate() {
        guard let onRotate, !isRotating else { return }
        isRotating = true
        Task {
            if let new = await onRotate(current) { current = new }
            isRotating = false
        }
    }

    /// Renders the photo/video. When `fill` is true (credentials hidden) the
    /// media expands to fill the available space; otherwise it sits at its
    /// natural size within the scrolling credential layout.
    @ViewBuilder
    private func mediaView(fill: Bool) -> some View {
        switch current.kind {
        case .video:
            VideoPlayer(player: AVPlayer(url: current.url))
                .frame(height: fill ? nil : 300)
                .frame(maxHeight: fill ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: fill ? 0 : 12))
        case .photo:
            if let image = UIImage(contentsOfFile: current.url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: fill ? 0 : 12))
            }
        }
    }
}
