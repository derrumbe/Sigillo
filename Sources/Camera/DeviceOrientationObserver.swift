import SwiftUI
import CoreMotion

/// Reports the physical device orientation from the accelerometer.
///
/// `UIDevice.orientationDidChangeNotification` is unreliable in this app — the
/// interface is locked to portrait and the system rotation lock suppresses those
/// notifications. Reading the accelerometer directly works regardless of either,
/// so a portrait-locked view can still react to the phone being turned.
@MainActor
final class DeviceOrientationObserver: ObservableObject {
    @Published private(set) var orientation: UIDeviceOrientation = .portrait

    private let motion = CMMotionManager()
    private let queue = OperationQueue()

    func start() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.15
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let data else { return }
            let a = data.acceleration
            // Ignore near-flat (face up/down) readings: keep the last orientation.
            guard abs(a.x) > 0.4 || abs(a.y) > 0.4 else { return }

            let next: UIDeviceOrientation
            if abs(a.x) >= abs(a.y) {
                next = a.x >= 0 ? .landscapeLeft : .landscapeRight
            } else {
                next = a.y >= 0 ? .portraitUpsideDown : .portrait
            }
            Task { @MainActor [weak self] in
                guard let self, self.orientation != next else { return }
                withAnimation(.easeInOut(duration: 0.25)) { self.orientation = next }
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
    }
}
