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
    case camera, film, development, print, output, geometry

    var id: String { rawValue }

    @MainActor var title: String {
        switch self {
        case .camera: L(.sectionCamera)
        case .film: L(.sectionFilm)
        case .development: L(.sectionDevelopment)
        case .print: L(.sectionPrint)
        case .output: L(.sectionOutput)
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
        case .geometry: "aspectratio"
        }
    }
}

struct RightPanel: View {
    @Bindable var session: Session
    var traditional = false

    var body: some View {
        VStack(spacing: 0) {
            if traditional {
                header
                Hairline()
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if traditional {
                        CameraSection(session: session)
                        Hairline()
                        FilmSection(session: session, part: .params)
                        Hairline()
                        DevelopmentSection(session: session)
                        Hairline()
                        PrintProfileSection(session: session, part: .params)
                        Hairline()
                        ScanOutputSection(session: session)
                        Hairline()
                        CropSection(session: session)
                        if FeatureFlags.masks { Hairline(); MasksSection(session: session) }
                    } else {
                        switch session.inspectorStage {
                        case .camera: CameraSection(session: session)
                        case .film: FilmSection(session: session, part: .params)
                        case .development: DevelopmentSection(session: session)
                        case .print: PrintProfileSection(session: session, part: .params)
                        case .output: ScanOutputSection(session: session)
                        case .geometry:
                            CropSection(session: session)
                            if FeatureFlags.masks {
                                Hairline()
                                MasksSection(session: session)
                            }
                        }
                    }
                }
                .id(traditional ? "traditional" : session.inspectorStage.rawValue)
                .padding(.horizontal, traditional ? 0 : Theme.Metric.modernContentInset)
                .padding(.vertical, traditional ? 0 : Theme.Metric.modernContentInset)
            }
            .environment(\.modernPanelChrome, !traditional)
        }
        .frame(maxHeight: .infinity)
        .modifier(EditorChromeSurface(modern: !traditional))
        .onAppear {
            guard !traditional else { return }
            let key = session.inspectorStage == .geometry ? "crop" : session.inspectorStage.rawValue
            UserDefaults.standard.set(true, forKey: Session.uiKey + "section." + key)
        }
    }

    private var header: some View {
        ZStack {
            Text(L(.railEdit))
                .font(Theme.Font.railTitle)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
            HStack {
                SidebarToggle(edge: .trailing, collapsed: $session.rightCollapsed)
                    .padding(.leading, Theme.Metric.panelHeaderTrailing)
                Spacer()
            }
        }
        .frame(height: Theme.Metric.panelHeaderHeight)
        .background(WindowDragHandle())
    }
}
