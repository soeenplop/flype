import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';

const RETURN = 'https://example.invalid/billing.html';

function fixture({
  authenticated = true, configured = true, customer = null, running = [], trialAvailable = true, stripeFailure = null,
} = {}) {
  const calls = { stripe: [], saved: [], status: 0 };
  const logs = [];
  const originalError = console.error;
  console.error = (...values) => logs.push(values.join(' '));
  const handler = createHandler({
    supabaseURL: 'https://example.invalid',
    returnURL: RETURN,
    prices: { month: 'price_month', year: configured ? 'price_year' : undefined },
    taxRate: 'txr_1',
    fetch: async url => {
      if (url.endsWith('/auth/v1/user')) {
        return new Response(JSON.stringify({ id: 'user-1', email: 'test@example.invalid' }), { status: authenticated ? 200 : 401 });
      }
      calls.status += 1;
      return new Response(JSON.stringify({ trial_available: trialAvailable }));
    },
    db: {
      customer: async () => customer,
      saveCustomer: async (userID, customerID) => calls.saved.push({ userID, customerID }),
    },
    stripe: async (method, path, params, idempotencyKey) => {
      calls.stripe.push({ method, path, params, idempotencyKey });
      if (stripeFailure) throw Object.assign(new Error('Stripe POST checkout failed'), { status: stripeFailure });
      if (path === 'customers') return { id: 'cus_new' };
      if (path === 'subscriptions') return { data: running };
      if (path === 'checkout/sessions') return { url: 'https://checkout.stripe.invalid/s' };
      if (path === 'billing_portal/sessions') return { url: 'https://billing.stripe.invalid/p' };
      return {};
    },
  });
  return {
    calls,
    logs,
    restore: () => { console.error = originalError; },
    invoke: (body, method = 'POST') => handler(new Request('https://example.invalid/billing', {
      method,
      headers: { apikey: 'public-test', Authorization: 'Bearer test-user' },
      ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    })),
  };
}

test('invalid requests, missing configuration and failed auth never reach Stripe', async () => {
  for (const [options, body, method, expected] of [
    [{}, { action: 'checkout', period: 'year' }, 'GET', 405],
    [{ configured: false }, { action: 'checkout', period: 'year' }, 'POST', 503],
    [{}, 'not json', 'POST', 400],
    [{}, { action: 'refund' }, 'POST', 400],
    [{}, { action: 'checkout' }, 'POST', 400],
    [{}, { action: 'checkout', period: 'week' }, 'POST', 400],
    [{ authenticated: false }, { action: 'checkout', period: 'year' }, 'POST', 401],
    [{}, { action: 'portal' }, 'POST', 404],
  ]) {
    const f = fixture(options);
    assert.equal((await f.invoke(body, method)).status, expected);
    assert.equal(f.calls.stripe.length, 0);
    f.restore();
  }
});

test('the first yearly checkout creates the customer once and offers the trial', async () => {
  const f = fixture();
  const response = await f.invoke({ action: 'checkout', period: 'year' });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { url: 'https://checkout.stripe.invalid/s', trial: true });
  const [customer, session] = f.calls.stripe;
  assert.equal(customer.path, 'customers');
  assert.equal(customer.idempotencyKey, 'flype-customer-user-1');
  assert.deepEqual(customer.params.metadata, { user_id: 'user-1' });
  assert.deepEqual(f.calls.saved, [{ userID: 'user-1', customerID: 'cus_new' }]);
  assert.equal(session.path, 'checkout/sessions');
  assert.equal(session.params.customer, 'cus_new');
  assert.equal(session.params.mode, 'subscription');
  assert.equal(session.params.client_reference_id, 'user-1');
  assert.deepEqual(session.params.line_items, [{ price: 'price_year', quantity: 1 }]);
  assert.equal(session.params.success_url, `${RETURN}?result=success`);
  assert.equal(session.params.cancel_url, `${RETURN}?result=cancel`);
  assert.deepEqual(session.params.subscription_data, { metadata: { user_id: 'user-1' }, trial_period_days: 7, default_tax_rates: ['txr_1'] });
  assert.equal(session.params.automatic_tax, undefined);
  f.restore();
});

test('the monthly plan never has a trial, and a used trial is not offered again', async () => {
  let f = fixture({ customer: { stripe_customer_id: 'cus_1' } });
  let response = await f.invoke({ action: 'checkout', period: 'month' });
  assert.equal((await response.json()).trial, false);
  let session = f.calls.stripe.find(call => call.path === 'checkout/sessions');
  assert.equal(session.params.subscription_data.trial_period_days, undefined);
  assert.deepEqual(session.params.line_items, [{ price: 'price_month', quantity: 1 }]);
  assert.equal(f.calls.status, 0);
  assert.equal(f.calls.saved.length, 0);
  f.restore();

  f = fixture({ customer: { stripe_customer_id: 'cus_1' }, trialAvailable: false });
  response = await f.invoke({ action: 'checkout', period: 'year' });
  assert.equal((await response.json()).trial, false);
  session = f.calls.stripe.find(call => call.path === 'checkout/sessions');
  assert.equal(session.params.subscription_data.trial_period_days, undefined);
  f.restore();
});

test('a running subscription opens the portal instead of a second checkout', async () => {
  const f = fixture({ customer: { stripe_customer_id: 'cus_1' }, running: [{ id: 'sub_1', status: 'trialing' }] });
  const response = await f.invoke({ action: 'checkout', period: 'month' });
  assert.deepEqual(await response.json(), { url: 'https://billing.stripe.invalid/p' });
  assert.ok(!f.calls.stripe.some(call => call.path === 'checkout/sessions'));
  assert.equal(f.calls.stripe.at(-1).params.return_url, `${RETURN}?result=portal`);
  f.restore();
});

test('cancel ends every running subscription and nothing else', async () => {
  let f = fixture({
    customer: { stripe_customer_id: 'cus_1' },
    running: [{ id: 'sub_1', status: 'active' }, { id: 'sub_2', status: 'canceled' }, { id: 'sub_3', status: 'past_due' }],
  });
  let response = await f.invoke({ action: 'cancel' });
  assert.deepEqual(await response.json(), { canceled: 2 });
  assert.deepEqual(f.calls.stripe.filter(call => call.method === 'DELETE').map(call => call.path), ['subscriptions/sub_1', 'subscriptions/sub_3']);
  f.restore();

  f = fixture();
  response = await f.invoke({ action: 'cancel' });
  assert.deepEqual(await response.json(), { canceled: 0 });
  assert.equal(f.calls.stripe.length, 0);
  f.restore();
});

test('a Stripe failure answers 502 and logs no account details', async () => {
  const f = fixture({ customer: { stripe_customer_id: 'cus_1' }, stripeFailure: 500 });
  assert.equal((await f.invoke({ action: 'portal' })).status, 502);
  assert.ok(f.logs.every(line => !line.includes('user-1') && !line.includes('cus_1') && !line.includes('example.invalid')));
  f.restore();
});
