# Physical-device QA

Simulator tests, native content galleries and mocked APNs do not establish real notification delivery or system-hosted rendering. Record device/OS, build, signing environment, source version, action times, APNs status and visible results. Do not include credentials, full tokens or private location data.

## Setup and data

1. Select your signing team, the `VIATracker` scheme and an iOS / iPadOS 26+ device in Xcode. Enable Developer Mode and register the device if required.
2. Check Push Notifications and the App Group on both app and widget identifiers. Re-sign development packages for newly registered devices.
3. Launch without QA variables. Check real trains, service dates, selected-station schedules/estimates and fetch times. Save intermediate-boarding and same-station-connection trips.
4. Enable airplane mode and relaunch. Saved trips and last valid data must remain. Restore connectivity and confirm a newer snapshot without stale-response rollback.

## Activities and notifications

1. Start a Live Activity. With the app backgrounded, confirm both APNs acceptance and a visible change on the Lock Screen. A transport response alone is insufficient. Resolve topic authorization failures with an appropriate signing key.
2. Check iPhone Lock Screen light/dark and compact/minimal/expanded Dynamic Island. On iPad check its Lock Screen presentation. Cover all phases, long station names, stale data, over-24-hour countdowns and overlapping connection times.
3. Dismiss a card, return to the app and start again. Confirm a new activity ID/token. Rapid taps must produce one request; reopening Settings must refresh permission state.
4. Cross departure, connection and arrival boundaries in foreground and background. Estimates take precedence, scheduled times are the fallback, and automatic arrival requires no destination confirmation. Network failure must not stop foreground clock progression.
5. Keep a long trip active beyond eight hours. Verify the server's replacement attempt three minutes before expiry and manual recovery if it fails. For future trips, cross the five-hour window with the app foregrounded and terminated.
6. Rotate tokens and verify old sessions stop updating. Ordinary alerts must continue after activity dismissal and stop after ending tracking. Test notification permission allow/deny/revoke separately from activity permission.
7. Verify one-time formal-schedule choice and per-journey synchronization preference. Registration must not replay old milestones; changed ETAs must shift reminders appropriately.

## Widgets, navigation and accessibility

- Add small/medium widgets, follow deep links, relaunch and lock the device. Verify shared-cache readability, freshness labels and eventual system timeline/push refresh.
- Verify current-trip selection follows the earliest unfinished planned departure. Starting a later activity must not replace it. Completion/end-tracking promotes the next trip; completed trips remain in History and recently completed for 24 hours.
- Use VoiceOver through phase, destination, countdown, time source, connection and controls; do not announce each second. Check largest text, narrow displays, dark mode, iPad landscape and real window resizing.
- Check map expansion, pan/zoom, compass and return-to-train behavior. Missing/old coordinates must not appear current. The route diagram must remain accessible without coordinates.

## Debug console and date editing

- Seven version taps expose the environment selector only in Debug. Release always uses production. Switching must preserve separate trip stores and end old activities; a failed switch must retain current data.
- Authenticate to the [test console](LIVE_ACTIVITY_AND_TEST_CONSOLE.md). Match date, train and boarding station before using scenarios. Verify both ordinary test alerts and activity updates on the actual device.
- Copy a missing date and confirm both dates remain independent. Repeat-copy must preserve edits. Check overnight routes, year boundaries and DST ambiguity/nonexistence.
- Edit concurrently in two browser windows. Unsaved drafts must survive polling; conflicts must allow draft download and reload.
- Search `Montreal` / `Montréal`, change dates rapidly and reopen the list. Results must match the add-trip flow; cancelled indexing must not restore old results.
- Tap the full iPad sidebar row and repeat the active section to return to its root. Verify history navigation and deletion recovery.

The `islands`, `small-device` and `ipad-narrow` QA containers are layout aids, not substitutes for these device checks.
