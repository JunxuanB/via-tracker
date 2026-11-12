# D1 write reduction — 31 October 2026

## Finding

The historical 24-hour metrics showed 24,684 production and 89,160 test row writes (113,844 total). That rolling interval differs from the account's daily quota interval. Production updated each train every minute; test refresh deleted and reinserted all trains, including index writes. Conditional HTTP responses still queried D1 before generating an ETag response.

Consult [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/) for current account limits. Reducing future writes does not recover an already exhausted quota.

## Storage change

`train_feeds` stores one JSON document per service date, keyed internally by train ID. Production merges returned trains and retains omitted trains for that date. Replacing each train object first removes optional fields that have disappeared; recursive merging must not preserve stale coordinates or estimates. Lease and freshness checks still apply.

Test heartbeats update date documents. Explicit edits/import/undo replace the test dataset so removed trains disappear correctly. Production removes dates older than 14 days. Documents have a 1.8 MB limit; exceeding it fails the transaction and retains the last valid snapshot.

Migration aggregates the old `trains` table without deleting it. Apply production `0004_train_feeds.sql` and test `0005_train_feeds.sql` before their Workers. Client contracts are unchanged.

## Historical verification

- Type checking and 33 tests passed.
- A local D1 run with 68 trains across four dates reported four snapshot row writes. This excludes leases, subscriptions and notifications and is not a production total.
- Migration equivalence, stale-lease rejection, clearing missing optional fields and retention of omitted trains were checked.
- Twelve local integration scenarios passed using existing VIA/APNs stand-ins, including failure/recovery, ETags, installation isolation, APNs retry and token invalidation.
- Test initialization/heartbeat/stale mode and both deployment dry runs passed.

## Deployment record

Private local database backups preceded deployment. Both migrations were applied with no pending migrations; the old tables remained.

| Worker | Historical version |
| --- | --- |
| Production | `945b825a-4b8b-42cd-aa42-447681f1345d` |
| Test | `ca444053-5710-4da9-a5e5-19fa1603672c` |

Both retained one-minute schedules. Production health/list/detail returned 200 and conditional reads 304. All 119 migrated production train objects matched the old table; test returned 67 trains. Cron runs succeeded and snapshot timestamps advanced. Long-term account usage still needs operational observation. Later validation supersedes these version IDs.
