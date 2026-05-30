import SwiftUI

/// Root screen: live camera preview with a shutter button. After capture it
/// presents the signed photo and its Content Credentials for review.
struct CameraScreen: View {
    @StateObject private var model = CameraViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch model.camera.status {
            case .unauthorized:
                permissionDenied
            case .failed:
                message("Camera unavailable on this device.")
            default:
                cameraUI
            }
        }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
        .sheet(item: $model.captured) { photo in
            PhotoReviewView(photo: photo, model: model)
        }
        .sheet(isPresented: $showSettings) {
            CreatorSettingsView(store: model.creatorStore)
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
            CameraPreview(session: model.camera.session)
                .ignoresSafeArea(edges: .top)

            ZStack {
                Color.black
                ShutterButton(isBusy: model.isBusy) { model.capture() }
            }
            .frame(height: 160)
        }
        .overlay(alignment: .top) {
            CredentialBadge(store: model.creatorStore)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding([.top, .trailing], 12)
            .accessibilityLabel("Creator settings")
        }
    }

    private var permissionDenied: some View {
        message(
            "Camera access is required.\nEnable it in Settings → Privacy → Camera."
        )
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding()
    }
}

/// Top badge showing that signing is on, plus the current creator if set.
private struct CredentialBadge: View {
    @ObservedObject var store: CreatorStore

    var body: some View {
        Label(text, systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var text: String {
        store.creator.isEmpty
            ? "Content Credentials on"
            : "Signed as \(store.creator.name)"
    }
}

/// The circular shutter button, showing a spinner while capture/signing runs.
private struct ShutterButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
        }
        .disabled(isBusy)
    }
}
