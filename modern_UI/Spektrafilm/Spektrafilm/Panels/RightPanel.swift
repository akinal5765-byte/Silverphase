//  RightPanel.swift — the parameters rail: everything you *set*.
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
//  Section order is the pipeline's, top to bottom: what the camera saw, what
//  the film did with it, what development did to the negative, what the paper
//  did with that, and finally how the frame is cropped. The two sections that
//  share a name with one on the left rail ("Film", "Print") are the *numbers*
//  for the catalogue entry chosen over there.
//
//  **The section keys are not the left rail's.** `PanelSection` persists
//  whether a section is open under a key, and the two rails have one section
//  each called "Film": `filmList` / `printList` on the left, `film` / `print`
//  here, so folding one does not fold the other.

import SwiftUI

struct RightPanel: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    let sections: [(String, AnyView)] =
                        [("camera", AnyView(CameraSection(session: session))),
                         ("film", AnyView(FilmSection(session: session, part: .params))),
                         ("development", AnyView(DevelopmentSection(session: session))),
                         ("print", AnyView(PrintProfileSection(session: session, part: .params))),
                         ("output", AnyView(ScanOutputSection(session: session))),
                         ("crop", AnyView(CropSection(session: session)))]
                        + (FeatureFlags.masks
                           ? [("masks", AnyView(MasksSection(session: session)))] : [])
                    ForEach(Array(sections.enumerated()), id: \.element.0) { index, entry in
                        if index > 0 { Hairline() }
                        entry.1
                    }
                }
            }
        }
        .railCard()
    }

    private var header: some View {
        HStack(spacing: 0) {
            // **No traffic-light reservation.** The window buttons sit on the
            // *left* rail's header, on the same centreline; this row starts at
            // the rail's own inset. The toggle leads rather than trails so it
            // is the first thing the eye meets coming from the canvas — the
            // door is at the edge the rail shares with the picture.
            SidebarToggle(edge: .trailing, collapsed: $session.rightCollapsed)
                .padding(.leading, Theme.Metric.panelHeaderTrailing)
            Text(L(.railEdit))
                .font(Theme.Font.railTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .frame(height: Theme.Metric.panelHeaderHeight)
        // The header row is the window's drag surface, as it is on the left:
        // with the titlebar hidden, a rail's header is where a title bar would
        // be, and both rails are part of the window's frame.
        .background(WindowDragHandle())
    }
}
