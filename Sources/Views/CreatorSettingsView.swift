import SwiftUI

/// Edits the creator/author identity that gets embedded into each photo's
/// Content Credentials as a signed schema.org `CreativeWork` author assertion.
struct CreatorSettingsView: View {
    @ObservedObject var store: CreatorStore
    @Environment(\.dismiss) private var dismiss

    /// Called when the Location toggle is switched on, so the host can request
    /// location permission and start updates.
    var onLocationEnabled: () -> Void = {}

    @State private var name = ""
    @State private var identifier = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Profile URL or handle (optional)", text: $identifier)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Creator")
                } footer: {
                    Text("Embedded in every photo as a signed schema.org "
                        + "CreativeWork author assertion. Because it is part of "
                        + "the C2PA claim signature, the attribution is "
                        + "tamper-evident. Leave the name blank to omit it.")
                }

                Section {
                    Toggle("Bind verifiable identity (CAWG)", isOn: $store.bindIdentity)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("Adds a CAWG X.509 identity assertion (cawg.identity) that "
                        + "cryptographically binds an identity certificate to the "
                        + "author assertion — the C2PA way to attach a verifiable "
                        + "creator credential. Requires a creator name. If identity "
                        + "signing fails on this device, the photo is still signed "
                        + "with the basic author assertion.")
                }

                Section {
                    Toggle("Location (GPS)", isOn: $store.metadata.location)
                    Toggle("Date & time", isOn: $store.metadata.dateTime)
                    Toggle("Camera settings", isOn: $store.metadata.cameraSettings)
                    Toggle("Device & iOS", isOn: $store.metadata.deviceInfo)
                } header: {
                    Text("Capture metadata")
                } footer: {
                    Text("Each enabled category is embedded in a signed stds.exif "
                        + "assertion: GPS coordinates, capture date/time, camera "
                        + "settings (focal length, aperture, exposure, ISO, lens), "
                        + "and the device model + iOS version. Location requires "
                        + "permission and is off by default.")
                }
                .onChange(of: store.metadata.location) { enabled in
                    if enabled { onLocationEnabled() }
                }
            }
            .navigationTitle("Creator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        store.creator = Creator(name: name, identifier: identifier).normalized
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = store.creator.name
                identifier = store.creator.identifier
            }
        }
    }
}
