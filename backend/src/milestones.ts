import { epoch, project, resolvedJourney, stations, type Journey } from './domain.ts';
import { sendAPNs } from './apns.ts';
import type { DeliveryObservation, SubscriptionRow } from './service.ts';

type Milestone = { key: string; at: number; title: string; body: string };
export function dueMilestones(journey: Journey, now: number): Milestone[] {
  const events: Milestone[] = [];
  const t = (zh: string, en: string) => journey.notificationLanguage === "en" ? en : zh;
  const resolved = resolvedJourney(journey, now);
  const first = journey.legs[0];
  const leave = first.planningDeparture - journey.travelToStationMinutes * 60;
  events.push({ key: `leave:${first.id}`, at: leave, title: t('该出门了', "Time to leave"),
    body: t(`准备前往 ${stations(first).boarding?.name ?? first.boardingCode}，乘坐 VIA ${first.trainNumber}。`, `Head to ${stations(first).boarding?.name ?? first.boardingCode} for VIA ${first.trainNumber}.`) });
  journey.legs.forEach((leg, index) => {
    const { boarding, alighting } = stations(leg);
    const departure = epoch(boarding?.departure?.estimated) ?? epoch(boarding?.departure?.scheduled) ?? leg.planningDeparture;
    const arrival = epoch(alighting?.arrival?.estimated) ?? epoch(alighting?.arrival?.scheduled);
    const key = `${leg.id}:${leg.trainNumber}:${leg.originServiceDate}:${leg.boardingIndex}:${leg.alightingIndex}`;
    const destination = alighting?.name ?? leg.alightingCode;
    events.push({ key: `${key}:boarding`, at: departure - 900, title: t(`VIA ${leg.trainNumber} 即将发车`, `VIA ${leg.trainNumber} departs soon`),
      body: t(`距 ${boarding?.name ?? leg.boardingCode} 发车还有约 ${Math.max(1, Math.ceil((departure - now) / 60))} 分钟，请留意站内乘车信息。`, `About ${Math.max(1, Math.ceil((departure - now) / 60))} min until departure from ${boarding?.name ?? leg.boardingCode}. Check station boarding information.`) });
    if (index <= resolved.currentLegIndex) events.push({ key: `${key}:departed`, at: departure, title: t(`VIA ${leg.trainNumber} 已到发车时间`, `VIA ${leg.trainNumber} departure time`),
      body: t(`本段目的地：${destination}。祝旅途愉快！`, `Bound for ${destination}. Enjoy your trip!`) });
    const reached = index < resolved.currentLegIndex || (resolved.completed && index === journey.legs.length - 1);
    const reportedArrival = leg.source === 'official' && (alighting?.reached === true
      || (leg.snapshot.arrived && leg.alightingIndex === leg.snapshot.calls.at(-1)?.index));
    const observedAt = Math.min(now, epoch(leg.snapshot.sourceFetchedAt) ?? now);
    if (arrival !== undefined && !reached && index === resolved.currentLegIndex && now >= departure && now < arrival) {
      events.push({ key: `${key}:approaching`, at: Math.max(departure, arrival - 600),
        title: t(`即将到达 ${destination}`, `Approaching ${destination}`),
        body: t(`预计约 ${Math.max(1, Math.ceil((arrival - now) / 60))} 分钟后到达${index === journey.legs.length - 1 ? '目的地' : '换乘站'}，请准备好随身物品。`, `About ${Math.max(1, Math.ceil((arrival - now) / 60))} min until your ${index === journey.legs.length - 1 ? "destination" : "connection"}. Gather your belongings.`) });
    }
    for (const stop of leg.snapshot.calls) {
      if (stop.index <= leg.boardingIndex || stop.index >= leg.alightingIndex || index > resolved.currentLegIndex) continue;
      const stopArrival = epoch(stop.arrival?.estimated) ?? epoch(stop.arrival?.scheduled);
      const confirmed = leg.source === 'official' && stop.reached === true;
      if (!confirmed && stopArrival === undefined) continue;
      events.push({ key: `${key}:stop:${stop.index}:${stop.code}`, at: confirmed ? observedAt : stopArrival!,
        title: confirmed ? t(`已到达经停站 ${stop.name}`, `Reached ${stop.name}`) : t(`预计到达经停站 ${stop.name}`, `Estimated arrival at ${stop.name}`),
        body: t(`VIA ${leg.trainNumber} · 本段目的地：${destination}。`, `VIA ${leg.trainNumber} · Bound for ${destination}.`) });
    }
    if (arrival !== undefined && reached) events.push({ key: `${key}:arrived`, at: reportedArrival ? observedAt : arrival,
      title: index === journey.legs.length - 1 ? t(`欢迎来到 ${destination}`, `Welcome to ${destination}`) : t(`已到达 ${destination}`, `Arrived at ${destination}`),
      body: index === journey.legs.length - 1 ? t('本次行程已完成，记得带好随身物品。', "Your trip is complete. Remember your belongings.")
        : t(`准备换乘 VIA ${journey.legs[index + 1].trainNumber}，请留意下一段发车时间。`, `Connect to VIA ${journey.legs[index + 1].trainNumber}. Check the next departure time.`) });
  });
  return events.filter(event => event.at <= now);
}

export function initialMilestoneState(journey: Journey, now: number): string {
  return JSON.stringify({ seen: dueMilestones(journey, now).map(event => event.key) });
}

