import SwiftUI

/// Root screen: live preview with the full control set (mode, zoom, flash,
/// exposure, night mode, aspect, timer, Live Photos), then a signed-credential
/// review of each capture.
struct CameraScreen: View {
    @StateObject private var model = CameraViewModel()
    @State private var showSettings = false
    @State private var showRoll = false
    @State private var pinchBase: CGFloat = 1
    @AppStorage("showCredentialBadge") private var showCredentialBadge = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.camera.status {
            case .unauthorized:
                message("Camera access is required.\nEnable it in Settings → Privacy → Camera.")
            case .failed:
                message("Camera unavailable on this device.")
            default:
                cameraUI
            }

            if let value = model.countdown {
                CountdownOverlay(value: value)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.countdown)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .sheet(item: $model.captured) { item in
            PhotoReviewView(item: item, model: model)
        }
        .sheet(isPresented: $showSettings) {
            CreatorSettingsView(store: model.creatorStore) { model.enableLocation() }
        }
        .sheet(isPresented: $showRoll) {
            CredentialRollView(store: model.rollStore)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var cameraUI: some View {
        VStack(spacing: 0) {
            CameraTopControls(camera: model.camera, showSettings: $showSettings,
                              showCredentialBadge: $showCredentialBadge)

            ZStack {
                CameraPreview(session: model.camera.session,
                              onPrimaryCapture: { model.shutter() })
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in model.camera.setZoom(pinchBase * scale) }
                            .onEnded { _ in pinchBase = model.camera.zoomFactor }
                    )

                VStack {
                    if showCredentialBadge {
                        Button { showCredentialBadge = false } label: {
                            Label(badgeText, systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tap to hide")
                        .padding(.top, 8)
                    }
                    Spacer()
                    ExposureControl(camera: model.camera)
                        .padding(.bottom, 8)
                    ZoomControls(camera: model.camera)
                        .padding(.bottom, 12)
                }
            }
            .clipped()

            CaptureBar(camera: model.camera, isBusy: model.isBusy,
                       onShutter: { model.shutter() },
                       onGallery: { showRoll = true })
        }
    }

    private var badgeText: String {
        let creator = model.creatorStore.creator
        return creator.isEmpty ? "Content Credentials on" : "Signed as \(creator.name)"
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding()
    }
}
