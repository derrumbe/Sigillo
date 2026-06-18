import SwiftUI

/// Top control strip: flash, night mode, Live Photo, timer, aspect, and the
/// creator/settings entry. Bound directly to the camera controller.
struct CameraTopControls: View {
    @ObservedObject var camera: CameraController
    @Binding var showSettings: Bool
    @Binding var showCredentialBadge: Bool

    var body: some View {
        HStack(spacing: 18) {
            // Show/hide the Content Credentials badge over the preview.
            controlButton(systemImage: showCredentialBadge ? "checkmark.seal.fill" : "checkmark.seal",
                          active: showCredentialBadge) {
                showCredentialBadge.toggle()
            }

            // Flash: off → auto → on
            controlButton(systemImage: camera.flashOption.icon,
                          active: camera.flashOption != .off) {
                let all = FlashOption.allCases
                let next = all[(all.firstIndex(of: camera.flashOption)! + 1) % all.count]
                camera.flashOption = next
            }

            // Night mode (low-light boost)
            controlButton(systemImage: "moon.stars.fill",
                          active: camera.nightModeEnabled,
                          enabled: camera.nightModeSupported) {
                camera.setNightMode(!camera.nightModeEnabled)
            }

            // Live Photo (photo mode only)
            controlButton(systemImage: camera.isLivePhotoEnabled ? "livephoto" : "livephoto.slash",
                          active: camera.isLivePhotoEnabled,
                          enabled: camera.isLivePhotoSupported && camera.captureMode == .photo) {
                camera.isLivePhotoEnabled.toggle()
            }

            // Self-timer: off → 3s → 10s
            labeledButton(systemImage: "timer", label: camera.timer.label,
                          active: camera.timer != .off) {
                let all = CaptureTimer.allCases
                camera.timer = all[(all.firstIndex(of: camera.timer)! + 1) % all.count]
            }

            // Aspect ratio: 4:3 → 16:9 → 1:1 (photo only)
            labeledButton(systemImage: "aspectratio", label: camera.aspect.rawValue,
                          active: camera.aspect != .fourThree,
                          enabled: camera.captureMode == .photo) {
                let all = AspectRatio.allCases
                camera.aspect = all[(all.firstIndex(of: camera.aspect)! + 1) % all.count]
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Creator & metadata settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.black)
    }

    private func controlButton(systemImage: String, active: Bool, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? .yellow : .white)
                .frame(width: 30, height: 30)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    private func labeledButton(systemImage: String, label: String, active: Bool,
                               enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                Text(label).font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(active ? .yellow : .white)
            .frame(minWidth: 30)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

/// Discrete zoom presets (1×, 2×, …) within the device's supported range.
struct ZoomControls: View {
    @ObservedObject var camera: CameraController

    private var presets: [CGFloat] {
        [1, 2, 3, 5].filter { $0 >= camera.minZoomFactor && $0 <= camera.maxZoomFactor }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { value in
                let selected = abs(camera.zoomFactor - value) < 0.05
                Button { camera.setZoom(value) } label: {
                    Text(selected ? String(format: "%.0f×", value) : String(format: "%g", value))
                        .font(.system(size: selected ? 14 : 12, weight: .bold))
                        .foregroundStyle(selected ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.4), in: Circle())
                }
            }
        }
        .padding(6)
        .background(.black.opacity(0.25), in: Capsule())
    }
}

/// Exposure compensation: a compact chip that reveals a radial dial when tapped.
/// The dial auto-hides a few seconds after the last adjustment.
struct ExposureControl: View {
    @ObservedObject var camera: CameraController
    @State private var open = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 10) {
            if open {
                ExposureDial(camera: camera) { scheduleHide() }
                    .frame(width: 200, height: 200)
                    .transition(.scale.combined(with: .opacity))
            }
            Button { toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                    Text(String(format: "%+.1f EV", camera.exposureBias))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(open || camera.exposureBias != 0 ? .yellow : .white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: open)
    }

    private func toggle() {
        open.toggle()
        if open { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { open = false }
        }
    }
}

/// A rotary exposure-compensation dial. Drag around the arc to set the value.
struct ExposureDial: View {
    @ObservedObject var camera: CameraController
    var onChange: () -> Void

