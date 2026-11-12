import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorizeConsole } from '../src/console-auth.ts';
import { handle } from '../src/test-worker.ts';

const request = (credentials?: string) => new Request('https://example.com/control/state', {
  headers: credentials ? { authorization: `Basic ${btoa(credentials)}` } : {},
});
test('console credentials fail closed and accept only the configured operator password', async () => {
  assert.equal(await authorizeConsole(request('admin:demo'), undefined), false);
  assert.equal(await authorizeConsole(request(), 'demo'), false);
  assert.equal(await authorizeConsole(request('guest:demo'), 'demo'), false);
  assert.equal(await authorizeConsole(request('admin:wrong'), 'demo'), false);
  assert.equal(await authorizeConsole(request('admin:demo'), 'demo'), true);
  assert.equal(await authorizeConsole(new Request('https://example.com', { headers: { authorization: 'Basic !bad!' } }), 'demo'), false);
});
test('anonymous console access is rejected before touching device data or the database', async () => {
  const context = {} as ExecutionContext;
  const env = { OPS_TOKEN: 'demo' } as Cloudflare.TestEnv;
  const denied = await handle(request(), env, context);
  assert.equal(denied.status, 401);
  assert.match(denied.headers.get('www-authenticate')!, /^Basic/);
  const disabled = await handle(request(), {} as Cloudflare.TestEnv, context);
  assert.equal(disabled.status, 503);
  const health = await handle(new Request('https://example.com/health'), env, context);
  assert.equal(health.status, 200);
});
