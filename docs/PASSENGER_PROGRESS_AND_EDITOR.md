# Passenger progress and journey editing

- The arbitrary phase override menu and reset banner are visible only when `AppConfiguration.isTest` is true. A Debug build using production data is still production.
- Both environments expose adjacent passenger confirmations: beforeDeparture → onTheWay → waiting. Here waiting means arrival at the boarding station, not completion at the destination. Completed, riding, transfer, and stopped journeys do not expose these actions.
- Passenger confirmations use the existing persisted manualPhase field, preserving compatibility with saved journeys and subscriptions. onTheWay/waiting confirmations stop overriding automatic progress at the latest estimated departure (scheduled departure fallback). Swift and backend projection apply the same rule. Other test overrides retain their existing behavior.
- Departure countdowns and labels use the latest stored estimate. Confirmation triggers a feed refresh; offline use retains the last available snapshot and existing freshness indicators. Planned leave time remains based on the user's plan.
- Editing starts with a summary, distinct editor wording and close action, plus a direct departure-planning entry. Initialization runs once per presentation; preview setup no longer overrides an existing journey editor.
- Shared buttons and notices support Dynamic Type. Navigation titles scale within the space available. Editing controls have larger touch targets.
- Detail hero shares its parent's timeline, station rows reuse their filtered list and next-stop calculation, and candidate indexing runs only on the train-selection page. These are reductions in redundant work; no device-level speedup percentage is claimed.

Regression coverage includes adjacent transition validation, backwards/skipped transition rejection, updated estimates, scheduled fallback, automatic departure, stopped journeys, production menu visibility, editor saving, and test-environment arbitrary corrections.
