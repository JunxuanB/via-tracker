# Engineering review — 30 October 2026

This historical record describes implementation work; checks were not run during that review. See [latest validation](RELEASE_VALIDATION.md) for subsequent evidence.

## Product behavior

Progress derives from selected-station estimates with scheduled fallback. Completion is reversible when later ETAs change. Update diagnostics stay in secondary information; routine arrival does not require confirmation. Search folds case, accents, width and punctuation, supports station codes and debounces input by 180 ms. Indexing and connection candidates are built off the main thread; formatter caches reduce repeated work. No measured speedup was claimed.

## Fixes

| Area | Change |
| --- | --- |
| Startup and navigation | Retain deep links during database startup; unknown journeys return home |
| Persistence and synchronization | Re-fetch records by ID after deletion, reject old snapshots, coalesce follow-up sync and process pending deletions |
| Push tokens | Clear pending state only if the sent token still matches the current token |
| Activity lifecycle | Restore before syncing; guard callbacks by activity ID/generation; detach state before awaiting termination |
| Widgets | Skip equal summaries, target reloads, avoid network calls without a trip and include each leg boundary in timelines |
| Domain projection | Align Swift and TypeScript automatic progress and derived current-leg selection |
| Subscription writes | Accept only newer revisions and return the stored result; report conflicts |
| Delivery leases | Claim with current time, re-read the row, and verify lease/revision/activity/reserved timestamp on writeback |
| APNs | Cache provider tokens for 50 minutes per credential fingerprint; invalidate only the matching device token |
| Contracts | Preserve validated position/advisory/status fields; validate identities, source times, station order and leg IDs |
| HTTP/runtime | Enable Node compatibility, return 400 for invalid URL encoding and honor Retry-After on limited writes |
| Tests | Update automatic-arrival, ETA correction, search and retained-snapshot cases |

These changes retained navigation, map and editing fixes from earlier work. No dependencies, secrets or remote resources were changed during the review.

## Limits

Lease/timestamp guards do not guarantee exactly-once delivery. Token caches are per Worker isolate. Native lifecycle, background rendering and long-running activities require device checks. Source estimates and reached markers must never be represented as documented actual-arrival events. Missing coordinates produce a schematic route.

Additional activity reconciliation, reached markers, speed/heading and console work is described in [the console guide](LIVE_ACTIVITY_AND_TEST_CONSOLE.md).
