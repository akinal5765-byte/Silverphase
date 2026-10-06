//  PrintProfileSection.swift — the paper list, grouped Still / Cine /
//  Positive, and the two actions that belong to the print.
//
//  The list is `StockList`, the same view the film list is, because the
//  drawing draws them the same: one well, one-line rows, a **band** on the
//  chosen one and the accent `CINE` pill on a cinema stock.
//
//  The Positive group holds one row, "No Print Profile": scan the developed
//  film instead of printing it. It is where a slide film belongs — printing
//  Provia onto Endura is a thing the engine will happily do and a thing
//  nobody wants — and it is also the only way to look at what the film stage
//  actually produced, orange mask and all.
//
//  It is `scan_film`, not a paper. Selecting it therefore does not clear the
//  paper: turn it off again and the print comes back on whatever was chosen
//  before, which is what makes it usable as a comparison rather than a
//  destination.
//
//  ## The two capsules, and why `Process` left them (v3, handoff §8.1)
//
//  v3 draws **Developed** and **Original** where `Process` and `Original`
//  were, and the handoff is explicit about the trap in that: "Do not rename
//  the solve button to Developed and leave its solve action behind that
//  label." A button reading *Developed* that auto-exposes the frame and
//  re-solves the filter pack is the worst available outcome — the word names
//  a state and the click performs an edit, so the one control in the section
//  that changes the picture is the one that looks like it changes the view.
//
//  So the pair is now **one two-state view selector**: Developed leaves the
//  original view, Original enters it, both through `showingOriginal`, which
//  is the state Space has always toggled on the canvas. Neither renders
//  anything.
//
//  **Solve did not disappear** — it is `Process this frame` in this section's
//  "•••", where it already was, with its own words and its own enabling. The
//  handoff's §8.1 recommendation is what this implements, and the decision it
//  asked the implementation session to make is the one recorded here.

import SwiftUI

struct PrintProfileSection: View {
    /// Rows of the print well on screen before it scrolls. **Odd** — see
    /// `StockList.visibleRows`, and `testStockListShowsAnOddNumberOfRows`.
    static let wellRows = 12

    @Bindable var session: Session
    /// The sentinel `StockList` row id for "No Print Profile". It is not a
    /// paper, so it cannot be a `print_stock` value — see `FilmParams.scanFilm`
    /// for why that separation is load-bearing — and this is the id the list
    /// uses to spell it without either side inventing a stock name.
    private static let positiveID = "__scan_film__"
    private static let diID = "__digital_intermediate__"

    /// Whether the chosen film is a slide film, in which case no paper on the
    /// list may be chosen.
    ///
    /// The section's own header has said since it was written that "printing
    /// Provia onto Endura is a thing the engine will happily do and a thing
    /// nobody wants". It was a comment; this is the rule. A positive is
    /// already a viewable image — the paper stage has nothing to interpret —
    /// so every paper greys out and "No Print Profile" is the only row left.
    private var filmIsPositive: Bool { session.filmIsPositive }

    private static var positiveOnlyReason: String { L(.reasonPositiveFilmDisablesPaper) }

    private var rows: [StockList.Row] {
        var out: [StockList.Row] = []
        for group in session.catalog.paperGroups where !group.papers.isEmpty {
            // Id keeps the catalogue's English title; only the label is
            // translated. Paper names themselves are profile names and stay.
            out.append(StockList.Row(id: "__group_" + group.title,
                                     name: L(paperGroup: group.title), isHeader: true))
            out += group.papers.map {
                StockList.Row(id: $0.id, name: MaterialBrowserChoice(id: $0.id, stock: $0).title, isCine: $0.isCine,
                              help: filmIsPositive ? "" : helpFor($0.id),
                              enabled: !filmIsPositive,
                              disabledReason: filmIsPositive ? Self.positiveOnlyReason : "")
            }
        }
        // A third "Positive" header, and a different string from the film
        // list's Positive: this one heads the paper list when the film is a
        // slide. The spec lists Positive as a *film* category (胶片分类) and
        // gives this one no row, so it is left as it is rather than collapsed
        // onto `filmGroupPositive`.
        out.append(StockList.Row(id: "__group_Positive", name: "Positive", isHeader: true))
        out.append(StockList.Row(id: Self.positiveID, name: L(.printNone),
                                 help: "Scan the developed film instead of printing it — a slide film reads as a positive, a negative film as the negative it is."))
        out.append(StockList.Row(id: Self.diID, name: L(.printDigitalIntermediate),
                                 help: L(.printDigitalIntermediateHelp), enabled: !filmIsPositive,
                                 disabledReason: filmIsPositive ? Self.positiveOnlyReason : ""))
        return out
    }

