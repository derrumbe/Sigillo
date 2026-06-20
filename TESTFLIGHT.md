# TestFlight copy

Paste these into App Store Connect → TestFlight. "Beta App Description" is the
app overview testers see; "What to Test" is the per-build note shown on the
build. Keep both well under the 4000-character limit.

---

## Beta App Description

Sigillo is a camera that proves where your photos come from. The moment you
press the shutter, every photo is signed with a tamper-evident **C2PA Content
Credential** — a cryptographic record, embedded directly in the image, asserting
that it was captured by a real camera on this device and stamped with a trusted
time. If anyone later edits or re-saves the photo, the signature no longer
matches, so viewers can tell.

You can review the credential in the app, inspect the raw manifest, and
optionally attach your name and identity as the creator. Capture works the way
you'd expect from a camera — front/back cameras, photo and video, zoom, flash,
exposure, aspect ratio, self-timer, Live Photos, and a low-light mode — and the
credential rides along with everything you shoot.

This beta is for testing capture quality, the signing flow, and how well the
credentials survive being saved and shared. Nothing you capture is uploaded to
us; signing happens on-device and photos stay in your library.

---

## What to Test

Thanks for testing Sigillo! Please try the following and report anything that
looks wrong:

**New in this build — please focus here**
- **Selfie camera:** tap the flip-camera button (bottom-right of the capture
  bar) to switch between the back and front camera. Works in Photo and Video.
- **Camera Control button (iPhone 16 family):** press the hardware Camera
  Control to take a photo / start-stop recording. The volume buttons also work
  as a shutter.
- **Photo orientation:** shoot photos holding the phone in **landscape** and
  confirm they come out upright (not sideways) in the Credential Roll and when
  saved to Photos.
- **Rotate a stored photo:** open a photo in the Credential Roll → **Rotate**
  menu → **Rotate Left** / **Rotate Right**. The photo is rotated *and re-signed*
  — confirm it still shows a valid credential afterward (the credential should
  note the orientation change and link the original).
- **Landscape viewing:** while viewing a photo in the Credential Roll, turn the
  phone sideways — a landscape photo should rotate to fill the screen. Turn back
  to portrait to get the controls again.
- **Hide/show credentials:** use the eye button in the roll viewer (and the seal
  button on the camera) to hide or show the Content Credentials display.

**Capture the basics**
- Take a few photos and a video. Confirm each one saves to your photo library.
- Open the in-app review screen and the **Credential Roll** — check that every
  shot shows a valid, signed credential with a signer and timestamp.

**Camera controls**
- Switch between Photo and Video.
- Zoom (pinch and the 1×/2×/3×/5× presets), Flash (off/auto/on + video torch).
- Tap the EV chip and drag the radial **exposure** dial.
- Change the **aspect ratio** (4:3 / 16:9 / 1:1) and confirm framing/crop.
- Try the **self-timer** (3s/10s), **Live Photos**, and **Night mode**.

**Creator identity (optional)**
- Tap the person icon, set a creator name and identifier, take a photo, and
  confirm the creator info appears in the credential.

**Verify the credential survives**
- Save a photo, then check it at <https://contentcredentials.org/verify> (or any
  C2PA verifier). It should report a valid capture credential. Note: because the
  beta signs with a self-signed test certificate, the verifier may flag the
  signer as "untrusted" — that's expected; the signature itself should be valid.

**Permissions**
- First launch should request Camera, Photos (add), and — only if you enable the
  Location metadata option — Location. Make sure the prompts make sense.

**Tell us**
- Device model and iOS version
- Anything that crashed, froze, looked wrong, or where a saved photo lost its
  credential
- Photos where the credential failed to verify
