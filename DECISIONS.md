# DECISIONS.md — Technical decision record and development log

This document is the source of truth for design decisions and a chronological
diary of the steps taken. Each decision has **context**, **decision** and
**rationale**.

---

## 0. Project goal

Build a macOS **Quick Look Preview Extension** that, when you press **SPACE** in
the Finder on a `.3mf`, `.gcode` or `.bgcode` file, shows **the thumbnail image
already embedded in the file, large**.

Difference from the reference app
[ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf): that one only
registers the `com.apple.quicklook.thumbnail` extension point (the Finder
icon/thumbnail). That's why SPACE shows no preview. What's missing — and what
this project delivers — is an extension at the `com.apple.quicklook.preview`
point.

---

## 1. New standalone project (not a fork)

**Decision:** A new, standalone project in this repository that reuses the
*logic* of ThumbHost3mf's extraction, rather than a fork of it.

**Rationale:** ThumbHost3mf is an AppKit Objective-C app with a *thumbnail*
target. We want a lean Swift app with a *preview* target. Forking would carry a
lot of code and configuration we wouldn't use. Reusing only the extraction logic
keeps the project small and auditable.

---

## 2. Re-implement in pure Swift (option b), not port the C/minizip (option a)

**Decision:** Re-implement extraction in **pure Swift**, with no vendored C and
**no external dependencies** (no SPM/CocoaPods).

**Rationale:**
- The only part that needs "unzip" is the `.3mf` (a ZIP in the OPC format). The
  `.gcode` (text with a base64 PNG thumbnail in the comments) and `.bgcode`
  (binary "GCDE" container with blocks; thumbnails may be PNG/JPG/QOI) formats
  need their own parsers anyway — minizip doesn't help there.
- For the `.3mf` ZIP, a **minimal ZIP reader** suffices (locate an entry by name,
  read the local header and decompress) using Apple's **`Compression`** framework
  for DEFLATE. It includes **ZIP64** support (real `.3mf` files in ZIP64 exist,
  per the ThumbHost3mf v1.7 history).
- Result: a 100% Swift project, no C build step, no embedded framework to sign, a
  smaller appex — exactly the v1 "keep it simple" goal.

**Alternative considered:** `ZIPFoundation` via SPM. Rejected for v1 because it
adds package resolution at build time and an extra binary to sign inside the
appex, with no real gain for reading a single small file from an OPC.

The re-implemented logic derives, clean-room, from the *behavior* of
ThumbHost3mf's Objective-C/C sources (`Thumbnail3MF`, `ThumbnailGCode`,
`ThumbnailBinaryGCode`, `Unzip3MF`, `QOIFImageFromData`). See `ARCHITECTURE.md`.

---

## 3. Licensing and attribution (Apache-2.0)

**Decision:** Keep the `LICENSE` Apache-2.0 and a `NOTICE` crediting
**David Phillip Oster** (ThumbHost3mf). The QOI decoder also credits Dominic
Szablewski's reference implementation (MIT).

**Rationale:** ThumbHost3mf is Apache-2.0; reusing its logic requires preserving
attribution and the license notice. It's the right thing to do and required by
section 4 of Apache-2.0.

---

## 4. View-based preview (`QLPreviewingController`), not data-based

**Decision:** Use an `NSViewController` that adopts `QLPreviewingController` and
implements `preparePreviewOfFile(at:)`, showing the image in an `NSImageView`
with `imageScaling = .scaleProportionallyUpOrDown`. No storyboard (view created
programmatically in `loadView`).

**Rationale:** It's the most direct, reliable path to "just show the image large"
(v1 scope). It avoids the uncertainties of the data-based API (`QLPreviewReply`)
and needs no storyboard. Rendering the 3D mesh is left for v2.

---

## 5. UTIs and extension point

**Decision:**
- `NSExtensionPointIdentifier = com.apple.quicklook.preview`.
- `QLSupportedContentTypes = [com.turbozen.3mf, com.turbozen.gcode,
  com.turbozen.bgcode]`.