    /// Which rail this section is on — `FilmSection.Part`'s arrangement, for
    /// the same reason: the paper list is a preset (left rail) and the print's
    /// parameters are parameters (right rail), and the two halves share the
    /// stock rows, the LUT help and the selection. UI-SPEC §1.4.
    enum Part { case list, params }
    var part: Part = .params

    var body: some View {
        switch part {
        case .list: listSection
        case .params: paramSection
        }
    }

    /// The papers, on the left rail. "No print profile" is a row in this list
    /// rather than a switch somewhere else: it *is* a choice of what to print
    /// on, and the list is where that choice is made.
    private var listSection: some View {
        PanelSection(L(.sectionPaper), key: "printList") {
            StockList(rows: rows,
                      selected: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive
                                ? (session.digitalIntermediateActive ? Self.diID : Self.positiveID) : session.params.printStock,
                      visibleRows: Self.wellRows) { id in
                if id == Self.diID {
                    session.selectDigitalIntermediate()
                } else if id == Self.positiveID {
                    session.selectScanFilm()
                } else {
                    // `rowEnabled` already withholds the click; this is the
                    // second door, because the row's own gesture is not the
                    // only way an id reaches here.
                    guard !filmIsPositive else { return }
                    session.selectPrintStock(id)
                }
            }
        }
    }

    /// The print's own parameters, on the right rail.
    private var paramSection: some View {
        PanelSection(L(.sectionPrint), key: "print",
                     blockTitle: T("Exposure & Filtration", "曝光与滤色"),
                     menu: { AnyView(menu) }) {
            VStack(alignment: .leading, spacing: 0) {
                RailRows {
                    ScrubSlider(label: L(.printExposure), sublabel: "stops · brighter +",
                                value: Binding(get: { session.params.printBrightnessStops },
                                               set: { var p = session.params; p.printBrightnessStops = $0; session.params = p }),
                                range: -3...3, snap: 0.25,
                                format: { String(format: "%+.2f", $0) },
                                disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive)
                    ScrubSlider(label: L(.printContrast),
                                value: Binding(get: { session.params.printContrast },
                                               set: { var p = session.params; p.printContrast = $0; session.params = p }),
                                range: 0.7...1.3, zero: 1, snap: 0.05,
                                format: { String(format: "%.2f×", $0) },
                                disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive)
                    .help("Reshapes the selected paper's density response, separate from film development contrast. 1× preserves the original paper profile.")
                    ScrubSlider(label: L(.printYellow), sublabel: "Kodak CC",
                                value: Binding(get: { session.params.yFilterShift },
                                               set: { var p = session.params; p.yFilterShift = $0; session.params = p }),
                                range: -50...50, snap: 1,
                                format: { String(format: "%+.1f", $0) },
                                disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive || session.paperIsMonochrome)
                        .help(T("Colour filtration is not available for the synthetic neutral B&W print; this is not a calibrated variable-contrast paper model.", "合成的中性黑白印相不使用彩色滤色控制，也不是经过标定的多反差相纸模型。"))
                    ScrubSlider(label: L(.printMagenta), sublabel: "Kodak CC",
                                value: Binding(get: { session.params.mFilterShift },
                                               set: { var p = session.params; p.mFilterShift = $0; session.params = p }),
                                range: -50...50, snap: 1,
                                format: { String(format: "%+.1f", $0) },
                                disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive || session.paperIsMonochrome)
                        .help(T("Colour filtration is not available for the synthetic neutral B&W print; use print contrast.", "合成的中性黑白印相不使用彩色滤色控制；请调整印相反差。"))
                    ScrubSlider(label: L(.printPreflash),
                                value: Binding(get: { session.params.preflashExposure },
                                               set: { var p = session.params; p.preflashExposure = $0; session.params = p }),
                                // The engine and sidecars still use raw 0...1.
                                // Only dragging is limited to the useful span.
                                range: 0...0.05, entryRange: 0...1, snap: 0.005,
                                format: { String(format: "%.3f", $0) },
                                disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive)
                }
                InspectorSubblock(title: T("Optical Diffusion", "光学柔化")) {
                    RailRows {
                        PillMenu(label: L(.enlargerDiffusion), options: DiffusionChoice.allCases,
                                 title: { $0.title },
                                 selection: Binding(
                                    get: { DiffusionChoice(rawValue: session.params.enlargerDiffusion) ?? .off },
                                    set: { var p = session.params; p.enlargerDiffusion = $0.rawValue; session.params = p }))
                        .disabled(session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive)
                        .help(L(.enlargerSoftnessHelp))
                        ScrubSlider(label: L(.enlargerSoftnessStrength),
                                    value: Binding(get: { session.params.enlargerDiffusionStrength },
                                                   set: { var p = session.params; p.enlargerDiffusionStrength = $0; session.params = p }),
                                    range: 0.125...2, zero: 0.5, snap: 0.125,
                                    format: { String(format: "%.3g", $0) },
                                    disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive ||
                                              session.params.enlargerDiffusion == "off")
                        ScrubSlider(label: L(.enlargerSoftnessRange),
                                    value: Binding(get: { session.params.enlargerDiffusionRange },
                                                   set: { var p = session.params; p.enlargerDiffusionRange = $0; session.params = p }),
                                    range: 0.5...2, zero: 1, snap: 0.1,
                                    format: { String(format: "%.1f×", $0) },
                                    disabled: session.params.scanFilm || filmIsPositive || session.digitalIntermediateActive ||
                                              session.params.enlargerDiffusion == "off")
                        .help(L(.enlargerSoftnessRangeHelp))
                    }
                }
            }
        }
    }

