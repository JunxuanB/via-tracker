import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { normalize } from "../src/normalize.ts";
import { validateJourney } from "../src/validation.ts";
import type { Journey, TrainSnapshot } from "../src/domain.ts";

const at = (time: string) => `2026-11-12T${time}:00-05:00`;
const stop = (code: string, time: string, extra: Record<string, unknown> = {}) => ({
  station: code, code, tz: "America/Toronto", scheduled: at(time), estimated: at(time), eta: "", ...extra,
});
const both = (code: string, time: string) =>
  stop(code, time, { arrival: { scheduled: at(time) }, departure: { scheduled: at(time) } });
const complete = () => ({
  "44": { instance: "2026-11-12", from: "A", to: "D", departed: false, arrived: false, times: [
    stop("A", "08:00", { departure: { scheduled: at("08:00") } }),
    both("B", "09:00"), both("C", "10:00"),
    stop("D", "11:00", { arrival: { scheduled: at("11:00") } }),
  ] },
});
const usable = (train: TrainSnapshot) => train.calls.some((b) => b.departure
  && train.calls.some((a) => a.index > b.index && a.arrival));

test("a stop published with an arrival only can still be boarded", () => {
  const raw = complete();
  for (const call of raw["44"].times) delete (call as { departure?: unknown }).departure;
  const [train] = normalize(raw, "2026-11-12T05:00:00Z", 2);
  assert.ok(usable(train));
  assert.equal(train.calls.length, 4);
  assert.equal(train.calls[0].departure?.scheduled, at("08:00"));
  assert.equal(train.calls[1].departure?.scheduled, at("09:00"));
  assert.equal(train.calls[3].departure, undefined, "a terminus never gains a departure");
  assert.equal(train.calls[0].arrival, undefined, "an origin never gains an arrival");
  assert.ok(train.qualityFlags?.includes("inferred_station_events"));
});

test("station-level times are used when both nested events are missing", () => {
  const raw = complete();
  raw["44"].times = raw["44"].times.map((call) => stop(call.code, call.scheduled.slice(11, 16)));
  const [train] = normalize(raw, "2026-11-12T05:00:00Z", 2);
  assert.equal(train.calls.length, 4);
  assert.ok(usable(train));
  assert.equal(train.calls[2].arrival?.scheduled, at("10:00"));
  assert.equal(train.calls[3].arrival?.scheduled, at("11:00"));
});

test("a degraded poll keeps the schedule an earlier poll already published", () => {
  const first = normalize(complete(), "2026-11-12T04:00:00Z", 1);
  const previous = new Map(first.map((train) => [train.id, train]));
  const raw = complete();
  // Upstream now lists B without any time and C with a later live arrival only.
  raw["44"].times[1] = { station: "B", code: "B", tz: "America/Toronto" } as never;
  raw["44"].times[2] = { station: "C", code: "C", tz: "America/Toronto",
    arrival: { scheduled: at("10:00"), estimated: at("10:20") } } as never;
  const [train] = normalize(raw, "2026-11-12T05:00:00Z", 2, { previous });
  assert.deepEqual(train.calls.map((call) => call.code), ["A", "B", "C", "D"]);
  assert.equal(train.calls[1].departure?.scheduled, at("09:00"));
  assert.equal(train.calls[2].departure?.scheduled, at("10:00"));
  assert.equal(train.calls[2].departure?.estimated, at("10:20"), "a retained departure follows the live delay");
  assert.ok(train.qualityFlags?.includes("retained_station_events"));
  assert.equal(train.version, 2);
});

test("a changed route is never patched with stops from the old one", () => {
  const previous = new Map(normalize(complete(), "2026-11-12T04:00:00Z", 1).map((train) => [train.id, train]));
  const raw = complete();
  raw["44"].times.splice(1, 1);
  const [train] = normalize(raw, "2026-11-12T05:00:00Z", 2, { previous });
  assert.deepEqual(train.calls.map((call) => call.code), ["A", "C", "D"]);
  assert.ok(!train.qualityFlags?.includes("retained_station_events"));
});

test("the observed feed is unchanged by repair and client snapshots are not repaired", () => {
  const raw = JSON.parse(readFileSync(new URL("../../contracts/fixtures/via-observed.json", import.meta.url), "utf8"));
  const strict = normalize(raw, "2026-10-31T02:00:00Z", 1, { repair: false });
  const repaired = normalize(raw, "2026-10-31T02:00:00Z", 1);
  const events = (trains: TrainSnapshot[]) => trains.map((train) => train.calls.map((call) =>
    [call.index, call.arrival?.scheduled, call.departure?.scheduled]));
  // Complete records pass through untouched: only missing sides are ever filled in.
  for (const [i, train] of strict.entries())
    for (const [n, call] of train.calls.entries()) {
      const fixed = repaired[i].calls[n];
      if (call.arrival) assert.deepEqual(fixed.arrival, call.arrival);
      if (call.departure) assert.deepEqual(fixed.departure, call.departure);
    }
  assert.equal(events(repaired).length, events(strict).length);
  const journey = JSON.parse(readFileSync(new URL("../../contracts/fixtures/demo-journey.json", import.meta.url), "utf8")) as Journey;
  const validated = validateJourney(journey);
  assert.deepEqual(validated.legs[0].snapshot.calls.map((call) => [!!call.arrival, !!call.departure]),
    journey.legs[0].snapshot.calls.map((call) => [!!call.arrival, !!call.departure]));
});
