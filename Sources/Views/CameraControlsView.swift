import SwiftUI

/// Top control strip: flash, night mode, Live Photo, timer, aspect, and the
/// creator/settings entry. Bound directly to the camera controller.
struct CameraTopControls: View {
    @ObservedObject var camera: CameraController
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 18) {
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

/// Exposure compensation as discrete EV stops (not a continuous slider),
/// matching the zoom-preset style.
struct ExposureControls: View {
    @ObservedObject var camera: CameraController

    private var stops: [Float] {
        [-2, -1, 0, 1, 2].filter { $0 >= camera.minExposureBias && $0 <= camera.maxExposureBias }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plusminus.circle.fill")
                .font(.caption2).foregroundStyle(.white).padding(.trailing, 2)
            ForEach(stops, id: \.self) { ev in
                let selected = abs(camera.exposureBias - ev) < 0.05
                Button { camera.setExposureBias(ev) } label: {
                    Text(label(ev))
                        .font(.system(size: selected ? 13 : 12, weight: .bold))
                        .foregroundStyle(selected ? .yellow : .white)
                        .frame(width: 38, height: 34)
                        .background(.black.opacity(0.4), in: Capsule())
                }
            }
        }
        .padding(6)
        .background(.black.opacity(0.25), in: Capsule())
    }

    private func label(_ ev: Float) -> String {
        ev == 0 ? "0" : String(format: "%+.0f", ev)
    }
}

/// Bottom bar: Photo/Video mode picker and the shutter/record button.
struct CaptureBar: View {
    @ObservedObject var camera: CameraController
    let isBusy: Bool
    let onShutter: () -> Void

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

            ShutterButton(mode: camera.captureMode, recording: camera.isRecording,
                          busy: isBusy, action: onShutter)
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
