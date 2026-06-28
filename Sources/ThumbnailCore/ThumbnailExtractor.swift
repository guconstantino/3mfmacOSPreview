//  ThumbnailExtractor.swift
//  ThumbnailCore
//
//  Entry point: given a .3mf / .gcode / .bgcode file URL, return the embedded
//  thumbnail as an NSImage (or nil if there isn't one). The sources of this
//  module are compiled directly into both the host app and the Quick Look
//  preview extension, so no shared framework is needed.
//
//  Clean-room Swift re-implementation derived from ThumbHost3mf (Apache-2.0).
//  See NOTICE / ARCHITECTURE.md.

import AppKit
import Foundation

enum ThumbnailExtractor {

    /// Priority order for the embedded image inside a .3mf (an OPC/ZIP archive).
    private static let threeMFCandidates = [
        "Metadata/thumbnail.png",   // PrusaSlicer
        "Metadata/plate_1.png",     // Bambu Studio / Orca
        "Metadata/plate_1_small.png",
        "Metadata/top_1.png",
    ]

    /// Extract the embedded thumbnail for the file at `url`.
    static func image(for url: URL) -> NSImage? {
        switch url.pathExtension.lowercased() {
        case "3mf":
            return imageFrom3MF(url)
        case "gcode":
            return largestImage(from: GCode.thumbnailDatas(from: url))
        case "bgcode":
            return largestImage(from: BinaryGCode.thumbnailDatas(from: url))
        default:
            return imageBySniffing(url)
        }
    }

    // MARK: - 3MF

    private static func imageFrom3MF(_ url: URL) -> NSImage? {
        guard let zip = MiniZip(url: url) else { return nil }
        for name in threeMFCandidates {
            if let data = zip.data(named: name), let image = makeImage(from: data) {
                return image
            }
        }
        // Fallback: the first *.png anywhere under Metadata/.
        if let entry = zip.firstEntry(where: {
            let n = $0.lowercased()
            return n.hasPrefix("metadata/") && n.hasSuffix(".png")
        }), let data = zip.extract(entry), let image = makeImage(from: data) {
            return image
        }
        return nil
    }

    // MARK: - Content sniffing (for files whose extension we weren't given)

    private static func imageBySniffing(_ url: URL) -> NSImage? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        try? handle.close()
        let bytes = [UInt8](head)
        if bytes.starts(with: [0x47, 0x43, 0x44, 0x45]) { // "GCDE"
            return largestImage(from: BinaryGCode.thumbnailDatas(from: url))
        }
        if bytes.starts(with: [0x50, 0x4b]) { // "PK" (zip / 3mf)
            return imageFrom3MF(url)
        }
        return largestImage(from: GCode.thumbnailDatas(from: url))
    }

    // MARK: - Image helpers

    /// Build an NSImage from raw image bytes (PNG/JPG via AppKit, QOI via our decoder).
    static func makeImage(from data: Data) -> NSImage? {
        guard data.count > 4 else { return nil }
        let b = [UInt8](data.prefix(4))
        if b == [0x71, 0x6f, 0x69, 0x66] { // "qoif"
            if let cg = QOIDecoder.decode(data) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            return nil
        }
        return NSImage(data: data)
    }

    /// Decode every candidate and return the one with the most pixels.
    private static func largestImage(from datas: [Data]) -> NSImage? {
        var best: NSImage?
        var bestArea: CGFloat = -1
        for data in datas {
            guard let image = makeImage(from: data) else { continue }
            let area = pixelArea(of: image)
            if area > bestArea {
                bestArea = area
                best = image
            }
        }
        return best
    }

    private static func pixelArea(of image: NSImage) -> CGFloat {
        if let rep = image.representations.first {
            return CGFloat(rep.pixelsWide) * CGFloat(rep.pixelsHigh)
        }
        return image.size.width * image.size.height
    }
}
