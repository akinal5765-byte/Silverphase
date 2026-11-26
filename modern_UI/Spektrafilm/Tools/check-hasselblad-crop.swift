// SPDX-License-Identifier: GPL-3.0-or-later
// Fixture adapted from SpektraLab a6979f7 (Wei Cheng); no camera image data.
// Standalone: swiftc Spektrafilm/Import/HasselbladCrop.swift Tools/check-hasselblad-crop.swift -o /tmp/check-3fr

import Foundation

/// A minimal classic TIFF with the same IFD0 → SubIFD and IFD0 → ExifIFD → MakerNotes route as a 3FR.
/// Nothing is decoded; both byte orders carry the same numbers as the owner's X2D files.
func synthetic3FR(littleEndian: Bool = true, mode: UInt16 = 12, y: UInt16 = 2316, height: UInt16 = 4302) -> Data {
    var bytes = [UInt8](repeating: 0, count: 154)
    func put16(_ value: UInt16, _ at: Int) {
        if littleEndian {
            bytes[at] = UInt8(value & 0xff); bytes[at + 1] = UInt8(value >> 8)
        } else {
            bytes[at] = UInt8(value >> 8); bytes[at + 1] = UInt8(value & 0xff)
        }
    }
    func put32(_ value: UInt32, _ at: Int) {
        if littleEndian {
            put16(UInt16(value & 0xffff), at); put16(UInt16(value >> 16), at + 2)
        } else {
            put16(UInt16(value >> 16), at); put16(UInt16(value & 0xffff), at + 2)
        }
    }
    func entry(_ at: Int, _ tag: UInt16, _ type: UInt16, _ count: UInt32, _ value: UInt32) {
        put16(tag, at); put16(type, at + 2); put32(count, at + 4); put32(value, at + 8)
    }
    bytes[0] = littleEndian ? 0x49 : 0x4d; bytes[1] = bytes[0]
    put16(42, 2); put32(8, 4)
    put16(3, 8)                                            // IFD0
    entry(10, 0x010f, 2, 11, 50)                          // Make
    entry(22, 0x014a, 4, 1, 62)                           // SubIFD
    entry(34, 0x8769, 4, 1, 108)                          // ExifIFD
    for (index, byte) in Array("Hasselblad\0".utf8).enumerated() { bytes[50 + index] = byte }
    put16(2, 62)                                           // SubIFD
    entry(64, 0xc61f, 4, 2, 92)                           // DefaultCropOrigin
    entry(76, 0xc620, 4, 2, 100)                          // DefaultCropSize
    put32(128, 92); put32(96, 96); put32(11656, 100); put32(8742, 104)
    put16(1, 108)                                          // ExifIFD
    entry(110, 0x927c, 7, 28, 126)                        // MakerNotes
    put16(1, 126)                                          // MakerNotes
    entry(128, 0x0059, 3, 5, 144)                         // in-camera crop
    for (index, value) in [mode, 128, y, 11656, height].enumerated() { put16(value, 144 + index * 2) }
    return Data(bytes)
}

@main enum CheckHasselbladCrop {
    static func main() {
        var assertions = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            assertions += 1
        }
        func rect(_ record: HasselbladCrop.Record, _ orientation: Int) -> HasselbladCrop.Normalized? {
            HasselbladCrop.normalized(record, storedWidth: 11664, storedHeight: 8750, orientation: orientation)
        }
        for littleEndian in [true, false] {
            let data = synthetic3FR(littleEndian: littleEndian)
            let expected = HasselbladCrop.Record(mode: 12, x: 128, y: 2316, width: 11656, height: 4302,
                                                 defaultX: 128, defaultY: 96, defaultWidth: 11656, defaultHeight: 8742)
            check(HasselbladCrop.read(data) == expected, "reads TIFF in both byte orders")
            let w = 11656.0 / 11664, h = 4302.0 / 8750
            let x = 4.0 / 11664, y = 2224.0 / 8750
            let positions = [(x, y), (1-x-w, y), (1-x-w, 1-y-h), (x, 1-y-h),
                             (y, x), (1-y-h, x), (1-y-h, 1-x-w), (y, 1-x-w)]
            for (i, p) in positions.enumerated() {
                guard let r = rect(expected, i + 1) else { fatalError("orientation missing") }
                check(abs(r.x-p.0) < 1e-9 && abs(r.y-p.1) < 1e-9 &&
                      abs(r.width-(i < 4 ? w : h)) < 1e-9 && abs(r.height-(i < 4 ? h : w)) < 1e-9,
                      "applies visible-frame inset and EXIF orientation \(i + 1)")
            }
            guard let whole = HasselbladCrop.read(synthetic3FR(littleEndian: littleEndian, mode: 1, y: 96, height: 8742)) else { fatalError("whole-frame fixture invalid") }
            check(rect(whole, 1) == nil, "mode 1 leaves the whole frame alone")
            check(HasselbladCrop.normalized(expected, storedWidth: 3888, storedHeight: 1434, orientation: 1) == nil,
                  "refuses to double-crop a smaller embedded preview")
            check(HasselbladCrop.read(synthetic3FR(littleEndian: littleEndian, y: 5000)) == nil, "rejects out-of-sensor crop")
            var wrongType = data
            wrongType[130] = littleEndian ? 4 : 0
            wrongType[131] = littleEndian ? 0 : 4
            check(HasselbladCrop.read(wrongType) == nil, "rejects non-SHORT MakerNote data")
            var giant = data
            giant.replaceSubrange(4..<8, with: [UInt8](repeating: 255, count: 4))
            check(HasselbladCrop.read(giant) == nil, "rejects invalid IFD offset")
            var makerBoundary = data
            makerBoundary.replaceSubrange(114..<118, with: littleEndian ? [5, 0, 0, 0] : [0, 0, 0, 5])
            check(HasselbladCrop.read(makerBoundary) == nil, "refuses to read past the MakerNotes block")
            for n in 0..<data.count {
                check(HasselbladCrop.read(Data(data.prefix(n))) == nil, "rejects truncated TIFF at byte \(n)")
            }
        }
        print("Hasselblad 3FR crop: \(assertions) assertions passed")
    }
}
