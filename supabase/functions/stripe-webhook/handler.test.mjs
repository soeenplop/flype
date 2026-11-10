import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';
import { NOW, sign, subscription } from '../_shared/billing.fixtures.mjs';

const SECRET = 'whsec_test';

function fixture({ configured = true, saveStatus = null } = {}) {
  const calls = { stripe: [], saved: [] };
  const logs = [];
  const originalError = console.error;
  const originalLog = console.log;
  console.error = (...values) => logs.push(values.join(' '));
  console.log = (...values) => logs.push(values.join(' '));
  const handler = createHandler({
    webhookSecret: configured ? SECRET : undefined,
    now: () => NOW * 1000,
    stripe: async (method, path) => {
      calls.stripe.push(`${method} ${path}`);
      return subscription({ id: path.split('/')[1] });
    },
    db: {
      entitlement: async () => null,
      markTrialUsed: async () => {},
      saveEntitlement: async row => {
        if (saveStatus) throw Object.assign(new Error('Database POST failed'), { status: saveStatus });
        calls.saved.push(row);
      },
    },
  });
  return {
    calls,
    logs,
    restore: () => { console.error = originalError; console.log = originalLog; },
    deliver: (event, { signature, method = 'POST' } = {}) => {
      const payload = JSON.stringify(event);
      return handler(new Request('https://example.invalid/stripe-webhook', {
        method,
        headers: { 'Stripe-Signature': signature ?? sign(payload, SECRET, NOW) },
        ...(method === 'POST' ? { body: payload } : {}),
      }));
    },
  };
}

const updated = { type: 'customer.subscription.updated', data: { object: { id: 'sub_1' } } };

test('unsigned, wrongly signed or misconfigured deliveries change nothing', async () => {
  for (const [options, delivery, expected] of [
    [{}, { method: 'GET' }, 405],
    [{ configured: false }, {}, 503],
    [{}, { signature: '' }, 400],
    [{}, { signature: sign('{}', SECRET, NOW) }, 400],
    [{}, { signature: sign(JSON.stringify(updated), 'whsec_other', NOW) }, 400],
  ]) {
    const f = fixture(options);
    assert.equal((await f.deliver(updated, delivery)).status, expected);
    assert.equal(f.calls.stripe.length, 0);
    f.restore();
  }
});

test('subscription events and completed checkouts sync the subscription they name', async () => {
  const f = fixture();
  assert.equal((await f.deliver(updated)).status, 204);
  assert.equal((await f.deliver({ type: 'customer.subscription.deleted', data: { object: { id: 'sub_2' } } })).status, 204);
  assert.equal((await f.deliver({
    type: 'checkout.session.completed', data: { object: { mode: 'subscription', subscription: 'sub_3' } },
  })).status, 204);
  assert.deepEqual(f.calls.stripe, ['GET subscriptions/sub_1', 'GET subscriptions/sub_2', 'GET subscriptions/sub_3']);
  assert.deepEqual(f.calls.saved.map(row => row.external_id), ['sub_1', 'sub_2', 'sub_3']);
  f.restore();
});

test('other events are acknowledged without a sync', async () => {
  const f = fixture();
  for (const event of [
    { type: 'invoice.paid', data: { object: { id: 'in_1' } } },
    { type: 'checkout.session.completed', data: { object: { mode: 'payment', subscription: null } } },
  ]) {
    assert.equal((await f.deliver(event)).status, 204);
  }
  assert.equal(f.calls.stripe.length, 0);
  f.restore();
});

test('a failed write answers 500 so Stripe delivers again', async () => {
  const f = fixture({ saveStatus: 503 });
  assert.equal((await f.deliver(updated)).status, 500);
  assert.ok(f.logs.every(line => !line.includes('user-1')));
  f.restore();
});
