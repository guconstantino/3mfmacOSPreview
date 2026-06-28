//  MiniZip.swift
//  ThumbnailCore
//
//  A minimal, dependency-free ZIP reader good enough to pull a single small
//  entry (an embedded thumbnail) out of a .3mf file (which is an OPC = ZIP
//  archive). Supports STORE (0) and DEFLATE (8) and ZIP64 central directories.
//
//  This is a clean-room Swift re-implementation of the role played by
//  Unzip3MF.m / minizip in ThumbHost3mf (Apache-2.0). See NOTICE / ARCHITECTURE.md.
//
//  DEFLATE is inflated with Apple's Compression framework (COMPRESSION_ZLIB,
//  which operates on the raw RFC-1951 stream that ZIP stores).

import Compression
import Foundation

struct MiniZip {
    struct Entry {
        let name: String
        let compressionMethod: UInt16
        let compressedSize: UInt64
        let uncompressedSize: UInt64
        let localHeaderOffset: UInt64
    }

    private let data: Data
    let entries: [Entry]

    /// Memory-maps the file and parses its central directory. Returns nil if the
    /// file is not a usable ZIP archive.
    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        guard let parsed = MiniZip.parseCentralDirectory(d) else { return nil }
        self.data = d
        self.entries = parsed
    }

    /// Returns the decompressed bytes for the named entry (exact, case-sensitive),
    /// or nil if not present / unreadable.
    func data(named name: String) -> Data? {
        guard let e = entries.first(where: { $0.name == name }) else { return nil }
        return extract(e)
    }

    /// First entry whose name matches `predicate`, in central-directory order.
    func firstEntry(where predicate: (String) -> Bool) -> Entry? {
        entries.first { predicate($0.name) }
    }

    func extract(_ e: Entry) -> Data? {
        // Read the local file header to find where the payload actually begins;
        // its name/extra lengths can differ from the central directory's.
        let lho = Int(e.localHeaderOffset)
        guard let sig = data.u32(lho), sig == 0x0403_4b50,
              let nameLen = data.u16(lho + 26),
              let extraLen = data.u16(lho + 28) else { return nil }
        let dataStart = lho + 30 + Int(nameLen) + Int(extraLen)
        let compSize = Int(e.compressedSize)
        guard dataStart >= 0, dataStart + compSize <= data.count else { return nil }
        let payload = data.subdata(in: dataStart ..< (dataStart + compSize))

        switch e.compressionMethod {
        case 0: // stored
            return payload
        case 8: // deflate
            return MiniZip.inflateRaw(payload, expectedSize: Int(e.uncompressedSize))
        default:
            return nil
        }
    }

    // MARK: - Central directory parsing

    private static func parseCentralDirectory(_ data: Data) -> [Entry]? {
        guard let eocd = findEOCD(data) else { return nil }

        var cdOffset = UInt64(data.u32(eocd + 16) ?? 0)
        var cdCount = UInt64(data.u16(eocd + 10) ?? 0)

        // ZIP64: if the classic fields are saturated, follow the locator.
        if cdOffset == 0xFFFF_FFFF || cdCount == 0xFFFF {
            if let z = findZip64EOCD(data, eocdOffset: eocd) {
                cdCount = data.u64(z + 32) ?? cdCount
                cdOffset = data.u64(z + 48) ?? cdOffset
            }
        }

        var entries: [Entry] = []
        var p = Int(cdOffset)
        var i: UInt64 = 0
        while i < cdCount {
            guard let sig = data.u32(p), sig == 0x0201_4b50 else { break }
            guard let method = data.u16(p + 10),
                  let compSize32 = data.u32(p + 20),
                  let uncompSize32 = data.u32(p + 24),
                  let nameLen = data.u16(p + 28),
                  let extraLen = data.u16(p + 30),
                  let commentLen = data.u16(p + 32),
                  let localOffset32 = data.u32(p + 42),
                  let name = data.string(p + 46, length: Int(nameLen))
            else { break }

            var compSize = UInt64(compSize32)
            var uncompSize = UInt64(uncompSize32)
            var localOffset = UInt64(localOffset32)

            // ZIP64 extra field (id 0x0001) overrides any saturated value, in a
            // fixed order: uncompressed, compressed, local-header offset.
            if uncompSize32 == 0xFFFF_FFFF || compSize32 == 0xFFFF_FFFF || localOffset32 == 0xFFFF_FFFF {
                let extraStart = p + 46 + Int(nameLen)
                var ep = extraStart
                let extraEnd = extraStart + Int(extraLen)
                while ep + 4 <= extraEnd {
                    guard let fid = data.u16(ep), let fsize = data.u16(ep + 2) else { break }
                    let fieldSize = Int(fsize)
                    var fp = ep + 4
                    if fid == 0x0001 {
                        if uncompSize32 == 0xFFFF_FFFF, let v = data.u64(fp) { uncompSize = v; fp += 8 }
                        if compSize32 == 0xFFFF_FFFF, let v = data.u64(fp) { compSize = v; fp += 8 }
                        if localOffset32 == 0xFFFF_FFFF, let v = data.u64(fp) { localOffset = v; fp += 8 }
                    }
                    ep += 4 + fieldSize
                }
            }

            entries.append(Entry(name: name,
                                 compressionMethod: method,
                                 compressedSize: compSize,
                                 uncompressedSize: uncompSize,
                                 localHeaderOffset: localOffset))
            p += 46 + Int(nameLen) + Int(extraLen) + Int(commentLen)
            i += 1
        }
        return entries.isEmpty ? nil : entries
    }

    /// Scan backwards for the End Of Central Directory signature (0x06054b50).
    private static func findEOCD(_ data: Data) -> Int? {
        let n = data.count
        guard n >= 22 else { return nil }
        let maxComment = 0xFFFF
        let lowerBound = max(0, n - 22 - maxComment)
        var p = n - 22
        while p >= lowerBound {
            if data.u32(p) == 0x0605_4b50 { return p }
            p -= 1
        }
        return nil
    }

    /// Locate the ZIP64 EOCD record via the ZIP64 EOCD locator (0x07064b50)
    /// which sits 20 bytes before the classic EOCD.
    private static func findZip64EOCD(_ data: Data, eocdOffset: Int) -> Int? {
        let loc = eocdOffset - 20
        guard loc >= 0, data.u32(loc) == 0x0706_4b50,
              let z = data.u64(loc + 8) else { return nil }
        let zi = Int(z)
        guard zi >= 0, zi + 4 <= data.count, data.u32(zi) == 0x0606_4b50 else { return nil }
        return zi
    }

    // MARK: - Inflate

    static func inflateRaw(_ src: Data, expectedSize: Int) -> Data? {
        if expectedSize <= 0 { return Data() }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { (dstRaw: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
                guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, expectedSize,
                                                 srcBase, src.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return dst
    }
}

// MARK: - Little-endian readers (absolute offsets into a non-sliced Data)

private extension Data {
    func u16(_ off: Int) -> UInt16? {
        guard off >= 0, off + 2 <= count else { return nil }
        return UInt16(self[off]) | (UInt16(self[off + 1]) << 8)
    }
    func u32(_ off: Int) -> UInt32? {
        guard off >= 0, off + 4 <= count else { return nil }
        return UInt32(self[off]) | (UInt32(self[off + 1]) << 8)
            | (UInt32(self[off + 2]) << 16) | (UInt32(self[off + 3]) << 24)
    }
    func u64(_ off: Int) -> UInt64? {
        guard off >= 0, off + 8 <= count else { return nil }
        var v: UInt64 = 0
        for i in 0 ..< 8 { v |= UInt64(self[off + i]) << (8 * i) }
        return v
    }
    func string(_ off: Int, length: Int) -> String? {
        guard off >= 0, length >= 0, off + length <= count else { return nil }
        return String(data: subdata(in: off ..< (off + length)), encoding: .utf8)
    }
}
