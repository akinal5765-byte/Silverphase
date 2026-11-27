# iOS localization

Use familiar local phrasing for controls and photography terms, not a literal
rendering of English. Preserve stock names, file formats, lens names and
technical identifiers. Check film vs. movie, paper printing vs. export,
a photographic stop vs. a menu action, and Photos (the system app) vs.
the Silverphase library in the context of the actual screen.

- Existing English, Simplified Chinese and Traditional Chinese content stays
  inline in `T` and `TDetached`. New in-app locales use
  `Silverphase/Resources/MobileCopy/<locale>.lproj/MobileCopy.json`.
- A catalog key is the English source template, optionally prefixed by
  `FileStem|` where the same English phrase requires different local wording.
  The more specific key wins. Preserve each numbered placeholder exactly;
  reorder placeholders if the language needs it. Preserve printf directives
  and export filename tokens such as `{original}` unchanged. A German
  singular variant can add `|one:N` to a key, where N is the count slot.
- Run `Silverphase/Tools/export-mobile-copy.sh` to export strings with source
  locations and existing language context, then
  `python3 Silverphase/Tools/check-mobile-catalog.py` to reject missing or
  malformed entries. This does not replace in-context copy and layout review.
- iOS owns permission prompts, Control Center and Shortcuts strings. Their
  resources are separate from live in-app copy. A new catalog must also add
  `Resources/System/<locale>.lproj/{InfoPlist,Localizable}.strings` and
  `Resources/LockedCamera/<locale>.lproj/InfoPlist.strings`. Regenerate the
  project and use `check-system-localization.py` with the built app path.
- Do not add a partially translated catalog to release resources. Test a
  live change in Settings, an app relaunch, a supported/unsupported system
  language and the returning path from the camera and photo viewer. Check
  menus at narrow iPhone and iPad/Duo widths, Dynamic Type, date and number
  conventions, and the actual system prompts on hardware.
