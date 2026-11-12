# Train Tracker

A native train-trip tracker for iPhone and iPad running iOS / iPadOS 26 or later. Built with SwiftUI, SwiftData, ActivityKit and WidgetKit, with a Cloudflare Workers / D1 backend.

Train Tracker is independent and unofficial. It is not affiliated with VIA Rail Canada. Train information may be delayed; confirm travel details with the railway.

## Features

- Save trips, choose boarding and alighting stations, and add connections at the same station.
- Set your planned departure and travel time to the station; delays do not silently change your plan.
- Follow estimated departures, arrivals, station progress and connection intervals.
- Start countdowns and Live Activities five hours before your planned leave time.
- View saved trips and the last valid train snapshot offline.
- Use Lock Screen Live Activities, Dynamic Island and home-screen widgets.
- English and Simplified Chinese interfaces, following the system app-language setting.
- No account, advertising, analytics or personal-location permission.

## Get started

You need macOS, Xcode with iOS 26+ SDK support, Node.js and npm. Open `ios/VIATracker.xcodeproj` and select the `VIATracker` scheme. For your own build, replace the signing team, bundle identifiers and App Group in `ios/project.yml`, then regenerate the project with XcodeGen.

```sh
npm --prefix backend ci
zsh scripts/verify.sh
```

The verification script runs shared Swift tests, backend type checking/tests and a simulator build. To run only the portable checks:

```sh
swift test --package-path packages/TrackerCore
npm --prefix backend run check
npm --prefix backend test
```

Normal app startup uses the production API. Debug fixtures and the test environment are separate. Device push delivery and system-hosted activity behavior still require [physical-device testing](docs/DEVICE_QA.md).

## Project layout

| Directory | Purpose |
| --- | --- |
| `ios/` | SwiftUI app, ActivityKit views, WidgetKit extension and UI tests |
| `packages/TrackerCore/` | Shared models, projection rules, localization and unit tests |
| `backend/` | Workers API, D1 migrations, APNs delivery and test console |
| `contracts/` | OpenAPI contract and fictional test fixtures |
| `postman/` | Local upstream and APNs simulations |
| `design/` | Design sources and developer handoff |
| `docs/` | English engineering, operation and user documentation |
| `scripts/` | Development, verification and preview tools |

## Documentation

- [Build, configuration and operations](docs/RUNBOOK.md)
- [Architecture and product rules](design/DEVELOPMENT_HANDOFF.md)
- [Test console and Live Activities](docs/LIVE_ACTIVITY_AND_TEST_CONSOLE.md)
- [Verification record](docs/VERIFICATION.md) and [latest validation](docs/RELEASE_VALIDATION.md)
- [UI implementation matrix](docs/UI_MATRIX.md) and [device QA](docs/DEVICE_QA.md)
- [Release notes](docs/RELEASE.md)
- [Privacy policy](docs/PRIVACY.md) and [support](docs/SUPPORT.md)

All repository documentation is maintained in English. App localization resources remain multilingual.

## Design previews

The design source contains 56 artboards in 19 groups. These use fictional trips and schematic maps; they are not live railway information or evidence of native system behavior.

On macOS, export system symbols locally and build the preview:

```sh
swift design/source/export-symbols.swift "$PWD/design/assets/symbols"
python3 design/source/build.py
python3 design/source/build-handoff.py
```

The handoff renderer needs `markdown-it-py`. Open `design/index.html` or `design/handoff.html` locally. Generated previews and exported symbols are ignored and must not be redistributed. Design layout checks are in `design/source/verify.cjs` and `verify-selection.cjs`.

## License

Original code is available under the [MIT License](LICENSE). Data, trademarks and Apple artwork have separate rights; see [third-party notices](THIRD_PARTY_NOTICES.md).