/** Separate from Live Activities: dismissing an island does not disable journey alerts. */
export async function deliverMilestones(env: Env, row: SubscriptionRow, journey: Journey,
  owner: string, now: number, observe?: (delivery: DeliveryObservation) => Promise<void>) {
  const due = dueMilestones(journey, now);
  const stored = row.milestone_state ? JSON.parse(row.milestone_state) as { seen: string[] } : undefined;
  const seen = new Set(stored?.seen ?? []);
  // Establish a baseline on registration/upgrade; never replay historical notifications.
  if (!stored || !row.push_token) due.forEach(event => seen.add(event.key));
  // Approaching remains useful throughout the ten-minute window. Other events
  // expire after five minutes; separate events must not silently consume each other.
  const pending = due.filter(event => !seen.has(event.key)
    && now - event.at <= (event.key.endsWith(':approaching') ? 600 : 300));
  const pendingKeys = new Set(pending.map(event => event.key));
  due.filter(item => !pendingKeys.has(item.key)).forEach(item => seen.add(item.key));
  const save = (revision: number | null = null) => env.DB.prepare('UPDATE subscriptions SET milestone_state=? WHERE id=? AND delivery_owner=? AND (? IS NULL OR revision=?)')
    .bind(JSON.stringify({ seen: [...seen] }), row.id, owner, revision, revision).run();
  const reserved = await save(row.revision);
  if (!reserved.meta.changes) return;
  for (const event of pending) {
    if (!row.push_token) break;
    // Recheck ownership/revision after each network suspension before another send.
    if (!(await save(row.revision)).meta.changes) return;
    const result = await sendAPNs(env, row.push_token, row.environment ?? 'sandbox', {
      aps: { alert: { title: event.title, body: event.body }, sound: 'default', 'thread-id': journey.id },
      journeyID: journey.id,
    }, false, 10, `${journey.id}:${event.key}`);
    if (result.ok) { seen.add(event.key); await save(); }
    else if (result.permanent) await env.DB.prepare('UPDATE installations SET push_token=NULL WHERE id=? AND push_token=?')
      .bind(row.installation_id, row.push_token).run();
    await observe?.({ installationID: row.installation_id, kind: 'notification', environment: row.environment ?? 'sandbox', ...result });
    if (result.permanent) return;
  }
  if (journey.pendingScheduleChange && !row.notification_state && row.push_token) {
    const result = await sendAPNs(env, row.push_token, row.environment ?? 'sandbox', {
      aps: { alert: { title: journey.notificationLanguage === 'en' ? 'Departure time changed' : '发车时间有变化', body: journey.notificationLanguage === 'en' ? 'Open your trip to review when to leave.' : '打开行程，看看是否需要调整出门时间。' }, sound: 'default', 'thread-id': journey.id },
      journeyID: journey.id,
    }, false, 10, `${journey.id}:schedule`);
    if (result.ok) await env.DB.prepare("UPDATE subscriptions SET notification_state='sent' WHERE id=? AND delivery_owner=?")
      .bind(row.id, owner).run();
    else if (result.permanent) await env.DB.prepare('UPDATE installations SET push_token=NULL WHERE id=? AND push_token=?')
      .bind(row.installation_id, row.push_token).run();
    await observe?.({ installationID: row.installation_id, kind: 'notification', environment: row.environment ?? 'sandbox', ...result });
  }
}

export async function deliverWidgets(env: Env, now: number, observe?: (delivery: DeliveryObservation) => Promise<void>) {
  const { results } = await env.DB.prepare(`SELECT i.id,i.widget_token,i.environment,i.widget_state,i.widget_sent_at,
    s.journey FROM installations i JOIN subscriptions s ON s.installation_id=i.id
    WHERE i.widget_token IS NOT NULL AND s.expires_at>? ORDER BY i.id,s.id`).bind(now)
    .all<{ id: string; widget_token: string; environment: string; widget_state: string | null; widget_sent_at: number; journey: string }>();
  const groups = new Map<string, typeof results>();
  for (const row of results) { const group = groups.get(row.id) ?? []; group.push(row); groups.set(row.id, group); }
  for (const group of groups.values()) {
    const row = group[0];
    const state = JSON.stringify(group.map(item => {
      const journey = JSON.parse(item.journey) as Journey;
      const s = project(journey, now);
      return [journey.id, s.phase, s.currentLegIndex, s.targetEpoch, s.progressStartEpoch,
        s.nextDepartureEpoch, s.reference, now > s.validUntilEpoch];
    }));
    if (row.widget_state === state && now - row.widget_sent_at < 900) continue;
    const claim = await env.DB.prepare('UPDATE installations SET widget_attempt_at=? WHERE id=? AND widget_token=? AND widget_attempt_at<?')
      .bind(now, row.id, row.widget_token, now - 55).run();
    if (!claim.meta.changes) continue;
    const result = await sendAPNs(env, row.widget_token, row.environment, { aps: { 'content-changed': true } }, 'widgets', 5, row.id);
    if (result.ok) await env.DB.prepare('UPDATE installations SET widget_state=?,widget_sent_at=? WHERE id=? AND widget_token=?')
      .bind(state, now, row.id, row.widget_token).run();
    else if (result.permanent) await env.DB.prepare('UPDATE installations SET widget_token=NULL WHERE id=? AND widget_token=?')
      .bind(row.id, row.widget_token).run();
    await observe?.({ installationID: row.id, kind: 'widget', environment: row.environment, ...result });
  }
}
