import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes, randomUUID } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { Miniflare, convertV4MiniflareOptions } from "miniflare";
import { route } from "../src/index.ts";
import { processSubscriptions } from "../src/service.ts";
import { trackingStart, TRACKING_LEAD_SECONDS, type Journey } from "../src/domain.ts";

const iso = (epoch: number) => new Date(epoch * 1000).toISOString();
function journey(departure: number): Journey {
  return { id: randomUUID(), title: "", createdAt: departure - 86400, travelToStationMinutes: 30,
    currentLegIndex: 0, completed: false, trackingEnded: false, syncChoice: "keep",
    pendingScheduleChange: false, scheduleChangePrompted: false,
    legs: [{ id: randomUUID(), trainNumber: "64", originServiceDate: iso(departure).slice(0, 10), boardingCode: "A",
      boardingIndex: 0, alightingCode: "C", alightingIndex: 1, planningDeparture: departure,
      source: "reference", snapshot: { id: `64:${iso(departure).slice(0, 10)}`, trainNumber: "64",
        originServiceDate: iso(departure).slice(0, 10), rawKey: "64", from: "A", to: "C", departed: false,
        arrived: false, sourceFetchedAt: iso(departure - 86400), version: 0, alerts: [], calls: [
          { index: 0, code: "A", name: "Origin", timeZone: "UTC", departure: { scheduled: iso(departure) } },
          { index: 1, code: "C", name: "Destination", timeZone: "UTC", arrival: { scheduled: iso(departure + 7200) } },
        ] } }] };
}

test("tracking window opens five hours before the planned time to leave", () => {
  const j = journey(1_800_000_000);
  assert.equal(TRACKING_LEAD_SECONDS, 18000);
  assert.equal(trackingStart(j), 1_800_000_000 - 1800 - 18000);
});

test("a Live Activity is started remotely once, only inside the tracking window and only when opted in", async () => {
  const runtime = new Miniflare(convertV4MiniflareOptions({ modules: true, script: "export default {fetch(){return new Response('ok')}}",
    d1Databases: ["DB"], compatibilityDate: "2026-10-30" }));
  const original = globalThis.fetch;
  try {
    const db = await runtime.getD1Database("DB");
    const folder = new URL("../migrations/", import.meta.url);
    for (const file of readdirSync(folder).sort())
      for (const sql of readFileSync(new URL(file, folder), "utf8").replace(/--[^\n]*/g, "").split(";").map((s) => s.trim()).filter(Boolean))
        await db.prepare(sql).run();
    const limiter = { limit: async () => ({ success: true }) };
    const env = { DB: db, INSTALLATION_LIMITER: limiter, WRITE_LIMITER: limiter, APNS_BUNDLE_ID: "com.example.app",
      APNS_TEAM_ID: "TEAM", APNS_KEY_ID: "KEY", APNS_PROXY_URL: "",
      APNS_PRIVATE_KEY: generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" }) as string,
    } as unknown as Env;
    const account = { id: randomUUID(), credential: randomBytes(32).toString("hex"), environment: "production" };
    const call = (path: string, method: string, body?: unknown) => route(new Request("https://api.test" + path, {
      method, headers: { "content-type": "application/json", authorization: `Bearer ${account.id}:${account.credential}` },
      ...(body ? { body: JSON.stringify(body) } : {}) }), env);
    assert.equal((await call("/v1/installations", "POST", account)).status, 201);
    assert.equal((await call("/v1/activity-start-token", "PUT", { token: "zz", environment: "production" }).catch((e) => e)).status, 400);
    assert.equal((await call("/v1/activity-start-token", "PUT", { token: "ab".repeat(32), environment: "sandbox" }).catch((e) => e)).status, 409);
    assert.equal((await call("/v1/activity-start-token", "PUT", { token: "ab".repeat(32), environment: "production" })).status, 200);

    const now = Math.floor(Date.now() / 1000);
    const today = journey(now + 3 * 3600), nextWeek = journey(now + 7 * 86400), manual = journey(now + 2 * 3600);
    assert.equal((await call("/v1/subscriptions", "POST", { journey: today, revision: 1, autoStart: {} })).status, 201);
    assert.equal((await call("/v1/subscriptions", "POST", { journey: nextWeek, revision: 1, autoStart: {} })).status, 201);
    assert.equal((await call("/v1/subscriptions", "POST", { journey: manual, revision: 1 })).status, 201);

    const pushes: { url: string; headers: Record<string, string>; body: any }[] = [];
    globalThis.fetch = async (url, options) => {
      pushes.push({ url: String(url), headers: options?.headers as Record<string, string>, body: JSON.parse(String(options?.body)) });
      return new Response(null, { status: 200 });
    };
    await processSubscriptions(env);
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.url, `https://api.push.apple.com/3/device/${"ab".repeat(32)}`);
    assert.equal(push.headers["apns-push-type"], "liveactivity");
    assert.equal(push.headers["apns-topic"], "com.example.app.push-type.liveactivity");
    assert.equal(push.body.aps.event, "start");
    assert.equal(push.body.aps["attributes-type"], "JourneyActivityAttributes");
    assert.deepEqual(push.body.aps.attributes, { journeyID: today.id, startedAt: push.body.aps.timestamp });
    assert.equal(push.body.aps["content-state"].phase, "beforeDeparture");
    assert.equal(push.body.aps["content-state"].targetEpoch, now + 3 * 3600 - 1800);
    assert.ok(push.body.aps.alert.title && push.body.aps.alert.body.includes("Origin → Destination"));
    assert.ok(new TextEncoder().encode(JSON.stringify(push.body)).length < 4096);

    await processSubscriptions(env);
    assert.equal(pushes.length, 1, "the same window is never started twice");

    // The app reports the session it was started with; from then on updates use that token.
    assert.equal((await call("/v1/subscriptions", "POST", { journey: today, revision: 2,
      activity: { id: "session", token: "cd".repeat(32), startedAt: now, revision: 1 } })).status, 200);
    await processSubscriptions(env);
    assert.equal(pushes.length, 2);
    assert.equal(pushes[1].body.aps.event, "update");
    assert.equal(pushes[1].url, `https://api.push.apple.com/3/device/${"cd".repeat(32)}`);
    const stored = await db.prepare("SELECT auto_start FROM subscriptions WHERE id=?").bind(today.id).first<{ auto_start: string | null }>();
    assert.equal(stored?.auto_start, null);

    // Two minutes before the eight-hour limit a fresh activity replaces the old one.
    assert.equal((await call("/v1/subscriptions", "POST", { journey: today, revision: 3,
      activity: { id: "session", token: "cd".repeat(32), startedAt: now - 28800 + 120, revision: 2 } })).status, 200);
    pushes.length = 0;
    await processSubscriptions(env);
    assert.deepEqual(pushes.map((p) => p.body.aps.event), ["start", "end"]);
    assert.ok(pushes[0].url.endsWith("ab".repeat(32)) && pushes[1].url.endsWith("cd".repeat(32)));
    const renewed = await db.prepare("SELECT activity FROM subscriptions WHERE id=?").bind(today.id).first<{ activity: string | null }>();
    assert.equal(renewed?.activity, null);
    await processSubscriptions(env);
    assert.equal(pushes.length, 2, "renewal happens once; the app registers the new session");
  } finally {
    globalThis.fetch = original;
    await runtime.dispose();
  }
});