    /// Only says something when there is something to say: which film the
    /// paper's baked LUT was paired with, and only while the fast flip is on.
    private func helpFor(_ stock: String) -> String {
        guard session.fastStockPreview, let entry = session.printLUTStocks[stock] else { return "" }
        return "Fast flip available — baked against \(entry.pairedFilm)."
    }

    // **No action row.** It held "Solve", and Solve turned out to do
    // nothing: measured through the shipping dylib, `solve(target: "both")`
    // left every parameter and every pixel exactly where the open path had
    // already put them — the exposure solve runs on open and the neutral
    // filter pack comes from the database during `digest`. What the button
    // *did* was force a re-render, which read as "refresh the picture".
    //
    // The develop it was there to ask for is now asked for by the selection
    // itself (`Session.select`), because a frame always has a film and a
    // paper and so always has a print. `solveNow` stays as the programmatic
    // re-solve; nothing in the interface calls it.

    private var menu: some View {
        Group {
            Button(L(.helpUseFilmPaper)) {
                if let t = session.catalog.stock(session.params.filmStock)?.targetPrint {
                    var p = session.params; p.printStock = t; p.scanFilm = false; session.params = p
                }
            }
            // A positive declares none, so this would do nothing; saying so is
            // better than a live-looking item that silently does not fire.
            .disabled(filmIsPositive
                      || session.catalog.stock(session.params.filmStock)?.targetPrint == nil)
            // **No second entry for the solve.** It was here under its longer
            // name while the row's capsule said only "配光"; now the row says
            // 自动测光与配光 and this is the same action twice.
            Divider()
            // The caveat is in the label because it is the whole decision.
            // A toggle called "Fast preview" with the explanation somewhere
            // else is a toggle whose behaviour is a surprise.
            Toggle(L(.helpFastFlip),
                   isOn: Binding(get: { session.fastStockPreview },
                                 set: { session.fastStockPreview = $0 }))
                .disabled(session.printLUTStocks.isEmpty)
        }
    }
}
