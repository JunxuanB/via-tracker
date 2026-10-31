import { normalize } from "./normalize.ts";
import { boundedJSON } from "./http.ts";
import {
  project,
  reconcile,
  shouldPush,
  type Journey,
  type TrainSnapshot,
  type ActivityState,
} from "./domain.ts";
import { activityPayload, sendAPNs } from "./apns.ts";
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
  expires_at: number;
  updated_at: number;
  push_token?: string;
  environment?: string;
}
export async function allTrains(env: Env): Promise<TrainSnapshot[]> {
  const { results } = await env.DB.prepare(
    "SELECT snapshot FROM trains ORDER BY number, service_date",
  ).all<{ snapshot: string }>();
  return results.map((r) => JSON.parse(r.snapshot) as TrainSnapshot);
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
    const normalized = normalize(
      await boundedJSON(response, 8_000_000),
      fetchedAt,
      version,
    );
    const statements = normalized.map((t) =>
      env.DB.prepare(
        "INSERT INTO trains(id,number,service_date,snapshot,fetched_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM source_state WHERE lease_owner=?) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot,fetched_at=excluded.fetched_at WHERE excluded.fetched_at>trains.fetched_at",
      ).bind(
        t.id,
        t.trainNumber,
        t.originServiceDate,
        JSON.stringify(t),
        fetchedAt,
        owner,
      ),
    );
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
export async function processSubscriptions(env: Env): Promise<void> {
  const now = Math.floor(Date.now() / 1000),
    snapshots = await allTrains(env);
  const { results: rows } = await env.DB.prepare(
    "SELECT s.*,i.push_token,i.environment FROM subscriptions s JOIN installations i ON i.id=s.installation_id WHERE expires_at>?",
  )
    .bind(now)
    .all<SubscriptionRow>();
  // Sequential sends keep the first release below Workers connection limits; each row has its own delivery lease.
  for (const row of rows) {
    const deliveryOwner = crypto.randomUUID();
    const claimed = await env.DB.prepare(
      "UPDATE subscriptions SET delivery_lease_until=?,delivery_owner=? WHERE id=? AND revision=? AND delivery_lease_until<?",
    )
      .bind(now + 55, deliveryOwner, row.id, row.revision, now)
      .run();
    if (!claimed.meta.changes) continue;
    try {
      const j = reconcile(JSON.parse(row.journey) as Journey, snapshots);
      await env.DB.prepare(
        "UPDATE subscriptions SET journey=? WHERE id=? AND revision=?",
      )
        .bind(JSON.stringify(j), row.id, row.revision)
        .run();
      if (
        j.pendingScheduleChange &&
        !row.notification_state &&
        row.push_token
      ) {
        const result = await sendAPNs(
          env,
          row.push_token,
          row.environment ?? "sandbox",
          {
            aps: {
              alert: {
                title: "列车正式时刻已同步",
                body: "官方计划与规划时间不同，请打开行程选择是否同步。",
              },
              sound: "default",
            },
            journeyID: j.id,
          },
          false,
          10,
        );
        if (result.ok)
          await env.DB.prepare(
            "UPDATE subscriptions SET notification_state='sent' WHERE id=? AND revision=?",
          )
            .bind(row.id, row.revision)
            .run();
        else if (result.permanent)
          await env.DB.prepare(
            "UPDATE installations SET push_token=NULL WHERE id=?",
          )
            .bind(row.installation_id)
            .run();
      }
      if (!row.activity || j.trackingEnded) continue;
      const activity = JSON.parse(row.activity) as ActivitySession;
      if (now >= activity.startedAt + 28800) {
        await env.DB.prepare(
          "UPDATE subscriptions SET activity=NULL WHERE id=? AND revision=?",
        )
          .bind(row.id, row.revision)
          .run();
        continue;
      }
      const next = project(j, now),
        previous = row.last_sent
          ? (JSON.parse(row.last_sent) as ActivityState)
          : undefined;
      if (!shouldPush(previous, next, row.last_sent_at ?? 0, now)) continue;
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
        activityPayload(next, timestamp, j.completed),
        true,
        previous && previous.phase !== next.phase ? 10 : 5,
      );
      if (delivery.ok)
        await env.DB.prepare(
          "UPDATE subscriptions SET last_sent=?,last_sent_at=?,last_apns_timestamp=?,activity=CASE WHEN ? THEN NULL ELSE activity END WHERE id=? AND revision=? AND activity=?",
        )
          .bind(
            JSON.stringify(next),
            now,
            timestamp,
            j.completed ? 1 : 0,
            row.id,
            row.revision,
            row.activity,
          )
          .run();
      else if (delivery.permanent) {
        await env.DB.prepare(
          "UPDATE subscriptions SET activity=NULL WHERE id=? AND activity=?",
        )
          .bind(row.id, row.activity)
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
      await env.DB.prepare(
        "UPDATE subscriptions SET delivery_lease_until=0,delivery_owner=NULL WHERE id=? AND delivery_owner=?",
      )
        .bind(row.id, deliveryOwner)
        .run();
    }
  }
  await env.DB.batch([
    env.DB.prepare("DELETE FROM subscriptions WHERE expires_at<?").bind(now),
    env.DB.prepare(
      "DELETE FROM installations WHERE updated_at<? AND id NOT IN(SELECT installation_id FROM subscriptions)",
    ).bind(now - 90 * 86400),
    env.DB.prepare("DELETE FROM trains WHERE service_date<?").bind(
      new Date((now - 14 * 86400) * 1000).toISOString().slice(0, 10),
    ),
  ]);
}
