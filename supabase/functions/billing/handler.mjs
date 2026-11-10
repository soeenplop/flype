import { authenticatedUser } from '../_shared/billing.mjs';

// Subscriptions that still cost money or grant Pro. A second checkout would bill twice.
const RUNNING = new Set(['trialing', 'active', 'past_due', 'unpaid', 'paused']);

// Answers the Mac app with Stripe pages to open in the browser:
// { action: 'checkout', period: 'month' | 'year' } starts a subscription, or opens the portal if one runs;
// { action: 'portal' } manages it; { action: 'cancel' } ends every subscription right before the account
// is deleted. The yearly plan alone has the seven-day trial, once per account.
export function createHandler({ supabaseURL, fetch, stripe, db, prices, taxRate, returnURL }) {
  const result = query => `${returnURL}?result=${query}`;
  const json = (status, body) =>
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

  async function runningSubscriptions(customerID) {
    const list = await stripe('GET', 'subscriptions', { customer: customerID, status: 'all', limit: 20 });
    return (list.data ?? []).filter(subscription => RUNNING.has(subscription.status));
  }

  async function portal(customerID) {
    const session = await stripe('POST', 'billing_portal/sessions', { customer: customerID, return_url: result('portal') });
    return json(200, { url: session.url });
  }

  async function trialAvailable(request) {
    const response = await fetch(`${supabaseURL}/rest/v1/rpc/flype_subscription_status`, {
      method: 'POST',
      headers: {
        apikey: request.headers.get('apikey') ?? '',
        Authorization: request.headers.get('Authorization') ?? '',
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!response.ok) throw new Error(`Subscription status failed with ${response.status}`);
    return (await response.json()).trial_available === true;
  }

  async function checkout(request, user, period) {
    let customerID = (await db.customer(user.id))?.stripe_customer_id;
    if (!customerID) {
      // The idempotency key keeps two quick taps from creating two customers.
      const customer = await stripe('POST', 'customers', {
        email: user.email ?? undefined,
        metadata: { user_id: user.id },
      }, `flype-customer-${user.id}`);
      customerID = customer.id;
      await db.saveCustomer(user.id, customerID);
    } else if ((await runningSubscriptions(customerID)).length > 0) {
      return portal(customerID);
    }
    const trial = period === 'year' && await trialAvailable(request);
    const session = await stripe('POST', 'checkout/sessions', {
      mode: 'subscription',
      customer: customerID,
      client_reference_id: user.id,
      line_items: [{ price: prices[period], quantity: 1 }],
      locale: 'auto',
      success_url: result('success'),
      cancel_url: result('cancel'),
      payment_method_collection: 'always',
      metadata: { user_id: user.id },
      subscription_data: {
        metadata: { user_id: user.id },
        ...(trial ? { trial_period_days: 7 } : {}),
        ...(taxRate ? { default_tax_rates: [taxRate] } : {}),
      },
    });
    return json(200, { url: session.url, trial });
  }

  async function cancel(user) {
    const customerID = (await db.customer(user.id))?.stripe_customer_id;
    if (!customerID) return json(200, { canceled: 0 });
    const running = await runningSubscriptions(customerID);
    for (const subscription of running) {
      await stripe('DELETE', `subscriptions/${subscription.id}`, {}, `flype-cancel-${subscription.id}`);
    }
    return json(200, { canceled: running.length });
  }

  return async request => {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    if (!stripe || !db || !prices.month || !prices.year) return new Response(null, { status: 503 });
    const input = await request.json().catch(() => null);
    const action = input?.action;
    if (!['checkout', 'portal', 'cancel'].includes(action)) return new Response(null, { status: 400 });
    if (action === 'checkout' && input.period !== 'month' && input.period !== 'year') {
      return new Response(null, { status: 400 });
    }
    const user = await authenticatedUser(request, { supabaseURL, fetch });
    if (!user) return new Response(null, { status: 401 });
    try {
      if (action === 'checkout') return await checkout(request, user, input.period);
      if (action === 'cancel') return await cancel(user);
      const customerID = (await db.customer(user.id))?.stripe_customer_id;
      if (!customerID) return new Response(null, { status: 404 });
      return await portal(customerID);
    } catch (error) {
      // Names only the failed step, never an account or a payment detail.
      console.error('billing:', action, error?.message ?? 'failed', error?.status ?? '');
      return new Response(null, { status: 502 });
    }
  };
}
