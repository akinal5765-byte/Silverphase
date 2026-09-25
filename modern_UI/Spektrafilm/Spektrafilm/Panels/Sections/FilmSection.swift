//  FilmSection.swift — what the photograph is recorded on: the stock, the
//  physical frame, and the three spatial effects that scale with it.
//
//  Three sections became one, because the drawing makes one: the film list,
//  the Film Format / Side / Side Length rows that used to be Camera's single
//  `Format` pill, and the Grain / Halation / Glare toggles that were their
//  own `Features` card. They belong together for a reason the PRD states —
//  "this is very important, as it goes straight into the grain, halation and
//  glare calculation pipeline" — and a toggle three cards away from the
//  number that scales it is a toggle nobody connects to it.
//
//  ## The frame, and why it is three controls
//
//  The engine takes one number, `film_format_mm`, and it means the frame's
//  **long edge**: pixel pitch is `film_format_mm * 1000 / max(w, h)`, and
//  grain, halation and DIR diffusion are micrometre quantities divided by it.
//  One number cannot tell 645 from 6×6. So the user says a **type**, a
//  **side** and a **length**, and `Session.filmFormatMM(side:sideLengthMM:aspect:)`
//  derives the long edge from that and the photograph's own aspect — which is
//  what makes one `120` entry cover 645, 6×6, 6×7 and 6×9 correctly.
//
//  Side Length is greyed unless the type is Custom, and shows the type's own
//  measurement otherwise: the PRD's "cannot be changed unless custom is
//  selected. Shows the actual Side length if non-custom film type is
//  selected."
//
//  Whether a **crop** re-scales any of this is a Settings toggle and is off by
//  default — cropping a negative does not make its grain coarser. See
//  `Session.physicalAspect`.

import SwiftUI

/// The halation row's choices: the four presets and the off switch, in one
/// menu.
///
/// `halation_active` and `antihalation_mode` are two wire fields but one
/// decision from the reader's side, and a switch plus a preset row that share a
/// name is worse than a slightly longer menu. Folding them also gives the
/// effect a real "off": the presets have no "no halation" state — the strongest
/// anti-halation layer still leaves some — but switching the node off does.
///
/// **The two axes run opposite ways.** The stock data and the wire name the
/// *anti*-halation layer (strong / weak / none of the coating); the reader sees
/// the halation it leaves behind, so a `strong` layer is **low** halation. This
/// enum is the one place that inversion is written down; everything else keeps
/// the wire's word.
enum HalationChoice: Hashable, CaseIterable {
    case profile, high, medium, low, off

    /// The wire value this choice selects, or `nil` for the off switch, which
    /// is `halation_active` rather than a preset.
    var mode: String? {
        switch self {
        case .profile: "profile"
        case .high: "none"      // no anti-halation layer -> most halation
        case .medium: "weak"
        case .low: "strong"     // strongest layer -> least halation
        case .off: nil
        }
    }

    /// The two wire fields, back as one choice. An unknown mode reads as the
    /// stock default, which is what the engine would fall back to anyway.
    static func of(active: Bool, mode: String) -> HalationChoice {
        guard active else { return .off }
        switch mode {
        case "none": return .high
        case "weak": return .medium
        case "strong": return .low
        default: return .profile
        }
    }

    /// `@MainActor` because `L` reads the `@Observable` language setting — that
    /// read is what makes a language change repaint every label.
    @MainActor var title: String {
        switch self {
        case .profile: L(.filmAntihalationProfile)
        case .high: L(.filmAntihalationHigh)
        case .medium: L(.filmAntihalationMedium)
        case .low: L(.filmAntihalationLow)
        case .off: L(.filmHalationOff)
        }
    }
}

struct FilmSection: View {
    /// Rows of the film list on screen before it scrolls.
    ///
    /// **20, up from the drawing's 9** (2026-09-23). With the parameters gone
    /// to the right rail the catalogue is the whole left rail, and nine rows
    /// left most of it empty while making the reader scroll for a film that
    /// would have fitted. 20 covers both groups — the still films and the
    /// cine ones — on a 1512 × 982 window and still scrolls on a short one.
    /// 22 is the whole catalogue: 20 films and the two group
    /// headers. It is the honest knob for "show more films": the list keeps its own
    /// fixed height rather than growing into the rail, because a `ScrollView`
    /// told to fill pushes the paper section to the bottom with the gap
    /// *between* the two lists (measured, and worse than the air it removed).
    static let wellRows = 22

