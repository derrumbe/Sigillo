import Foundation
import C2PA

/// Embeds and verifies C2PA Content Credentials in captured photos.
///
/// This is the heart of the app. Given the raw JPEG bytes from the camera it:
///   1. Builds a C2PA v2 manifest (`ManifestDefinition`) asserting that the
///      asset was *created* by a *digital capture* (per the C2PA actions
///      assertion, https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html#_actions).
///   2. Cryptographically signs and embeds that manifest into the JPEG using the
///      `Builder` from the open-source `c2pa-ios` SDK
///      (https://github.com/contentauth/c2pa-ios).
///   3. Reads the credential back out so the UI can display it.
///
/// The signing credentials are a developer/test ES256 certificate + private key
/// bundled with the app. See `scripts/make_test_certs.sh` and `README.md`.
@MainActor
final class ContentCredentialSigner {

    /// Result of signing: the new asset bytes plus the manifest read back from them.
    struct Result {
        let signedImageData: Data
        let manifestJSON: String
        /// True if a CAWG X.509 identity assertion was successfully bound.
        let identityBound: Bool
    }

    enum SignerError: LocalizedError {
        case missingCredentials
        case emptyCredentials

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Signing certificate/key not found in the app bundle. "
                    + "Run scripts/make_test_certs.sh and rebuild."
            case .emptyCredentials:
                return "The bundled certificate or private key is empty."
            }
        }
    }

    private let certPEM: String
    private let keyPEM: String
    private let signerInfo: SignerInfo

    private static let tsaURL = "http://timestamp.digicert.com"

    /// Loads the bundled PEM certificate chain and private key.
    init() throws {
        guard
            let certURL = Bundle.main.url(forResource: "es256_certs", withExtension: "pem"),
            let keyURL = Bundle.main.url(forResource: "es256_private", withExtension: "key")
        else {
            throw SignerError.missingCredentials
        }

        let certPEM = try String(contentsOf: certURL, encoding: .utf8)
        let keyPEM = try String(contentsOf: keyURL, encoding: .utf8)
        guard !certPEM.isEmpty, !keyPEM.isEmpty else {
            throw SignerError.emptyCredentials
        }
        self.certPEM = certPEM
        self.keyPEM = keyPEM

        // A timestamp authority records *when* the asset was signed. DigiCert's
        // public RFC 3161 TSA is used here for convenience.
        self.signerInfo = SignerInfo(
            algorithm: .es256,
            certificatePEM: certPEM,
            privateKeyPEM: keyPEM,
            tsa: URL(string: Self.tsaURL)
        )
    }

    // MARK: - Signing

    /// Signs the given JPEG data, embedding Content Credentials, and returns the
    /// signed asset together with the manifest read back from it.
    ///
    /// - Parameters:
    ///   - creator: optional author identity. When non-empty it is added to the
    ///     manifest as a signed schema.org `CreativeWork` author assertion.
    ///   - bindIdentity: when `true` *and* a creator is set, also bind a CAWG
    ///     X.509 identity assertion (`cawg.identity`) that cryptographically ties
    ///     the creator's identity certificate to the author assertion. If CAWG
    ///     signing fails on this device, the method transparently falls back to a
    ///     basic signature so capture never breaks; the returned
    ///     ``Result/identityBound`` reports what actually happened.
    func sign(jpegData: Data, creator: Creator = .empty, bindIdentity: Bool = false) throws -> Result {
        let format = "image/jpeg"
        let manifest = makeManifest(format: format, creator: creator)
        let wantsIdentity = bindIdentity && !creator.normalized.isEmpty

        var identityBound = false
        let signedData: Data

        if wantsIdentity, let cawgSigner = try? Signer(settingsTOML: cawgSettingsTOML()),
           let data = try? performSign(jpegData, manifest: manifest, format: format, signer: cawgSigner) {
            signedData = data
            identityBound = true
        } else {
            // Basic path (or CAWG fall-back): explicit PEM signer.
            signedData = try performSign(
                jpegData, manifest: manifest, format: format,
                signer: try Signer(info: signerInfo)
            )
        }

        let manifestJSON = (try? readManifest(from: signedData, format: format)) ?? "{}"
        return Result(
            signedImageData: signedData,
            manifestJSON: manifestJSON,
            identityBound: identityBound
        )
    }

    /// Runs one Builder sign pass with the given signer and returns the bytes.
    ///
    /// c2pa-ios writes to a destination stream backed by a real file, so we stage
    /// the signed asset in the caches directory before reading it back.
    private func performSign(
        _ jpegData: Data,
        manifest: ManifestDefinition,
        format: String,
        signer: Signer
    ) throws -> Data {
        let outputURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let builder = try Builder(manifest: manifest)
        try builder.sign(
            format: format,
            source: try Stream(data: jpegData),
            destination: try Stream(writeTo: outputURL),
            signer: signer
        )
        return try Data(contentsOf: outputURL, options: .uncached)
    }

    /// Builds a c2pa-rs settings document (TOML) that configures both the main
    /// claim signer and a CAWG X.509 identity signer. The identity signature
    /// references the `CreativeWork` author assertion, binding the creator's
    /// X.509 identity to the attribution. The same test credential is reused for
    /// both signers (matching the SDK's own CAWG fixture).
    private func cawgSettingsTOML() -> String {
        let cert = certPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = keyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        let block: (String) -> [String] = { section in
            [
                "[\(section).local]",
                "alg = \"es256\"",
                "sign_cert = \"\"\"", cert, "\"\"\"",
                "private_key = \"\"\"", key, "\"\"\"",
                "tsa_url = \"\(Self.tsaURL)\"",
            ]
        }
        var lines = ["version = 1", "", "[core]", "decode_identity_assertions = true", ""]
        lines += block("signer")
        lines += [""]
        lines += block("cawg_x509_signer")
        lines += ["referenced_assertions = [\"\(StandardAssertionLabel.creativeWork.rawValue)\"]"]
        return lines.joined(separator: "\n")
    }

    /// Builds the C2PA manifest describing a freshly captured photo.
    private func makeManifest(format: String, creator: Creator) -> ManifestDefinition {
        let claimGenerator = ClaimGeneratorInfo(
            operatingSystem: ClaimGeneratorInfo.operatingSystem
        )

        var assertions: [AssertionDefinition] = [
            // c2pa.actions: this asset was created by capturing it on a camera.
            .actions(actions: [
                Action(action: .created, digitalSourceType: .digitalCapture)
            ])
        ]

        // Attribution: a signed schema.org CreativeWork author assertion.
        if let creativeWork = Self.creativeWorkData(for: creator) {
            assertions.append(.creativeWork(data: creativeWork))
        }

        return ManifestDefinition(
            assertions: assertions,
            claimGeneratorInfo: [claimGenerator],
            format: format,
            title: "C2PA Camera \(Self.timestamp).jpg"
        )
    }

    /// Builds the schema.org `CreativeWork` payload for the given creator, or
    /// `nil` if no creator name is set.
    ///
    /// Produces JSON-LD of the form:
    /// ```json
    /// {
    ///   "@context": "https://schema.org",
    ///   "@type": "CreativeWork",
    ///   "author": [ { "@type": "Person", "name": "...", "identifier": "..." } ]
    /// }
    /// ```
    private static func creativeWorkData(for creator: Creator) -> [String: AnyCodable]? {
        let creator = creator.normalized
        guard !creator.isEmpty else { return nil }

        var author: [String: Any] = [
            "@type": "Person",
            "name": creator.name
        ]
        if !creator.identifier.isEmpty {
            author["identifier"] = creator.identifier
        }

        return [
            "@context": AnyCodable("https://schema.org"),
            "@type": AnyCodable("CreativeWork"),
            "author": AnyCodable([author])
        ]
    }

    // MARK: - Verification / read-back

    /// Reads the embedded manifest store out of a signed asset as pretty JSON.
    func readManifest(from data: Data, format: String = "image/jpeg") throws -> String {
        let reader = try Reader(format: format, stream: try Stream(data: data))
        return try reader.json()
    }

    private static var timestamp: String {
        ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withInternetDateTime]
        )
        .replacingOccurrences(of: ":", with: ".")
    }
}
