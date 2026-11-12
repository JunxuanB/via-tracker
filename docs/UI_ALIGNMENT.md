# Visual alignment and startup — 30 October 2026

The native interface follows the design sources rather than changing the designs to match implementation. Shared colors, cards, spacing and typography use paper/dark backgrounds, yellow fills and dark ochre text.

The phone home card orders train, route, countdown and connection information. Detail uses a light-weight timer, compact station timeline and separate planned/estimated times, preserving cross-day/time-zone context. iPad uses a 256-point sidebar and adaptive detail columns. The add flow provides station sheets, planning times, 15-minute travel steps and fixed actions. Settings groups activity, display/planning and data controls.

MapKit shows valid source coordinates only. Missing coordinates produce a labelled route diagram; inferred progress never becomes an official confirmed event.

## Startup investigation

Synchronous `AppStore` initialization opened SwiftData, read caches and restored ActivityKit before the first visible SwiftUI screen. `AppBootstrap` now appears first, opens storage asynchronously and restores activities after the main interface appears. Activity permission state is cached and refreshed on foreground entry. Loading has progress and retry; failures preserve trips. Startup logs contain stages and monotonic timing, without journey or credential contents.

One observed restart on an installed iPhone 15 Pro Max produced:

| Stage | Seconds after app initialization |
| --- | ---: |
| Loading screen | 0.163 |
| Database open begins | 0.168 |
| Database open ends | 0.200 |
| Cache read complete | 0.221 |
| Home visible | 0.281 |
| Activity restoration complete | 0.316 |

This single restart excludes time before app code and does not measure first-install startup. The original first-launch stall was not captured, so its unique root cause was not established.

Local evidence was saved in ignored `tmp/device-startup-fixed.log` and `tmp/startup-fixed.stderr`. UI regression coverage includes delayed storage warmup, creation/editing, zero travel time, persistence and formal-schedule choice. Full device/accessibility validation remains separate.
