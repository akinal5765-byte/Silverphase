//  RightPanel.swift — parameters: one selected stage in Modern, the whole
//  process chain in Traditional.
//
//  The counterpart of `LeftPanel`, and the division is Lightroom Classic's:
//  the left rail holds the two catalogues (choose a film, choose a paper), and
//  this one holds every number that decides what the photograph looks like.
//  UI-SPEC §1.4.
//
//  **Why the split.** Swapping a film stock and nudging a halation slider are
//  two different acts — one replaces a recipe, the other edits it — and a
//  single rail holding both is where "the buttons have no logic" came from.
//  The stock lists went left; the sliders came here.
//
//  The toolbar selects one physical stage at a time, in pipeline order:
//  capture, film, development, enlargement and scan/output. Geometry groups
//  crop and (when enabled) masks outside that chain. This changes navigation,
//  not the parameter bindings or the engine.
//
//  **The section keys are not the left rail's.** `PanelSection` persists
//  whether a section is open under a key, and the two rails have one section
//  each called "Film": `filmList` / `printList` on the left, `film` / `print`
//  here, so folding one does not fold the other.

import SwiftUI

enum InspectorStage: String, CaseIterable, Identifiable {
    case camera, film, development, print, output, geometry, filmEdge

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .camera: L(.sectionCamera)
        case .film: L(.sectionFilm)
        case .development: L(.sectionDevelopment)
        case .print: L(.sectionPrint)
        case .output: L(.sectionOutput)
        case .filmEdge: T("Film Edge", "片边")
        case .geometry: T("Geometry", "构图")
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.aperture"
        case .film: "film"
        case .development: "drop.fill"
        case .print: "photo.on.rectangle.angled"
        case .output: "scanner"
        case .filmEdge: "rectangle.dashed"
        case .geometry: "aspectratio"
        }
    }
}

struct RightPanel: View {
    @Bindable var session: Session
    /// Stage identity stays pinned; its operation blocks scroll below.
    var body: some View {
        VStack(spacing: 0) {
            // Keep the stage title visible while its content blocks scroll.
            StageHeader(title: session.inspectorStage.title) { EmptyView() }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    switch session.inspectorStage {
                    case .camera:
                        LatitudeSection(session: session)
                        if session.halfFramePair == nil { ScenePlacementSection(session: session) } else { HalfFramePairSection(session: session) }
                        CameraSection(session: session)
                    case .film: FilmSection(session: session, part: .params)
                    case .development: DevelopmentSection(session: session)
                    case .print: PrintProfileSection(session: session, part: .params)
                    case .output: ScanOutputSection(session: session)
                    case .filmEdge: FilmEdgeSection(session: session)
                    case .geometry:
                        if session.halfFramePair == nil { CropSection(session: session) } else { HalfFramePairSection(session: session) }
                        if FeatureFlags.masks {
                            Hairline()
                            MasksSection(session: session)
                        }
                    }
                }
                .id(session.inspectorStage.rawValue)
                .padding(.horizontal, Theme.Metric.modernContentInset)
                .padding(.vertical, Theme.Metric.modernPanelVerticalInset)
            }
        }
        .disabled(session.batchExporting)
        .frame(maxHeight: .infinity)
        .modifier(EditorChromeSurface())
    }
}
