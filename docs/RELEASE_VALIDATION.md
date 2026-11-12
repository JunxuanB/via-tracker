# Validation checkpoint — 12 November 2026

This is a historical engineering record, not a claim that the documentation cleanup reran application tests. It supersedes earlier build checkpoints. System-hosted activity behavior and physical-device push delivery remain unverified.

## Results at the checkpoint

| Check | Observed result |
| --- | --- |
| Toolchain | Xcode 27.2, Swift 6.4.2 |
| Shared core | 16 tests passed, including translation parity/placeholders, DST and five-hour tracking |
| Backend | Type checking and 45 tests passed, including contracts, feed repair, remote start/renewal, languages and console authentication |
| Native UI | 12 distinct tests passed across iPhone iOS 27.2 and iPad iOS 27.0 simulators |
| UI scope | Both languages, onboarding, editor/persistence, schedule choice, future dates, settings, largest text, storage warmup, iPad landscape and real-service refresh |
| Debug build | App and widget simulator build succeeded |
| Release build | Device archive succeeded; Debug environment controls were absent from the checked binary |
| Production API | Health and train list returned 200; native real-service refresh succeeded |
| Test console | Anonymous UI/control requests returned 401; authenticated state read returned 200 |

The English-settings test initially exposed an incorrect Debug scenario route; the route was fixed and the test passed on rerun. Logs and XCTest results remain local under ignored `tmp/` and `build/`.

Reproduce core/backend/simulator checks with `zsh scripts/verify.sh`. Deployment and database operations are separate and must not be inferred from a local test run.

## Services at that checkpoint

- Production: migration 0005 applied; Worker `ec0e61ec-0e0c-4d4c-b93d-a5016d3e97c6`.
- Test: migration 0006 applied; synthetic seed and authenticated console deployed; operator secret rotated.
- Static privacy/support: assets-only Worker `786fe5ab-4373-413b-a0d7-d5ca791c28a0`, without a database or scheduled work.

These are historical observations, not a live service-health assertion.

## Ordering follow-up

A dedicated iPhone regression passed for creation order, legacy selection, ending tracking and relaunch. The current card, deep link and widget now choose the earliest unfinished trip by planned departure. The English passenger-progress/editor test also passed. Local evidence includes `tmp/current-trip-retest.log` and `tmp/current-trip-tests.log`.

See [DEVICE_QA.md](DEVICE_QA.md) for outstanding system-hosted rendering, real push delivery, remote start, long-running renewal and accessibility checks.
