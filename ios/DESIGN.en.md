# Silverphase iOS interface specification

[简体中文](DESIGN.md) · [English](DESIGN.en.md)

> This English companion covers current design. For the full dated notes and numeric details not repeated here, consult the Chinese source.

The current specification was first consolidated on 2026-11-04. Layout constants live in `Silverphase/Sources/EditorDesign.swift`. Desktop defines process semantics and shared controls; mobile places navigation and panels around the device's actual workspace. The [2026-11-02 iPhone captures](../screenshots/ios/2026-11-02/README.md) predate the native process bar and current material entry points. Follow this specification and source for current behavior; see the [historical snapshot](history/DESIGN-through-2026-11-02.md) for superseded layouts.

Process names come from `MobileStage.title(in:)`: **Prep → Film → Development → Color Enlargement → Scan**. Compact navigation shortens Color Enlargement to **Print**. Crop and Film Edge are independent tools in the same seven-item picker, not extra process stages. Supported RAW files can match camera preview brightness in Prep.

## Standard iPhone editor

Standard iPhone runs in portrait through launch, library, editor and presented pages. Duo and iPad keep their own orientation policies.

The top bar shows the return button on the left, Export and Menu on the right. Undo, redo, resets outside a process section and zoom are in the menu. No process or film/paper banner appears at the top; the active process title is in the parameter panel. Settings and About follow the same presentation rules: full screen with a top-left close action on folded Duo, native large sheets with Done elsewhere. The common iOS page background is sRGB `#181818`.

Status is independently anchored below the toolbar in the safe content area, inset 16 pt from the leading edge and 12 pt from the top. It shows the filename, original pixel dimensions and the current preview/original/processing/development state. Canvas zoom, comparison, section changes and rotation cannot move status into the image or behind Back.

The canvas and floating tools are independent. The image may extend behind the transparent toolbar and top/bottom safe areas, but controls stay within their safe workspace. Fit preserves aspect ratio; margins are not an overlay, and zooming must not reveal fixed top/bottom masks. The floating panel has a 14 pt grabber; its grabber and the left 44 pt title area resize it, while the right-side actions remain independent. Maximum height is 520 pt and 72% of the safe workspace, excluding bottom navigation and the batch filmstrip. The panel scrolls internally. Its height, collapse state and process do not change the fit rectangle.

The fixed bottom process bar is 56 pt tall with at least 44 pt of touch width per item. A native toolbar segmented control owns the glass selection, tapping, dragging and tracking; there is no outer horizontal scroller. Its selected accent is orange, and reduced-motion/transparency preferences remain native. Do not reproduce it with a moving custom capsule.

Film and Print tabs open their parameter panel directly. The first row is Current Film or Current Paper: thumbnail, full name, category and **Change ›**, with the whole row tappable. The title bar does not repeat the material name or offer a second switcher. The list replaces parameters within the same height-adjustable panel, keeping the canvas in place. Categories, search, favourites and recents remain; Film shows only film, and Paper shows papers plus direct scan/digital intermediate. Selecting a stock updates the preview without closing the list; Done returns to parameters. Automatically direct-scanned reversal stocks explain why paper cannot be changed.

Duo keeps material switching inside the panel; Duo and iPad keep horizontal material cards. Single-photo editing hides the filmstrip and batch editing shows only the batch. Export uses the shared panel without recreating the canvas. Panels use `ChromeSurface` directly, without extra blur or a separate glass layer. The canvas is not inside the glass-compositing container.

## Duo and iPad

Duo uses system `UIHingeInteraction` and window orientation. Folded and landscape layouts use the shared native rail; unfolded portrait uses floating tools. Export and Menu sit in native navigation chrome. The process group uses native `bottomBar` with `verticalPreferred` and aligns to the rail's safe bottom edge. Under pressure, collapse actions before losing process tools. The seven vertical segments are 44 pt each, 308 pt total, with upright icons and no TabView overflow. Do not reserve a separate canvas column for the rail. Until a real hinge is detected, use ordinary iPhone's horizontal bottom process bar, not a model-name or width heuristic.

Duo's canvas extends behind the top, bottom and right rails. Floating controls and fit are independent; only the measured native rail rectangle is used to clear it horizontally. The workspace ends at the window's real safe edge, not at a shifted process group or a hard-coded device offset. In unfolded landscape, align the bottom of the floating tools and photo/material strip with the measured bottom of the process rail without moving the tools' top.

iPad uses the same icon-only segmented process control in the native top row with Back, Export and Menu, never a second row. It is 336 pt overall, 48 pt per segment, with accessible process labels. The top centre shows the active process/title or Export Photos, and omits it in an empty session. Keep the right inspector and bottom browser. The canvas extends behind transparent chrome and the real safe area constrains controls. Ordinary iPhone screenshots cannot establish iPad or Duo device acceptance.

## Library and batch operations

The app launches into the local grid. Imported originals, edits, crop, ratings and flags survive relaunch; disposable previews, undo history and GPU state do not. Storage and memory are separate Settings sections. Confirm removal and delete only app-owned records/files; the Photos library and the import source remain untouched.