    private let sweep = 270.0   // degrees of usable arc (gap at the bottom)
    private var lo: Float { max(camera.minExposureBias, -3) }
    private var hi: Float { min(camera.maxExposureBias, 3) }
    private var ticks: [Float] { Array(stride(from: lo, through: hi, by: Float(1))) }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2 - 10
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle().fill(.black.opacity(0.55))
                Circle().strokeBorder(.white.opacity(0.2), lineWidth: 3).padding(6)

                ForEach(ticks, id: \.self) { ev in
                    Circle()
                        .fill(ev == 0 ? .white : .white.opacity(0.45))
                        .frame(width: ev == 0 ? 6 : 4, height: ev == 0 ? 6 : 4)
                        .position(point(forValue: ev, center: center, radius: radius))
                }

                Circle()
                    .fill(.yellow)
                    .frame(width: 18, height: 18)
                    .position(point(forValue: camera.exposureBias, center: center, radius: radius))

                VStack(spacing: 0) {
                    Text(String(format: "%+.1f", camera.exposureBias))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("EV").font(.caption2)
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { update(at: $0.location, center: center) }
            )
        }
    }

    private func angle(forValue v: Float) -> Double {
        let span = max(hi - lo, 0.0001)
        let t = Double((v - lo) / span)
        return -sweep / 2 + t * sweep
    }

    private func point(forValue v: Float, center: CGPoint, radius: CGFloat) -> CGPoint {
        let rad = angle(forValue: v) * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(rad)),
                       y: center.y - radius * CGFloat(cos(rad)))
    }

    private func update(at location: CGPoint, center: CGPoint) {
        let dx = Double(location.x - center.x)
        let dy = Double(location.y - center.y)
        var deg = atan2(dx, -dy) * 180 / .pi          // 0° at top, clockwise
        deg = max(-sweep / 2, min(sweep / 2, deg))      // clamp into the arc
        let t = Float((deg + sweep / 2) / sweep)
        camera.setExposureBias(lo + t * (hi - lo))
        onChange()
    }
}

/// Bottom bar: Photo/Video mode picker and the shutter/record button.
struct CaptureBar: View {
    @ObservedObject var camera: CameraController
    let isBusy: Bool
    let onShutter: () -> Void
    let onGallery: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: Binding(
                get: { camera.captureMode },
                set: { camera.setCaptureMode($0) }
            )) {
                Text("Photo").tag(CaptureMode.photo)
                Text("Video").tag(CaptureMode.video)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(camera.isRecording || isBusy)

            ZStack {
                ShutterButton(mode: camera.captureMode, recording: camera.isRecording,
                              busy: isBusy, action: onShutter)
                HStack {
                    Button(action: onGallery) {
                        Image(systemName: "photo.stack")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Credential Roll")
                    Spacer()
                    if camera.canSwitchCamera {
                        Button { camera.switchCamera() } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .accessibilityLabel("Switch camera")
                        .disabled(camera.isRecording || isBusy)
                        .opacity(camera.isRecording || isBusy ? 0.3 : 1)
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.black)
    }
}

/// Shutter for photo, red record/stop for video, spinner while busy.
struct ShutterButton: View {
    let mode: CaptureMode
    let recording: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                if busy {
                    ProgressView().tint(.white)
                } else if mode == .video {
                    if recording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 60, height: 60)
                    }
                } else {
                    Circle().fill(.white).frame(width: 60, height: 60)
                }
            }
        }
        .disabled(busy)
    }
}

/// Full-screen countdown number shown during a self-timer.
struct CountdownOverlay: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.system(size: 120, weight: .thin, design: .rounded))
            .foregroundStyle(.white)
            .shadow(radius: 12)
            .transition(.scale.combined(with: .opacity))
    }
}
