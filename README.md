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

## Camera controls

The capture screen ([CameraControlsView](Sources/Views/CameraControlsView.swift),
driven by [CameraController](Sources/Camera/CameraController.swift)) offers:

| Control | Notes |
|---|---|
| **Photo / Video** | Segmented mode switch. Video records QuickTime and is signed the same way (`video/quicktime` manifest). |
| **Zoom** | Pinch-to-zoom plus 1×/2×/3×/5× presets, clamped to the device's range (uses the best back virtual camera). |
| **Flash** | Off / Auto / On — photo flash, or torch while recording video. |
| **Exposure** | Exposure-bias slider over the device's supported range. |
| **Aspect ratio** | 4:3 (native), 16:9, 1:1 — photos are center-cropped at full resolution ([ImageCrop](Sources/Camera/ImageCrop.swift)). |
| **Timer** | Off / 3s / 10s self-timer with an on-screen countdown. |
| **Live Photos** | Captures the paired movie; the **still carries the credential**, and the (unsigned) movie is kept so the Live Photo pairing survives a save to Photos. |
| **Night mode** | Toggles low-light boost where supported. *Note:* Apple does not expose its computational Night Mode for stills to third-party apps, so this is the closest public-API equivalent, not the system Night Mode. |

Camera settings (focal length, exposure, ISO, lens, …) are read from
`AVCapturePhoto.metadata` and, when the Camera-settings toggle is on, embedded in
the signed `stds.exif` assertion — so they survive the aspect-ratio crop.

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

### Verifiable identity (CAWG)

