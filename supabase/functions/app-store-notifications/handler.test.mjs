import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';
import { USER, database, jws, statusResponse, transaction } from '../_shared/appstore.fixtures.mjs';

function fixture({ configured = true, apple = statusResponse(), saveStatus = null } = {}) {
  const calls = { apple: [] };
  const logs = [];
  const originalError = console.error;
  const originalLog = console.log;
  console.error = (...values) => logs.push(values.join(' '));
  console.log = (...values) => logs.push(values.join(' '));
  const db = database({ saveStatus });
  const handler = createHandler({
    appStore: configured ? async (transactionID, environment) => {
      calls.apple.push({ transactionID, environment });
      return apple;
    } : null,
    db,
  });
  return {
    calls,
    db,
    logs,
    restore: () => { console.error = originalError; console.log = originalLog; },
    deliver: (body, method = 'POST') => handler(new Request('https://example.invalid/app-store-notifications', {
      method,
      ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    })),
  };
}

const notification = (overrides = {}, data = {}) => ({
  signedPayload: jws({
    notificationType: 'DID_RENEW',
    data: { bundleId: 'one.binda.flype.app', environment: 'Sandbox', signedTransactionInfo: jws(transaction()), ...data },
    ...overrides,
  }),
});

test('malformed or misconfigured deliveries are rejected without asking Apple', async () => {
  for (const [options, body, method, expected] of [
    [{}, notification(), 'GET', 405],
    [{ configured: false }, notification(), 'POST', 503],
    [{}, 'not json', 'POST', 400],
    [{}, { signedPayload: 'nonsense' }, 'POST', 400],
    [{}, {}, 'POST', 400],
  ]) {
    const f = fixture(options);
    assert.equal((await f.deliver(body, method)).status, expected);
    assert.equal(f.calls.apple.length, 0);
    f.restore();
  }
});

test('a notification syncs the transaction it names in its environment', async () => {
  const f = fixture();
  assert.equal((await f.deliver(notification())).status, 200);
  assert.deepEqual(f.calls.apple, [{ transactionID: '2000000000000002', environment: 'Sandbox' }]);
  assert.equal(f.db.calls.saved[0].user_id, USER);
  f.restore();
});

test('test notifications and other apps are acknowledged without a sync', async () => {
  const f = fixture();
  assert.equal((await f.deliver(notification({ notificationType: 'TEST' }, { signedTransactionInfo: undefined }))).status, 200);
  assert.equal((await f.deliver(notification({}, { bundleId: 'com.other.app' }))).status, 200);
  assert.equal(f.calls.apple.length, 0);
  f.restore();
});

test('a forged notification grants nothing, and a failed write asks Apple to deliver again', async () => {
  let f = fixture({ apple: null });
  assert.equal((await f.deliver(notification())).status, 200);
  assert.equal(f.db.calls.saved.length, 0);
  f.restore();

  f = fixture({ saveStatus: 503 });
  assert.equal((await f.deliver(notification())).status, 500);
  assert.ok(f.logs.every(line => !line.includes(USER)));
  f.restore();
});
