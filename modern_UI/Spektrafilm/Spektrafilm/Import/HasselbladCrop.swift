// SPDX-License-Identifier: GPL-3.0-or-later
// Hasselblad 3FR MakerNote reader adapted from Wei Cheng's SpektraLab change:
// https://github.com/JamesQiu2005/SpektraLab/commit/a6979f7cf9f0445d2498d89ca2b14d29c1ee8100
// Silverphase: bound MakerNote directories, limit Make, require a SHORT crop
// record and keep orientation arithmetic independent of the app and ImageIO.

import Foundation

enum HasselbladCrop {
    struct Record: Equatable {
        var mode: Int
        var x: Double, y: Double, width: Double, height: Double
        var defaultX: Double, defaultY: Double, defaultWidth: Double, defaultHeight: Double
    }

    struct Normalized: Equatable {
        let x: Double, y: Double, width: Double, height: Double
    }

    static func normalized(_ crop: Record, storedWidth: Double, storedHeight: Double,
                           orientation: Int) -> Normalized? {
        // Upstream verified the half-difference inset against the X2D's
        // visible frame. If ImageIO reports a smaller preview, do not apply it.
        guard crop.mode != 1, storedWidth.isFinite, storedHeight.isFinite,
              storedWidth >= crop.defaultWidth, storedHeight >= crop.defaultHeight,
              storedWidth > 0, storedHeight > 0, (1...8).contains(orientation) else { return nil }
        let x = (crop.x - crop.defaultX + (storedWidth - crop.defaultWidth) / 2) / storedWidth
        let y = (crop.y - crop.defaultY + (storedHeight - crop.defaultHeight) / 2) / storedHeight
        let w = crop.width / storedWidth, h = crop.height / storedHeight
        let right = min(1, x + w), bottom = min(1, y + h)
        guard x >= 0, y >= 0, x + w <= 1 + 1e-9, y + h <= 1 + 1e-9,
              right > x, bottom > y else { return nil }
        func point(_ x: Double, _ y: Double) -> (Double, Double) {
            switch orientation {
            case 2: (1 - x, y)
            case 3: (1 - x, 1 - y)
            case 4: (x, 1 - y)
            case 5: (y, x)
            case 6: (1 - y, x)
            case 7: (1 - y, 1 - x)
            case 8: (y, 1 - x)
            default: (x, y)
            }
        }
        let (a, b) = point(x, y), (c, d) = point(right, bottom)
        return Normalized(x: min(a, c), y: min(b, d), width: abs(c - a), height: abs(d - b))
    }

