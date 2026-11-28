import CoreImage

/// Optional system edge sharpening at the RAW input boundary. This does not
/// touch demosaicing, lens correction, local contrast, or the scanner stage.
enum RAWDecodeSharpening {
    static let disabledStamp = "|raw-sharpening-off-v1"

    static func apply(to raw: CIRAWFilter, useSystemDefault: Bool) {
        if !useSystemDefault, raw.isSharpnessSupported { raw.sharpnessAmount = 0 }
    }
}