In the normal grid, Import, Select, rating/flag filters and More have distinct controls; active filters use orange. The grid does not offer undo or redo and thumbnails carry no original/edit-preview label. Multi-select hides Import, filters and application menu. Keep selection controls distinct from batch Edit, Export and More. Select, Done, Select All and Clear have accessible names. Horizontal range selection can continue across rows, deselects if started on a selected item, and restores items outside a retracted range. Vertical scrolling continues; edge auto-scroll stops on termination/cancellation.

Long-press menus and multi-select expose copy/paste. Apply to explicit target IDs, not the currently previewed photo. Crop copy uses only the numeric ratio (e.g. 3:4 becomes 4:3 on a landscape target); it preserves the target's centre, straighten, flip and rotation.

A photo tap animates just the selected thumbnail into the detail viewer. Back or pull-down shrinks only the picture into its visible thumbnail; **Edit** enters the editor. The camera thumbnail opens the same viewer, preferring the latest local capture. Live preview pauses until returning to camera; the library filter is not changed.

Use the system scroll container for pinch, point-centred double-tap zoom and panning. Show a current recipe cache first; on a cold cache, show a small film preview before the screen-sized render. When zoom settles, progressively add viewport detail. The viewer and editor have separate render sessions. Decode standard 8-bit JPEG at the working size with its colour profile; RAW and gain-map sources keep their own paths. In fit view a drag locks to one direction: horizontal paging moves both photos under the finger; pull-down shrinks only the photo to expose the grid. Transitions stay below the controls.

Press and hold to compare: first show a lightweight original, then the fit original without simulation. Release returns to the film result without affecting zoom or position. Show a small loading indicator in the shared glass status while original fit/detail is pending, and dismiss it on release. Holding does not cancel in-flight film detail. Both views add detail as zoom demands. More offers Fit and Actual Pixels (1:1); 1:1 requests native output dimensions without waiting for pinch thresholds. Status reflects the rendered tier; never label a reduced render as original resolution.

Tap to hide/show chrome without moving or rescaling the photo or overriding manual zoom. The filmstrip borrows Layerlight's coasting, centring and scrubbing behaviour: during drag it shows cached or lightweight images, and after settling it renders the recipe. Integer-pixel dimensions and edge sampling avoid translucent edge lines. As in [SSPhotoViewer](https://github.com/rimalamir/SSPhotoViewer), all items stay narrow in motion and only the selected one expands when snapped. Keep the orange selection marker and subtle end fade; no full-strip glass slab. The strip may overlay the image. In Duo rail mode use normal bottom spacing. Fit is aspect-preserving and centred in the whole window. On Duo the viewer and editor may enlarge by up to 6% beyond fit, capped at fill. Respect Reduce Motion and Reduce Transparency.

Capture date and time are leading, beside but not inside the Back control, using the system region format and complete short date/time. Give way by shrinking the film control, not truncating the date. Original/resolution badges remain over the canvas below the bar. Rating, flag and film are spaced at the trailing edge. A wide film button shows icon/name with end truncation; compact shows only its icon. Changing film must not reflow the bar.

The film chooser anchors to its system glass button as a popover, even in compact width, and narrows on the outer Duo display to clear the rail. Search and filter share horizontal insets with the 2–4-column cover grid, reused by library and camera. Keep filter/close targets at 44 pt without extra plates; an active filter uses the accent. Current film comes first; Fotufilm reuses a cover badge with ISO/EI still visible. Use native toolbars and no full-width top blur. More is top trailing on ordinary iPhone; Export, Info, Edit and Delete are in the bottom bar. iPad keeps the same regions in portrait and landscape: More alone at the far top-right, Export bottom-left, the other three actions bottom-right. Folded Duo and unfolded landscape use the shared rail; unfolded portrait uses top Back/date and trailing rating/flag/film, with bottom Export on the left, More/Info/Edit centred and Delete at right. Delete uses the library confirmation. The Format filter derives choices from the extensions already present.

## Spacing, glass and cards

Use 4 pt base spacing, 12 pt workspace spacing and 16 pt parameter side insets. Optical symbol bounds fit the common 20 × 20 pt box; targets are at least 44 × 44 pt. Preserve the special optical adjustment for Export. Establish a panel's frame before applying glass and clip body and scroller to its shape. Its heading is 44 pt tall; constrained content scrolls. Use solid colour with Reduce Transparency. Select cards with an orange inner edge and modest background highlight, not inverted white/black. Material covers are 16:9 with 6 pt inset, and concentric 12/6 pt outer/inner radii. Favourite and selected have separate accessibility semantics.

Categories come from catalogue fields. Ordinary iPhone uses a category menu and vertical material list; other layouts scroll categories and cards horizontally in separate rows. Search replaces the category entry. All, Search, Favourites and Recents observe catalogue visibility. Public builds omit private experimental materials.

## Parameter controls and typography

