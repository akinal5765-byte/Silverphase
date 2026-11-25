// Silverphase uses the same final-space chroma policy in both hosts.
// The knee is adopted from Hanze Qiu's SpektraLab (GPL-3.0-or-later):
// https://github.com/JamesQiu2005/SpektraLab/commit/d661b3b957adfd0fa90259d7c3b67cfe0d996165

enum OutputGamutPolicy {
    /// Preserve chroma up to 70% of the destination's hue/lightness limit.
    /// The 0.995 asymptote leaves headroom for the interpolated gamut table
    /// near the cube boundary. The engine has already applied its lightness
    /// shoulder in the working space; do not apply it again here.
    static let finalTransform = #"{"lightness_compression_active": false, "knee": [0.7, 0.995, 6]}"#
}
