/** Local-only data sandbox. It reuses the production normalizer, but has no DB, credentials or APNs. */
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { readFile } from 'node:fs/promises';
import { hostname, networkInterfaces } from 'node:os';
import { normalize } from '../../src/normalize.ts';

import { seed, validate, editTrain, modes, type Feed, type Mode } from '../../src/test-data.ts';
const arg = (key: string, fallback: string) => {
  const index = process.argv.indexOf(key);
  return index < 0 ? fallback : process.argv[index + 1] ?? fallback;
};
const host = arg('--host', '127.0.0.1');
const port = Number(arg('--port', '4318'));
if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('Port must be between 1024 and 65535');
const sample: Feed = JSON.parse(await readFile(new URL('../../../contracts/fixtures/via-synthetic.json', import.meta.url), 'utf8'));
const staticFiles = new Map(await Promise.all([
  ['/', 'index.html', 'text/html; charset=utf-8'],
  ['/app.js', 'app.js', 'text/javascript; charset=utf-8'],
  ['/style.css', 'style.css', 'text/css; charset=utf-8'],
].map(async ([path, file, contentType]) => [path, { body: await readFile(new URL(file, import.meta.url)), contentType }] as const)));
const allowedHosts = new Set(['localhost', '127.0.0.1', '[::1]', hostname().toLowerCase(), hostname().toLowerCase() + '.local', host.toLowerCase()]);
for (const addresses of Object.values(networkInterfaces())) {
  for (const address of addresses ?? []) allowedHosts.add(address.address.toLowerCase());
}
let raw: Feed = seed(sample);
let mode: Mode = 'healthy';
let revision = Date.now();
let lastRead: string | null = null;
let feedReads = 0;
let lastAction = '已加载示例车次，均从现在起约 20 分钟后发车';
let undo: { raw: Feed; mode: Mode }[] = [];
const iso = (value: number) => new Date(value).toISOString();
function checkpoint() {
  undo.push({ raw: structuredClone(raw), mode });
  if (undo.length > 20) undo.shift();
}
function mutate(body: Record<string, unknown>) {
  const action = String(body.action);
  if (action === 'undo') {
    const previous = undo.pop();
    if (!previous) throw new Error('没有可撤销的修改');
    raw = previous.raw; mode = previous.mode;
  } else if (action === 'reset') {
    checkpoint(); raw = seed(sample); mode = 'healthy';
  } else if (action === 'mode') {
    if (!modes.includes(body.mode as Mode)) throw new Error('未知数据状态');
    checkpoint(); mode = body.mode as Mode;
  } else if (action === 'import') {
    const next = validate(body.raw); checkpoint(); raw = next;
  } else {
    const next = editTrain(raw, body); checkpoint(); raw = next;
  }
  revision = Math.max(revision + 1, Date.now());
  lastAction = action;
}
async function body(req: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = []; let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 8 * 1024 * 1024) throw new Error('数据不能超过 8 MB');
    chunks.push(Buffer.from(chunk));
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
function send(res: ServerResponse, status: number, value: unknown) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(value));
}
const server = createServer(async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-VIA-Test-Data', 'true');
  res.setHeader('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
  try {
    const url = new URL(req.url ?? '/', 'http://' + req.headers.host);
    if (!allowedHosts.has(url.hostname.toLowerCase())) return send(res, 403, { error: { code: 'invalid_host' } });
    if (req.headers.origin && req.headers.origin !== url.origin) return send(res, 403, { error: { code: 'cross_origin_denied' } });
    if (req.method === 'POST' && url.pathname === '/control') {
      if (req.headers['x-via-test'] !== '1' || !req.headers['content-type']?.startsWith('application/json')) return send(res, 403, { error: { code: 'invalid_control_request' } });
      const input = await body(req);
      if (input.revision !== revision) return send(res, 409, { error: { code: 'revision_conflict', message: '数据已被另一个页面修改，请复制未保存内容后刷新页面。' } });
      mutate(input);
      return send(res, 200, { ok: true, revision });
    }
    if (req.method !== 'GET') return send(res, 405, { error: { code: 'test_feed_is_read_only' } });
    if (url.pathname === '/control/state') return send(res, 200, { raw, mode, revision, lastRead, feedReads, lastAction, undoCount: undo.length });
    if (url.pathname === '/control/status') return send(res, 200, { mode, revision, lastRead, feedReads, lastAction });
    if (url.pathname === '/control/export') {
      res.setHeader('Content-Disposition', 'attachment; filename="via-test-data.json"');
      return send(res, 200, raw);
    }
    if (url.pathname === '/health') return send(res, 200, { status: 'ok', schemaVersion: 1, test: true });
    if (url.pathname === '/v1/trains' || url.pathname.startsWith('/v1/trains/') || url.pathname === '/data/allData.json') {
      lastRead = iso(Date.now()); feedReads++;
      if (mode === 'failure') return send(res, 503, { error: { code: 'test_source_unavailable' } });
      if (url.pathname === '/data/allData.json') return send(res, 200, mode === 'empty' ? {} : raw);
      const fetched = iso(Date.now() - (mode === 'stale' ? 20 * 60_000 : 0));
      const version = Math.max(revision, Date.now());
      let trains = mode === 'empty' || mode === 'unavailable' ? [] : normalize(raw, fetched, version);
      const dates = [...new Set(trains.map(t => t.originServiceDate))].sort();
      const date = url.searchParams.get('originServiceDate');
      const fold = (v: string) => v.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/quebec city|ville de quebec/g, 'quebec');
      const terms = fold(url.searchParams.get('q') ?? '').split(/\s+/).filter(Boolean);
      trains = trains.filter(t => (!date || t.originServiceDate === date) && terms.every(q => fold([t.trainNumber, t.from, t.to, ...t.calls.flatMap(c => [c.name, c.code])].join(' ')).includes(q)));
      if (url.pathname.startsWith('/v1/trains/')) {
        const id = decodeURIComponent(url.pathname.slice('/v1/trains/'.length));
        trains = trains.filter(t => t.id === id);
        if (!trains.length) return send(res, 404, { error: { code: 'train_not_found' } });
      }
      return send(res, 200, { schemaVersion: 1, snapshotVersion: version, sourceFetchedAt: mode === 'unavailable' ? null : fetched,
        sourceStatus: mode === 'stale' ? 'stale' : mode === 'unavailable' ? 'unavailable' : 'healthy', availableServiceDates: dates, trains });
    }
    const file = staticFiles.get(url.pathname);
    if (file) { res.writeHead(200, { 'Content-Type': file.contentType }); return res.end(file.body); }
    return send(res, 404, { error: { code: 'not_found' } });
  } catch (error) {
    if (!res.headersSent) send(res, 400, { error: { code: 'invalid_test_data', message: error instanceof Error ? error.message : '操作失败' } });
    else res.end();
  }
});
server.requestTimeout = 15_000;
server.on('error', error => { console.error('测试台无法启动：', error.message); process.exitCode = 1; });
server.listen(port, host, () => {
  console.log(`VIA 测试台：http://${host === '0.0.0.0' ? 'localhost' : host}:${port}`);
  console.log('Xcode Debug → Run → Arguments → Environment Variables: VIA_API_URL=http://localhost:' + port);
  if (host === '0.0.0.0') console.log('局域网模式已启用：真机请使用这台 Mac 的局域网地址；只在可信网络中使用。');
  console.log('数据仅存在内存中，关闭后重置；可在网页中导入/导出。不会发送推送或访问正式数据库。');
});