`ToolTickRuler` provides the moving scale, fixed pointer, inertia, haptics and adjustable accessibility action. The heading/value and scale each supply 44 pt of interaction height, with 8 pt after each item. Tap the value to type; double-tap restores the actual photo/material default in undo history. Anchor default and bounds clearly. Major ticks centre on zero but fine changes do not snap to them. Coalesce changes, keep digits and inertia in sync and end the edit on release, cancellation or before another menu/switch/material/input commit. Direction recognition sends vertically directed drags to panel scrolling. Menus and pickers stay native.

Custom editing controls use `EditorDesign`: panel title 15 pt semibold (one line, truncate material before process title), group title 13 pt semibold with 24/10 pt spacing, parameter label 13 pt regular, menu value 13 pt medium, editable number 14 pt medium with tabular digits. Use 12 pt for combination/size/filename summaries, 11 pt for status and secondary explanatory text, and 10 pt for scale labels, card subheads and small badges. System Settings, menus and sheets retain Dynamic Type and semantic fonts. Export sections run Preset, File and Colour, Output Size, Naming and Metadata, Destination.

## Crop tools

Crop shares desktop `Geometry.swift`: oriented crop/straighten, then quarter turns and flips. Core Image preview and export each use the same inverse `outputToSourceTransform`; explicitly convert coordinate origin when bridging from top-left normalised source coordinates. Use rule-of-thirds lines, eight 44 pt touch handles, inside drag to move and outside drag to draw a new crop. Drag drafts stay local; release commits one undo entry and then updates the render. Straightening turns the photo under a level frame. Image and touch points must share the affine mapping and named coordinate space.

Ratios: free, original, 1:1, 3:2, 4:3, 16:9, 5:4 and 7:5. Orientation is independent; straighten spans ±45° with the shared ruler, animated readout, direct entry and zero on double-tap. Reset, turns and flips are undoable. Show resulting native pixels and MP. For images with film edge/date back, crop the unframed original and reapply the authentic frame during film-gate preparation; the crop-only original is released when leaving the tool or exporting.

## Preview, comparison and first print

Choose fit base, coalesced interactive refresh and viewport detail automatically. No fixed preview-resolution picker. Double-tap or use the menu for fit/1:1. The document owns zoom/pan; hidden canvases must not submit viewport work for the same document.

Hold still about 250 ms to view the original; moving more than 8 pt does not trigger. Release, cancel or background returns to the film result. Freeze its viewport and do not interpret the temporary comparison viewport as a new fit. Reuse prepared original detail and reconcile unfinished work on release.

The first paper render uses real film scan and the shared print animation, never an inverted final render as a stand-in for a negative. Tap to print. Settings can show it once per launch (default) or once per photo in the session; adjustments never replay it. Reduce Motion, direct scan and setup failures show the finished result instead. Expired callbacks cannot overwrite a new photo.

## Import, export and progress

Validate contents and dimensions from the system photo picker for RAW, JPEG, HEIC/HEIF, PNG and TIFF. Prefer a provider's RAW over its embedded JPEG. Use the supplied filename, omit missing EXIF fields and do not invent camera metadata.

Export the current photo or explicit batch with resolution independent of preview. Never quietly lower a requested full-resolution export: explain memory gating. JPEG, PNG, 16-bit TIFF and Cineon DI boundaries are in the [control audit](CONTROL-AUDIT.en.md). Preview and cache housekeeping cannot cancel export. Naming checkboxes combine original filename, film, paper, date and sequence with underscores in fixed order; retain at least one component. Preview the first real target; use a four-digit sequence. Support legacy rules until the user changes the checkboxes, without exposing the internal template syntax.

`MobileOperationProgress` is distinct from the busy state of ordinary parameter renders. Import starts before provider access, spans coordination/copy and the first usable output-colour preview when applicable; empty results, complete skips and errors unlock. If a background copy finishes before preview, resume on foreground. A shared central glass card shows system progress, stage, file index/count and filename, not a fabricated percentage. Render/colour/write callbacks advance export; Photos saving waits for the system. Task and batch IDs prevent stale callbacks and stage regression.

Long tasks block workspace gestures, native rails, menus and comparison, and VoiceOver visits progress only. Model guards also reject switching, editing, undo/redo, rating, removal and duplicate import/export, not merely via a UI overlay. Close the keyboard and old popovers at task start. Ordinary preview adjustment remains interactive.

## Camera orientation

Camera policy applies only inside the app camera and lock-screen camera, not the viewer or editor. Keep device-relative shutter/control position while glyphs and text respond to gravity. The camera container compensates for actual host-window rotation rather than using width/height to guess physical orientation. Window geometry and hinge state govern viewfinder presentation; see the [device-specific Duo camera layout](README.md#locked-camera-film-and-orientation) for unfolded and tabletop exceptions. Freeze physical pose at shutter and map it through AVFoundation to the sensor's capture angle. Release the camera-specific orientation policy on exit.

## Evidence and maintenance

The [1.4.0 real-photo screenshots](../screenshots/ios/2026-11-27/README.md) show the running app; the [2026-11-02 synthetic captures](../screenshots/ios/2026-11-02/README.md) are layout history. See the [control audit](CONTROL-AUDIT.en.md) for controls and test boundaries. Historical checks do not establish current device or real-photo export acceptance. Keep superseded layouts in the historical directory rather than appending contradictory specifications.
