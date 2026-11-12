# UI interaction and map improvements

Historical implementation notes from 30–31 October 2026. No builds, simulator runs or performance measurements were performed during these edits; later validation is recorded separately.

## Navigation, maps and editing

- Root tabs stay in root layouts and disappear in detail. Content accounts for navigation height and remains scrollable.
- iPad saved trips scroll; section changes reset stale detail navigation; deleting the selected trip returns to a valid root.
- Train detail reads the latest snapshot and includes map, advisories, fetch time, refresh and a fixed add action. Trip detail exposes stations/maps before departure and during connections.
- Expanded maps support zoom, pan, compass and return-to-train. Compact maps do not steal page scrolling; location updates respect the inspected region. Invalid, stale or undated coordinates have explicit fallbacks.
- Search trims input, offers clear/empty states and natural train ordering. Add flow uses the current filtered candidates, resets scroll per step and confirms discarded edits.
- Fixed action areas are smaller. Existing-trip editing omits the ineffective activity toggle. Planning displays station-local time.
- Failed saves/deletes retain the current screen and show errors. Activity operations prevent duplicate requests and stale asynchronous closure of new sessions.
- Denied notification access links to system Settings; controls have consistent disabled states and larger touch targets.

## Dynamic Island and environment notices

The main test-mode notice appears only in Settings. Collapsed tools expose environment choice, console links and the short device code.

Expanded Island content has one destination line, one route line, a bounded countdown and progress before connection information. Compact timers have bounded width and scalable text; VoiceOver retains full station names. Lock Screen cards have their own layout. Timer ranges use a single comparison time to avoid reversed intervals.

Zero/negative connections describe the actual overlap or late arrival without risk ratings. `VIA_QA_SCENARIO=islands` previews shared views at narrow widths, with long names and long countdowns; it does not simulate system hosting.

## Date editing and redundant work

The console selects date before train. Copying creates independent instances with complete shifted schedules; it preserves other dates. Search indexes and device/log lists are reused, polling cannot overlap or overwrite drafts, and conflicts support draft download/reload.

App candidate searches use a lightweight data version, reuse station indexes and cancel obsolete indexing. Validated API bytes become the offline cache without re-encoding the whole feed on the main thread. Unchanged trips do not trigger redundant writes; idle subscription reads are limited to once per minute.

Home/detail cards redraw on a 15-second timeline while timer text remains system-driven. Signing-environment parsing is cached. Train lists filter by origin date and label overnight arrival dates. These are implementation changes, not quantified performance results.
