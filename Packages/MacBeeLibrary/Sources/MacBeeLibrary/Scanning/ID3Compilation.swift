import Foundation

/// Reads the iTunes "part of a compilation" frame (TCMP) of an MP3's ID3v2 tag.
/// The audio engine treats the frame being there as "yes", but taggers also write "0" for no
/// (Troy's Mintzkov albums showed up under Various Artists because of that).
enum ID3Compilation {
    /// true / false from the TCMP frame, or nil when the file has no ID3v2 tag or no TCMP frame.
    static func value(in url: URL) -> Bool? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 10), header.count == 10,
              header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return nil } // "ID3"
        let version = header[3]
        guard version == 3 || version == 4 else { return nil }
        let size = syncsafe(header[6], header[7], header[8], header[9])
        guard size > 0, size < 50_000_000, let tag = try? handle.read(upToCount: size), tag.count == size else { return nil }
        return compilation(inTag: tag, version: version, hasExtendedHeader: header[5] & 0x40 != 0)
    }

    /// Walks the frames of a tag body.
    static func compilation(inTag tag: Data, version: UInt8, hasExtendedHeader: Bool) -> Bool? {
        let bytes = [UInt8](tag)
        var index = 0
        if hasExtendedHeader, bytes.count >= 4 {
            let extended = version == 4 ? syncsafe(bytes[0], bytes[1], bytes[2], bytes[3])
                                        : Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            index = version == 4 ? extended : extended + 4
        }
        while index + 10 <= bytes.count {
            let id = String(bytes: bytes[index..<index + 4], encoding: .ascii) ?? ""
            if id.first == "\0" || id.isEmpty { break } // padding
            let frameSize = version == 4
                ? syncsafe(bytes[index + 4], bytes[index + 5], bytes[index + 6], bytes[index + 7])
                : Int(bytes[index + 4]) << 24 | Int(bytes[index + 5]) << 16 | Int(bytes[index + 6]) << 8 | Int(bytes[index + 7])
            let start = index + 10
            guard frameSize >= 0, start + frameSize <= bytes.count else { break }
            if id == "TCMP", frameSize > 1 {
                let text = decode(Array(bytes[start + 1..<start + frameSize]), encoding: bytes[start])
                return text.trimmingCharacters(in: CharacterSet(charactersIn: "\0 ")).hasPrefix("1")
            }
            index = start + frameSize
        }
        return nil
    }

    private static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
        switch encoding {
        case 1: return String(bytes: bytes, encoding: .utf16) ?? ""
        case 2: return String(bytes: bytes, encoding: .utf16BigEndian) ?? ""
        case 3: return String(bytes: bytes, encoding: .utf8) ?? ""
        default: return String(bytes: bytes, encoding: .isoLatin1) ?? ""
        }
    }

    private static func syncsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        Int(a & 0x7F) << 21 | Int(b & 0x7F) << 14 | Int(c & 0x7F) << 7 | Int(d & 0x7F)
    }
}
