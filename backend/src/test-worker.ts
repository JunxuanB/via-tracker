import { authenticate, route } from './index.ts';
import { APIError, boundedJSON, json, obj, sha256 } from './http.ts';
import { normalize } from './normalize.ts';
import { processSubscriptions, type DeliveryObservation } from './service.ts';
import { sendAPNs } from './apns.ts';
import { seed, validate, editTrain, modes, type Feed, type Mode } from './test-data.ts';
import sample from '../../contracts/fixtures/via-observed.json';

type State = { raw: string | null; mode: Mode; revision: number; last_action: string; last_read: string | null; feed_reads: number };
const codeFor = async (id: string) => (await sha256(id)).slice(0, 8).toUpperCase();
async function readState(env: Env): Promise<State> {
  const state = await env.DB.prepare('SELECT * FROM test_state WHERE id=1').first<State>();
  if (!state) throw new Error('test_database_not_initialized');
  if (state.raw) return state;
  await saveState(env, state, seed(sample as Feed), 'healthy', '初始化', false);
  return (await env.DB.prepare('SELECT * FROM test_state WHERE id=1').first<State>())!;
}
/** One D1 transaction: a losing editor cannot publish snapshots from an obsolete draft. */
async function saveState(env: Env, old: State, raw: Feed, mode: Mode, action: string, history = true, heartbeat = false) {
  const token = crypto.randomUUID();
  const revision = heartbeat ? old.revision : Math.max(Date.now(), old.revision + 1);
  const fetched = new Date(Date.now() - (mode === 'stale' ? 1_200_000 : 0)).toISOString();
  const version = Date.now();
  const statements = [env.DB.prepare('UPDATE test_state SET raw=?,mode=?,revision=?,last_action=?,write_token=? WHERE id=1 AND revision=?')
    .bind(JSON.stringify(raw), mode, revision, action, token, old.revision)];
  if (history && old.raw) statements.push(env.DB.prepare('INSERT OR REPLACE INTO test_history(revision,raw,mode) SELECT ?,?,? WHERE EXISTS(SELECT 1 FROM test_state WHERE write_token=?)')
    .bind(old.revision, old.raw, old.mode, token));
  if (mode === 'healthy' || mode === 'stale') {
    const trains = normalize(raw, fetched, version);
    statements.push(env.DB.prepare('DELETE FROM trains WHERE EXISTS(SELECT 1 FROM test_state WHERE write_token=?)').bind(token));
    for (const train of trains) statements.push(env.DB.prepare('INSERT INTO trains(id,number,service_date,snapshot,fetched_at) SELECT ?,?,?,?,? WHERE EXISTS(SELECT 1 FROM test_state WHERE write_token=?)')
      .bind(train.id, train.trainNumber, train.originServiceDate, JSON.stringify(train), fetched, token));
    statements.push(env.DB.prepare('UPDATE source_state SET version=?,fetched_at=?,status=? WHERE id=1 AND EXISTS(SELECT 1 FROM test_state WHERE write_token=?)')
      .bind(version, fetched, mode, token));
  } else {
    statements.push(env.DB.prepare("UPDATE source_state SET status='unavailable' WHERE id=1 AND EXISTS(SELECT 1 FROM test_state WHERE write_token=?)").bind(token));
  }
  statements.push(env.DB.prepare('DELETE FROM test_history WHERE revision NOT IN(SELECT revision FROM test_history ORDER BY revision DESC LIMIT 20)'));
  const results = await env.DB.batch(statements);
  if (!results[0].meta.changes) throw new APIError(409, 'revision_conflict');
  return revision;
}
async function observe(env: Env, delivery: DeliveryObservation) {
  await env.DB.prepare('INSERT INTO test_deliveries(id,device_code,kind,accepted,reason,sent_at,environment) VALUES(?,?,?,?,?,?,?)')
    .bind(crypto.randomUUID(), await codeFor(delivery.installationID), delivery.kind, delivery.ok ? 1 : 0,
      delivery.reason ?? null, Date.now(), delivery.environment).run();
}
async function deliver(env: Env, force = false) {
  await processSubscriptions(env, { force, onDelivery: delivery => observe(env, delivery) });
  await env.DB.prepare('DELETE FROM test_deliveries WHERE sent_at<?').bind(Date.now() - 7 * 86400000).run();
}
async function summary(env: Env, state: State) {
  const { results } = await env.DB.prepare('SELECT id,push_token IS NOT NULL AS notification_ready,environment,updated_at,(SELECT count(*) FROM subscriptions s WHERE s.installation_id=i.id AND s.activity IS NOT NULL) AS activities FROM installations i ORDER BY updated_at DESC LIMIT 100')
    .all<{ id: string; notification_ready: number; environment: string; updated_at: number; activities: number }>();
  const devices = await Promise.all(results.map(async device => ({ code: await codeFor(device.id),
    notifications: !!device.notification_ready, activities: device.activities, environment: device.environment,
    updatedAt: device.updated_at })));
  const logs = await env.DB.prepare('SELECT device_code,kind,accepted,reason,sent_at,environment FROM test_deliveries ORDER BY sent_at DESC LIMIT 30').all();
  return { mode: state.mode, revision: state.revision, lastRead: state.last_read, feedReads: state.feed_reads,
    lastAction: state.last_action, public: true, pushConfigured: !!(env.APNS_PRIVATE_KEY && env.APNS_TEAM_ID && env.APNS_KEY_ID), devices, deliveries: logs.results };
}
async function handle(request: Request, env: Cloudflare.TestEnv, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(request.url), path = url.pathname;
  if (path === '/health') return json({ status: 'ok', schemaVersion: 1, environment: 'test', remotePush: true,
    pushConfigured: !!(env.APNS_PRIVATE_KEY && env.APNS_TEAM_ID && env.APNS_KEY_ID) });
  if (path.startsWith('/internal/')) throw new APIError(404, 'not_found');
  const state = path.startsWith('/control') || path.startsWith('/v1/trains') || path.startsWith('/data/')
    ? await readState(env) : undefined;
  if (request.method === 'GET' && (path === '/control/state' || path === '/control/status')) {
    const status = await summary(env, state!);
    return json(path.endsWith('/state') ? { ...status, raw: JSON.parse(state!.raw!),
      undoCount: (await env.DB.prepare('SELECT count(*) AS count FROM test_history').first<{ count: number }>())?.count ?? 0 } : status);
  }
  if (request.method === 'GET' && path === '/control/export') return json(JSON.parse(state!.raw!), 200,
    { 'content-disposition': 'attachment; filename="via-public-test-data.json"' });
  if (request.method === 'POST' && path.startsWith('/control')) {
    // The panel is deliberately public. Same-origin and size checks prevent accidental cross-site writes.
    if (request.headers.get('origin') && request.headers.get('origin') !== url.origin) throw new APIError(403, 'cross_origin_denied');
    if (request.headers.get('x-via-test') !== '1' || !request.headers.get('content-type')?.startsWith('application/json')) throw new APIError(400, 'invalid_control_request');
    if (!(await env.WRITE_LIMITER.limit({ key: 'panel:' + (request.headers.get('cf-connecting-ip') ?? 'local') })).success) throw new APIError(429, 'rate_limited');
    const input = obj(await boundedJSON(request, 1_500_000));
    if (path === '/control/push') {
      ctx.waitUntil(deliver(env, true));
      return json({ ok: true, message: '已请求推送，请查看下方记录。' });
    }
    if (path === '/control/notify') {
      const { results } = await env.DB.prepare('SELECT id,push_token,environment FROM installations WHERE push_token IS NOT NULL').all<{ id: string; push_token: string; environment: string }>();
      const choices = await Promise.all(results.map(async row => ({ row, code: await codeFor(row.id) })));
      const target = choices.find(item => item.code === String(input.code).toUpperCase())?.row;
      if (!target) throw new APIError(404, 'device_not_ready');
      const result = await sendAPNs(env, target.push_token, target.environment, {
        aps: { alert: { title: 'VIA Tracker · 测试通知', body: '公网测试通知已送达。打开 App 查看测试行程。' }, sound: 'default' },
        testSource: url.origin,
      }, false, 10);
      await observe(env, { installationID: target.id, kind: 'notification', environment: target.environment, ok: result.ok, reason: result.reason });
      if (result.permanent) await env.DB.prepare('UPDATE installations SET push_token=NULL WHERE id=? AND push_token=?').bind(target.id, target.push_token).run();
      return json({ ok: result.ok, message: result.ok ? 'Apple 已接收，是否显示请在设备确认。' : `Apple 未接收：${result.reason ?? 'unknown'}` });
    }
    if (path !== '/control') throw new APIError(404, 'not_found');
    if (input.revision !== state!.revision) throw new APIError(409, 'revision_conflict');
    let raw: Feed = JSON.parse(state!.raw!), mode = state!.mode;
    const action = String(input.action);
    let undoRevision: number | undefined;
    if (action === 'reset') { raw = seed(sample as Feed); mode = 'healthy'; }
    else if (action === 'import') raw = validate(input.raw);
    else if (action === 'mode') {
      if (!modes.includes(input.mode as Mode)) throw new APIError(400, 'invalid_mode');
      mode = input.mode as Mode;
    } else if (action === 'undo') {
      const previous = await env.DB.prepare('SELECT * FROM test_history ORDER BY revision DESC LIMIT 1').first<{ raw: string; mode: Mode; revision: number }>();
      if (!previous) throw new APIError(400, 'nothing_to_undo');
      raw = JSON.parse(previous.raw); mode = previous.mode; undoRevision = previous.revision;
    } else raw = editTrain(raw, input);
    const revision = await saveState(env, state!, raw, mode, action, action !== 'undo');
    if (undoRevision !== undefined) await env.DB.prepare('DELETE FROM test_history WHERE revision=?').bind(undoRevision).run();
    ctx.waitUntil(deliver(env));
    return json({ ok: true, revision });
  }
  if (path === '/v1/test-device') {
    const owner = await authenticate(request, env);
    if (request.method === 'DELETE') {
      await env.DB.batch([env.DB.prepare('DELETE FROM subscriptions WHERE installation_id=?').bind(owner),
        env.DB.prepare('UPDATE installations SET push_token=NULL WHERE id=?').bind(owner)]);
      return new Response(null, { status: 204 });
    }
    return json({ code: await codeFor(owner) });
  }
  if (path.startsWith('/v1/trains') || path === '/data/allData.json') {
    ctx.waitUntil(env.DB.prepare('UPDATE test_state SET last_read=?,feed_reads=feed_reads+1 WHERE id=1').bind(new Date().toISOString()).run());
    if (state!.mode === 'failure') throw new APIError(503, 'test_source_unavailable');
    if (path === '/data/allData.json') return json(state!.mode === 'empty' ? {} : JSON.parse(state!.raw!));
    if (state!.mode === 'empty') return json({ schemaVersion: 1, snapshotVersion: Date.now(), sourceFetchedAt: new Date().toISOString(), sourceStatus: 'healthy', availableServiceDates: [], trains: [] });
  }
  if (path.startsWith('/v1/')) {
    const response = await route(request, env);
    if (response.ok && path.startsWith('/v1/subscriptions') && ['POST', 'PATCH'].includes(request.method)) ctx.waitUntil(deliver(env));
    const headers = new Headers(response.headers); headers.set('cache-control', 'no-store');
    return new Response(response.body, { status: response.status, headers });
  }
  return env.TEST_ASSETS.fetch(request);
}
export default {
  async fetch(request, env, ctx) {
    try {
      const response = await handle(request, env, ctx);
      const headers = new Headers(response.headers);
      headers.set('X-VIA-Test-Data', 'true'); headers.set('X-Content-Type-Options', 'nosniff');
      headers.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
      return new Response(response.body, { status: response.status, headers });
    } catch (error) {
      if (error instanceof APIError) return json({ error: { code: error.code,
        message: error.code === 'revision_conflict' ? '数据已更新，请保存草稿后刷新页面。' : error.code } }, error.status);
      console.error(JSON.stringify({ event: 'test_console_request_failed' }));
      return json({ error: { code: 'test_data_invalid', message: '数据无法保存，请检查车次字段、坐标和带时区的时间。' } }, 400);
    }
  },
  async scheduled(_controller, env, ctx) {
    ctx.waitUntil((async () => {
      const state = await readState(env);
      try { await saveState(env, state, JSON.parse(state.raw!), state.mode, state.last_action, false, true); }
      catch (error) { if (!(error instanceof APIError && error.status === 409)) throw error; }
      await deliver(env);
    })());
  },
} satisfies ExportedHandler<Cloudflare.TestEnv>;