The `CreativeWork` author above is bound into the C2PA claim, but it's just a
*name* — it doesn't prove the creator is who they say. For a genuinely
verifiable creator identity, enable **Bind verifiable identity (CAWG)** in the
creator settings. Each photo then also gets a
[CAWG identity assertion](https://cawg.io/identity/) (`cawg.identity`): a
separate identity signature, made with an X.509 identity certificate, over the
author assertion. This is the C2PA-native "verifiable credential for the
creator" — a verifier can independently check the identity signature and the
certificate behind it, not just read a name.

Implementation ([`ContentCredentialSigner.cawgSettingsTOML`](Sources/C2PA/ContentCredentialSigner.swift)):
the SDK's settings-based signer ([`Signer(settingsTOML:)`](https://github.com/contentauth/c2pa-ios))
is configured with both a `[signer.local]` (claim signer) and a
`[cawg_x509_signer.local]` whose `referenced_assertions` points at the
`stds.schema-org.CreativeWork` author assertion.

Notes:

- It's **opt-in** and **degrades gracefully** — if CAWG signing fails on a given
  device, the photo is still signed with the basic author assertion, and the
  review screen says so. (Verify it works on your device before relying on it.)
- The claim and the identity assertion are signed by **distinct credentials**:
  the claim signer uses `es256_certs.pem` / `es256_private.key`, while the
  `cawg_x509_signer` uses a separate `identity_certs.pem` / `identity_private.key`
  (subject `CN=C2PA Camera Creator Identity`), both issued by the same test root.
  In a real deployment the identity certificate would be issued to the actual
  creator (its subject identifying them) — or you'd use the CAWG *identity claims
  aggregation* flavor backed by a W3C Verifiable Credential. If the identity
  files are absent, the signer falls back to reusing the claim credential.
- Reading is enabled via `core.decode_identity_assertions = true` so verifiers
  expand the identity assertion.

## Capture metadata

The creator settings also let you choose, **per category at runtime**, what
capture metadata to embed. Enabled categories are written to a signed
[`stds.exif`](https://spec.c2pa.org/specifications/specifications/2.4/specs/C2PA_Specification.html#_exif_information)
assertion (so the metadata is covered by the claim signature and tamper-evident):

| Toggle | Embedded EXIF fields |
|--------|----------------------|
| **Location (GPS)** | `exif:GPSLatitude`, `exif:GPSLongitude`, `exif:GPSAltitude`, `exif:GPSTimeStamp` |
| **Date & time**    | `exif:DateTimeOriginal`, `exif:DateTimeDigitized` |
| **Camera settings**| `exif:FocalLength`, `FocalLengthIn35mmFilm`, `FNumber`, `ApertureValue`, `ExposureTime`, `ShutterSpeedValue`, `ExposureBiasValue`, `ISOSpeedRatings`, `WhiteBalance`, `Flash`, `LensModel`, … |
| **Device & iOS**   | `exif:Make` (Apple), `exif:Model` (e.g. `iPhone16,2`), `exif:Software` (iOS version) |

Camera settings are read from the EXIF the camera already embeds in the JPEG;
GPS comes from CoreLocation ([`LocationProvider`](Sources/Camera/LocationProvider.swift));
the assertion is assembled by
[`CaptureMetadataBuilder`](Sources/Camera/CaptureMetadataBuilder.swift). Defaults:
date/time, camera settings, and device info **on**; location **off** (it needs
permission). The review screen shows the embedded values, and they round-trip to
`c2patool` / contentcredentials.org.

> **Privacy:** location is opt-in and only requested when you enable it. As with
> all the metadata here, it's embedded in the signed credential and travels with
> the photo — share accordingly.

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
which mints a test root CA and issues **two distinct ES256 (P-256) leaves** from
it — one for the claim signer and one for the creator identity — each as a
full chain (leaf + root) plus its PKCS#8 private key, into `Sources/Resources/`:

| File | Purpose |
|------|---------|
| `es256_certs.pem` / `es256_private.key`       | Claim signer (signs the C2PA manifest) |
| `identity_certs.pem` / `identity_private.key` | Creator identity (signs the CAWG `cawg.identity` assertion) |

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

### Why a trusted certificate matters (what shows up in verifiers)

Test certificates produce a **fully valid** credential — `c2patool` reports
`validation_state: "Valid"`, every assertion hash matches, and even the CAWG
identity signature validates. But because the signing cert isn't on the C2PA
trust list, the issuer is **untrusted**, and that changes what *consumer*
verifiers display:

- **`c2patool` shows everything** regardless of trust — author, full `stds.exif`
  (camera/GPS/device), the CAWG identity, etc. Use it as the authoritative view.
- **[contentcredentials.org/verify](https://contentcredentials.org/verify)
  collapses to a minimal view for untrusted provenance** — it leads with
  "the issuer couldn't be recognized" and shows only the issuer, the claim
  generator, and the actions. It will *not* surface the author, EXIF, location,
  or the (untrusted) CAWG identity, even though they're present and valid. It
  also labels "App or device used" from the **signing certificate's common
  name**, not from `claim_generator_info`.

To make the richer cards (producer/identity, location map, capture info) appear
in consumer verifiers, sign with a certificate issued by a CA on the
[C2PA known-certificate list](https://opensource.contentauthenticity.org/docs/verify-known-cert-list/).
No code changes are needed — replace `Sources/Resources/es256_certs.pem` and
`es256_private.key` (and, for the identity assertion, `identity_certs.pem` /
`identity_private.key`) with trust-listed credentials and rebuild. With the
bundled self-signed test certs you'll get the minimal/untrusted view no matter
how much metadata is embedded — that's a property of the certificate, not the
manifest.

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
scripts/make_app_icon.py            renders the film-noir app icon (Pillow)
Sources/
  C2PACameraApp.swift               @main App entry point
  Camera/
    CameraController.swift          AVCaptureSession: stills, video, controls
    CameraControls.swift            control enums (mode/flash/aspect/timer)
    CameraPreview.swift             live preview (UIViewRepresentable)
    CameraViewModel.swift           capture/record → sign → review orchestration
    ImageCrop.swift                 aspect-ratio crop (full resolution)
    LocationProvider.swift          CoreLocation (GPS for metadata)
    CaptureMetadataBuilder.swift    builds the stds.exif assertion
  C2PA/
    ContentCredentialSigner.swift   builds manifest, signs photo+video  ← core
    Creator.swift                   author identity + metadata options + storage
  Views/
    CameraScreen.swift              preview + controls composition
    CameraControlsView.swift        top bar, zoom, exposure, mode, shutter
    CreatorSettingsView.swift       edit author credential + metadata toggles
    PhotoReviewView.swift           credential summary + raw manifest JSON + Share
  Assets.xcassets/AppIcon...        film-noir camera-aperture icon (generated)
  Resources/                        es256_* (claim) + identity_* (CAWG) creds (generated)
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
