import SwiftUI

/// Edits the creator/author identity that gets embedded into each photo's
/// Content Credentials as a signed schema.org `CreativeWork` author assertion.
struct CreatorSettingsView: View {
    @ObservedObject var store: CreatorStore
    @Environment(\.dismiss) private var dismiss

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
