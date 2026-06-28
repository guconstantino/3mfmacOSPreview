# 3MF Preview — Quick Look for `.3mf`, `.gcode` and `.bgcode`

A macOS **Quick Look Preview** extension. Press **SPACE** in the Finder on a
`.3mf`, `.gcode` or `.bgcode` file and it shows, **large, the thumbnail image
already embedded in the file** by your slicer (PrusaSlicer, Bambu Studio, Orca,
etc.).

<p align="center">
  <img src="docs/preview-example.png" alt="Embedded thumbnail of a .3mf file shown by the 3MF Preview Quick Look extension" width="420">
</p>

<p align="center"><sub>The embedded thumbnail the extension shows when you press Space on a <code>.3mf</code> file.</sub></p>

<!--
  TODO (nice-to-have): replace the image above with a real Finder Quick Look
  screenshot or a short GIF of pressing Space on a .3mf file — far more
  compelling for the README and for launch posts. To capture one:
    1. Put a real .3mf (with a thumbnail) on the Desktop.
    2. Select it in the Finder and press Space.
    3. Screenshot the Quick Look window (Cmd+Shift+4, then Space to grab the
       window), or record a GIF with QuickTime / Kap (https://getkap.co).
  Avoid capturing a Finder window full of personal file names in the shot.
-->

> This is the missing piece next to
> [ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf): that project
> registers the **thumbnail** (the Finder icon, extension point
> `com.apple.quicklook.thumbnail`); this one registers the **preview** (the large
> SPACE window, extension point `com.apple.quicklook.preview`). The two can
> coexist.

Scope of v1: **only display the embedded image**. Rendering the 3D mesh is left
for v2 (see `DECISIONS.md`).

---

## Requirements

- macOS (Apple Silicon or Intel) with **Xcode** installed.
- An **Apple ID** (the **free** / *Personal Team* account is enough — a paid
  Apple Developer account is not required).
- _(Optional, only to regenerate the project)_ [XcodeGen](https://github.com/yonaskolb/XcodeGen):
  `brew install xcodegen`. The `.xcodeproj` is already committed, so to just
  build it you do **not** need XcodeGen.

---

## Building in Xcode

1. Open `MF3Preview.xcodeproj` in Xcode.
2. Select the **MF3Preview** target → **Signing & Capabilities** tab:
   - Check **Automatically manage signing**.
   - In **Team**, select your **Personal Team** (your name / free Apple ID).
   - Do the same for the **PreviewExtension** target (use the same Team).
   > With a Personal Team the `Bundle Identifier` must be unique to your account.
   > If Xcode complains, change the `com.guconstantino` prefix to something of
   > your own in both targets (keeping the appex as `…<app>.PreviewExtension`).
3. Select the **MF3Preview** scheme and **Product → Build** (⌘B).

From the command line (debug):

```bash
xcodebuild -project MF3Preview.xcodeproj -scheme MF3Preview \
  -configuration Debug -destination 'platform=macOS' build
```

---

## Installing (MUST go into `/Applications`)

macOS only activates the Quick Look extension if the host app lives in
**`/Applications`** (or a subfolder of it) — **not** in `~/Applications`,
Downloads or Desktop.

1. In Xcode: **Product → Archive** (or copy the `.app` from the build folder).
2. Copy **`MF3Preview.app` into `/Applications`**.
3. **Launch the app once** (double-click). This registers the extension with the
   system. You can close it afterwards — it only needs to run once to register.
4. _(Optional)_ Confirm in **System Settings → General → Login Items &
   Extensions → Quick Look** that **3MF Preview** appears and is enabled.

### Gatekeeper step (for other users / machines)

Because the app is **not notarized** (notarization requires a paid account),
opening it on another machine may trigger a "cannot verify the developer" block.
To allow it (one-time step):

> **System Settings → Privacy & Security** → scroll to the message about the
> blocked app → **"Open Anyway"** → confirm.

On your own machine (the one that signed it with your Personal Team) this usually
doesn't even appear.

---

## Testing

1. Download a real `.3mf` **locally** that **has a thumbnail** (most files
   exported by PrusaSlicer/Bambu/Orca since ~2021 do).
   > ⚠️ Make sure the file is **actually downloaded** — not a **0 KB** iCloud
   > placeholder. Non-downloaded items have no content for Quick Look to read.
2. In the Finder, select the file and press **SPACE**. The embedded image should
   appear, large.

### If the preview doesn't show up

Reset the Quick Look cache and the Finder:

```bash
qlmanage -r && qlmanage -r cache && killall Finder
```

You can also force a preview from the command line to debug:

```bash
qlmanage -p /path/to/file.3mf
```

And list the Quick Look preview extensions the system sees:

```bash
pluginkit -mAvvv -p com.apple.quicklook.preview | grep -i mf3
```

Common-problem checklist:
- The `.app` is **not** in `/Applications` → move it and launch it again.
- The app was never opened after installing → open it once.
- The `.3mf` has no embedded thumbnail, or it's a non-downloaded iCloud item.
- Stale cache → run the `qlmanage -r …` commands above.

---

## Supported types

| Extension | Thumbnail source | Image formats |
|---|---|---|
| `.3mf`   | image under `Metadata/…` inside the ZIP/OPC | PNG (JPG/QOI also accepted) |
| `.gcode` | base64 PNG in the comments | PNG (JPG/QOI also accepted) |
| `.bgcode`| thumbnail block in the "GCDE" container | PNG / JPG / QOI |

Path priority inside the `.3mf`: `Metadata/thumbnail.png` →
`Metadata/plate_1.png` → `Metadata/plate_1_small.png` → `Metadata/top_1.png` →
first `*.png` under `Metadata/`.

---

## Distribution (planned for v2 — not implemented yet)

Without a paid Apple Developer account, the free path is a **self-hosted
Homebrew tap** with the non-notarized `.app`:

```bash
# (planned, does not exist yet)
brew tap guconstantino/3mfpreview
brew install --cask 3mf-preview
```

…plus the **one-time Gatekeeper step** above. The frictionless (notarized)
experience would require the $99/year paid account — a conscious decision to
defer, recorded in `DECISIONS.md` (section 8).

---

## License and credits

[Apache-2.0](LICENSE). The thumbnail-extraction logic is a Swift
re-implementation derived from
[ThumbHost3mf](https://github.com/DavidPhillipOster/ThumbHost3mf) by
**David Phillip Oster** (Apache-2.0). The QOI decoder is a port of `qoi.h` by
Dominic Szablewski (MIT). See `NOTICE` and `ARCHITECTURE.md`.
