import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { project, reconcile, shouldPush, type Journey } from "../src/domain.ts";
import { normalize } from "../src/normalize.ts";
import { validateJourney } from "../src/validation.ts";
import { activityPayload } from "../src/apns.ts";
const cases = JSON.parse(
  readFileSync(
    new URL("../../contracts/fixtures/projections.json", import.meta.url),
    "utf8",
  ),
) as {
  name: string;
  journey: Journey;
  now: number;
  expectedPhase: string;
  expectedTarget: number;
  expectedWaiting: boolean;
  expectedConnectionMinutes?: number;
}[];
for (const c of cases)
  test(`shared: ${c.name}`, () => {
    const state = project(c.journey, c.now);
    assert.equal(state.phase, c.expectedPhase);
    assert.equal(state.targetEpoch, c.expectedTarget);
    assert.equal(state.waitingForUpdate, c.expectedWaiting);
    assert.ok(state.progress >= 0 && state.progress <= 1);
    if (c.expectedConnectionMinutes !== undefined)
      assert.equal(state.connectionMinutes, c.expectedConnectionMinutes);
    validateJourney(c.journey);
  });
test("real observation normalizes without inventing actual events", () => {
  const raw = JSON.parse(
    readFileSync(
      new URL("../../contracts/fixtures/via-observed.json", import.meta.url),
      "utf8",
    ),
  );
  const trains = normalize(raw, "2026-10-31T02:00:00Z", 1);
  assert.ok(trains.length > 20);
  const train = trains.find((t) => t.trainNumber === "38");
  assert.ok(train?.calls.some((s) => s.code === "OTTW"));
  assert.ok(trains.every((t) => !("actualArrival" in t)));
});
test("bad and empty source rejected; individual malformed records tolerated", () => {
  assert.throws(() => normalize({}, "", 1));
  assert.throws(() => normalize([], "", 1));
  const raw = JSON.parse(
    readFileSync(
      new URL("../../contracts/fixtures/via-observed.json", import.meta.url),
      "utf8",
    ),
  );
  raw.bad = {};
  assert.ok(normalize(raw, "2026-10-31T02:00:00Z", 1).length > 0);
});
test("only station event estimates used and absent estimate falls back", () => {
  const j = structuredClone(cases[3].journey);
  delete j.legs[0].snapshot.calls[2].arrival!.estimated;
  assert.equal(
    project(j, cases[3].now).targetEpoch,
    Date.parse(j.legs[0].snapshot.calls[2].arrival!.scheduled) / 1000,
  );
});
test("delay recovery, cumulative threshold and heartbeat", () => {
  const a = project(cases[3].journey, cases[3].now);
  assert.equal(
    shouldPush(a, { ...a, targetEpoch: a.targetEpoch + 30 }, 100, 120),
    false,
  );
  assert.equal(
    shouldPush(a, { ...a, targetEpoch: a.targetEpoch + 60 }, 100, 120),
    true,
  );
  assert.equal(
    shouldPush(a, { ...a, targetEpoch: a.targetEpoch - 60 }, 100, 120),
    true,
  );
  assert.equal(shouldPush(a, a, 100, 400), true);
});
test("formal match retains planning unless accepted and rejects missing stations", () => {
  const j = structuredClone(cases[0].journey);
  j.legs[0].source = "reference";
  j.legs[0].planningDeparture -= 600;
  const next = reconcile(j, [j.legs[0].snapshot]);
  assert.ok(next.pendingScheduleChange);
  assert.equal(next.legs[0].planningDeparture, j.legs[0].planningDeparture);
  const invalid = structuredClone(j.legs[0].snapshot);
  invalid.calls = [];
  assert.equal(reconcile(j, [invalid]).legs[0].source, "reference");
});
test("station codes, leg bounds, source identity and durations validated", () => {
  const j = structuredClone(cases[0].journey);
  j.legs.push({ ...j.legs[0], id: "second" });
  assert.throws(() => validateJourney(j));
  j.legs.pop();
  j.travelToStationMinutes = 1;
  assert.throws(() => validateJourney(j));
  j.travelToStationMinutes = 30;
  j.currentLegIndex = 5;
  assert.throws(() => validateJourney(j));
});
test("negative connection and payload remains bounded", () => {
  const j = structuredClone(cases[3].journey);
  const next = structuredClone(j.legs[0]);
  next.id = "next";
  next.boardingCode = "OTTW";
  next.boardingIndex = 2;
  next.snapshot.calls[2].departure = { scheduled: "2026-11-06T18:30:00-05:00" };
  j.legs.push(next);
  const p = project(j, cases[3].now);
  assert.equal(p.connectionMinutes, -12);
  assert.ok(Buffer.byteLength(JSON.stringify(activityPayload(p, 100))) < 4096);
});
test("same train number on another service date and old responses cannot replace selected instance", () => {
  const j = structuredClone(cases[3].journey),
    other = structuredClone(j.legs[0].snapshot);
  other.originServiceDate = "2026-11-07";
  other.id = "44:2026-11-07";
  other.version += 100;
  assert.deepEqual(reconcile(j, [other]), j);
  other.originServiceDate = j.legs[0].originServiceDate;
  other.version = 0;
  assert.deepEqual(reconcile(j, [other]), j);
});
test("malformed events and duplicate station indices rejected", () => {
  const j = structuredClone(cases[0].journey);
  j.legs[0].snapshot.calls[1].index = 0;
  assert.throws(() => validateJourney(j));
  j.legs[0].snapshot.calls[1].index = 1;
  j.legs[0].snapshot.calls[1].timeZone = "Invalid/Zone";
  assert.throws(() => validateJourney(j));
});