    @Bindable var session: Session
    /// Display only; the wire is always millimetres. An app preference rather
    /// than part of a frame's settings, because "show me inches" is a fact
    /// about the reader, not about the photograph.
    @AppStorage(Session.uiKey + "sideUnit") private var unitRaw = SideUnit.mm.rawValue

    private var unit: Binding<SideUnit> {
        Binding(get: { SideUnit(rawValue: unitRaw) ?? .mm }, set: { unitRaw = $0.rawValue })
    }
    private var isCustom: Bool { session.params.filmFrame == FilmFrame.custom.id }

    /// Which rail this section is on.
    ///
    /// The film **list** is a preset and belongs in the left rail; the film's
    /// **parameters** belong in the right one (UI-SPEC §1.4). One type with two
    /// parts rather than two files, because the halves share the catalogue, the
    /// stock rows and the selection — a split would have had to duplicate all
    /// three, and duplicated lists drift apart.
    enum Part { case list, params }
    var part: Part = .params

    var body: some View {
        switch part {
        case .list: listSection
        case .params: paramSection
        }
    }

    /// The catalogue, on the left rail.
    ///
    /// Its one action is the stock reset — that is a *selection*, so it belongs
    /// with the thing that selects rather than with the sliders the selection
    /// feeds. The name it resets to stays in English on purpose: a film name is
    /// a profile name and the spec keeps those as they are. It is not
    /// `helpResetFilmExposure`: this resets the stock, that one the exposure.
    private var listSection: some View {
        PanelSection(L(.sectionFilm), key: "filmList",
                     action: SectionAction(help: L(.helpResetFilmStock)) {
                         var p = session.params; p.filmStock = "kodak_portra_400"; session.params = p
                         session.applyFilmStageRule()
                     }) {
            StockList(rows: stockRows,
                      selected: session.params.filmStock,
                      visibleRows: Self.wellRows) { id in
                select(id)
            }
        }
    }

    /// The film's own parameters, on the right rail.
    private var paramSection: some View {
        PanelSection(L(.sectionFilm), key: "film",
                     blockTitle: T("Frame", "画幅"),
                     menu: { AnyView(formatMenu) }) {
            VStack(alignment: .leading, spacing: 0) {
                RailRows {
                    // `title: { $0.id }` — a film format is `135`, `120`, `APS`
                    // and so on, which the spec keeps as they are. Only the
                    // row's label is translated.
                    // **No `fill: false`.** It asked for a 107 pt pill at the
                    // trailing edge, and Modern ignores it (`FormatPicker`'s
                    // `fillsControlColumn`): a 344 pt panel's controls share
                    // one left edge and one right edge, so a row that stopped
                    // two thirds of the way across read as an unfinished one.
                    PillMenu(label: L(.filmFormat), options: FilmFrame.all, title: { $0.id },
                             selection: Binding(get: { session.filmFrame },
                                                set: { session.setFilmFrame($0) }),
                             trailingBadge: { $0.isCine })
                    PillMenu(label: L(.filmFormatSide), options: FilmSide.allCases, title: { L($0.key) },
                             selection: Binding(get: { session.filmSide },
                                                set: { session.setFilmSide($0) }))
                    UnitField(label: L(.filmFormatSideLength),
                              value: Binding(get: { session.params.sideLengthMM },
                                             set: { session.setSideLengthMM($0) }),
                              unit: unit,
                              enabled: isCustom,
                              reason: L(.reasonNonCustomSideLength))
                }
                InspectorSubblock(title: T("Grain & Halation", "颗粒与光晕"),
                                  menu: { AnyView(effectsMenu) }) {
                    RailRows {
                        ToggleRow(label: L(.filmGrain), isOn: param(\.grainActive))
                        ScrubSlider(label: L(.filmGrainSize),
                                    value: Binding(get: { session.params.grainSizeScale },
                                                   set: { var p = session.params; p.grainSizeScale = $0; session.params = p }),
                                    range: 0.5...2, zero: 1, snap: 0.1,
                                    format: { String(format: "%.1f×", $0) },
                                    disabled: !session.params.grainActive)
                        .help("Changes the modeled particle diameter relative to 1×. Film format still sets its physical scale; this does not alter the stock profile.")
                        PillMenu(label: L(.filmHalation),
                                 options: HalationChoice.allCases,
                                 title: { $0.title },
                                 selection: Binding(
                                    get: { HalationChoice.of(active: session.params.halationActive,
                                                             mode: session.params.antihalationMode) },
                                    set: { choice in
                                        var p = session.params
                                        // Off writes only the switch; the chosen preset is left
                                        // alone, so turning it back on returns to where it was.
                                        if let mode = choice.mode {
                                            p.halationActive = true
                                            p.antihalationMode = mode
                                        } else {
                                            p.halationActive = false
                                        }
                                        session.params = p
                                    }))
                        .help("How much light the film base reflects back into the emulsion — the source of halation. Default follows the selected film's own data; High, Medium and Low override the simulation only and never rewrite it. Off switches the stage out of the render.")
                        ScrubSlider(label: L(.filmHalationAmount),
                                    value: Binding(get: { session.params.halationAmount },
                                                   set: { var p = session.params; p.halationAmount = $0; session.params = p }),
                                    range: 1...4, zero: 1, snap: 0.1,
                                    format: { String(format: "%.1f×", $0) },
                                    disabled: !session.params.halationActive)
                        .help("A multiplier on the chosen halation setting: 1× leaves it as chosen, up to 4× amplifies the reflection. Choose Off above to remove the effect.")
                    }
                }
            }
        }
    }

