import { deliverMilestones, deliverWidgets } from "./milestones.ts";
import { normalize } from "./normalize.ts";
import { boundedJSON } from "./http.ts";
import { feedStatements } from "./train-feed.ts";
import {
  project,
  reconcile,
  shouldPush,
  stations,
  trackingStart,
  type Journey,
  type TrainSnapshot,
  type ActivityState,
} from "./domain.ts";
import { activityPayload, activityStartPayload, sendAPNs } from "./apns.ts";
import type { ActivitySession } from "./validation.ts";
export interface SourceState {
  version: number;
  fetched_at: string | null;
  status: string;
}
export interface SubscriptionRow {
  id: string;
  installation_id: string;
  revision: number;
  journey: string;
  activity: string | null;
  last_sent: string | null;
  last_sent_at: number | null;
  last_apns_timestamp: number;
  notification_state: string;
  milestone_state: string;
  expires_at: number;
  updated_at: number;
  push_token?: string;
  environment?: string;
  auto_start?: string | null;
  auto_start_sent_for?: number;
  activity_start_token?: string | null;
}
export async function allTrains(env: Env): Promise<TrainSnapshot[]> {
  const { results } = await env.DB.prepare(
    "SELECT snapshots FROM train_feeds ORDER BY service_date",
  ).all<{ snapshots: string }>();
  return results.flatMap((r) => Object.values(JSON.parse(r.snapshots) as Record<string, TrainSnapshot>))
    .sort((a, b) => a.trainNumber.localeCompare(b.trainNumber) || a.originServiceDate.localeCompare(b.originServiceDate));
}
/** Snapshots already stored for the service dates named in an upstream response. */
async function storedTrains(env: Env, raw: unknown): Promise<Map<string, TrainSnapshot>> {
  const dates = [...new Set(Object.values(raw as Record<string, unknown>).flatMap((value) => {
    const instance = (value as { instance?: unknown } | null)?.instance;
    return typeof instance === "string" && /^\d{4}-\d{2}-\d{2}$/.test(instance) ? [instance] : [];
  }))].slice(0, 30);
  const stored = new Map<string, TrainSnapshot>();
  if (!dates.length) return stored;
  const { results } = await env.DB.prepare(
    `SELECT snapshots FROM train_feeds WHERE service_date IN(${dates.map(() => "?").join(",")})`,
  ).bind(...dates).all<{ snapshots: string }>();
  for (const row of results)
    for (const train of Object.values(JSON.parse(row.snapshots) as Record<string, TrainSnapshot>))
      stored.set(train.id, train);
  return stored;
}
export async function refresh(env: Env): Promise<void> {
  const now = Date.now(),
    owner = crypto.randomUUID();
  const lock = await env.DB.prepare(
    "UPDATE source_state SET lease_until=?, lease_owner=? WHERE id=1 AND lease_until<?",
  )
    .bind(now + 55000, owner, now)
    .run();
  if (!lock.meta.changes) return;
  try {
    const response = await fetch(env.SOURCE_URL, {
      signal: AbortSignal.timeout(20000),
      headers: { "user-agent": "VIA-Tracker/1.0 (aggregated minute cache)" },
    });
    if (!response.ok) throw new Error("source_http_failure");
    const fetchedAt = new Date().toISOString(),
      version = Date.now();
    const raw = await boundedJSON(response, 8_000_000);
    if (raw && typeof raw === "object" && !Array.isArray(raw) && !Object.keys(raw).length) {
      // An empty object is a valid answer when upstream lists no train at all.
      // Stored schedules stay available and each journey reports its own data age.
      await env.DB.prepare(
        "UPDATE source_state SET fetched_at=?,status='healthy' WHERE id=1 AND lease_owner=?",
      ).bind(fetchedAt, owner).run();
      return;
    }
    const normalized = normalize(raw, fetchedAt, version, { previous: await storedTrains(env, raw) });
    const statements = feedStatements(env.DB, normalized, fetchedAt, "source", owner);
    statements.push(
      env.DB.prepare(
        "UPDATE source_state SET version=?,fetched_at=?,status='healthy' WHERE id=1 AND lease_owner=?",
      ).bind(version, fetchedAt, owner),
    );
    await env.DB.batch(statements);
  } catch {
    await env.DB.prepare(
      "UPDATE source_state SET status='unavailable' WHERE id=1 AND lease_owner=?",
    )
      .bind(owner)
      .run();
    console.error(JSON.stringify({ event: "source_refresh_failed" }));
  } finally {
    await env.DB.prepare(
      "UPDATE source_state SET lease_until=0,lease_owner=NULL WHERE id=1 AND lease_owner=?",
    )
      .bind(owner)
      .run();
  }
}
/**
 * A journey saved days ahead has no Live Activity yet. Once its tracking window
 * opens, ask the device to start one; the app then registers the new session.
 */
