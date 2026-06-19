import SwiftUI
import AVKit
import Combine

/// Full-screen viewer for a stored Credential Roll item: shows the photo/video,
/// its embedded Content Credentials (read back from the file), and Share/Rotate/
/// Delete. Rotating re-signs the photo, so `current` tracks the replacement item.
///
/// The app is locked to portrait, so to let a landscape photo use the full
/// landscape real estate this view watches the *physical* device orientation and
/// rotates the media itself when the phone is turned sideways.
struct RollItemView: View {
    @ObservedObject var store: CredentialRollStore
    /// Rotate + re-sign a photo, returning the replacement item.
    var onRotate: ((CredentialRollStore.RollItem) async -> CredentialRollStore.RollItem?)?

    @State private var current: CredentialRollStore.RollItem
    @Environment(\.dismiss) private var dismiss

    @State private var manifestJSON = "{}"
    @State private var showRawJSON = false
    @State private var isRotating = false
    @State private var deviceOrientation: UIDeviceOrientation = .portrait
    @AppStorage("showRollCredentials") private var showCredentials = true

    init(item: CredentialRollStore.RollItem,
         store: CredentialRollStore,
         onRotate: ((CredentialRollStore.RollItem) async -> CredentialRollStore.RollItem?)? = nil) {
        self._store = ObservedObject(wrappedValue: store)
        self._current = State(initialValue: item)
        self.onRotate = onRotate
    }

    private var canRotate: Bool { onRotate != nil && current.kind == .photo }

    private var isLandscape: Bool {
        deviceOrientation == .landscapeLeft || deviceOrientation == .landscapeRight
    }

    /// Counter-rotation applied to the media so it appears upright while the
    /// phone is held in landscape (the UI itself stays portrait).
    private var contentRotation: Angle {
        switch deviceOrientation {
        case .landscapeLeft: return .degrees(90)
        case .landscapeRight: return .degrees(-90)
        default: return .degrees(0)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLandscape {
                    landscapeMedia
                } else if showCredentials {
                    portraitWithCredentials
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
            // Hide the chrome in landscape for a full-bleed view; rotate back to
            // portrait for the toolbar actions.
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            .toolbar { toolbarContent }
            .task(id: current.url) {
                manifestJSON = ManifestReader.json(fileURL: current.url, kind: current.kind) ?? "{}"
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                updateOrientation(UIDevice.current.orientation)
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIDevice.orientationDidChangeNotification)) { _ in
                updateOrientation(UIDevice.current.orientation)
            }
        }
    }

    // MARK: - Layouts

    private var portraitWithCredentials: some View {
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
    }

    /// Media rotated to match the landscape-held phone, sized against the swapped
    /// screen dimensions so a landscape photo fills the available space.
    private var landscapeMedia: some View {
        GeometryReader { geo in
            mediaView(fill: true)
                .frame(width: geo.size.height, height: geo.size.width)
                .rotationEffect(contentRotation)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    // MARK: - Actions

    private func updateOrientation(_ o: UIDeviceOrientation) {
        guard o == .portrait || o == .landscapeLeft || o == .landscapeRight else { return }
        withAnimation(.easeInOut(duration: 0.25)) { deviceOrientation = o }
    }

    private func rotate() {
        guard let onRotate, !isRotating else { return }
        isRotating = true
        Task {
            if let new = await onRotate(current) { current = new }
            isRotating = false
        }
    }

    /// Renders the photo/video. When `fill` is true the media expands to fill the
    /// available space; otherwise it sits at its natural size within the
    /// scrolling credential layout.
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
