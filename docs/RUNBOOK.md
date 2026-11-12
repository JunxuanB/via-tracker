# Build and operations

The app targets iOS / iPadOS 26+. Trips are stored locally; the backend stores installation-scoped tracking subscriptions. Normal startup reads real train data. Debug fixtures and test storage are isolated.

## Components

| Component | Location |
| --- | --- |
| Xcode project / scheme | `ios/VIATracker.xcodeproj` / `VIATracker` |
| XcodeGen source | `ios/project.yml` |
| Shared domain model | `packages/TrackerCore` |
| OpenAPI 3.1 contract | `contracts/openapi.json`, schema version 1 |
| Production API | <https://via-tracker-api.junxuan-bao.workers.dev> |
| Test API and console | <https://via-tracker-test.junxuan-bao.workers.dev> |

The checked-in identifiers belong to the original project. Forks must configure their own signing team, bundle identifiers, App Group, Workers and D1 database IDs. The app uses native MapKit and does not request personal location.

Deep links include `viatracker://journey/<journeyID>`, `viatracker://trains` and `viatracker://settings`.

## Local build

Use macOS, Xcode, Node.js/npm and optionally XcodeGen. Run from the repository root:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
npm --prefix backend ci
zsh scripts/verify.sh
zsh scripts/archive.sh
```

`archive.sh` exports a development-signed package using Release optimization and development APNs. Register the device and enable Developer Mode before installing. Change target configuration in `ios/project.yml`, then run `xcodegen generate --spec ios/project.yml`.

## Backend development

```sh
cd backend
npm ci
npx wrangler login
npm run db:local
npm run dev
```

Create your own D1 databases and update `backend/wrangler.jsonc` when using another Cloudflare account. Production and test have separate migrations and bindings.

## Credentials and deployment

From `backend/`, configure an APNs signing key locally:

```sh
node scripts/configure-secrets.mjs /path/to/AuthKey.p8 YOUR_TEAM_ID YOUR_KEY_ID
node scripts/sync-secrets.mjs
npm run db:remote
npm run deploy
node scripts/ops.mjs refresh
node scripts/ops.mjs apns-probe
```

The configuration script writes ignored `.dev.vars` with mode 0600 and preserves existing operator/proxy settings. A shared signing key must be rotated in every dependent service. No private key or operator token belongs in Git, logs or screenshots.

`OPS_TOKEN` protects internal operations. Installation credentials are generated in the Keychain; the server stores a SHA-256 hash. Installation APIs use `Authorization: Bearer <installationID>:<credential>`, write rate limits and installation-scoped authorization.

A `BadDeviceToken` probe proves an APNs response path, not topic authorization or device delivery. Production Workers contact APNs directly. For local HTTP/2 debugging only, run `node scripts/apns-proxy.mjs` and set `APNS_PROXY_URL="http://127.0.0.1:8790"` in local configuration.

Apply migrations before deploying the corresponding Worker. Test operations use `npm run db:test`, `node scripts/sync-secrets.mjs .dev.vars test` and `npm run deploy:test`. Never point fault-injection tools at production.

## Local failure simulation

Use three terminals with the existing Postman simulation:

```sh
# Repository root
postman simulation run postman/simulations/tracker.sim.yaml --port 4010 --no-history

# backend/
npx wrangler dev --test-scheduled --port 8787 --var SOURCE_URL:http://127.0.0.1:4010/via/data/allData.json --var APNS_PROXY_URL:http://127.0.0.1:4010/apns

# backend/
node --import tsx tests/integration.ts
```

Mock delivery records omit authorization headers and device tokens. Simulation establishes local error handling, not real push delivery.

## Data and concurrency rules

- Fetch the upstream feed centrally once per minute. Retain the last valid snapshot on failure, preserving source identity, service date, station order, time zones and quality flags.
- Keep official scheduled times, official estimates and user planning separate. Planned leave time is planning departure minus travel time to the station (default 30 minutes, 15-minute steps, minimum zero).
- Reference schedules migrate local wall times with IANA time zones and clear live fields. Reject nonexistent DST times and require an explicit choice for ambiguous times.
- Derive progress from the selected stations' latest estimates, with scheduled fallback. A later ETA can reverse derived completion; do not permanently write automatic progress into the saved journey.
- Connections require matching station codes. Existing negative intervals remain visible without risk ratings or automatic rebooking.
- SwiftData keeps journeys, the latest feed and pending subscription deletions. The app atomically writes App Group summaries; widgets keep their own network cache.
- Foreground polling normally runs every minute, with 5/15/30/60-second retry backoff and jitter. Backgrounding cancels dense polling. Revisions prevent old responses from overwriting newer edits.
- Push on phase/leg changes or accumulated ETA changes of at least 60 seconds; healthy renewal runs every five minutes. Source age over ten minutes and position age over five minutes are distinct warnings.
- Fetch/delivery leases, revision checks and monotonic APNs timestamps protect concurrent work. Network retries can still cause duplicate transmission.

## Native QA and test tools

`VIA_QA_SCENARIO` selects isolated Debug fixtures. By default they use in-memory SwiftData, no network and no App Group writes. `VIA_QA_STORE=<UUID>` selects a separate persistent UI-test store. Do not set these variables for normal startup.

```sh
python3 scripts/capture-simulator.py <BOOTED_SIMULATOR_UUID> detail detail-dark connection
```

Captures go to ignored `tmp/native-qa/`. Galleries reuse native content views but do not reproduce system-hosted Lock Screen or Dynamic Island rendering. See [UI matrix](UI_MATRIX.md), [verification](VERIFICATION.md) and [device QA](DEVICE_QA.md).

UI tests are in `ios/UITests/JourneyFlowTests.swift`. Run them in Xcode or use `xcodebuild test` with the scheme, simulator destination and desired `-only-testing` selector.

The public test console requires HTTPS Basic authentication: username `admin`, password from the test Worker's `OPS_TOKEN`. In Debug, tap the settings version seven times to select the test environment. Release always uses production. See [test-console instructions](LIVE_ACTIVITY_AND_TEST_CONSOLE.md).
