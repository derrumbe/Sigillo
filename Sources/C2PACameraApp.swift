import SwiftUI

/// Entry point for the C2PA Camera app.
///
/// The app captures a photo with the device camera and, before showing it to the
/// user, embeds a cryptographically signed C2PA manifest ("Content Credentials")
/// describing how the image was created. See ``ContentCredentialSigner`` for the
/// signing pipeline and `README.md` for the spec references.
@main
struct C2PACameraApp: App {
    var body: some Scene {
        WindowGroup {
            CameraScreen()
                .preferredColorScheme(.dark)
        }
    }
}