    /// Positive and Negative, as two visible groups — v3's own division, and
    /// taken from the catalogue's `type` rather than from the artwork's order
    /// (handoff §8.6). A group with nothing in it is not drawn, so a
    /// catalogue with no slide films shows one list rather than an empty
    /// caption.
    private var stockRows: [StockList.Row] {
        session.catalog.filmGroups.filter { !$0.films.isEmpty }.flatMap { group in
            // The id keeps the catalogue's English title — it is the row's
            // identity — while the *name* is what the spec translates. A film
            // entry's own name is a profile name and stays as it is.
            [StockList.Row(id: "__group_" + group.title, name: L(filmGroup: group.title), isHeader: true)]
            + group.films.map {
                StockList.Row(id: $0.id, name: $0.name, isCine: $0.isCine, help: "")
            }
        }
    }

    /// Choosing a film also follows its **declared** paper, unless the user
    /// has already made a pairing of their own.
    private func select(_ id: String) {
        session.selectFilmStock(id)
    }

    private func param(_ kp: WritableKeyPath<FilmParams, Bool>) -> Binding<Bool> {
        Binding(get: { session.params[keyPath: kp] },
                set: { var p = session.params; p[keyPath: kp] = $0; session.params = p })
    }

    private var formatMenu: some View {
        Button("Reset the film stock to Portra 400") {
            var p = session.params; p.filmStock = "kodak_portra_400"; session.params = p
            session.applyFilmStageRule()
        }
    }

    private var effectsMenu: some View {
        Group {
            Button(L(.helpAllEffectsOn)) {
                var p = session.params
                p.grainActive = true; p.halationActive = true
                session.params = p
            }
            Button(L(.helpAllEffectsOff)) {
                var p = session.params
                p.grainActive = false; p.halationActive = false
                session.params = p
            }
        }
    }
}

/// The film and print lists: rows of one line each, sitting **directly on
/// the rail**, with the chosen row carrying a white capsule.
///
/// **v3 (2026-09-18) took the plate away.** There is no lighter well behind
/// these rows any more and no outer clipping radius — `Theme.stockList` is
/// the rail's own colour — and the rounding moved to the *mark*: the
/// selection is a 15.27 pt capsule inset 16.79 from the leading edge and
/// 26.48 from the trailing one, in `#ffffff`, with the row's text inverted to
/// near-black. The 2026-09-17 version was a full-width `#c9caca` band on a
/// well; the reason the drawing changed it is legible in the two side by
/// side — a band the width of its container reads as "this cell is filled",
/// a capsule inside it reads as "this row is chosen", and only the second one
/// survives being the only mark in a list of 28.
///
/// One view for both lists, because the two drawings of them are the same
/// drawing — and because the previous two implementations had drifted into
/// different row heights, different insets and two spellings of the mark.
struct StockList: View {
    struct Row: Identifiable, Hashable {
        let id: String
        let name: String
        var isCine = false
        var help = ""
        /// A group caption — "Positive", "Negative", "Still", "Cine" —
        /// rather than a selectable row.
        var isHeader = false
        /// Whether the row can be chosen. A disabled row greys and stops
        /// taking clicks, which is the PRD's one rule for anything
        /// non-selectable (`View.rowEnabled(_:)`), rather than a row that
        /// looks live and quietly does nothing.
        var enabled = true
        /// Why it cannot be chosen — shown as the row's tooltip, so the greying
        /// is explained where it is seen.
        var disabledReason = ""
    }

