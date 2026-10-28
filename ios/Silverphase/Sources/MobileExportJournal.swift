import Foundation
import Darwin

/// Small app-private breadcrumbs survive a killed export; never store pixels.
/// The lock covers both the engine actor and the lightweight peak sampler.
final class MobileExportJournal: @unchecked Sendable {
    static let shared = MobileExportJournal()
    private let lock = NSLock()
    private var active = false
    private var state: [String: Any] = [:]
    private var events: [[String: Any]] = []
    private var peak: UInt64 = 0
    private var persistedPeak: UInt64 = 0
    private var started = ProcessInfo.processInfo.systemUptime
    private var previousTime = ProcessInfo.processInfo.systemUptime
    private var previousPhase = "begin"
    private var phaseSeconds: [String: Double] = [:]
    private let url = URL.documentsDirectory.appendingPathComponent("last-export.json")

    private func footprint() -> UInt64 {
        var value = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? value.phys_footprint : 0
    }
    func begin(options: MobileExportRecipe, count: Int, previewEdge: Int, destination: String) {
        lock.lock(); defer { lock.unlock() }
        active = true; peak = footprint(); persistedPeak = peak; events = []
        started = ProcessInfo.processInfo.systemUptime; previousTime = started; previousPhase = "begin"; phaseSeconds = [:]
        state = ["status": "running", "phase": "begin", "date": ISO8601DateFormatter().string(from: Date()),
                 "count": count, "previewEdge": previewEdge, "destination": destination,
                 "physicalMemory": ProcessInfo.processInfo.physicalMemory,
                 "options": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(options))) ?? [:]]
        writeLocked()
    }
    func record(_ phase: String, detail: [String: Any] = [:]) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        let current = footprint(); peak = max(peak, current)
        let now = ProcessInfo.processInfo.systemUptime
        phaseSeconds[previousPhase, default: 0] += now - previousTime
        previousTime = now; previousPhase = phase
        state["phase"] = phase
        events.append(["phase": phase, "footprint": current, "elapsed": now - started, "detail": detail])
        if events.count > 40 { events.removeFirst(events.count - 40) }
        writeLocked()
    }
    func delivery(_ phase: String) {
        lock.lock(); defer { lock.unlock() }
        guard !state.isEmpty else { return }
        peak = max(peak, footprint())
        events.append(["phase": phase, "footprint": footprint()])
        state["delivery"] = phase
        writeLocked()
    }
    func sample() {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        peak = max(peak, footprint())
        // Bound disk traffic: at most one checkpoint per additional 64 MB.
        if peak > persistedPeak + 64 * 1024 * 1024 { writeLocked() }
    }
    func finish(error: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        state["status"] = error == nil ? "completed" : "failed"
        let now = ProcessInfo.processInfo.systemUptime
        phaseSeconds[previousPhase, default: 0] += now - previousTime
        state["seconds"] = now - started
        state["error"] = error
        peak = max(peak, footprint())
        writeLocked(); active = false
    }
    private func writeLocked() {
        state["peakFootprint"] = peak
        state["available"] = os_proc_available_memory()
        state["thermal"] = ProcessInfo.processInfo.thermalState.rawValue
        state["events"] = events
        state["phaseSeconds"] = phaseSeconds
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
        persistedPeak = peak
    }
}