    /// Memory mapping keeps this a header read even though a 3FR is hundreds of megabytes: only the
    /// pages the TIFF directories point at are touched, never the pixel payload as an image decode.
    static func read(_ url: URL) -> Record? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return read(data)
    }

    static func read(_ data: Data) -> Record? {
        let tiff = TIFF(data)
        guard tiff.headerIsValid, let first = tiff.firstDirectory(),
              let makeEntry = first.first(where: { $0.tag == 0x010f }),
              tiff.text(makeEntry)?.lowercased().contains("hasselblad") == true else { return nil }

        var defaultCrop: (x: Double, y: Double, w: Double, h: Double)?
        if let subIDs = first.first(where: { $0.tag == 0x014a }), let offsets = tiff.numbers(subIDs) {
            for offset in offsets {
                guard let directory = tiff.directory(at: Int(offset)),
                      let origin = directory.first(where: { $0.tag == 0xc61f }).flatMap({ tiff.numbers($0) }),
                      let size = directory.first(where: { $0.tag == 0xc620 }).flatMap({ tiff.numbers($0) }),
                      origin.count == 2, size.count == 2 else { continue }
                defaultCrop = (origin[0], origin[1], size[0], size[1])
                break
            }
        }
        guard let defaultCrop,
              let exifOffset = first.first(where: { $0.tag == 0x8769 }).flatMap({ tiff.numbers($0)?.first }),
              let exif = tiff.directory(at: Int(exifOffset)),
              let makerEntry = exif.first(where: { $0.tag == 0x927c }),
              makerEntry.type == 7,
              let maker = tiff.payload(makerEntry, unitSize: 1), maker.count >= 2,
              let notes = tiff.directory(at: maker.offset, end: maker.offset + maker.count),
              let cropEntry = notes.first(where: { $0.tag == 0x0059 && $0.type == 3 }),
              let values = tiff.numbers(cropEntry), values.count == 5 else { return nil }

        let record = Record(mode: Int(values[0]), x: values[1], y: values[2], width: values[3], height: values[4],
                            defaultX: defaultCrop.x, defaultY: defaultCrop.y,
                            defaultWidth: defaultCrop.w, defaultHeight: defaultCrop.h)
        guard record.mode > 0, record.width > 0, record.height > 0,
              record.defaultWidth > 0, record.defaultHeight > 0,
              record.x >= record.defaultX, record.y >= record.defaultY,
              record.x + record.width <= record.defaultX + record.defaultWidth,
              record.y + record.height <= record.defaultY + record.defaultHeight else { return nil }
        return record
    }

    /// The small, bounds-checked subset of classic TIFF that a 3FR's three directories need.
    private struct TIFF {
        let data: Data
        let littleEndian: Bool

        init(_ data: Data) {
            self.data = data
            littleEndian = data.count >= 2 && data[data.startIndex] == 0x49 && data[data.startIndex + 1] == 0x49
        }

        var headerIsValid: Bool {
            guard data.count >= 8 else { return false }
            let big = data[data.startIndex] == 0x4d && data[data.startIndex + 1] == 0x4d
            return (littleEndian || big) && u16(2) == 42
        }

        struct Entry {
            var tag: UInt16, type: UInt16, count: UInt32, valueField: Int
        }

        func valid(_ offset: Int, _ count: Int) -> Bool {
            offset >= 0 && count >= 0 && count <= data.count && offset <= data.count - count
        }

        func u16(_ offset: Int) -> UInt16? {
            guard valid(offset, 2) else { return nil }
            let a = UInt16(data[data.startIndex + offset]), b = UInt16(data[data.startIndex + offset + 1])
            return littleEndian ? a | b << 8 : a << 8 | b
        }

        func u32(_ offset: Int) -> UInt32? {
            guard valid(offset, 4) else { return nil }
            let a = UInt32(data[data.startIndex + offset]), b = UInt32(data[data.startIndex + offset + 1])
            let c = UInt32(data[data.startIndex + offset + 2]), d = UInt32(data[data.startIndex + offset + 3])
            return littleEndian ? a | b << 8 | c << 16 | d << 24 : a << 24 | b << 16 | c << 8 | d
        }

        func firstDirectory() -> [Entry]? {
            guard let offset = u32(4) else { return nil }
            return directory(at: Int(offset))
        }

        func directory(at offset: Int, end: Int? = nil) -> [Entry]? {
            guard let count = u16(offset), count <= 512 else { return nil }
            let bytes = Int(count) * 12 + 4
            guard valid(offset + 2, bytes), end.map({ offset + 2 + bytes <= $0 }) ?? true else { return nil }
            return (0..<Int(count)).compactMap { index in
                let at = offset + 2 + index * 12
                guard let tag = u16(at), let type = u16(at + 2), let count = u32(at + 4) else { return nil }
                return Entry(tag: tag, type: type, count: count, valueField: at + 8)
            }
        }

        func payload(_ entry: Entry, unitSize: Int) -> (offset: Int, count: Int)? {
            guard unitSize > 0, entry.count <= 1 << 24 else { return nil }
            let (count, overflow) = Int(entry.count).multipliedReportingOverflow(by: unitSize)
            guard !overflow else { return nil }
            let offset: Int
            if count <= 4 {
                offset = entry.valueField
            } else {
                guard let pointed = u32(entry.valueField) else { return nil }
                offset = Int(pointed)
            }
            return valid(offset, count) ? (offset, count) : nil
        }

        func numbers(_ entry: Entry) -> [Double]? {
            guard [3, 4].contains(entry.type), entry.count <= 32,
                  let payload = payload(entry, unitSize: entry.type == 3 ? 2 : 4) else { return nil }
            var out: [Double] = []
            for index in 0..<Int(entry.count) {
                let at = payload.offset + index * (entry.type == 3 ? 2 : 4)
                guard let value = entry.type == 3 ? u16(at).map(Double.init) : u32(at).map(Double.init) else { return nil }
                out.append(value)
            }
            return out
        }

        func text(_ entry: Entry) -> String? {
            guard entry.type == 2, entry.count <= 128, let payload = payload(entry, unitSize: 1) else { return nil }
            let bytes = (0..<payload.count).map { data[data.startIndex + payload.offset + $0] }
            return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        }
    }
}