- Declare those three as **`UTImportedTypeDeclarations`** (*imported* types),
  mapping the `3mf`/`gcode`/`bgcode` extensions, since the `com.turbozen.*`
  identifiers belong to the original author (TurboZen / David Oster).

**Rationale:** `.3mf`/`.gcode`/`.bgcode` have no Apple system UTI. Reusing the
`com.turbozen.*` identifiers (the same ones ThumbHost3mf uses) keeps things
compatible: if ThumbHost3mf is installed, both talk about the same type; if it
isn't, our *imported* declaration acts as a fallback and Quick Look still matches
the files by extension.

---

## 6. Sandbox and signing (free Apple ID / Personal Team)

**Decision:**
- App and appex with **App Sandbox** enabled; read entitlement for the selected
  file (`com.apple.security.files.user-selected.read-only`). Quick Look grants
  the appex read access to the file under preview.
- **Local signing with a Personal Team (free Apple ID)**, automatic signing in
  Xcode. **No notarization** (requires the $99/year paid account).

**Rationale:** The user has no paid Apple Developer account. A free Personal Team
signs and runs locally without issues for personal use. The lack of notarization
means **other** users will need the one-time Gatekeeper step ("Open Anyway") —
documented in the README.

**Conscious (deferred) consequence:** frictionless (notarized) distribution would
require the paid account. We chose to defer it (see section 8).

---

## 7. Xcode project generation via XcodeGen

**Decision:** Describe the targets in `project.yml` (XcodeGen) and **also commit
the generated `.xcodeproj`**. `project.yml` is the source of truth; the committed
`.xcodeproj` lets it open in Xcode without installing XcodeGen.

**Rationale:** Hand-writing a `.pbxproj` for an app + appex (with embedding,
entitlements, Info.plists and build settings) is fragile and error-prone.
XcodeGen makes it declarative and reproducible. Committing the `.xcodeproj` avoids
requiring the tool from anyone who just wants to open and build.

---

## 8. Distribution (v2 — planned only, NOT implemented yet)

**Plan:** Without a paid account, the free path is a **self-hosted Homebrew tap**
with the **unsigned/non-notarized** `.app`: the user runs
`brew tap guconstantino/...` and `brew install --cask ...`, plus the one-time
Gatekeeper step.

**Recorded trade-off:** The "frictionless" experience (notarized, no Gatekeeper
warning) would require the **$99/year** paid account. Conscious decision to
**defer** notarization. We won't set up the tap in v1.

---

## 9. v1 scope (keep it simple)

- Show **only** the embedded image, large, on SPACE.
- **Do not** render the 3D mesh (v2).
- Image path priority inside the `.3mf` ZIP:
  1. `Metadata/thumbnail.png` (PrusaSlicer)
  2. `Metadata/plate_1.png` (Bambu/Orca)
  3. `Metadata/plate_1_small.png`
  4. `Metadata/top_1.png`
  5. fallback: the first `*.png` under `Metadata/`
- `.gcode`: base64 PNG in the comments (`; thumbnail begin` … `; thumbnail end`).
- `.bgcode`: thumbnail block in the binary "GCDE" container (PNG/JPG/QOI).

---

## 10. 3D mesh rendering and other formats (STL/OBJ/PLY) — investigated, deferred

**Context:** Could we make `.3mf` rotate like the system's native STL preview,
and could we add STL/OBJ/PLY?

**Findings (verified on-device):**
- macOS previews STL/OBJ/USDZ natively because Apple's **Model I/O** imports
  them and **SceneKit** renders them. `MDLAsset.canImportFileExtension` returns
  YES for `stl`, `obj`, `ply`, `usd`, `usdz`, `abc` — and **NO for `3mf`** (also
  no `gltf`/`dae`).
- Therefore STL/OBJ/PLY would be nearly free (Model I/O + a SceneKit `SCNView`
  with `allowsCameraControl`), but the system already previews STL, so the value
  is limited.
- A rotatable `.3mf` mesh is feasible but requires **writing our own 3MF mesh
  parser** (read `3D/3dmodel.model` XML from the OPC zip: vertices, triangles,
  component/build transforms, units), then feeding SceneKit. SceneKit gives the
  interactive rotation for free; the parser is the bulk of the work.

