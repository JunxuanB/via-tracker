# Train Tracker developer handoff

Updated 12 November 2026. This document describes the current architecture and product rules. Historical HTML designs are previews, not proof of native implementation or system delivery. See [operations](../docs/RUNBOOK.md) and [validation](../docs/RELEASE_VALIDATION.md) for build instructions and evidence.

[Local design preview](index.html#journey) · [HTML handoff](handoff.html) · [historical source observation](reference/api-observation.json)

## 01. Components and preview sources

The project includes an iOS / iPadOS 26+ app, shared Swift package, widgets, Live Activities and a Workers/D1 backend. The design source has 56 artboards in 19 groups, including phone/tablet, dark mode, accessibility and system-content previews.

| Path | Purpose |
| --- | --- |
| `source/screens.js` | Artboards, scenario groups and navigation |
| `source/station-selection.js` | Prototype station selection and travel-time steps |
| `source/style.css`, `source/shell.html` | Preview appearance and shell |
| `source/build.py` | Self-contained preview generator |
| `source/build-handoff.py` | Markdown-to-HTML handoff renderer |
| `source/export-symbols.swift` | Local-only system-symbol export |
| `source/verify.cjs`, `source/verify-selection.cjs` | Preview layout and interaction checks |
| `../contracts/openapi.json` | Implemented API contract |

Generated `index.html` and exported symbols are ignored. Build them locally; do not redistribute exported Apple artwork. Station selection in the HTML is a session-only demonstration and does not create a persisted native journey.

## 02. Product decisions

Use yellow accents, clear functional text and native navigation. Keep station names as published; app text supports English and Simplified Chinese. Passengers select boarding/alighting stations from lists, set planning departure and travel time, and optionally add same-station connections.

Travel time defaults to 30 minutes, changes in 15-minute steps and can be zero. Planned leave time is the passenger's plan, never a recommendation silently shifted by train delays. Connections require identical station codes and have no transfer-duration input or risk rating.

A journey contains ordered train legs. Current-trip presentation selects the earliest unfinished journey by planned departure. A single activity window follows its current leg. Trips can exceed the activity's lifecycle limit. Maps are supplementary; no personal-location permission is needed.

## 03. Navigation and scope

Phone navigation is single-column with lists and sheets. Tablet uses sidebar/detail columns and collapses in narrow windows. Trip detail includes countdowns, station times, connection intervals, maps/diagrams, freshness, editing and activity controls.

No ticket sales, rebooking, guaranteed connections, cross-station transfers, account system, automatic cross-device sync or personal tracking is provided. Devices manage their own journeys.

## 04. Time semantics

Keep three separate values: official `scheduled`, official `estimated`, and user `planningDeparture`. `plannedLeaveAt` is planning departure minus `travelToStationMinutes`. Delays do not overwrite that plan.

Use the selected boarding station's departure and selected alighting station's arrival, never the whole train's origin/destination times. Departure/arrival countdowns use estimates with scheduled fallback. Connection intervals use the relevant arrival/departure events. Calculate durations with absolute instants and display times in each station's IANA time zone.

Missing estimates are labelled as scheduled fallback. Never substitute the current time for a missing event or call an estimate an actual event. Time-based progress is not GPS distance.

## 05. Progress and passenger confirmations

Progress is derived from current snapshots and time: before departure, travel to station, waiting, riding, connection and completion. New estimates can reverse automatic completion, so derived progress must not permanently overwrite saved state.

Adjacent passenger confirmations can move from beforeDeparture to onTheWay to waiting; waiting means arrival at the boarding station. Those overrides expire at estimated departure, with scheduled fallback. Arbitrary phase overrides are test-only. Routine destination arrival needs no confirmation. Swift and TypeScript apply matching rules.

## 06. Same-station connections

Match station codes, train identity, service date and station order. Adding a leg fixes the previous alighting station as the next boarding station and filters infeasible scheduled connections. If none exist, allow changing the date or previous station.

An existing zero/negative interval remains visible with the actual times and an edit option. Do not hide the leg, invent a safety rating or rebook automatically.

## 07. Future reference timetables

When no usable target-date run exists, choose a complete same-weekday run first, then the nearest suitable run. A reference is not a guarantee that the service operates on that date.

Migrate station-local wall times using IANA calendars and relative service-day offsets, not fixed 24-hour increments. Handle DST ambiguity explicitly and reject nonexistent local times. Clear estimates, reached flags, positions and whole-train running flags.

Match the formal train by number and origin service date, then verify selected stations/order. Boarding date can differ from origin date. Ask once about a first planning-time difference; keep/sync choice applies only to that journey.

## 08. Source observation and uncertainty

The observed endpoint is <https://tsimobile.viarail.ca/data/allData.json>. The historical 31 October 2026 observation contained 68 trains and 869 station calls across multiple service dates; counts are not a contract. No versioned upstream schema or SLA was established.

Preserve raw keys; display keys may include month/day or only a number. `instance` is treated as origin service date. `times` may be partial and its first station need not be the true origin. Nested arrival/departure events can omit estimates; origins/termini can have only one event.

Optional `lat`/`lng`/`poll` describe location and its age. Fetch time must not replace position report time. `eta == "ARR"` is an observed reached marker, not an actual timestamp. Whole-train `departed` does not establish departure from an intermediate boarding station. Do not parse display strings into authoritative times.

Advisories contain English/French fields. Render remote text safely and validate links. Missing trains do not imply cancellation. Data access does not by itself establish redistribution rights. Test fixtures are fictional; source observations must not become a production timetable.

## 09. Domain identity and quality

Train identity includes number and full origin service date. Station references include instance, code and order. Keep original time strings, parsed instants, event type and zone. Decode `Z`, offsets and fractional seconds.

Separate source fetch time, content-change time, position report time, device receipt time and validity threshold. A bad individual record should not make every train unusable. Preserve quality flags for retained or inferred station events.

`Journey`, `TrainLeg`, `TrainSnapshot`, `StationCall`, shared snapshots, activity sessions and installation-scoped subscriptions are implemented in the shared core and backend. Consult code and OpenAPI for exact field names rather than historical design drafts.

## 10. Offline behavior and recovery

Load persisted trips/feed before requesting fresh data. Distinguish device offline, upstream failure and stale position. Keep valid cached data and system timers; do not invent new estimates. Reconnection updates existing journeys without losing edits.

Foreground startup, manual refresh and connectivity recovery request the normalized API. Retry with capped backoff/jitter and cancel dense polling in background. Revisions prevent obsolete responses from winning. Background scheduling cannot guarantee every intermediate event is observed.

## 11. Architecture

SwiftUI provides the interface, SwiftData local persistence, ActivityKit live content, WidgetKit extensions, App Group summaries, URLSession networking and MapKit valid train locations.

A central scheduled Worker fetches the upstream feed once per minute, normalizes/validates it, stores date documents in D1 and distributes relevant changes through authenticated APIs and APNs. Avoid fetching the whole upstream feed separately for each passenger. D1 leases and guarded writes coordinate overlapping work.

A local HTTP/2 proxy exists for APNs debugging. A successful provider response is transport evidence; real token authorization and visible delivery require device checks.

## 12. Refresh and delivery

Compare visible phase/current leg and estimates against the last sent state. Send phase changes promptly and ETA changes after at least 60 seconds of accumulated difference. Handle delay increases and recoveries alike. Five-minute healthy renewals preserve activity freshness without rewriting old position timestamps.

Countdowns use system timestamps, without per-second pushes. APNs timestamps are monotonic; retries and collapse identifiers reduce duplicate/outdated work but do not guarantee exactly-once delivery. Source absence is not arrival/cancellation evidence.

## 13. Activity and widget lifecycle

Tracking begins five hours before planned leave time. Earlier saved trips show dates and planning information. Remote start requires a previously issued push-to-start token and system permission. The server attempts replacement three minutes before the eight-hour activity limit; manual reopening remains the recovery path.

Activity payloads carry only necessary summaries, not complete station lists. Permission, dismissal, token rotation, expiry and trip completion are distinct states. Activity callbacks and asynchronous operations are guarded by session identity/generation. Deep links open the correct trip.

Widgets use shared summaries, their own network cache, timeline boundaries and push registration. Actual refresh remains subject to system budgets. Neither content galleries nor compiled extensions prove system-hosted behavior.

## 14. API and security

The implemented routes and schemas are in `../contracts/openapi.json`, including `/v1/trains`, subscriptions and activity-start token registration. API envelopes retain schema/snapshot versions, source time/status and quality information. ETags reduce unchanged transfers.

Installations authenticate with random Keychain credentials; only hashes are stored server-side. Validate IDs, station order, dates, sizes and counts. Keep APNs keys/operator credentials server-side and omit full tokens from logs. Subscription expiry and installation retention are described in the [privacy policy](../docs/PRIVACY.md).

The test console requires HTTPS Basic authentication, has independent storage and cannot expose installation credentials. Debug environment selection is absent from Release builds.

## 15. Design groups and accessibility

Groups cover trip detail/home, train/station selection, planning, connections, phases, reference matching, offline quality, activity lifecycle, edge cases, settings, accessibility, tablet layouts, Lock Screen, activity states, Island, widgets and foundations. [The matrix](../docs/UI_MATRIX.md) retains all 56 IDs.

Design colors include yellow `#FFCC00`, ink `#252622`, pale yellow `#FFF1B8`, accent `#705600`, dark background `#191917` and dark card `#262622`. Use dark text on yellow, system typography/symbols and monospaced timers. Controls need generous hit areas; Dynamic Type should wrap or rearrange content rather than simply shrink it.

VoiceOver should expose phase, destination, duration, source/freshness, legs/connections and actions without announcing every second. Device testing is required.

## 16. Fictional demonstration timeline

The primary design snapshot is 6 November 2026 at 17:24 America/Toronto. VIA 44 departs Toronto at 14:00, reaches Ottawa at scheduled 18:30 / estimated 18:42, then VIA 38 leaves at 19:15 and reaches Montréal at 21:12. This yields a 78-minute arrival countdown and a 33-minute connection.

A separate before-leaving snapshot is 12:55 with planned departure 14:00 and 30-minute travel, giving planned leave 13:30 and a 35-minute countdown. Other snapshots deliberately show different phases/delays. Overnight and cross-zone examples exercise layout only. None is a verified operating timetable.

## 17. Verification priorities

Cover multi-date identity, year boundaries, intermediate boarding, missing events, same-station constraints, zero/negative intervals, DST, offline recovery, retained snapshots, newer edits, permission denial, token rotation, concurrent/old pushes and long-running lifecycle.

Use domain/contract tests for rules, local simulations for dependency failure, native UI tests for interaction, preview checks for design layout and devices for system delivery/rendering. Do not substitute one form of evidence for another.

## 18. Open questions and references

Remaining device questions include terminated-app remote start, long-running replacement, actual notification delivery, system widget budgets, VoiceOver and real tablet resizing. Upstream cancellation semantics, route completeness and undocumented field guarantees remain uncertain.

- [ActivityKit](https://developer.apple.com/documentation/activitykit)
- [WidgetKit](https://developer.apple.com/documentation/widgetkit)
- [MapKit](https://developer.apple.com/documentation/mapkit)
- [Cloudflare Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/)

Use the code and current official documentation when changing APIs; this handoff is not a platform guarantee.
