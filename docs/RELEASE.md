# Release 1.0.0 — engineering notes

See [latest validation](RELEASE_VALIDATION.md) for the historical build and test checkpoint. This file describes behavior, not a new verification run.

## Incomplete feeds

The normalizer retains earlier station schedules for the same unchanged route when a later poll omits times. Retained departures follow newer delays. Arrival-only or departure-only intermediate stops can infer the missing counterpart; station-level times are a fallback. Origins do not gain arrivals and termini do not gain departures. Repairs are marked with `retained_station_events` or `inferred_station_events`; uploaded trip snapshots remain strictly validated.

A healthy empty list is distinct from an outage. Stored schedules remain available. Future reference selection prefers a complete same-weekday run, then the nearest suitable date; an incomplete published run does not hide a complete reference.

## Tracking window and localization

Countdowns and activities begin five hours before planned leave time. Before that, home/detail/widgets show dates and planned times. Remote start uses an installation's push-to-start token; renewal attempts replace a long-running activity before its eight-hour limit. These paths need device verification and depend on system permission, issued tokens and valid APNs configuration.

English and Simplified Chinese cover the app, shared core, widgets, activities and production alerts. Existing subscriptions without a language retain their legacy language until synchronization.

## Current-trip ordering

The current card, current-trip link and widget choose the first unfinished trip in planned-departure order. Starting an activity for a later trip cannot replace it. Completion or ending tracking promotes the next trip. Legacy manual-primary preferences are ignored.

## Backend compatibility and deployment

Apply migrations before deploying the Worker and updating clients. Production uses `npm --prefix backend run db:remote` followed by `npm --prefix backend run deploy`; test uses `db:test` followed by `deploy:test`.

The API adds `PUT` / `DELETE /v1/activity-start-token` and subscription `autoStart` / `activity.testSource`. Older clients remain supported. Release builds omit Debug environment tools and always use production. The public test console requires authentication.

## Remaining engineering limits

Real push delivery, terminated-app remote start, eight-hour replacement, widget budgets and VoiceOver require [device QA](DEVICE_QA.md). The all-train list includes retained history and could benefit from date filtering. Data-source access does not establish redistribution rights; see [third-party notices](../THIRD_PARTY_NOTICES.md).
