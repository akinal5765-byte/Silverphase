import os.signpost

/// Stable Instruments intervals for the app's expensive image boundaries.
/// The same category covers decode, interactive renders and export, so a
/// single Points of Interest track shows where the user's wait went.
enum PerformanceTrace {
    private static let log = OSLog(subsystem: "com.hanze.filmify", category: .pointsOfInterest)

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