    let rows: [Row]
    let selected: String?
    /// How many rows of the list are on screen before it scrolls.
    ///
    /// **A whole number, and that is now the whole rule.** It used to have to
    /// be *odd*: the list centred its selected row, which put that row's
    /// centre on the viewport's centre, so the rows landed on the viewport's
    /// edges only with a whole number of them either side of the middle one.
    /// At an even count every row sat half a row out of register and the
    /// well's 11.5 pt corner cut the first and last rows through the glyphs.
    ///
    /// v3 removes both halves of that. There is no corner to cut with, and
    /// the lists are grouped now — a viewport holding a header and four rows
    /// cannot be described by the parity of a row count at all. What matters
    /// instead is that the viewport is a whole multiple of the row pitch, so
    /// that whatever is scrolled to rests on a row boundary; handoff §3 asks
    /// for exactly that ("a grouped implementation must use complete row
    /// alignment and update that assumption rather than blindly reuse the
    /// odd-count rule"). `StockListTests` pins it.
    var visibleRows: Int
    let select: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            // `showsIndicators: true`: v3 draws a 3.04 pt thumb beside each
            // group, and unlike the old well — whose plate told you where the
            // list ended — a list sitting straight on the rail has no other
            // edge to say that it scrolls.
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.isHeader {
                            Text(row.name)
                                .font(Theme.Font.stockGroup)
                                .foregroundStyle(Theme.Ink.tertiary)
                                .padding(.leading, Theme.Metric.stockTextLeadingInset)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: Theme.Metric.listRowHeight)
                        } else {
                            StockRow(row: row, selected: row.id == selected) { select(row.id) }
                                .id(row.id)
                        }
                    }
                }
            }
            .scrollIndicators(.visible)
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
            .onChange(of: selected) { _, new in
                guard let new else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) }
            }
        }
        // A whole number of rows, and **no vertical padding**: the old 8 pt
        // existed to hold the rows off a corner radius that no longer exists,
        // and with the plate gone it is just a gap that makes the list's top
        // row float away from the section header above it.
        .frame(height: Theme.Metric.listRowHeight * CGFloat(visibleRows))
        .background(Theme.stockList)
    }
}

struct StockRow: View {
    let row: StockList.Row
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        // A plain view with a tap gesture, not a `Button`. macOS gives even a
        // `.plain` button a shape of its own on this release, and it was
        // drawing a rounded plate inside the mark — a second selection mark,
        // 8 pt of radius, inset from the one the drawing asks for.
        HStack(spacing: 4) {
            Text(row.name)
                .font(Theme.Font.stockItem)
                // An unselected row is a thing being offered, not a thing
                // being said; the selected one is the answer and takes the
                // near-black ink against the white capsule.
                .foregroundStyle(selected ? Theme.onSelection : Theme.Ink.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if row.isCine { CinePill().padding(.trailing, Theme.Metric.cinePillTrailing) }
        }
        // The text sits inside the capsule, not flush with it: v3 puts the
        // capsule's leading edge at 16.79 and the glyphs at 21.33.
        .padding(.leading, Theme.Metric.stockTextLeadingInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The **row** is the pitch and the **capsule** is the mark, and they
        // are deliberately not the same height: 18 against 15.27. A mark as
        // tall as its own row is a filled cell.
        //
        // The capsule is a surface now (UI-SPEC §2.4): a white fill with a
        // 1 px dark edge and one soft shadow, so it sits *on* the rail rather
        // than being a hole punched in it. Hover is a 5 % wash and nothing
        // else — no edge, no movement; a row that shifts under the pointer
        // makes a list of 28 feel unstable.
        .frame(height: Theme.Metric.listRowHeight)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let w = max(0, geo.size.width
                               - Theme.Metric.stockLeadingInset
                               - Theme.Metric.stockTrailingInset)
                let h = Theme.Metric.stockSelectionHeight
                let y = (geo.size.height - h) / 2
                let shape = Capsule()
                if selected {
                    shape
                        .fill(Theme.selection)
                        .overlay { shape.strokeBorder(Color.black.opacity(0.18), lineWidth: 1) }
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: w, height: h)
                        .offset(x: Theme.Metric.stockLeadingInset, y: y)
                } else if hovered && row.enabled {
                    shape
                        .fill(Theme.rowHoverWash)
                        .frame(width: w, height: h)
                        .offset(x: Theme.Metric.stockLeadingInset, y: y)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
        .rowEnabled(row.enabled, because: row.disabledReason)
        .help(row.help)
    }
}
