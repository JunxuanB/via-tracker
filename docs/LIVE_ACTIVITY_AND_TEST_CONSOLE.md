# Live Activities and the test console

## Activity lifecycle

Foreground entry reconciles the app with system activities. Dismissed cards are not automatically revived with old tokens. Starting again creates a new activity and push session; buttons show progress, completion or a usable error. Activity restoration and generation checks prevent old asynchronous work from closing a newer session.

Notification permission and Live Activity availability are separate. Ordinary journey alerts continue independently of an activity token. Countdown text and progress bars use system time ranges; background phase changes still depend on server processing and APNs.

Tracking begins five hours before planned leave time. The implementation supports remote start and replacement three minutes before the eight-hour activity limit. These paths remain subject to physical-device verification and system policy; reopen the app if remote start fails.

## Source fields and maps

The historical source observation is recorded in `design/reference/api-observation.json`.

| Source field | Use and limits |
| --- | --- |
| `lat`, `lng`, `poll` | Train coordinates and position report time, all optional |
| `speed`, `direction` | Optional speed and heading |
| Station `eta == "ARR"` | Observed reached marker, not an actual-arrival timestamp |
| `arrival`, `departure` | Event-specific scheduled and estimated station times |
| `alerts` | Source advisories rendered as text with validated links |

A selected alighting station's reached marker can advance progress. Time-based progress uses estimates with scheduled fallback. Borrowed reference timetables clear reached flags, location, speed, heading and estimates.

The station diagram is schematic. The app does not invent railway geometry or station coordinates, reuse the operator's map token, or request personal location.

## Public console access

Open <https://via-tracker-test.junxuan-bao.workers.dev>. HTTPS Basic authentication is required for the page, device summaries, exports and all `/control` operations. Username: `admin`; password: the test Worker's `OPS_TOKEN`. Missing configuration disables console access. Keep local credentials in ignored `.dev.vars.test`, never in a URL or report.

The test Worker and D1 database are separate from production. Test data is shared by connected test devices and persists across Worker restarts. The panel does not return installation credentials, full push tokens or private keys. Health/feed routes remain public; installation APIs retain their own authentication.

## Connect the Debug app

1. Install a Debug build, open Settings and tap the version seven times.
2. Select the test environment, directly or through the information panel.
3. Add a test trip and enable its Live Activity. Copy the short device code from the collapsed test-tools section if needed.
4. Edit the corresponding train in the browser, then lock the phone and observe the activity and delivery log.
5. Permit ordinary notifications before using the test-notification action.

Only Settings shows the main test-mode notice; activities and widgets retain small test markers. Release builds omit the selector and always use production. Environment changes validate service availability, open the matching local store, end old activities and clean old subscriptions. Trips, caches, credentials and synchronization state are isolated by environment.

APNs sandbox/production is determined by signing, independently of the selected API environment. An APNs acceptance response does not prove that a card or notification appeared on the device.

## Select dates and edit trains

Choose the origin service date first, then search for a train. This date may differ from the passenger's boarding date on an overnight service.

To add a missing date, copy all available routes or a selected source date. Copying preserves origin-local departure time and elapsed route durations, clears delays/reached flags/advisories, and adds only missing instances. Existing edits and the source date remain intact. Ambiguous or nonexistent DST departure times produce an error. Train identity includes the full date, such as `14:2026-10-31`; direct identity changes in advanced JSON are rejected.

Across all dates, the console accepts at most 300 trains and a 1.4 MB import. It supports import/export, reset to current-time samples and undo of the last 20 changes. Download a draft before reloading after an edit conflict. Polling must not overwrite unsaved work.

Scenarios include departure in two minutes, departure from a selected intermediate station, riding, arrival in 30 seconds, final arrival, delays, station times, advisories, position/speed/heading, missing or stale coordinates, stale feeds, HTTP 503 and invalid empty data. Use ISO 8601 times with an offset or `Z`.

Select the same boarding station as the app when testing intermediate boarding. A whole-train departed flag does not prove departure from that station. To replay deduplicated milestone alerts, create a new test journey.

## Notifications, widgets and history

Foreground local clocks advance known milestones even when requests time out, return 304 or fail offline. Background delivery uses APNs; important phase changes use higher priority, ordinary refreshes lower priority. Collapse IDs and expiration reduce obsolete queued updates.

Alerts cover planned leave time, pre-departure, departure, intermediate stops, approach and arrival. Registration initializes history rather than replaying old events. Recovery sends only the latest eligible recent milestone; successful deliveries are deduplicated and temporary failures retained for retry. Ending tracking cancels the subscription.

Widgets register their own push tokens and retain a network snapshot. Timeline requests are subject to system budgets, even when the app requests five-minute test or fifteen-minute production refresh. Completed summaries remain for at most 24 hours. Completed/stopped trips are available in History; later ETA corrections can restore an automatically completed trip to the active list.

## Maintenance and local mode

From `backend/`:

```sh
npm run db:test
node scripts/sync-secrets.mjs .dev.vars test
npm run deploy:test
```

Test migrations are independent. The console reuses `src/test-data.ts`, normalization, subscriptions and APNs logic. Control routes include `/control/state`, `/control/status`, `/control/export`, `POST /control`, `POST /control/push` and `POST /control/notify`.

For a local, in-memory console without APNs:

```sh
npm --prefix backend ci
npm --prefix backend run test-console
```

Open `http://localhost:4318`. A Debug `VIA_API_URL` override applies before an explicit in-app environment choice. For a trusted LAN, add `-- --host 0.0.0.0` and use the Mac's LAN address on the device. Local data resets on restart; export it first.

Physical-device delivery, long-running renewal, system-hosted layouts and widget scheduling remain manual checks in [DEVICE_QA.md](DEVICE_QA.md).
