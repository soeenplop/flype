import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';
import { OTHER, USER, database, statusResponse } from '../_shared/appstore.fixtures.mjs';

function fixture({ authenticated = true, configured = true, apple = statusResponse(), appleFailure = null, user = USER } = {}) {
  const calls = { apple: [], status: 0 };
  const logs = [];
  const originalError = console.error;
  const originalLog = console.log;
  console.error = (...values) => logs.push(values.join(' '));
  console.log = (...values) => logs.push(values.join(' '));
  const db = database();
  const handler = createHandler({
    supabaseURL: 'https://example.invalid',
    fetch: async url => {
      if (url.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: user }), { status: authenticated ? 200 : 401 });
      calls.status += 1;
      return new Response('{"plan":"pro","trial_available":false}');
    },
    appStore: configured ? async (transactionID, environment) => {
      calls.apple.push({ transactionID, environment });
      if (appleFailure) throw Object.assign(new Error('App Store Production request failed'), { status: appleFailure });
      return apple;
    } : null,
    db,
  });
  return {
    calls,
    db,
    logs,
    restore: () => { console.error = originalError; console.log = originalLog; },
    invoke: (body, method = 'POST') => handler(new Request('https://example.invalid/app-store-verify', {
      method,
      headers: { apikey: 'public-test', Authorization: 'Bearer test-user' },
      ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    })),
  };
}

test('invalid requests, missing configuration and failed auth never reach Apple', async () => {
  for (const [options, body, method, expected] of [
    [{}, { transactionId: '1' }, 'GET', 405],
    [{ configured: false }, { transactionId: '1' }, 'POST', 503],
    [{}, 'not json', 'POST', 400],
    [{}, { transactionId: 1 }, 'POST', 400],
    [{}, { transactionId: '12a' }, 'POST', 400],
    [{}, { transactionId: '1'.repeat(21) }, 'POST', 400],
    [{ authenticated: false }, { transactionId: '1' }, 'POST', 401],
  ]) {
    const f = fixture(options);
    assert.equal((await f.invoke(body, method)).status, expected);
    assert.equal(f.calls.apple.length, 0);
    f.restore();
  }
});

test('a purchase is checked with Apple, written and answered with the account status', async () => {
  const f = fixture();
  const response = await f.invoke({ transactionId: '2000000000000002' });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { plan: 'pro', trial_available: false });
  assert.deepEqual(f.calls.apple, [{ transactionID: '2000000000000002', environment: undefined }]);
  assert.equal(f.db.calls.saved[0].user_id, USER);
  assert.equal(f.db.calls.saved[0].source, 'app_store');
  f.restore();
});

test('another account\'s purchase, an unknown transaction and Apple failures change nothing', async () => {
  for (const [options, expected] of [[{ user: OTHER }, 409], [{ apple: null }, 404], [{ appleFailure: 401 }, 502]]) {
    const f = fixture(options);
    assert.equal((await f.invoke({ transactionId: '2000000000000002' })).status, expected);
    assert.equal(f.db.calls.saved.length, 0);
    assert.equal(f.calls.status, 0);
    assert.ok(f.logs.every(line => !line.includes(USER) && !line.includes(OTHER)));
    f.restore();
  }
});
