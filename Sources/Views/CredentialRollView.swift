import SwiftUI

/// A grid gallery of signed assets stored in the app's Credential Roll. Tap an
/// item to inspect its credentials, share it, or delete it.
struct CredentialRollView: View {
    @ObservedObject var store: CredentialRollStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: CredentialRollStore.RollItem?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.items) { item in
                                RollCell(store: store, item: item)
                                    .onTapGesture { selected = item }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.delete(item)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .navigationTitle("Credential Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { item in
                RollItemView(item: item, store: store)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No saved captures yet")
                .font(.headline)
            Text("Photos and videos you capture are stored here with their "
                + "Content Credentials preserved exactly.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

/// One square thumbnail in the grid.
private struct RollCell: View {
    @ObservedObject var store: CredentialRollStore
    let item: CredentialRollStore.RollItem
    @State private var image: UIImage?

    var body: some View {
        Color.gray.opacity(0.2)
            .aspectRatio(1, contentMode: .fill)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
                if item.kind == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .task(id: item.url) {
                if image == nil { image = await store.thumbnail(for: item) }
            }
    }
}
