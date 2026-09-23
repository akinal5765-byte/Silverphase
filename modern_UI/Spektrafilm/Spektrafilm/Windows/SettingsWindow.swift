//  SettingsWindow.swift — SpektraLab ▸ Settings… (⌘,).
//
//  RFC-016 §6 specifies a diagnostics column and names the controls it needs
//  to exist. This is that page, plus the two render settings that were
//  already settable in code and had nowhere to be set from (the preview
//  resolution, which `Session.setPreviewLongEdge` has always accepted, and
//  the fast stock preview).
//
//  Two rules this page follows, both from the RFC:
//
//  - **Every number it shows comes from the same place the log does.** The
//    memory readout reads `Diagnostics.memory`, which is the `memory` sampler
//    the log records from — not a second call to `phys_footprint`. §8's "the
//    memory numbers are the same numbers" is only checkable because there is
//    one source, and a page that sampled on its own would make that check
//    pass while the claim it stands for quietly stopped being true.
//  - **A control that costs something says so where it is.** Per-node GPU
//    timings give up the batching the engine depends on; the caption under
//    the checkbox is `Diagnostics.perNodeTimingsNote`, and it is the RFC's
//    own sentence rather than a paraphrase that could drift from it. These
//    captions were briefly moved to hover help to make the page more compact;
//    RFC-016 §5.2 says "the Settings toggle must say so in the same
//    sentence", and a tooltip only says it to somebody who already suspected
//    there was something to hover over.
//
//  Visually this is the app's right panel: `PanelSection` headers, rail rows,
//  hairlines and `Theme` tokens, with no second card/well language inside the
//  rail. Not an AppKit-standard
//  preferences window, because the rest of the interface is not one either.
//
//  **The whole page is localized** (2026-09-23). The first pass translated
//  Language and Interface only, on the argument that half a page reads worse
//  than either whole state; the user's instruction was to finish it — "整理和
//  翻译设置以及各种菜单" — so every label, caption and readout here comes from
//  the string table now, like the rest of the interface. The *sentences* that
//  used to live beside their controls in `Diagnostics` (`memoryReserveNote` and
//  the rest) moved into the table too, because one sentence with two homes is
//  the thing that drifts.

import AppKit
import SwiftUI

struct SettingsWindow: View {
    @Bindable var session: Session
    /// The observable the RFC-016 work put the settings on. Read directly
    /// rather than copied into `@State`: a copy is a second source of truth,
    /// and the whole point of §8.5 is that there is one.
    private var diagnostics: Diagnostics { Diagnostics.shared }
    /// A capture gets the page's **whole height**: the real window is a
    /// scrolling rail 640 pt tall, and a reviewer looking at one screenshot of
    /// it can only ever see the first four sections — which is how the bottom
    /// half of this page stayed English for a release. `Tools/snapshot.sh`
    /// asks for a tall window and this lets the stack fill it.
    @Environment(\.snapshotMode) private var snapshotMode

