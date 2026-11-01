import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dueMilestones, initialMilestoneState, deliverMilestones } from '../src/milestones.ts';
import type { Journey } from '../src/domain.ts';
import type { SubscriptionRow } from '../src/service.ts';

const base = 1_800_000_000;
const iso = (offset: number) => new Date((base + offset) * 1000).toISOString();
function journey(): Journey {
  return { id: 'journey', title: 'Trip', createdAt: base - 3600, travelToStationMinutes: 30,
    currentLegIndex: 0, completed: false, trackingEnded: false, syncChoice: 'keep',
    pendingScheduleChange: false, scheduleChangePrompted: false,
    legs: [{ id: 'leg', trainNumber: '64', originServiceDate: '2027-01-15', boardingCode: 'A',
      boardingIndex: 0, alightingCode: 'C', alightingIndex: 2, planningDeparture: base,
      source: 'official', snapshot: { id: 'train', trainNumber: '64', originServiceDate: '2027-01-15',
        rawKey: '64', from: 'A', to: 'C', departed: false, arrived: false,
        sourceFetchedAt: iso(-60), version: 1, alerts: [], calls: [
          { index: 0, code: 'A', name: 'Origin', timeZone: 'UTC', departure: { scheduled: iso(0) } },
          { index: 1, code: 'B', name: 'Stop', timeZone: 'UTC', arrival: { scheduled: iso(1200) } },
          { index: 2, code: 'C', name: 'Destination', timeZone: 'UTC', arrival: { scheduled: iso(1800) } },
        ] } }] };
}
test('departure, approaching, intermediate stop, and destination have distinct events', () => {
  const j = journey();
  assert.ok(dueMilestones(j, base).some(e => e.key.endsWith(':departed')));
  const approach = dueMilestones(j, base + 1200);
  assert.ok(approach.some(e => e.key.endsWith(':approaching')));
  assert.ok(approach.some(e => e.key.endsWith(':stop:1:B')));
  const arrived = dueMilestones(j, base + 1800);
  assert.ok(arrived.some(e => e.key.endsWith(':arrived')));
  assert.ok(!arrived.some(e => e.key.endsWith(':approaching')));
});
test('ETA changes move approach window and confirmed early arrival supersedes it', () => {
  const j = journey();
  j.legs[0].snapshot.calls[2].arrival!.estimated = iso(2400);
  assert.ok(!dueMilestones(j, base + 1200).some(e => e.key.endsWith(':approaching')));
  assert.ok(dueMilestones(j, base + 1800).some(e => e.key.endsWith(':approaching')));
  j.legs[0].snapshot.calls[2].reached = true;
  j.legs[0].snapshot.sourceFetchedAt = iso(1810);
  const events = dueMilestones(j, base + 1810);
  assert.ok(events.some(e => e.key.endsWith(':arrived') && e.at === base + 1810));
  assert.ok(!events.some(e => e.key.endsWith(':approaching')));
});
test('stops outside selected segment do not notify', () => {
  const j = journey(); j.legs[0].boardingIndex = 1; j.legs[0].boardingCode = 'B';
  assert.ok(!dueMilestones(j, base + 1200).some(e => e.key.includes(':stop:')));
});
test('delivery without an activity preserves events after registration, retries, and deduplicates', async () => {
  const j = journey();
  const row = { id: j.id, installation_id: 'device', revision: 1, activity: null,
    milestone_state: initialMilestoneState(j, base - 30), push_token: 'token', environment: 'sandbox',
  } as SubscriptionRow;
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const key = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  let persisted = row.milestone_state;
  const db = { prepare: () => ({ bind: (state: string) => ({ run: async () => {
    persisted = state; return { meta: { changes: 1 } };
  } }) }) };
  const env = { DB: db, APNS_PRIVATE_KEY: key, APNS_TEAM_ID: 'team', APNS_KEY_ID: 'key', APNS_BUNDLE_ID: 'app' } as unknown as Env;
  const original = globalThis.fetch;
  const sent: string[] = [];
  let fail = true;
  globalThis.fetch = async (_url, options) => {
    sent.push(JSON.parse(String(options?.body)).aps.alert.title);
    return new Response(fail ? '{"reason":"ServiceUnavailable"}' : null, { status: fail ? 503 : 200 });
  };
  async function deliver(offset: number) {
    row.milestone_state = persisted;
    await deliverMilestones(env, row, j, 'owner', base + offset);
  }
  try {
    await deliver(10);
    assert.equal(sent.length, 1); // First poll must not swallow departure.
    fail = false;
    await deliver(60);
    assert.equal(sent.length, 2); // Failed delivery remains retryable.
    await deliver(90);
    assert.equal(sent.length, 2);
    await deliver(1200);
    assert.equal(sent.length, 4); // Stop and approaching must both survive.
    await deliver(1260);
    assert.equal(sent.length, 4);
    await deliver(1800);
    assert.equal(sent.length, 5);
    await deliver(1860);
    assert.equal(sent.length, 5);
  } finally { globalThis.fetch = original; }
});
test('registration mid-trip baselines historical events but leaves future arrival eligible', () => {
  const j = journey();
  const baseline = JSON.parse(initialMilestoneState(j, base + 1260)).seen as string[];
  assert.ok(baseline.some(key => key.endsWith(':departed')));
  assert.ok(baseline.some(key => key.endsWith(':approaching')));
  assert.ok(baseline.some(key => key.endsWith(':stop:1:B')));
  assert.ok(!baseline.some(key => key.endsWith(':arrived')));
});
test('confirmed stop arriving later than its ETA uses the report time', () => {
  const j = journey();
  j.legs[0].snapshot.calls[2].arrival!.estimated = iso(3000);
  j.legs[0].snapshot.calls[1].reached = true;
  j.legs[0].snapshot.sourceFetchedAt = iso(1600);
  const stop = dueMilestones(j, base + 1600).find(e => e.key.endsWith(':stop:1:B'));
  assert.equal(stop?.at, base + 1600);
  assert.equal(stop?.title, '已到达经停站 Stop');
});
