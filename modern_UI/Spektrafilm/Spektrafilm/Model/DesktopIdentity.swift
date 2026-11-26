import Foundation

/// Product-owned desktop runtime namespaces. The former SpektraLab
/// directories may also belong to an upstream installation; no default
/// cache/cleanup or settings operation may write into those directories.
enum DesktopIdentity {
    static let bundleIdentifier = "com.silverphase.editor"
    static let supportDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Silverphase", directoryHint: .isDirectory)
    static let logsDirectory = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appending(path: "Logs/Silverphase", directoryHint: .isDirectory)
    static let cacheDirectory = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: bundleIdentifier, directoryHint: .isDirectory)
}