    @State private var bundleResult: String?
    @State private var savingBundle = false
    /// The memory readout refreshes while the page is open and stops when it
    /// closes. A settings page nobody is looking at has no business taking
    /// samples.
    @State private var ticker: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                languageSection
                appearanceSection
                renderingSection
                diagnosticsSection
                memorySection
                diskCacheSection
                logsSection
                bundleSection
                machineSection
            }
            .padding(.vertical, Theme.Metric.Settings.verticalInset)
        }
        .frame(width: Theme.Metric.Settings.width,
               height: snapshotMode ? nil : Theme.Metric.Settings.height)
        .background(Theme.cardFill)
        .preferredColorScheme(.dark)
        .onAppear {
            diagnostics.refreshMemory()
            session.refreshDiskCacheUsage()
            // 2 s: fast enough to watch a render land, slow enough that the
            // page is not itself a load. The sampler's own records are
            // written at boundaries, not on this timer.
            ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated {
                    diagnostics.refreshMemory()
                    session.refreshDiskCacheUsage()
                }
            }
        }
        .onDisappear { ticker?.invalidate(); ticker = nil }
    }

    // MARK: - language

    /// First on the page, because it is the control for the thing that changes
    /// every other word on the screen — including the caption under it.
    ///
    /// The menu's three labels come from `LanguageSetting.label(in:)` and not
    /// from `L(_:)`, and the active language is read **once, here, outside the
    /// closure**: `PillMenu` takes a plain `(T) -> String`, so a closure that
    /// reached into main-actor state on its own could not be built in a view's
    /// body without a concurrency error. Reading it outside keeps that closure
    /// a pure function of a captured value.
    private var languageSection: some View {
        let active = Localization.shared.resolved
        return PanelSection(L(.setLanguage), systemImage: "globe", key: "setLanguage") {
            SettingsRows {
                VStack(spacing: 4) {
                    PillMenu(label: L(.setLanguage),
                             options: LanguageSetting.allCases,
                             title: { $0.label(in: active) },
                             selection: Binding(get: { Localization.shared.language },
                                                set: { Localization.shared.language = $0 }))
                    caption(L(.setLanguageCaption))
                }
            }
        }
    }

    // MARK: - appearance

    private var appearanceSection: some View {
        return PanelSection(L(.setInterface),
                            systemImage: "textformat.size", key: "setAppearance") {
            SettingsRows {
                VStack(spacing: Theme.Metric.Settings.rowSpacing) {
                    PillMenu(label: L(.setScale),
                             options: InterfaceScale.allCases,
                             title: { $0.label },
                             selection: Binding(get: { InterfaceScaleStore.shared.scale },
                                                set: { InterfaceScaleStore.shared.scale = $0 }))
                    caption(L(.setScaleCaption))
                }
            }
        }
    }

    // MARK: - rendering

    private var renderingSection: some View {
        PanelSection(L(.setRendering), systemImage: "slider.horizontal.3", key: "setRendering") {
            SettingsRows {
                VStack(spacing: 4) {
                    PillMenu(label: L(.setPreview), options: Session.previewEdgeChoices,
                             title: { "\($0) px" },
                             selection: Binding(get: { session.previewLongEdge },
                                                set: { session.setPreviewLongEdge($0) }))
                    caption(L(.setPreviewCaption))
                    ToggleRow(label: L(.setFastStockPreview), isOn: $session.fastStockPreview)
                    caption(L(.setFastStockPreviewCaption))
                    ToggleRow(label: L(.setCropRemaps),
                              isOn: Binding(get: { Session.recalculateEffectsAfterCrop },
                                            set: { Session.recalculateEffectsAfterCrop = $0
                                                   session.recomputeFilmFormat() }))
                    caption(L(.setCropRemapsCaption))
                }
            }
        }
    }

    // MARK: - diagnostics

    private var diagnosticsSection: some View {
        PanelSection(L(.setDiagnostics), systemImage: "stethoscope", key: "setDiagnostics") {
            SettingsRows {
                VStack(spacing: 4) {
                    PillMenu(label: L(.setLogLevel), options: LogLevelSetting.allCases,
                             title: { L($0.key) },
                             selection: Binding(get: { diagnostics.level },
                                                set: { diagnostics.level = $0 }))
                    caption(L(diagnostics.level.detailKey))
                    ToggleRow(label: L(.setPerNodeTimings),
                              isOn: Binding(get: { diagnostics.perNodeGPUTimings },
                                            set: { diagnostics.perNodeGPUTimings = $0 }))
                    // Visible, not hover help. RFC-016 §5.2 is specific: "the
                    // Settings toggle must say so in the same sentence". A
                    // tooltip is not the toggle saying so — it is the toggle
                    // saying so to whoever already suspected there was
                    // something to hover over.
                    caption(L(.setPerNodeTimingsNote))
                }
            }
        }
    }

    // MARK: - memory

    /// §6's live readout, and §11.5's override in the one place it can be
    /// taken back. The override is a *standing* permission — granting it from
    /// a warning is easy and forgetting it was granted is easier, so this is
    /// where it is visible and revocable.
    private var memorySection: some View {
        PanelSection(L(.setMemory), systemImage: "memorychip", key: "setMemory") {
            SettingsRows {
                VStack(alignment: .leading, spacing: 3) {
                    if let m = diagnostics.memory {
                        readout(L(.setFootprint), bytes(m.footprintBytes))
                        readout(L(.setSessionPeak), bytes(m.peakBytes))
                        readout(L(.setFree), bytes(m.freeBytes))
                    } else {
                        readout(L(.setFootprint), L(.setNotSampled))
                    }
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    // A setting, not a readout — so it lives outside the
                    // `memory` branch above. Inside it, the control would
                    // disappear until the first sample landed, which is
                    // exactly when someone setting up a small machine would
                    // go looking for it.
                    intRow(L(.setReserve), diagnostics.memoryReserveMegabytes, "MB",
                           Diagnostics.memoryReserveRange) {
                        diagnostics.memoryReserveMegabytes = $0
                    }
                    caption(L(.setReserveNote))
                    intRow(L(.setWorkingSetCap),
                           diagnostics.memoryCapIsUnlimited
                               ? Diagnostics.defaultMemoryCapMB
                               : diagnostics.memoryCapMegabytes,
                           "MB", Diagnostics.memoryCapRange) {
                        diagnostics.memoryCapMegabytes = $0
                    }
                    .disabled(diagnostics.memoryCapIsUnlimited)
                    ToggleRow(label: L(.setUnlimited),
                              isOn: Binding(get: { diagnostics.memoryCapIsUnlimited },
                                            set: { diagnostics.memoryCapIsUnlimited = $0 }))
                    caption(L(.setCapNote))
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    readout(L(.setHeldByApp),
                            bytes(UInt64(max(0, diagnostics.arena.totalBytes))),
                            help: arenaBreakdown())
                    readout(L(.setEvictable),
                            bytes(UInt64(max(0, diagnostics.arena.evictableBytes))))
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    ToggleRow(label: L(.setAllowOverReserve),
                              isOn: Binding(get: { diagnostics.allowOverReserve },
                                            set: { diagnostics.allowOverReserve = $0 }))
                    caption(L(.setAllowOverReserveCaption))
                }
            }
        }
    }

    // MARK: - disk cache

    /// The disk half of what the app holds, and until now the half nobody
    /// could see. `DiskCacheStore` has always evicted — against a 16 GB
    /// constant compiled into it, which is not the same as being managed: no
    /// readout, no control, and no line in the session record. This section is
    /// the readout and the control; `Diagnostics.diskCacheCapMegabytes` is the
    /// line in the record.
    ///
    /// It sits under Memory rather than under Logs because it answers the same
    /// question — what is SpektraLab holding, and what may it hold — for the
    /// other kind of storage. The unit differs and so does the consequence:
    /// over the memory cap the app evicts to keep working, over this one it
    /// evicts to stop growing.
    private var diskCacheSection: some View {
        PanelSection(L(.setDiskCache), systemImage: "internaldrive", key: "setDiskCache") {
            SettingsRows {
                VStack(alignment: .leading, spacing: 3) {
                    if session.hasDiskCache {
                        readout(L(.setInUse), "\(bytes(session.diskCacheBytes)) of "
                                          + "\(bytes(diagnostics.diskCacheCapBytes))")
                    } else {
                        readout(L(.setInUse), L(.setCacheUnavailable))
                    }
                    intRow(L(.setLimit), diagnostics.diskCacheCapMegabytes / 1_000, "GB",
                           Diagnostics.diskCacheCapGigabyteRange) {
                        diagnostics.diskCacheCapMegabytes = $0 * 1_000
                    }
                    caption(L(.setCacheNote))
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    labelled(L(.setLocation)) {
                        Text(Session.diskCacheRoot.path)
                            .font(Theme.Font.caption).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 16)
                            .pillSurface(base: Theme.field)
                    }
                    HStack(spacing: 10) {
                        Button(L(.setRevealInFinder)) {
                            NSWorkspace.shared.activateFileViewerSelecting([Session.diskCacheRoot])
                        }
                        .buttonStyle(.surface)
                        Button(L(.setEmptyCache)) {
                            session.clearDiskCacheNow()
                        }
                        .buttonStyle(.surface)
                        .foregroundStyle(session.hasDiskCache ? Theme.accent : Theme.dim)
                        .disabled(!session.hasDiskCache)
                        .help(L(.setEmptyCacheHelp))
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - logs

    private var logsSection: some View {
        PanelSection(L(.setLogs), systemImage: "doc.text", key: "setLogs") {
            SettingsRows {
                VStack(spacing: 4) {
                    intRow(L(.setKeepFor), diagnostics.retentionDays, L(.setUnitDays), 1...365) {
                        diagnostics.retentionDays = $0
                    }
                    intRow(L(.setKeepAtMost), diagnostics.retentionMegabytes, "MB", 10...10_000) {
                        diagnostics.retentionMegabytes = $0
                    }
                    intRow(L(.setKeepAtMost), diagnostics.retentionFiles, L(.setUnitFiles), 1...500) {
                        diagnostics.retentionFiles = $0
                    }
                    caption(L(.setRetentionCaption))
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    labelled(L(.setDestination)) {
                        Text(diagnostics.logDirectory.path)
                            .font(Theme.Font.caption).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.head)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .frame(height: 16)
                            .pillSurface(base: Theme.field)
                        Button(L(.setChoose)) { chooseLogDirectory() }
                            .buttonStyle(.surface)
                    }
                    caption(L(.setLogDirectoryNote))
                    if let f = diagnostics.cleanupFailure { warning(f) }
                    if let f = diagnostics.writeFailure { warning(f) }
                    HStack(spacing: 10) {
                        Button(L(.setRevealInFinder)) { diagnostics.revealLogsInFinder() }
                            .buttonStyle(.surface)
                        Button(L(.setClearLogs)) { diagnostics.clearLogsNow() }
                            .buttonStyle(.surface)
                            .help(L(.setClearLogsHelp))
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - the bundle

    private var bundleSection: some View {
        PanelSection(L(.setBundle), systemImage: "shippingbox", key: "setBundle") {
            SettingsRows {
                VStack(spacing: 4) {
                    ToggleRow(label: L(.setIncludeFileNames),
                              isOn: Binding(get: { diagnostics.includeFileNamesInBundle },
                                            set: { diagnostics.includeFileNamesInBundle = $0 }))
                    caption(L(.setFileNamesNote))
                    HStack(spacing: 10) {
                        // The section's one primary action (UI-SPEC §3.6):
                        // accent-filled, dark ink, the same pairing the export
                        // page's Export button uses.
                        Button(savingBundle ? L(.setSaving) : L(.setSaveBundle)) { saveBundle() }
                            .buttonStyle(.primarySurface)
                            .disabled(savingBundle)
                        Spacer()
                    }
                    caption(L(.setBundleCaption))
                    if let bundleResult { caption(bundleResult) }
                }
            }
        }
    }

    // MARK: - this machine

    /// §1.1 and §1.7, where a person can read them: which engine is actually
    /// running, and whether the last session ended cleanly. The second is the
    /// only place a hang, a jetsam kill or a panic shows up at all — its
    /// evidence is a *missing* record, so if this page did not say so nothing
    /// would.
    private var machineSection: some View {
        PanelSection(L(.setMachine), systemImage: "info.circle", key: "setMachine") {
            SettingsRows {
                VStack(alignment: .leading, spacing: 3) {
                    readout(L(.setApp), Diagnostics.bundleInfo.version)
                    readout(L(.setEngine), diagnostics.engineVersion ?? L(.setNotReported))
                    readout(L(.setRenderCore), session.renderCore ?? L(.setNotReported))
                    readout(L(.setLogFile), diagnostics.currentLogFile?.lastPathComponent ?? L(.setNone))
                    Divider().overlay(Theme.plotGrid).padding(.vertical, 4)
                    if diagnostics.previousSessionChecked {
                        if let p = diagnostics.previousSession {
                            readout(L(.setLastSession), p.endedCleanly
                                    ? L(.setEndedCleanly)
                                    : "\(L(.setEndedUnclean)) (\(p.file))")
                            if !p.endedCleanly {
                                caption(L(.setUncleanCaption))
                            }
                        } else {
                            readout(L(.setLastSession), L(.setNoEarlierLog))
                        }
                    }
                    if let e = diagnostics.lastError { warning(L(.setLastError) + " — " + e) }
                }
            }
        }
    }

    // MARK: - pieces

    private func readout(_ label: String, _ value: String, help: String? = nil) -> some View {
        HStack(spacing: 0) {
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.dim)
                .frame(width: 96, alignment: .leading)
            Text(value).font(Theme.Font.caption).foregroundStyle(Theme.text)
                .lineLimit(1).truncationMode(.middle)
        }
        .help(help ?? "")
    }

    private func arenaBreakdown() -> String {
        let parts = diagnostics.arena.breakdown().map {
            "\($0.kind): \(bytes(UInt64(max(0, $0.bytes))))"
        }
        return parts.isEmpty ? L(.setNoCacheAllocations)
                             : parts.joined(separator: "\n")
    }

    /// An integer field with its unit beside it. A stepper rather than a
    /// slider: these are typed numbers with meaningful exact values, and the
    /// clamping lives in `Diagnostics` so a typed value cannot get out of
    /// range from here.
    private func intRow(_ label: String, _ value: Int, _ unit: String,
                        _ range: ClosedRange<Int>, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(Theme.Font.label).foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.sliderLabelWidth, alignment: .leading)
            Stepper(value: Binding(get: { value }, set: set), in: range) {
                Text("\(value)").font(Theme.Font.value).foregroundStyle(Theme.text)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            Text(unit).font(Theme.Font.caption).foregroundStyle(Theme.dim)
            Spacer()
        }
        .frame(height: Theme.Metric.rowHeight)
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 4) {
            Text(label).font(Theme.Font.label).foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.sliderLabelWidth, alignment: .leading)
            content()
        }
        .frame(height: Theme.Metric.rowHeight)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption).foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func warning(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.caption).foregroundStyle(Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    /// Bytes as a person reads them. Decimal units, because that is what
    /// Activity Monitor and the `phys_footprint` figures in the RFC use, and
    /// two numbers for the same memory that differ by 7 % is its own bug
    /// report.
    private func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_000_000_000
        return gb >= 1 ? String(format: "%.2f GB", gb)
                       : String(format: "%.0f MB", Double(b) / 1_000_000)
    }

    private func chooseLogDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L(.setChoose)
        panel.message = L(.setChooseLogMessage)
        panel.directoryURL = diagnostics.logDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        diagnostics.logDirectory = url
    }

    private func saveBundle() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Silverphase-diagnostics.zip"
        panel.allowedContentTypes = [.zip]
        // §7: "the bundle dialog says so plainly before saving". The message
        // is the same sentence the checkbox above carries, so what the user
        // agreed to and what the bundle contains cannot differ.
        panel.message = diagnostics.includeFileNamesInBundle
            ? L(.setFileNamesNote)
            : L(.setPlaceholderNames)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        savingBundle = true
        bundleResult = nil
        Task {
            defer { savingBundle = false }
            do {
                let written = try await diagnostics.saveDiagnosticBundle(to: url)
                bundleResult = String(format: L(.setWroteBundle), written.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([written])
            } catch {
                bundleResult = L(.setBundleFailed) + error.localizedDescription
            }
        }
    }

}

/// Settings content sits directly on the rail, like the editor's controls.
/// Keeping the inset and spacing in `Theme` prevents this window from growing
/// a parallel preferences-page visual system.
private struct SettingsRows<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, Theme.Metric.rowInset)
            .padding(.vertical, Theme.Metric.Settings.rowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
