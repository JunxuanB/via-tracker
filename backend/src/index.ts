import { initialMilestoneState } from "./milestones.ts";
import { APIError, boundedJSON, obj, str, int, json, sha256 } from "./http.ts";
import { validateJourney, validateActivity } from "./validation.ts";
import {
  allTrains,
  refresh,
  processSubscriptions,
  type SourceState,
  type SubscriptionRow,
} from "./service.ts";
import { reconcile, type Journey } from "./domain.ts";
import { sendAPNs } from "./apns.ts";
import { timingSafeEqual } from "node:crypto";

function decodePath(value: string): string {
  try { return decodeURIComponent(value); }
  catch { throw new APIError(400, "invalid_path"); }
}

function searchText(value: string): string {
  return value.normalize("NFD").replace(/\p{M}/gu, "").toLocaleLowerCase().trim()
    .replace(/quebec city|ville de quebec/g, "quebec");
}

export async function authenticate(request: Request, env: Env): Promise<string> {
  const authorization = request.headers
    .get("authorization")
    ?.match(/^Bearer ([^:]+):(.+)$/);
  if (!authorization) throw new APIError(401, "unauthorized");
  const [, id, secret] = authorization;
  const hash = await sha256(secret);
  // Lookup by both ID and hash avoids exposing either credential in logs or application comparisons.
  const row = await env.DB.prepare(
    "SELECT id FROM installations WHERE id=? AND credential_hash=?",
  )
    .bind(id, hash)
    .first<{ id: string }>();
  if (!row) throw new APIError(401, "unauthorized");
  if (
    request.method !== "GET" &&
    !(await env.WRITE_LIMITER.limit({ key: id })).success
  )
    throw new APIError(429, "rate_limited");
  return id;
}
export async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url),
    path = url.pathname,
    method = request.method;
  if (method === "POST" && path.startsWith("/internal/")) {
    const provided =
      request.headers.get("authorization")?.replace(/^Bearer /, "") ?? "";
    const expected = env.OPS_TOKEN;
    if (
      !expected ||
      !timingSafeEqual(
        new TextEncoder().encode(await sha256(provided)),
        new TextEncoder().encode(await sha256(expected)),
      )
    )
      throw new APIError(401, "unauthorized");
    if (path === "/internal/refresh") {
      await refresh(env);
      await processSubscriptions(env);
      return json({ ok: true });
    }
    if (path === "/internal/apns-probe") {
      const result = await sendAPNs(
        env,
        "0".repeat(64),
        "sandbox",
        {
          aps: {
            timestamp: Math.floor(Date.now() / 1000),
            event: "update",
            "content-state": {},
          },
        },
        true,
      );
      return json({
        transportResponded: result.reason !== "transport_failure",
        reason: result.reason ?? "accepted",
      });
    }
    throw new APIError(404, "not_found");
  }
  if (path === "/health" && method === "GET") return json({ status: "ok", schemaVersion: 1 });
  if (
    method === "GET" &&
    (path === "/v1/trains" || path.startsWith("/v1/trains/"))
  ) {
    const source = await env.DB.prepare(
      "SELECT version,fetched_at,status FROM source_state WHERE id=1",
    ).first<SourceState>();
    const snapshots = await allTrains(env);
    const q = searchText(url.searchParams.get("q") ?? ""),
      date = url.searchParams.get("originServiceDate");
    let trains = snapshots.filter(
      (t) =>
        (!date || t.originServiceDate === date) &&
        (!q ||
          t.trainNumber.includes(q) ||
          t.calls.some((s) => searchText(`${s.name} ${s.code}`).includes(q))),
    );
    if (path.startsWith("/v1/trains/")) {
      trains = snapshots.filter(
        (t) => t.id === decodePath(path.slice("/v1/trains/".length)),
      );
      if (!trains.length) throw new APIError(404, "train_not_found");
    }
    const stale =
      !source?.fetched_at ||
      Date.now() - Date.parse(source.fetched_at) > 600000;
    const body = {
      schemaVersion: 1,
      snapshotVersion: source?.version ?? 0,
      sourceFetchedAt: source?.fetched_at ?? null,
      sourceStatus: !source?.fetched_at ? "unavailable" : stale ? "stale" : source.status,
      availableServiceDates: [
        ...new Set(snapshots.map((t) => t.originServiceDate)),
      ].sort(),
      trains,
    };
    const etag = '"' + (await sha256(JSON.stringify(body))) + '"';
    // Cloudflare may weaken ETags when compressing the response. GET validators
    // use weak comparison, so either representation still identifies this snapshot.
    if (
      request.headers
        .get("if-none-match")
        ?.split(",")
        .some((value) => value.trim() === "*" || value.trim().replace(/^W\//, "") === etag)
    )
      return new Response(null, {
        status: 304,
        headers: { etag, "cache-control": "public,max-age=15" },
      });
    return json(body, 200, { etag, "cache-control": "public,max-age=15" });
  }
  if (path === "/v1/installations" && method === "POST") {
    if (
      !(
        await env.INSTALLATION_LIMITER.limit({
          key: request.headers.get("cf-connecting-ip") ?? "local",
        })
      ).success
    )
      throw new APIError(429, "rate_limited");
    const body = obj(await boundedJSON(request)),
      id = str(body.id, 100),
      credential = str(body.credential, 128);
    if (!/^[a-fA-F0-9]{64}$/.test(credential))
      throw new APIError(400, "invalid_credential");
    const environment = body.environment;
    if (environment !== "sandbox" && environment !== "production")
      throw new APIError(400, "invalid_environment");
    await env.DB.prepare(
      "INSERT OR IGNORE INTO installations(id,credential_hash,environment,updated_at) VALUES(?,?,?,?)",
    )
      .bind(
        id,
        await sha256(credential),
        environment,
        Math.floor(Date.now() / 1000),
      )
      .run();
    const owner = await authenticate(
      new Request(request.url, {
        headers: { authorization: `Bearer ${id}:${credential}` },
      }),
      env,
    );
    await env.DB.prepare(
      "UPDATE installations SET push_token=CASE WHEN environment=? THEN push_token ELSE NULL END,widget_token=CASE WHEN environment=? THEN widget_token ELSE NULL END,activity_start_token=CASE WHEN environment=? THEN activity_start_token ELSE NULL END,environment=?,updated_at=? WHERE id=?",
    )
      .bind(environment, environment, environment, environment, Math.floor(Date.now() / 1000), owner)
      .run();
    return json({ id: owner }, 201);
  }
  const owner = await authenticate(request, env);
  if (path === "/v1/widget-token" && (method === "PUT" || method === "DELETE")) {
    if (method === "DELETE") {
      await env.DB.prepare("UPDATE installations SET widget_token=NULL,widget_state=NULL WHERE id=?").bind(owner).run();
    } else {
      const body = obj(await boundedJSON(request)), token = str(body.token, 512);
      if (!/^[a-fA-F0-9]{32,512}$/.test(token) || token.length % 2) throw new APIError(400, "invalid_push_token");
      if (body.environment !== "sandbox" && body.environment !== "production") throw new APIError(400, "invalid_environment");
      const updated = await env.DB.prepare("UPDATE installations SET widget_state=CASE WHEN widget_token=? THEN widget_state ELSE NULL END,widget_token=? WHERE id=? AND environment=?")
        .bind(token, token, owner, body.environment).run();
      if (!updated.meta.changes) throw new APIError(409, "environment_mismatch");
    }
    return json({ id: owner });
  }
  if (path === "/v1/activity-start-token" && (method === "PUT" || method === "DELETE")) {
    if (method === "DELETE") {
      await env.DB.prepare("UPDATE installations SET activity_start_token=NULL WHERE id=?").bind(owner).run();
    } else {
      const body = obj(await boundedJSON(request)), token = str(body.token, 512);
      if (!/^[a-fA-F0-9]{32,512}$/.test(token) || token.length % 2) throw new APIError(400, "invalid_push_token");
      if (body.environment !== "sandbox" && body.environment !== "production") throw new APIError(400, "invalid_environment");
      const updated = await env.DB.prepare("UPDATE installations SET activity_start_token=? WHERE id=? AND environment=?")
        .bind(token, owner, body.environment).run();
      if (!updated.meta.changes) throw new APIError(409, "environment_mismatch");
    }
    return json({ id: owner });
  }
  if (path === "/v1/installations" && method === "PATCH") {
    const body = obj(await boundedJSON(request)),
      token = body.pushToken == null ? null : str(body.pushToken, 512);
    if (token && (!/^[a-fA-F0-9]{32,512}$/.test(token) || token.length % 2))
      throw new APIError(400, "invalid_push_token");
    const environment = body.environment;
    if (environment !== "sandbox" && environment !== "production")
      throw new APIError(400, "invalid_environment");
    await env.DB.prepare(
      "UPDATE installations SET push_token=?,widget_token=CASE WHEN environment=? THEN widget_token ELSE NULL END,activity_start_token=CASE WHEN environment=? THEN activity_start_token ELSE NULL END,environment=?,updated_at=? WHERE id=?",
    )
      .bind(token, environment, environment, environment, Math.floor(Date.now() / 1000), owner)
      .run();
    return json({ id: owner });
  }
  if (path === "/v1/subscriptions" && method === "GET") {
    const { results } = await env.DB.prepare(
      "SELECT * FROM subscriptions WHERE installation_id=?",
    )
      .bind(owner)
      .all<SubscriptionRow>();
    return json({
      subscriptions: results.map((r) => ({
        id: r.id,
        revision: r.revision,
        journey: JSON.parse(r.journey),
      })),
    });
  }
  const item = path.match(/^\/v1\/subscriptions\/([^/]+)$/)?.[1];
  if (item && method === "DELETE") {
    await env.DB.prepare(
      "DELETE FROM subscriptions WHERE id=? AND installation_id=?",
    )
      .bind(decodePath(item), owner)
      .run();
    return new Response(null, { status: 204 });
  }
  if (
    (path === "/v1/subscriptions" && method === "POST") ||
    (item && method === "PATCH")
  ) {
    const body = obj(await boundedJSON(request, 1_500_000)),
      revision = int(body.revision, 1, 2e9);
    let journey = validateJourney(body.journey);
    const activity = validateActivity(body.activity),
      id = journey.id;
    // Opt-in to a remote Live Activity start; a running session makes it moot.
    let autoStart: string | null = null;
    if (body.autoStart != null && !activity) {
      const source = obj(body.autoStart).testSource;
      autoStart = JSON.stringify(source == null ? {} : { testSource: str(source, 300) });
    }
    if (item && decodePath(item) !== id)
      throw new APIError(400, "id_mismatch");
    const existing = await env.DB.prepare(
      "SELECT * FROM subscriptions WHERE id=?",
    )
      .bind(id)
      .first<SubscriptionRow>();
    if (existing && existing.installation_id !== owner)
      throw new APIError(404, "subscription_not_found");
    if (existing && existing.revision > revision)
      throw new APIError(409, "old_revision");
    if (existing && existing.revision === revision)
      return json({ id, revision, journey: JSON.parse(existing.journey) });
    journey = reconcile(journey, await allTrains(env));
    const lastLeg = journey.legs.at(-1)!,
      expires = Math.floor(
        Math.max(
          Date.now() / 1000 + 86400,
          ...lastLeg.snapshot.calls.flatMap((s) =>
            s.arrival ? [Date.parse(s.arrival.scheduled) / 1000 + 86400] : [],
          ),
        ),
      );
    const activityJSON = activity ? JSON.stringify(activity) : null;
    await env.DB.prepare(
      "INSERT INTO subscriptions(id,installation_id,revision,journey,activity,expires_at,updated_at,milestone_state,auto_start) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,journey=excluded.journey,activity=excluded.activity,expires_at=excluded.expires_at,updated_at=excluded.updated_at,auto_start=excluded.auto_start,last_sent=CASE WHEN subscriptions.activity IS excluded.activity THEN subscriptions.last_sent ELSE NULL END WHERE subscriptions.installation_id=excluded.installation_id AND excluded.revision>subscriptions.revision",
    )
      .bind(
        id,
        owner,
        revision,
        JSON.stringify(journey),
        activityJSON,
        expires,
        Date.now(),
        initialMilestoneState(journey, Math.floor(Date.now() / 1000)),
        autoStart,
      )
      .run();
    // The preflight read may race another write; acknowledge only the stored winner.
    const stored = await env.DB.prepare("SELECT * FROM subscriptions WHERE id=?")
      .bind(id).first<SubscriptionRow>();
    if (!stored || stored.installation_id !== owner)
      throw new APIError(404, "subscription_not_found");
    if (stored.revision > revision) throw new APIError(409, "old_revision");
    return json({ id, revision: stored.revision, journey: JSON.parse(stored.journey) }, existing ? 200 : 201);
  }
  throw new APIError(404, "not_found");
}
export default {
  async fetch(request, env, ctx) {
    try {
      const response = await route(request, env);
      if (
        response.ok &&
        new URL(request.url).pathname.startsWith("/v1/subscriptions") &&
        ["POST", "PATCH"].includes(request.method)
      )
        ctx.waitUntil(processSubscriptions(env));
      return response;
    } catch (e) {
      if (e instanceof APIError)
        return json({ error: { code: e.code } }, e.status,
          e.status === 429 ? { "retry-after": "60" } : undefined);
      console.error(JSON.stringify({ event: "request_failed" }));
      return json({ error: { code: "internal_error" } }, 500);
    }
  },
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(
      (async () => {
        await refresh(env);
        await processSubscriptions(env);
      })(),
    );
  },
} satisfies ExportedHandler<Env>;