**Trade-off:** the embedded thumbnail is colorful and arranged by the slicer;
a raw mesh render is monochrome geometry but rotatable and reflects the true
geometry. A mesh-primary approach with the embedded thumbnail as fallback would
be the way, plus a size/triangle guard for the sandboxed appex.

**Decision:** **Deferred.** v1 already meets its goal with the embedded image,
which covers the common case (modern slicer files ship a good thumbnail). Recorded
here in case it's picked up later.

---

## DEVELOPMENT LOG (chronological)

- **Step 1.** Cloned the empty repo `guconstantino/3mfmacOSPreview` and, for
  study, `DavidPhillipOster/ThumbHost3mf`. Read the extraction sources
  (`Thumbnail3MF.m`, `ThumbnailGCode.m`, `ThumbnailBinaryGCode.m`, `Unzip3MF.h`,
  `QOIFImageFromData.m`) and the thumbnail `Info.plist`.
- **Step 2.** Added `LICENSE` (Apache-2.0), `NOTICE` (attribution to David Oster
  + the QOI MIT notice), `.gitignore`.
- **Step 3.** Created `DECISIONS.md` (this file), `README.md` and
  `ARCHITECTURE.md` with the plan. **(checkpoint commit)**
- **Step 4.** Implemented `ThumbnailCore` in pure Swift (`QOIDecoder`, `MiniZip`,
  `GCode`, `BinaryGCode`, `ThumbnailExtractor`). Validated with `swiftc` against
  generated fixtures (a Deflate `.3mf` and a base64 `.gcode`): both extracted the
  embedded PNG correctly. **(commit)**
- **Step 5.** Created the `PreviewExtension` (`QLPreviewingController` +
  `preparePreviewOfFile(at:)` + `NSImageView` `.scaleProportionallyUpOrDown`),
  the SwiftUI host app `MF3Preview` (with an "Open File…" tester), the
  `Info.plist`/entitlements and the `project.yml`. **(commit)**
- **Step 6.** `xcodegen generate` + `xcodebuild` (Debug, no signing):
  **BUILD SUCCEEDED**. The `.appex` is embedded in `Contents/PlugIns/` and
  validated; the processed `Info.plist`s resolve the principal class
  (`PreviewExtension.PreviewViewController`) and the `QLSupportedContentTypes`.
- **Step 7.** Release build with **ad-hoc signing** (`-`) for local validation
  only; sandbox entitlements applied. Installed into
  `/Applications/MF3Preview.app` and registered (`lsregister`/`pluginkit`).
  `pluginkit -m -p com.apple.quicklook.preview` lists our extension.
- **Step 8.** Headless integration validation: `mdls` shows that a `.3mf`
  resolves to `kMDItemContentType = com.turbozen.3mf` — the same UTI the
  extension declares, so Quick Look will route the preview to it. Note:
  `lsregister -dump` revealed that **ThumbHost3mf is already installed** on this
  machine (a *thumbnail* extension), confirming the `com.turbozen.*` UTIs are the
  real ones and that the two extensions coexist at different points. **(commit)**
- **Step 9.** ✅ **End-to-end visual validation succeeded.** With the ad-hoc
  build installed in `/Applications`, the user selected a real `.3mf`
  (`slide_puzzle+3x3.3mf`) in the Finder and pressed **SPACE**: Quick Look showed
  the embedded image large and at full resolution — the behavior of our
  `QLPreviewingController`. v1 goal achieved.

### Validation notes / open items

- ✅ Final visual confirmation (SPACE on a real `.3mf`) done and working.
- Rigor note: because ThumbHost3mf (a *thumbnail* extension) is installed, for a
  100% unambiguous proof that the preview comes from this extension (and not an
  upscale of the thumbnail), temporarily uninstall ThumbHost and repeat SPACE —
  the preview should persist.
- bgcode/QOI/ZIP64: the logic is a faithful port of the reference, but not yet
  exercised against real fixtures (no samples available). Left as future
  verification.
