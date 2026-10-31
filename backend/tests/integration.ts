// Run against wrangler dev plus the checked-in Postman simulation, never production.
import assert from "node:assert/strict";
import { randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import type { Journey, TrainSnapshot } from "../src/domain.ts";
const base = "http://127.0.0.1:8787",
  simulation = "http://127.0.0.1:4010";
const sample = JSON.parse(
  readFileSync(
    new URL("../../contracts/fixtures/demo-journey.json", import.meta.url),
    "utf8",
  ),
) as Journey;
const accounts = [0, 1].map(() => ({
  id: randomUUID(),
  credential: randomBytes(32).toString("hex"),
  environment: "sandbox",
}));
async function request(
  path: string,
  method = "GET",
  body?: unknown,
  account = 0,
) {
  return fetch(base + path, {
    method,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${accounts[account].id}:${accounts[account].credential}`,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}
async function poll(predicate: () => Promise<boolean>) {
  for (let n = 0; n < 50; n++) {
    if (await predicate()) return;
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("timed_out");
}
const control = async (member: string, mode: string) => {
  const r = await fetch(`${simulation}/${member}/control?mode=${mode}`);
  assert.equal(r.status, 200);
};
interface Feed {
  sourceStatus: string;
  snapshotVersion: number;
  trains: TrainSnapshot[];
}
interface List {
  subscriptions: unknown[];
}
interface Delivery {
  topic: string;
  pushType: string;
  payload: {
    journeyID?: string;
    aps: {
      timestamp: number;
      event: string;
      "content-state": { phase: string };
    };
  };
}
async function decoded<T>(r: Response): Promise<T> {
  return (await r.json()) as T;
}
const subscriptions = async (account = 0) =>
  decoded<List>(await request("/v1/subscriptions", "GET", undefined, account));
let deliveryOffset = 0;
const deliveriesNow = async () =>
  (await decoded<Delivery[]>(await fetch(simulation + "/apns/deliveries"))).slice(deliveryOffset);
const feed = async () => {
  const r = await request("/v1/trains");
  assert.equal(r.status, 200);
  return decoded<Feed>(r);
};
await control("via", "healthy");
deliveryOffset = (await deliveriesNow()).length;
const previousVersion = (await feed()).snapshotVersion;
await request("/__scheduled");
await poll(async () => {
  const x = await feed();
  return x.sourceStatus === "healthy" && x.snapshotVersion > previousVersion;
});
await new Promise((r) => setTimeout(r, 250));
const initial = await feed();
assert.ok(initial.trains.length > 20);
const cached = await request("/v1/trains");
assert.equal(
  (
    await fetch(base + "/v1/trains", {
      headers: { "if-none-match": cached.headers.get("etag")! },
    })
  ).status,
  304,
);
assert.equal(
  (await fetch(base + "/v1/trains", {
    headers: { "if-none-match": `"older", W/${cached.headers.get("etag")!}` },
  })).status,
  304,
  "A weak validator returned by Cloudflare compression must still match",
);
for (let i = 0; i < accounts.length; i++)
  assert.equal(
    (await request("/v1/installations", "POST", accounts[i], i)).status,
    201,
  );
const j = structuredClone(sample);
j.id = randomUUID();
j.createdAt = Math.floor(Date.now() / 1000);
const body = {
  journey: j,
  revision: 1,
  activity: {
    id: "test-session",
    token: "aa".repeat(32),
    startedAt: Math.floor(Date.now() / 1000),
    revision: 1,
  },
};
assert.equal((await request("/v1/subscriptions", "POST", body)).status, 201);
assert.equal(
  (await request("/v1/subscriptions", "GET", undefined, 1)).status,
  200,
);
assert.equal((await subscriptions(1)).subscriptions.length, 0);
assert.equal(
  (await request(`/v1/subscriptions/${j.id}`, "PATCH", body, 1)).status,
  404,
);
assert.equal(
  (await request(`/v1/subscriptions/${j.id}`, "DELETE", undefined, 1)).status,
  204,
);
assert.equal((await subscriptions()).subscriptions.length, 1);
assert.equal(
  (await request("/v1/subscriptions", "POST", { ...body, revision: 2 })).status,
  200,
);
assert.equal((await request("/v1/subscriptions", "POST", body)).status, 409);
const invalid = structuredClone(j);
invalid.legs.push({ ...invalid.legs[0], id: "wrong-station" });
assert.equal(
  (
    await request("/v1/subscriptions", "POST", {
      journey: invalid,
      revision: 3,
    })
  ).status,
  400,
);
await control("via", "failure");
await request("/__scheduled");
await poll(async () => (await feed()).sourceStatus === "unavailable");
const failure = await feed();
assert.equal(failure.snapshotVersion, initial.snapshotVersion);
assert.equal(failure.trains.length, initial.trains.length);
await control("via", "empty");
await request("/__scheduled");
await new Promise((r) => setTimeout(r, 500));
assert.equal((await feed()).snapshotVersion, initial.snapshotVersion);
await control("apns", "failure");
const beforeFailure = (await deliveriesNow()).length;
await request("/v1/subscriptions", "POST", {
  ...body,
  revision: 3,
  activity: { ...body.activity, token: "bb".repeat(32), revision: 2 },
});
await control("via", "healthy");
await request("/__scheduled");
await poll(
  async () => (await feed()).snapshotVersion > initial.snapshotVersion,
);
await poll(async () => {
  return (await deliveriesNow()).length > beforeFailure;
});
assert.equal(
  (await subscriptions()).subscriptions.length,
  1,
  "APNs failure must retain subscription",
);
await control("apns", "healthy");
const beforeRetry = (await deliveriesNow()).length;
await request("/v1/subscriptions", "POST", {
  ...body,
  revision: 4,
  activity: { ...body.activity, token: "cc".repeat(32), revision: 3 },
});
await new Promise((r) => setTimeout(r, 500));
await poll(async () => {
  await request("/__scheduled");
  await new Promise((r) => setTimeout(r, 300));
  return (await deliveriesNow()).length > beforeRetry;
});
const deliveries = await deliveriesNow();
assert.ok(
  deliveries.every(
    (d: { topic: string; pushType: string }) =>
      d.topic === "com.junxuanb.viatracker.push-type.liveactivity" &&
      d.pushType === "liveactivity",
  ),
);
const rotated = deliveries
  .filter((d) => d.pushType === "liveactivity")
  .slice(-3);
for (let i = 1; i < rotated.length; i++)
  assert.ok(
    rotated[i].payload.aps.timestamp >= rotated[i - 1].payload.aps.timestamp,
    "APNs timestamps cannot regress",
  );
await control("apns", "invalid");
const beforeInvalid = (await deliveriesNow()).length;
await request("/v1/subscriptions", "POST", {
  ...body,
  revision: 5,
  activity: { ...body.activity, token: "dd".repeat(32), revision: 4 },
});
await request("/__scheduled");
await poll(async () => (await deliveriesNow()).length > beforeInvalid);
await new Promise((r) => setTimeout(r, 300));
const afterInvalid = (await deliveriesNow()).length;
await request("/__scheduled");
await new Promise((r) => setTimeout(r, 300));
assert.equal(
  (await deliveriesNow()).length,
  afterInvalid,
  "410 invalidates the old activity token",
);
await control("apns", "healthy");
await request("/v1/subscriptions", "POST", {
  ...body,
  revision: 6,
  activity: {
    ...body.activity,
    token: "ee".repeat(32),
    revision: 5,
    startedAt: Math.floor(Date.now() / 1000) - 28801,
  },
});
await request("/__scheduled");
await new Promise((r) => setTimeout(r, 500));
assert.equal(
  (await deliveriesNow()).length,
  afterInvalid,
  "expired 8-hour activity receives no further update",
);
assert.equal(
  (await request(`/v1/subscriptions/${j.id}`, "DELETE")).status,
  204,
);
const official = initial.trains.find(
  (t) =>
    t.trainNumber === "38" &&
    t.calls.some((c) => c.departure) &&
    t.calls.some((c) => c.arrival),
)!;
assert.ok(official);
const b = official.calls.find((c) => c.departure)!,
  a = official.calls.findLast((c) => c.arrival)!;
const matching = structuredClone(sample);
matching.id = randomUUID();
matching.legs = [
  {
    ...matching.legs[0],
    trainNumber: official.trainNumber,
    originServiceDate: official.originServiceDate,
    boardingCode: b.code,
    boardingIndex: b.index,
    alightingCode: a.code,
    alightingIndex: a.index,
    source: "reference",
    planningDeparture: Date.parse(b.departure!.scheduled) / 1000 - 600,
    snapshot: { ...official, version: 0 },
  },
];
assert.equal(
  (
    await request("/v1/installations", "PATCH", {
      environment: "sandbox",
      pushToken: "11".repeat(32),
    })
  ).status,
  200,
);
const matched = await request("/v1/subscriptions", "POST", {
  journey: matching,
  revision: 1,
});
assert.equal(matched.status, 201);
const matchedBody = await decoded<{ journey: Journey }>(matched);
assert.equal(matchedBody.journey.legs[0].source, "official");
assert.equal(matchedBody.journey.pendingScheduleChange, true);
await request("/__scheduled");
await poll(async () =>
  (await deliveriesNow()).some(
    (d) => d.pushType === "alert" && d.payload.journeyID === matching.id,
  ),
);
await request("/__scheduled");
await new Promise((r) => setTimeout(r, 300));
assert.equal(
  (await deliveriesNow()).filter(
    (d) => d.pushType === "alert" && d.payload.journeyID === matching.id,
  ).length,
  1,
  "formal match should notify once",
);
await request(`/v1/subscriptions/${matching.id}`, "DELETE");
assert.equal(
  (await request(`/v1/subscriptions/${j.id}`, "DELETE")).status,
  204,
);
console.log(
  JSON.stringify({
    passed: true,
    sourceCount: initial.trains.length,
    deliveries: deliveries.length,
    scenarios: [
      "ETag",
      "installation isolation",
      "revision conflict",
      "station validation",
      "VIA 503",
      "empty VIA",
      "APNs retry",
      "token rotation and invalidation",
      "monotonic APNs timestamps",
      "eight-hour expiration",
      "formal match and one-time notification",
      "idempotent delete",
    ],
  }),
);
