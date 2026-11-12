# Tracking and notification fixes — 2026-10-31

## Changes

- Explicitly end dismissed ActivityKit instances when detected, and clear remaining instances in the current environment before requesting a replacement. Preserve the normal display period of activities ended by arrival.
- Reconcile ActivityKit state before deciding whether the detail button should close or start an activity. Show the system error when a request fails.
- Initialize milestone history when a subscription is created, rather than at its first scheduled processing pass. Updates to the same subscription preserve delivery history.
- Add an arrival reminder during the final ten minutes and intermediate-stop notifications within the selected boarding/alighting segment. Stop messages distinguish an observed arrival from an estimated one.
- Deliver independent due events separately; retain temporary failures for retry and deduplicate successful sends. Notifications do not require a Live Activity token.

## Automated evidence

Backend type checking and all 32 contract/domain/milestone tests pass. The six milestone tests cover departure, approach, destination, intermediate stops, changed ETA, early/late reported arrival, registration history, absent activity token, concurrent due events, temporary APNs failure, and deduplication. Delivery tests use an in-process transport/database double; they do not establish Apple delivery or D1 integration.

TrackerCore's ten Swift tests pass with the Xcode developer directory selected. The iOS simulator target builds successfully. ActivityKit's system lifecycle is not covered by these unit tests.

## Device verification still required

1. Start an activity, dismiss its card on the lock screen, return to the journey, and start it again. Confirm a new activity ID/token and visible card. Repeat after suspending/relaunching the app.
2. With notifications permitted, dismiss the activity and keep the app in the background across departure, an intermediate stop, the ten-minute arrival window, and arrival. Confirm alerts still arrive once each.
3. Change the ETA before the reminder window and verify the reminder follows the new ETA. Exercise a confirmed arrival before the ETA.
4. Confirm arrival-ended cards retain their normal display period, and that explicit restart clears older cards.

## Deployment — 2026-10-31

Published both Workers with the existing one-minute cron schedule. Both databases reported no pending migrations.

- Production: `c972e25e-d521-4c9c-b101-65d93c1fdd05`
- Test: `1dc02e71-8234-4901-b9a3-d005a5d0e7c5`

Both health endpoints returned HTTP 200, and the test endpoint reported push configuration present. Production's train endpoint returned HTTP 200 with 116 cached trains, but the source snapshot was stale (last fetched 2026-10-31T08:50:46.218Z). The operational refresh failed; a minimal D1 write confirmed Cloudflare error 7500: the account exceeded its free-tier daily row write limit. This account-level quota blocks normal refresh and notification persistence until midnight UTC (2026-10-31 20:00 America/Toronto) or a plan upgrade. No billing changes were made. Read-only health checks do not establish operational notification delivery.

The updated iOS app still needs installation for the ActivityKit restart fix. Real device delivery remains unverified.
