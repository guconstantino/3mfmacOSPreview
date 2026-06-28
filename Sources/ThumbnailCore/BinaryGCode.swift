//  BinaryGCode.swift
//  ThumbnailCore
//
//  Extract thumbnails from a binary G-code (.bgcode) file. The container starts
//  with the magic "GCDE" followed by a sequence of typed blocks; a block of type
//  5 is a thumbnail (PNG/JPG/QOI bytes). Format reference:
//  https://github.com/prusa3d/libbgcode
//
//  Clean-room Swift re-implementation of ThumbnailBinaryGCode.m (ThumbHost3mf,
//  Apache-2.0). See NOTICE / ARCHITECTURE.md.

import Foundation

enum BinaryGCode {
    private static let maxHead = 512 * 1024
    private static let thumbnailBlockType: UInt16 = 5
    private static let parameterSize = 2

    static func thumbnailDatas(from url: URL) -> [Data] {
        guard let data = readHead(url) else { return [] }
        return thumbnailDatas(in: data)
    }

    static func thumbnailDatas(in data: Data) -> [Data] {
        let bytes = [UInt8](data)
        guard bytes.count > 10,
              bytes[0] == 0x47, bytes[1] == 0x43, bytes[2] == 0x44, bytes[3] == 0x45 // "GCDE"
        else { return [] }

        func u16(_ p: Int) -> UInt16 { UInt16(bytes[p]) | (UInt16(bytes[p + 1]) << 8) }
        func u32(_ p: Int) -> UInt32 {
            UInt32(bytes[p]) | (UInt32(bytes[p + 1]) << 8)
                | (UInt32(bytes[p + 2]) << 16) | (UInt32(bytes[p + 3]) << 24)
        }

        var index = 4
        let version = u32(index); index += 4
        guard version == 1 else { return [] }
        let checktype = u16(index); index += 2
        guard checktype <= 1 else { return [] }

        var result: [Data] = []
        while index + 12 < bytes.count {
            let blockType = u16(index); index += 2
            guard blockType <= 5 else { break }
            let compressionType = u16(index); index += 2
            guard compressionType <= 3 else { break }
            let uncompressedSize = u32(index); index += 4
            var compressedSize = uncompressedSize
            if compressionType >= 1, compressionType <= 3 {
                guard index + 4 <= bytes.count else { break }
                compressedSize = u32(index); index += 4
            }
            if checktype != 0 {
                index += 4 // checksum size
                guard index <= bytes.count else { break }
            }
            index += parameterSize

            if blockType == thumbnailBlockType {
                let size = Int(compressedSize)
                guard index + size <= bytes.count else { break }
                result.append(Data(bytes[index ..< index + size]))
                index += size
                index += 4 // trailing bytes to the next block (per reference impl)
            } else {
                index += Int(compressedSize)
                if index > bytes.count { break }
            }
        }
        return result
    }

    private static func readHead(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxHead)
    }
}