async function startActivity(env: Env, row: SubscriptionRow, journey: Journey, owner: string,
  now: number, observe?: (delivery: DeliveryObservation) => Promise<void>) {
  if (!row.auto_start || !row.activity_start_token) return;
  const window = trackingStart(journey);
  if (now < window || row.auto_start_sent_for === window) return;
  const state = project(journey, now);
  if (state.phase === "completed") return;
  const reserved = await env.DB.prepare(
    "UPDATE subscriptions SET auto_start_sent_for=? WHERE id=? AND revision=? AND delivery_owner=? AND activity IS NULL",
  ).bind(window, row.id, row.revision, owner).run();
  if (!reserved.meta.changes) return;
  let testSource: string | undefined;
  try {
    const value = (JSON.parse(row.auto_start) as { testSource?: unknown }).testSource;
    if (typeof value === "string") testSource = value;
  } catch { /* A malformed opt-in still starts a production activity. */ }
  const first = journey.legs[0], last = journey.legs.at(-1)!;
  const environment = row.environment ?? "sandbox";
  const result = await sendAPNs(env, row.activity_start_token, environment,
    activityStartPayload(state, now, journey.id, {
      title: "今天的行程已开始追踪",
      body: `VIA ${first.trainNumber} · ${stations(first).boarding?.name ?? first.boardingCode} → ${stations(last).alighting?.name ?? last.alightingCode}`,
    }, testSource), true, 10);
  await observe?.({ installationID: row.installation_id, kind: "activity", environment, ok: result.ok, reason: result.reason });
  if (result.ok) return;
  if (result.permanent)
    await env.DB.prepare("UPDATE installations SET activity_start_token=NULL WHERE id=? AND activity_start_token=?")
      .bind(row.installation_id, row.activity_start_token).run();
  // Let the next minute retry a transient failure.
  await env.DB.prepare("UPDATE subscriptions SET auto_start_sent_for=0 WHERE id=? AND delivery_owner=?")
    .bind(row.id, owner).run();
  console.warn(JSON.stringify({ event: "activity_start_failed", reason: result.reason }));
}
export interface DeliveryObservation {
  installationID: string;
  kind: "activity" | "notification" | "widget";
  environment: string;
  ok: boolean;
  reason?: string;
}
export async function processSubscriptions(env: Env, options?: {
  force?: boolean;
  onDelivery?: (delivery: DeliveryObservation) => Promise<void>;
}): Promise<void> {
  const now = Math.floor(Date.now() / 1000),
    snapshots = await allTrains(env);
  const { results: rows } = await env.DB.prepare(
    "SELECT s.*,i.push_token,i.environment,i.activity_start_token FROM subscriptions s JOIN installations i ON i.id=s.installation_id WHERE expires_at>?",
  )
    .bind(now)
    .all<SubscriptionRow>();
  // Sequential sends keep the first release below Workers connection limits; each row has its own delivery lease.
  for (const candidate of rows) {
    const deliveryOwner = crypto.randomUUID();
    const claimedAt = Math.floor(Date.now() / 1000);
    const claimed = await env.DB.prepare(
      "UPDATE subscriptions SET delivery_lease_until=?,delivery_owner=? WHERE id=? AND revision=? AND delivery_lease_until<?",
    )
      .bind(claimedAt + 55, deliveryOwner, candidate.id, candidate.revision, claimedAt)
      .run();
    if (!claimed.meta.changes) continue;
    let reminder: { row: SubscriptionRow; journey: Journey; now: number } | undefined;
    try {
      // A previous delivery can update this row without changing its client revision.
      const row = await env.DB.prepare(
        "SELECT s.*,i.push_token,i.environment,i.activity_start_token FROM subscriptions s JOIN installations i ON i.id=s.installation_id WHERE s.id=? AND s.delivery_owner=?",
      ).bind(candidate.id, deliveryOwner).first<SubscriptionRow>();
      if (!row) continue;
      const now = Math.floor(Date.now() / 1000);
      const j = reconcile(JSON.parse(row.journey) as Journey, snapshots);
      const updated = await env.DB.prepare(
        "UPDATE subscriptions SET journey=? WHERE id=? AND revision=? AND delivery_owner=?",
      )
        .bind(JSON.stringify(j), row.id, row.revision, deliveryOwner)
        .run();
      if (!updated.meta.changes || j.trackingEnded) continue;
      reminder = { row, journey: j, now };
      if (!row.activity) {
        await startActivity(env, row, j, deliveryOwner, now, options?.onDelivery);
        continue;
      }
      const activity = JSON.parse(row.activity) as ActivitySession;
      if (now >= activity.startedAt + 28800) {
        await env.DB.prepare(
          "UPDATE subscriptions SET activity=NULL WHERE id=? AND revision=? AND activity=? AND delivery_owner=?",
        )
          .bind(row.id, row.revision, row.activity, deliveryOwner)
          .run();
        continue;
      }
      const next = project(j, now),
        previous = row.last_sent
          ? (JSON.parse(row.last_sent) as ActivityState)
          : undefined;
      if (!options?.force && !shouldPush(previous, next, row.last_sent_at ?? 0, now)) continue;
      const timestamp = Math.max(now, row.last_apns_timestamp + 1);
      const reserved = await env.DB.prepare(
        "UPDATE subscriptions SET last_apns_timestamp=? WHERE id=? AND revision=? AND activity=? AND delivery_owner=? AND last_apns_timestamp<?",
      )
        .bind(
          timestamp,
          row.id,
          row.revision,
          row.activity,
          deliveryOwner,
          timestamp,
        )
        .run();
      if (!reserved.meta.changes) continue;
      const delivery = await sendAPNs(
        env,
        activity.token,
        row.environment ?? "sandbox",
        activityPayload(next, timestamp, next.phase === "completed"),
        true,
        options?.force || !previous || previous.phase !== next.phase || previous.currentLegIndex !== next.currentLegIndex ? 10 : 5,
        activity.id,
      );
      await options?.onDelivery?.({ installationID: row.installation_id, kind: "activity",
        environment: row.environment ?? "sandbox", ok: delivery.ok, reason: delivery.reason });
      if (delivery.ok)
        await env.DB.prepare(
          "UPDATE subscriptions SET last_sent=?,last_sent_at=?,activity=CASE WHEN ? THEN NULL ELSE activity END WHERE id=? AND revision=? AND activity=? AND delivery_owner=? AND last_apns_timestamp=?",
        )
          .bind(
            JSON.stringify(next),
            now,
            next.phase === "completed" ? 1 : 0,
            row.id,
            row.revision,
            row.activity,
            deliveryOwner,
            timestamp,
          )
          .run();
      else if (delivery.permanent) {
        await env.DB.prepare(
          "UPDATE subscriptions SET activity=NULL WHERE id=? AND activity=? AND delivery_owner=?",
        )
          .bind(row.id, row.activity, deliveryOwner)
          .run();
        console.warn(
          JSON.stringify({
            event: "apns_token_invalidated",
            reason: delivery.reason,
          }),
        );
      } else
        console.warn(
          JSON.stringify({
            event: "apns_delivery_failed",
            reason: delivery.reason,
          }),
        );
    } catch {
      console.error(
        JSON.stringify({ event: "subscription_processing_failed" }),
      );
    } finally {
      // Prioritize the island's phase transition; alerts have an independent failure path.
      if (reminder) {
        try {
          await deliverMilestones(env, reminder.row, reminder.journey, deliveryOwner, reminder.now, options?.onDelivery);
        } catch { console.error(JSON.stringify({ event: "milestone_delivery_failed" })); }
      }
      await env.DB.prepare(
        "UPDATE subscriptions SET delivery_lease_until=0,delivery_owner=NULL WHERE id=? AND delivery_owner=?",
      )
        .bind(candidate.id, deliveryOwner)
        .run();
    }
  }
  try { await deliverWidgets(env, Math.floor(Date.now() / 1000), options?.onDelivery); }
  catch { console.error(JSON.stringify({ event: "widget_delivery_failed" })); }
  await env.DB.batch([
    env.DB.prepare("DELETE FROM subscriptions WHERE expires_at<?").bind(now),
    env.DB.prepare(
      "DELETE FROM installations WHERE updated_at<? AND id NOT IN(SELECT installation_id FROM subscriptions)",
    ).bind(now - 90 * 86400),
    env.DB.prepare("DELETE FROM train_feeds WHERE service_date<?").bind(
      new Date((now - 14 * 86400) * 1000).toISOString().slice(0, 10),
    ),
  ]);
}
