# ARCHITECTURE.md — How it works and what was reused

## Overview

```
Finder (SPACE)
   │
   ▼
Quick Look  ──►  PreviewExtension.appex  (com.apple.quicklook.preview)
                      │
                      ▼
               PreviewViewController : NSViewController, QLPreviewingController
                      │  preparePreviewOfFile(at:)
                      ▼
               ThumbnailCore.image(for: url)  ──►  NSImage
                      │                                  │
                      │                                  ▼
                      │                            NSImageView (.scaleProportionallyUpOrDown)
                      ▼
        ┌─────────────┴───────────────┬───────────────────────────┐
        ▼                             ▼                           ▼
   .3mf  (ZIP/OPC)            .gcode (text)              .bgcode ("GCDE" binary)
   MiniZip + Compression      base64 in comments         block parser
        │                             │                           │
        └─────────────► PNG/JPG/QOI ◄─┴───────────────────────────┘
                              │
                              ▼
                    QOIDecoder (if "qoif")  →  CGImage  →  NSImage
```

The same `ThumbnailCore` is compiled into **both the appex and the host app**, so
the app can show a test preview without installing the extension.

## `ThumbnailCore` modules (pure Swift)

| File | Responsibility | Derived from (ThumbHost3mf) |
|---|---|---|
| `ThumbnailExtractor.swift` | Dispatches by extension and returns an `NSImage` | `ThumbnailProvider.m`, `Thumbnail3MF.m`, `ThumbnailGCode.m` |
| `MiniZip.swift` | Minimal ZIP reader (EOCD, ZIP64, central dir, inflate via `Compression`) | `Unzip3MF.m` (minizip) |
| `GCode.swift` | Finds and decodes base64 thumbnails in `.gcode` comments | `ThumbnailGCode.m` |
| `BinaryGCode.swift` | Walks the "GCDE" container blocks and extracts the thumbnail block | `ThumbnailBinaryGCode.m` |
| `QOIDecoder.swift` | Decodes QOI (`qoif`) images into a `CGImage` | `QOIFImageFromData.m` (port of qoi.h, MIT) |

## What was reused (and how)

The extraction is a **clean-room Swift re-implementation** based on the
*behavior* of ThumbHost3mf (Apache-2.0). In particular:

- **3MF** — open the `.3mf` as a ZIP and look for the image under `Metadata/…`.
  The original read `Metadata/thumbnail.png|jpg` and `Metadata/plate_1.png|jpg`.
  Here the priority order is: `thumbnail.png` → `plate_1.png` →
  `plate_1_small.png` → `top_1.png` → first `*.png` under `Metadata/`.
- **gcode** — locate the region between `; thumbnail begin` and
  `; thumbnail end`, join the lines, strip the `; ` prefix and base64-decode.
  There can be several sizes; we pick the one with the largest area.
- **bgcode** — validate the `GCDE` magic + version 1, walk the blocks reading
  `blockType`, `compressionType`, sizes and (if present) checksum; block
  `blockType == 5` is the image (PNG/JPG/QOI).
- **QOI** — a direct port of the reference `qoi.h` decoder (MIT) to Swift.

## MiniZip — details

For a `.3mf` (OPC = ZIP), `MiniZip`:

1. Memory-maps the file and locates the **End Of Central Directory (EOCD)** by
   scanning backwards for the `0x06054b50` signature.
2. If present, follows the **ZIP64 EOCD locator** (`0x07064b50`) and the **ZIP64
   EOCD** (`0x06064b50`) for 64-bit offsets/counts.
3. Iterates the **central directory** entries (`0x02014b50`), matching the wanted
   file name (case-insensitive when falling back to a `.png` search).
4. Reads the entry's **local file header** (`0x04034b50`) and extracts the data:
   - method **0 (stored)** → direct copy;
   - method **8 (deflate)** → inflate via `Compression` (`COMPRESSION_ZLIB` in
     raw/`-MAX_WBITS` mode).

We only need one small entry (the image), so there's no complex streaming: read
what's needed and decompress in memory.

## Why not render the 3D mesh (v1)

The v1 goal is parity with the embedded thumbnail experience: the slicer already
produced a good image of the plate. Rendering the mesh would require parsing
`3D/3dmodel.model` (XML), triangulation and a renderer — that's v2 scope. See
`DECISIONS.md` for the trade-offs (including why STL "just works" natively via
Model I/O while 3MF does not).
