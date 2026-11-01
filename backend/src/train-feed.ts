import type { TrainSnapshot } from "./domain.ts";

// Consumers read the whole feed. One document per date avoids per-train writes.
// Merge within a date to retain trains missing from a subsequent upstream poll.
export function feedStatements(db: D1Database, trains: TrainSnapshot[], fetchedAt: string,
  guard: "source" | "test", owner: string): D1PreparedStatement[] {
  const dates = new Map<string, Record<string, TrainSnapshot>>();
  for (const train of trains) {
    const group = dates.get(train.originServiceDate) ?? {};
    group[train.id] = train;
    dates.set(train.originServiceDate, group);
  }
  const condition = guard === "source"
    ? "EXISTS(SELECT 1 FROM source_state WHERE id=1 AND lease_owner=?)"
    : "EXISTS(SELECT 1 FROM test_state WHERE id=1 AND write_token=?)";
  return [...dates].map(([date, snapshots]) => db.prepare(
    `INSERT INTO train_feeds(service_date,snapshots,fetched_at) SELECT ?,?,? WHERE ${condition}
     ON CONFLICT(service_date) DO UPDATE SET snapshots=json_patch(json_patch(train_feeds.snapshots,?),excluded.snapshots),
     fetched_at=excluded.fetched_at WHERE excluded.fetched_at>train_feeds.fetched_at`,
  // Remove replaced IDs first: recursive JSON merge must not retain old optional fields.
  ).bind(date, JSON.stringify(snapshots), fetchedAt, owner,
    JSON.stringify(Object.fromEntries(Object.keys(snapshots).map(id => [id, null])))));
}
