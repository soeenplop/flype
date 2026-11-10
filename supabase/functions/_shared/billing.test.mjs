import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GRACE_MS, entitlementFromSubscription, formEncode, syncSubscription, verifyStripeSignature } from './billing.mjs';
import { DAY, NOW, sign, subscription } from './billing.fixtures.mjs';

test('nested Stripe parameters become form fields and empty values are left out', () => {
  const form = formEncode({ line_items: [{ price: 'price_1', quantity: 1 }], metadata: { user_id: 'u' }, email: undefined, trial: null });
  assert.equal(form.toString(), 'line_items%5B0%5D%5Bprice%5D=price_1&line_items%5B0%5D%5Bquantity%5D=1&metadata%5Buser_id%5D=u');
});

test('only a fresh signature over the exact body with the right secret passes', async () => {
  const payload = '{"type":"customer.subscription.updated"}';
  assert.equal(await verifyStripeSignature(payload, sign(payload, 'whsec_test'), 'whsec_test', NOW), true);
  assert.equal(await verifyStripeSignature(payload, `t=${NOW},v1=00,${sign(payload, 'whsec_test').split(',')[1]}`, 'whsec_test', NOW), true);
  for (const [header, secret, at] of [
    [sign(payload, 'whsec_other'), 'whsec_test', NOW],
    [sign(`${payload} `, 'whsec_test'), 'whsec_test', NOW],
    [sign(payload, 'whsec_test', NOW - 301), 'whsec_test', NOW],
    [sign(payload, 'whsec_test'), '', NOW],
    [null, 'whsec_test', NOW],
    ['v1=abc', 'whsec_test', NOW],
    [`t=${NOW}`, 'whsec_test', NOW],
  ]) {
    assert.equal(await verifyStripeSignature(payload, header, secret, at), false);
  }
});

test('subscription states map to entitlements with a grace period', () => {
  const active = entitlementFromSubscription(subscription());
  assert.deepEqual(active, {
    source: 'direct', external_id: 'sub_1', period: 'month', status: 'active', will_renew: true,
    expires_at: new Date((NOW + 29 * DAY) * 1000 + GRACE_MS).toISOString(),
    period_ends_at: new Date((NOW + 29 * DAY) * 1000).toISOString(),
  });

  const trial = entitlementFromSubscription(subscription({
    status: 'trialing',
    items: { data: [{ current_period_start: NOW, current_period_end: NOW + 7 * DAY, price: { recurring: { interval: 'year' } } }] },
  }));
  assert.equal(trial.status, 'trialing');
  assert.equal(trial.period, 'year');

  // Older API versions keep the period on the subscription itself.
  const legacy = entitlementFromSubscription(subscription({
    items: { data: [{ price: { recurring: { interval: 'year' } } }] }, current_period_start: NOW, current_period_end: NOW + 365 * DAY,
  }));
  assert.equal(legacy.expires_at, new Date((NOW + 365 * DAY) * 1000 + GRACE_MS).toISOString());

  assert.equal(entitlementFromSubscription(subscription({ cancel_at_period_end: true })).will_renew, false);
  assert.equal(entitlementFromSubscription(subscription({ cancel_at: NOW + DAY })).will_renew, false);

  // A failed renewal keeps Pro only for the grace period, not for the whole new period.
  const pastDue = entitlementFromSubscription(subscription({ status: 'past_due' }));
  assert.equal(pastDue.status, 'past_due');
  assert.equal(pastDue.expires_at, new Date((NOW - DAY) * 1000 + GRACE_MS).toISOString());

  const canceled = entitlementFromSubscription(subscription({ status: 'canceled', ended_at: NOW }));
  assert.equal(canceled.status, 'canceled');
  assert.equal(canceled.expires_at, new Date(NOW * 1000).toISOString());
  assert.equal(canceled.period_ends_at, canceled.expires_at);

  assert.equal(entitlementFromSubscription(subscription({ status: 'incomplete' })), null);
});

function database({ existing = null, saveStatus = null } = {}) {
  const calls = { saved: [], trials: [] };
  return {
    calls,
    entitlement: async () => existing,
    saveEntitlement: async row => {
      if (saveStatus) throw Object.assign(new Error('failed'), { status: saveStatus });
      calls.saved.push(row);
    },
    markTrialUsed: async (userID, at) => calls.trials.push({ userID, at }),
  };
}

test('sync writes the current state fetched from Stripe and records a used trial', async () => {
  const db = database();
  const requested = [];
  const stripe = async (method, path) => {
    requested.push(`${method} ${path}`);
    return subscription({ status: 'trialing', trial_start: NOW });
  };
  assert.equal(await syncSubscription({ stripe, db, subscriptionID: 'sub_1', now: () => NOW * 1000 }), 'trialing');
  assert.deepEqual(requested, ['GET subscriptions/sub_1']);
  assert.equal(db.calls.saved[0].user_id, 'user-1');
  assert.deepEqual(db.calls.trials, [{ userID: 'user-1', at: new Date(NOW * 1000).toISOString() }]);
});

test('sync skips foreign, unpaid and superseded subscriptions and deleted accounts', async () => {
  const now = () => NOW * 1000;
  let db = database();
  assert.equal(await syncSubscription({ stripe: async () => subscription({ metadata: {} }), db, subscriptionID: 'sub_1', now }), 'unassigned');
  assert.equal(await syncSubscription({ stripe: async () => subscription({ status: 'incomplete' }), db, subscriptionID: 'sub_1', now }), 'ignored');
  assert.equal(db.calls.saved.length, 0);

  db = database({ existing: { external_id: 'sub_2', expires_at: new Date((NOW + DAY) * 1000).toISOString() } });
  assert.equal(await syncSubscription({ stripe: async () => subscription({ status: 'canceled', ended_at: NOW }), db, subscriptionID: 'sub_1', now }), 'superseded');
  assert.equal(db.calls.saved.length, 0);

  // The same subscription ending, or an old one ending after the newer one ran out, is written.
  db = database({ existing: { external_id: 'sub_1', expires_at: new Date((NOW + DAY) * 1000).toISOString() } });
  assert.equal(await syncSubscription({ stripe: async () => subscription({ status: 'canceled', ended_at: NOW }), db, subscriptionID: 'sub_1', now }), 'canceled');
  db = database({ existing: { external_id: 'sub_2', expires_at: new Date((NOW - DAY) * 1000).toISOString() } });
  assert.equal(await syncSubscription({ stripe: async () => subscription({ status: 'canceled', ended_at: NOW }), db, subscriptionID: 'sub_1', now }), 'canceled');

  db = database({ saveStatus: 409 });
  assert.equal(await syncSubscription({ stripe: async () => subscription(), db, subscriptionID: 'sub_1', now }), 'account deleted');
  db = database({ saveStatus: 500 });
  await assert.rejects(syncSubscription({ stripe: async () => subscription(), db, subscriptionID: 'sub_1', now }));
});
