//  QOIDecoder.swift
//  ThumbnailCore
//
//  Swift port of the reference QOI decoder from https://github.com/phoboslab/qoi
//  (qoi.h), Copyright (c) 2021 Dominic Szablewski, MIT License. See NOTICE.
//
//  QOI ("Quite OK Image") thumbnails appear inside some .bgcode and .gcode files
//  produced by recent slicers. AppKit's NSImage cannot decode them, so we do it
//  ourselves and hand back a CGImage.

import CoreGraphics
import Foundation

enum QOIDecoder {

    private static let opIndex: UInt8 = 0x00 // 00xxxxxx
    private static let opDiff: UInt8 = 0x40  // 01xxxxxx
    private static let opLuma: UInt8 = 0x80  // 10xxxxxx
    private static let opRun: UInt8 = 0xc0   // 11xxxxxx
    private static let opRGB: UInt8 = 0xfe   // 11111110
    private static let opRGBA: UInt8 = 0xff  // 11111111
    private static let mask2: UInt8 = 0xc0   // 11000000
    private static let headerSize = 14
    private static let padding = 8 // 7 zero bytes + 0x01

    /// Decode a QOI image (must start with the "qoif" magic) into a CGImage.
    static func decode(_ data: Data) -> CGImage? {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize + padding,
              bytes[0] == 0x71, bytes[1] == 0x6f, bytes[2] == 0x69, bytes[3] == 0x66 // "qoif"
        else { return nil }

        func read32(_ p: Int) -> UInt32 {
            (UInt32(bytes[p]) << 24) | (UInt32(bytes[p + 1]) << 16)
                | (UInt32(bytes[p + 2]) << 8) | UInt32(bytes[p + 3])
        }

        let width = Int(read32(4))
        let height = Int(read32(8))
        let channels = Int(bytes[12])
        let colorspace = Int(bytes[13])

        guard width > 0, height > 0, channels >= 3, channels <= 4, colorspace <= 1,
              // guard against absurd sizes / overflow
              width <= 1 << 16, height <= 1 << 16, width * height <= 400_000_000
        else { return nil }

        let outChannels = 4 // we always emit RGBA so the CGImage layout is simple
        var pixels = [UInt8](repeating: 0, count: width * height * outChannels)

        var index = [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)](
            repeating: (0, 0, 0, 0), count: 64)
        var r: UInt8 = 0, g: UInt8 = 0, b: UInt8 = 0, a: UInt8 = 255
        var run = 0
        var p = headerSize
        let chunksLen = bytes.count - padding

        var pos = 0
        let pxLen = width * height * outChannels
        while pos < pxLen {
            if run > 0 {
                run -= 1
            } else if p < chunksLen {
                let b1 = bytes[p]; p += 1
                if b1 == opRGB {
                    r = bytes[p]; g = bytes[p + 1]; b = bytes[p + 2]; p += 3
                } else if b1 == opRGBA {
                    r = bytes[p]; g = bytes[p + 1]; b = bytes[p + 2]; a = bytes[p + 3]; p += 4
                } else if (b1 & mask2) == opIndex {
                    let e = index[Int(b1)]
                    r = e.r; g = e.g; b = e.b; a = e.a
                } else if (b1 & mask2) == opDiff {
                    r = r &+ UInt8(truncatingIfNeeded: Int((b1 >> 4) & 0x03) - 2)
                    g = g &+ UInt8(truncatingIfNeeded: Int((b1 >> 2) & 0x03) - 2)
                    b = b &+ UInt8(truncatingIfNeeded: Int(b1 & 0x03) - 2)
                } else if (b1 & mask2) == opLuma {
                    let b2 = bytes[p]; p += 1
                    let vg = Int(b1 & 0x3f) - 32
                    r = r &+ UInt8(truncatingIfNeeded: vg - 8 + Int((b2 >> 4) & 0x0f))
                    g = g &+ UInt8(truncatingIfNeeded: vg)
                    b = b &+ UInt8(truncatingIfNeeded: vg - 8 + Int(b2 & 0x0f))
                } else if (b1 & mask2) == opRun {
                    run = Int(b1 & 0x3f)
                }
                let hash = (Int(r) * 3 + Int(g) * 5 + Int(b) * 7 + Int(a) * 11) % 64
                index[hash] = (r, g, b, a)
            }
            pixels[pos] = r
            pixels[pos + 1] = g
            pixels[pos + 2] = b
            pixels[pos + 3] = a
            pos += outChannels
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * outChannels,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)
    }
}
