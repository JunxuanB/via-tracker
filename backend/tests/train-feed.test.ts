import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { normalize } from "../src/normalize.ts";
import { feedStatements } from "../src/train-feed.ts";
import type { TrainSnapshot } from "../src/domain.ts";

test("daily documents bound refresh writes, migrate losslessly, and fence obsolete publishers", async () => {
  const runtime = new Miniflare(convertV4MiniflareOptions({ modules: true, script: "export default {fetch(){return new Response('ok')}}",
    d1Databases: ["DB"], compatibilityDate: "2026-10-30" }));
  try {
    const db = await runtime.getD1Database("DB");
    const at = "2026-10-31T02:00:00Z";
    const trains = normalize(JSON.parse(readFileSync(new URL("../../contracts/fixtures/via-observed.json", import.meta.url), "utf8")), at, 1);
    // Apply the old schema and seed it before migration to exercise existing installations.
    const initial = readFileSync(new URL("../migrations/0001_initial.sql", import.meta.url), "utf8");
    for (const sql of initial.split(";").map(s => s.trim()).filter(Boolean)) await db.prepare(sql).run();
    await db.batch(trains.map(t => db.prepare("INSERT INTO trains VALUES(?,?,?,?,?)")
      .bind(t.id, t.trainNumber, t.originServiceDate, JSON.stringify(t), at)));
    const migration = readFileSync(new URL("../migrations/0004_train_feeds.sql", import.meta.url), "utf8");
    for (const sql of migration.replace(/--[^\n]*/g, "").split(";").map(s => s.trim()).filter(Boolean)) await db.prepare(sql).run();
    const read = async () => {
      const rows = await db.prepare("SELECT snapshots FROM train_feeds").all<{ snapshots: string }>();
      return rows.results.flatMap(r => Object.values(JSON.parse(r.snapshots) as Record<string, TrainSnapshot>));
    };
    assert.deepEqual((await read()).sort((a,b) => a.id.localeCompare(b.id)),
      [...trains].sort((a,b) => a.id.localeCompare(b.id)));
    await db.prepare("UPDATE source_state SET lease_owner='winner' WHERE id=1").run();
    const next = trains.map(t => ({ ...t, version: 2, sourceFetchedAt: "2026-10-31T02:01:00Z" }));
    const results = await db.batch(feedStatements(db, next, next[0].sourceFetchedAt, "source", "winner"));
    const writes = results.reduce((n, r) => n + r.meta.rows_written, 0);
    const dates = new Set(trains.map(t => t.originServiceDate)).size;
    assert.equal(results.length, dates);
    assert.ok(writes <= dates * 2, `daily refresh wrote ${writes} rows`);
    assert.ok(writes < trains.length / 2);
    const before = await read();
    const rejected = await db.batch(feedStatements(db, trains, "2026-10-31T02:02:00Z", "source", "loser"));
    assert.equal(rejected.reduce((n,r) => n + r.meta.changes, 0), 0);
    assert.deepEqual(await read(), before);
    // Replacement clears absent optional fields, while unrelated trains remain cached.
    const replacement = { ...next[0], sourceFetchedAt: "2026-10-31T02:03:00Z" };
    delete replacement.position;
    await db.batch(feedStatements(db, [replacement], replacement.sourceFetchedAt, "source", "winner"));
    const after = await read() as typeof trains;
    assert.equal(after.length, trains.length);
    assert.deepEqual(after.find(t => t.id === replacement.id), replacement);
    console.log(JSON.stringify({ trains: trains.length, dates, rowsWrittenPerRefresh: writes }));
  } finally { await runtime.dispose(); }
});
