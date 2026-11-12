# Design-to-native implementation matrix

The 56 scenario IDs are retained as navigation and QA references. Historical captures are not proof of native system behavior. Automatic departure/connection/arrival supersedes the old pending-update screen. The expanded Island uses dedicated shared content; the main test notice appears only in Settings.

`small-device` uses a 320-point container and `ipad-narrow` a 600-point container. Actual resizing, VoiceOver, Lock Screen, Dynamic Island, notification banners and widget scheduling require device QA. See [latest validation](RELEASE_VALIDATION.md) for checks performed after this historical matrix.

| Design group | Scenario ID | Implementation | Historical check |
| --- | --- | --- | --- |
| Journey detail | `detail` | JourneyDetail / JourneyHero / StationTimeline | Native capture; domain, API and UI tests cover behavior separately |
| Journey detail | `connection` | JourneyDetail / JourneyHero / StationTimeline | Native capture; domain, API and UI tests cover behavior separately |
| Journey detail | `detail-dark` | JourneyDetail / JourneyHero / StationTimeline | Native capture; domain, API and UI tests cover behavior separately |
| My trips | `empty` | JourneyHome / SwiftData | Native capture; domain, API and UI tests cover behavior separately |
| My trips | `upcoming` | JourneyHome / SwiftData | Native capture; domain, API and UI tests cover behavior separately |
| My trips | `home` | JourneyHome / SwiftData | Native capture; domain, API and UI tests cover behavior separately |
| Add: trains and stations | `search` | TrainBrowser / AddJourneyFlow / native DatePicker and station sheet | Native capture; domain, API and UI tests cover behavior separately |
| Add: trains and stations | `date` | TrainBrowser / AddJourneyFlow / native DatePicker and station sheet | Native date control and add-form capture |
| Add: trains and stations | `stations` | TrainBrowser / AddJourneyFlow / native DatePicker and station sheet | Native capture; domain, API and UI tests cover behavior separately |
| Add: trains and stations | `boarding-picker` | TrainBrowser / AddJourneyFlow / native DatePicker and station sheet | Native capture; domain, API and UI tests cover behavior separately |
| Add: trains and stations | `alighting-picker` | TrainBrowser / AddJourneyFlow / native DatePicker and station sheet | Native capture; domain, API and UI tests cover behavior separately |
| Add: planning and travel | `departure` | AddJourneyFlow / native DatePicker and Stepper | Native capture; domain, API and UI tests cover behavior separately |
| Add: planning and travel | `travel` | AddJourneyFlow / native DatePicker and Stepper | Native capture; domain, API and UI tests cover behavior separately |
| Add: planning and travel | `review` | AddJourneyFlow / native DatePicker and Stepper | Native capture; domain, API and UI tests cover behavior separately |
| Add: connections | `add-transfer` | AddJourneyFlow / same-station and scheduled-time filtering | Native capture; domain, API and UI tests cover behavior separately |
| Add: connections | `transfer-unavailable` | AddJourneyFlow / same-station and scheduled-time filtering | Native capture; domain, API and UI tests cover behavior separately |
| Add: connections | `transfer-review` | AddJourneyFlow / same-station and scheduled-time filtering | Native capture; domain, API and UI tests cover behavior separately |
| Before departure, travel, waiting | `before` | Projection / JourneyHero / passenger confirmations | Native capture; domain, API and UI tests cover behavior separately |
| Before departure, travel, waiting | `onway` | Projection / JourneyHero / passenger confirmations | Native capture; domain, API and UI tests cover behavior separately |
| Before departure, travel, waiting | `waiting` | Projection / JourneyHero / passenger confirmations | Native capture; domain, API and UI tests cover behavior separately |
| Connection, next leg, arrival | `interchange` | Projection / Journey.advanceLeg / JourneyHero | Native capture; domain, API and UI tests cover behavior separately |
| Connection, next leg, arrival | `second-leg` | Projection / Journey.advanceLeg / JourneyHero | Native capture; domain, API and UI tests cover behavior separately |
| Connection, next leg, arrival | `complete` | Projection / Journey.advanceLeg / JourneyHero | Native capture; domain, API and UI tests cover behavior separately |
| Reference timetable and sync | `reference` | ReferenceSchedule / Projection.reconcile / schedule-choice entry | Native capture; domain, API and UI tests cover behavior separately |
| Reference timetable and sync | `manual-warning` | ReferenceSchedule / Projection.reconcile / schedule-choice entry | Native capture; domain, API and UI tests cover behavior separately |
| Reference timetable and sync | `sync` | ReferenceSchedule / Projection.reconcile / schedule-choice entry | Native capture; domain, API and UI tests cover behavior separately |
| Reference timetable and sync | `notification` | ReferenceSchedule / Projection.reconcile / schedule-choice entry | Local APNs mock checks deduplication; in-app sync entry; system banner needs device QA |
| Offline and data quality | `offline` | AppStore / NWPathMonitor / last valid snapshot / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Offline and data quality | `server-error` | AppStore / NWPathMonitor / last valid snapshot / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Offline and data quality | `stale-position` | AppStore / NWPathMonitor / last valid snapshot / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Offline and data quality | `recovered` | AppStore / NWPathMonitor / last valid snapshot / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Activity lifecycle | `pending-update` | ActivityManager / passenger confirmation / ActivityKit lifecycle | Native capture; domain, API and UI tests cover behavior separately |
| Activity lifecycle | `expired` | ActivityManager / passenger confirmation / ActivityKit lifecycle | Native capture; domain, API and UI tests cover behavior separately |
| Activity lifecycle | `activity-off` | ActivityManager / passenger confirmation / ActivityKit lifecycle | Native capture; domain, API and UI tests cover behavior separately |
| Dates, time zones, intermediate boarding | `midboard` | StationCall / ReferenceSchedule / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Dates, time zones, intermediate boarding | `crossday` | StationCall / ReferenceSchedule / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Dates, time zones, intermediate boarding | `timezone` | StationCall / ReferenceSchedule / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Dates, time zones, intermediate boarding | `no-position` | StationCall / ReferenceSchedule / TrainMap | Native capture; domain, API and UI tests cover behavior separately |
| Settings and management | `settings` | SettingsView / JourneyDetail menus and confirmation dialogs | Native capture; domain, API and UI tests cover behavior separately |
| Settings and management | `edit` | SettingsView / JourneyDetail menus and confirmation dialogs | Native capture; domain, API and UI tests cover behavior separately |
| Settings and management | `correct-stage` | SettingsView / JourneyDetail menus and confirmation dialogs | Native capture; domain, API and UI tests cover behavior separately |
| Settings and management | `end-confirm` | SettingsView / JourneyDetail menus and confirmation dialogs | Native capture; domain, API and UI tests cover behavior separately |
| Small screens and large text | `small-device` | Dynamic Type vertical layout / scrollable content / VoiceOver labels | Native narrow-container capture |
| Small screens and large text | `large-text` | Dynamic Type vertical layout / scrollable content / VoiceOver labels | Largest-text native capture; title, timer and timeline layout fixes |
| iPad landscape and windows | `ipad-detail` | NavigationSplitView / adaptive content width / add sheet | Native capture and iPad landscape UI test |
| iPad landscape and windows | `ipad-dark` | NavigationSplitView / adaptive content width / add sheet | Native capture; domain, API and UI tests cover behavior separately |
| iPad landscape and windows | `ipad-create` | NavigationSplitView / adaptive content width / add sheet | Native capture; domain, API and UI tests cover behavior separately |
| iPad landscape and windows | `ipad-narrow` | NavigationSplitView / adaptive content width / add sheet | Native narrow-container capture |
| iPhone and iPad Lock Screen | `lock-light` | JourneyLiveActivity / ActivitySummary | Shared content gallery; system Lock Screen needs device QA |
| iPhone and iPad Lock Screen | `lock-dark` | JourneyLiveActivity / ActivitySummary | Shared content gallery; system Lock Screen needs device QA |
| iPhone and iPad Lock Screen | `ipad-lock` | JourneyLiveActivity / ActivitySummary | Shared content gallery; system Lock Screen needs device QA |
| Live Activity states | `live-states` | JourneyLiveActivity / ActivitySummary | Shared content gallery; system Lock Screen needs device QA |
| Dynamic Island presentations | `islands` | DynamicIsland / IslandExpandedContent / IslandCompactTime | At this checkpoint unbuilt; shared previews cover narrow widths, long names and overlaps; system rendering needs device QA |
| Widgets | `widgets` | JourneyProvider / JourneyWidgetView / App Group | Small/medium content gallery and extension build; system timeline needs device QA |
| Visual and implementation rules | `foundation` | DesignSystem / TrackerCore / OpenAPI / RUNBOOK | Rules mapped to shared components and operations docs, without product pages |
| Visual and implementation rules | `architecture` | DesignSystem / TrackerCore / OpenAPI / RUNBOOK | Rules mapped to shared components and operations docs, without product pages |


Additional cases cover zero/negative connections, offline relaunch, token rotation/invalidation, old revisions, source 503/empty responses and ambiguous/nonexistent DST times. Captures show only the visible region, not every scrollable control or accessibility behavior.
