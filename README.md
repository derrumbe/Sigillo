# C2PA Camera

An iOS camera app that takes a photo and **automatically embeds signed
[C2PA](https://spec.c2pa.org/specifications/specifications/2.4/index.html)
Content Credentials** into it before you ever see the image.

Every photo carries a cryptographically signed manifest asserting that it was
*created* by a *digital capture* on this device, plus an RFC 3161 trusted
timestamp. You can review the credential in-app and inspect the raw manifest
JSON.

## How it works

```
 AVFoundation                 c2pa-ios (Builder)              Photos
  capture  ──▶ JPEG Data ──▶  build manifest + sign  ──▶  signed JPEG ──▶ save
                              (embeds C2PA manifest)        + read back
```

- **Capture** — [`CameraController`](Sources/Camera/CameraController.swift) runs an
  `AVCaptureSession` and returns the photo as JPEG `Data`.
- **Sign + embed** — [`ContentCredentialSigner`](Sources/C2PA/ContentCredentialSigner.swift)
  builds a C2PA v2 manifest with a [`c2pa.actions`](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html#_actions)
  assertion (`c2pa.created` / digital source type `digitalCapture`), optionally an
  author credential (see below), and signs it with the
  [`c2pa-ios`](https://github.com/contentauth/c2pa-ios) SDK's `Builder`.
- **Verify** — the same SDK's `Reader` reads the manifest back out so the
  [review screen](Sources/Views/PhotoReviewView.swift) can show who signed it,
  when, and how the asset was produced.
- **Save** — the *signed file bytes* are written to the photo library (not a
  re-encoded `UIImage`), so the embedded credential survives.

Built on the open-source Content Authenticity tools:
<https://opensource.contentauthenticity.org/docs/introduction/>

## Author / creator credential

Tap the **person icon** (top-right of the camera) to set a creator name and an
optional identifier (profile URL or handle). When set, every photo gets a signed
[`stds.schema-org.CreativeWork`](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html#_creativework)
assertion with a schema.org `author`:

```json
{
  "@context": "https://schema.org",
  "@type": "CreativeWork",
  "author": [ { "@type": "Person", "name": "Jane Doe", "identifier": "https://janedoe.example" } ]
}
```

Because the assertion is covered by the C2PA **claim signature**, the attribution
is *tamper-evident* — altering the name or identifier breaks signature
validation. Verifiers (contentcredentials.org, `c2patool`) and the in-app review
screen surface it as the asset's author. The identity is stored locally in
`UserDefaults` ([`Creator`](Sources/C2PA/Creator.swift)).

> **Note on "verifiable":** this binds the author *into the signed claim*, which
> is what Content Credentials uses for attribution today. It is distinct from a
> fully *independently* verifiable creator identity — the
> [CAWG identity assertion](https://cawg.io/identity/), which cryptographically
> links the creator to an external identity (e.g. a W3C Verifiable Credential or
> an X.509 identity) via a separate identity signature. That requires an identity
> signer/credential and is a natural next step; the SDK exposes a
> `cawgIdentity` assertion for it.

## Requirements

- macOS with **Xcode 16+** (tested with Xcode 26.5)
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** — `brew install xcodegen`
- A **physical iPhone** to actually capture photos (the Simulator has no camera)
- An Apple Developer team for on-device signing

## Quick start

```bash
# 1. Generate the test signing certificate/key and the Xcode project
make bootstrap          # == make certs + make project

# 2. Open it
make open               # or: open C2PACamera.xcodeproj
```

Then in Xcode:

1. Select the **C2PACamera** target → **Signing & Capabilities** → choose your
   Team (or set `DEVELOPMENT_TEAM` in [`project.yml`](project.yml) and re-run
   `make project`).
2. Pick your iPhone as the run destination and press **▶︎ Run**.
3. Grant camera access, tap the shutter, and review the embedded Content
   Credentials.

> The project file is generated from [`project.yml`](project.yml). Edit the YAML,
> not the `.xcodeproj`, then re-run `make project`.

## Signing credentials

`make certs` runs [`scripts/make_test_certs.sh`](scripts/make_test_certs.sh),
which generates a two-link **ES256 (P-256)** chain — a root CA that issues a leaf
signing certificate — plus the leaf's PKCS#8 private key, into
`Sources/Resources/`:

| File | Purpose |
|------|---------|
| `es256_certs.pem`   | Leaf certificate **followed by the root** (full chain, PEM) |
| `es256_private.key` | The leaf's private key (PEM) |

The leaf carries the extensions the C2PA certificate profile expects of an
end-entity signer (`keyUsage = digitalSignature` critical,
`extendedKeyUsage = emailProtection`, `CA:FALSE`), and the root carries
`CA:TRUE` + `keyCertSign`.

> **Why a chain and not a single self-signed cert?** A lone self-signed leaf
> with `CA:FALSE` cannot be its own issuer under RFC 5280 path validation, so
> c2pa-rs rejects it at signing time with
> *"Signature: the certificate is invalid"*. A proper root→leaf chain fixes this.

⚠️ **These are test credentials.** Because the root is not on the
[C2PA trust list](https://opensource.contentauthenticity.org/docs/verify-known-cert-list/),
verifiers will show the signer as **untrusted / unknown** — that is expected and
correct for development. The *signature itself* is cryptographically valid and
the manifest is well-formed. For a trusted credential, obtain a certificate from
a CA on the trust list and replace the two files. For production you should also
keep the private key in the **Secure Enclave** rather than bundling it — the
`c2pa-ios` SDK supports this via `SecureEnclaveSigner` / `KeychainSigner`.

## Getting a photo off the device with credentials intact

The review screen has two export buttons:

- **Share (recommended)** — uses a `ShareLink` to share the *signed file itself*
  (e.g. AirDrop to a Mac). The exact signed bytes are transferred, so the
  embedded manifest is preserved. **Use this to verify.**
- **Save to Photos** — saves the signed bytes into the library. The stored asset
  keeps the manifest, but iOS's Photos *export/share* pipeline re-encodes in many
  flows (including "Export Unmodified Original" in some cases) and strips C2PA.
  This is a known Photos limitation, which is exactly why the in-app **Share**
  path exists.

## Verifying a captured photo

After AirDropping the photo off the device (via **Share**), verify it with any
C2PA tool:

- **Web:** <https://contentcredentials.org/verify> (drag the image in)
- **CLI:** [`c2patool`](https://github.com/contentauth/c2pa-rs/tree/main/cli)
  ```bash
  c2patool photo.jpg          # prints the manifest store
  ```

The in-app review screen does the same check locally using the SDK's `Reader`.

## Project layout

```
project.yml                         XcodeGen project spec (edit this)
Makefile                            certs / project / open / clean targets
scripts/make_test_certs.sh          generates the test ES256 cert + key
Sources/
  C2PACameraApp.swift               @main App entry point
  Camera/
    CameraController.swift          AVCaptureSession + photo capture
    CameraPreview.swift             live preview (UIViewRepresentable)
    CameraViewModel.swift           capture → sign → review orchestration
  C2PA/
    ContentCredentialSigner.swift   builds manifest, signs, reads back  ← core
    Creator.swift                   author identity model + persistence
  Views/
    CameraScreen.swift              shutter UI + creator badge / settings entry
    CreatorSettingsView.swift       edit the embedded author credential
    PhotoReviewView.swift           credential summary + raw manifest JSON + Share
  Resources/                        es256_certs.pem / es256_private.key (generated)
                                    Info.plist is generated from project.yml
```

## Dependencies

Resolved automatically by Swift Package Manager:

| Package | Version | Role |
|---------|---------|------|
| [`c2pa-ios`](https://github.com/contentauth/c2pa-ios) | 0.0.9 | C2PA reading/signing (wraps the Rust `c2pa-rs` core) |
| `swift-certificates`, `swift-asn1`, `swift-crypto` | (transitive) | X.509 / crypto |

## License

Sample/demo code. The bundled C2PA SDK is dual-licensed Apache-2.0 / MIT.
