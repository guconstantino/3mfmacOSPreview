//  GCode.swift
//  ThumbnailCore
//
//  Extract base64-encoded thumbnails embedded in the comment block at the top of
//  a textual .gcode file, e.g.:
//
//      ; thumbnail begin 220x124 7500
//      ; iVBORw0KGgoAAAANSUhEUgAA...
//      ; ...
//      ; thumbnail end
//
//  Slicers may embed several sizes and/or formats (PNG and QOI). We decode all of
//  them and let the caller pick the largest.
//
//  Clean-room Swift re-implementation of ThumbnailGCode.m (ThumbHost3mf,
//  Apache-2.0). See NOTICE / ARCHITECTURE.md.

import Foundation

enum GCode {
    /// Read the first `maxHead` bytes — thumbnails live near the top of the file.
    private static let maxHead = 512 * 1024

    /// Returns each decoded thumbnail's image data (PNG/JPG/QOI bytes).
    static func thumbnailDatas(from url: URL) -> [Data] {
        guard let head = readHead(url) else { return [] }
        // Treat as text; gcode is ASCII. Lossy keeps us robust to stray bytes.
        let text = String(decoding: head, as: UTF8.self)
        return base64Blocks(in: text).compactMap {
            Data(base64Encoded: $0, options: .ignoreUnknownCharacters)
        }
    }

    /// Each returned string is the concatenated base64 payload of one thumbnail
    /// (comment prefixes and newlines are left in; base64 decoding ignores them).
    private static func base64Blocks(in text: String) -> [String] {
        var blocks: [String] = []
        var current: String?
        text.enumerateLines { line, _ in
            let lower = line.lowercased()
            let isThumb = lower.contains("thumbnail")
            if isThumb, lower.contains("begin") {
                current = ""
                return
            }
            if isThumb, lower.contains("end") {
                if let c = current, !c.isEmpty { blocks.append(c) }
                current = nil
                return
            }
            if current != nil {
                // Strip the leading comment marker ("; " or ";").
                var payload = line
                if let semi = payload.firstIndex(of: ";") {
                    payload = String(payload[payload.index(after: semi)...])
                }
                current?.append(payload.trimmingCharacters(in: .whitespaces))
            }
        }
        return blocks
    }

    private static func readHead(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxHead)
    }
}
