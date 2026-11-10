// Stripe and database helpers for the billing functions. Stripe is called through its REST API, so the
// functions need no SDK and the tests can replace fetch.

// Covers retried renewals and late webhooks, so a renewal never shows as an expired Pro.
export const GRACE_MS = 3 * 86_400_000;
const SIGNATURE_TOLERANCE_SECONDS = 300;

// Stripe takes nested parameters as form fields such as line_items[0][price].
export function formEncode(params, prefix = '', form = new URLSearchParams()) {
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    const name = prefix ? `${prefix}[${key}]` : key;
    if (typeof value === 'object') formEncode(value, name, form);
    else form.append(name, String(value));
  }
  return form;
}

export function createStripe({ secretKey, fetch }) {
  return async (method, path, params, idempotencyKey) => {
    const query = method === 'GET' && params ? `?${formEncode(params)}` : '';
    const response = await fetch(`https://api.stripe.com/v1/${path}${query}`, {
      method,
      headers: {
        Authorization: `Bearer ${secretKey}`,
        ...(method === 'GET' ? {} : { 'Content-Type': 'application/x-www-form-urlencoded' }),
        ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
      },
      ...(method === 'GET' ? {} : { body: formEncode(params ?? {}).toString() }),
    });
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      const error = new Error(`Stripe ${method} ${path.split('/')[0]} failed`);
      error.status = response.status;
      error.code = body?.error?.code;
      throw error;
    }
    return body;
  };
}

// The service role is only used here on the server; the apps never see it.
export function createDatabase({ supabaseURL, serviceKey, fetch }) {
  const call = async (method, path, body, prefer) => {
    const response = await fetch(`${supabaseURL}/rest/v1/${path}`, {
      method,
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        ...(prefer ? { Prefer: prefer } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    if (!response.ok) {
      const error = new Error(`Database ${method} ${path.split('?')[0]} failed with ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return method === 'GET' ? response.json() : null;
  };
  return {
    customer: async userID =>
      (await call('GET', `flype_billing_customers?user_id=eq.${userID}&select=stripe_customer_id,trial_used_at`))[0] ?? null,
    saveCustomer: (userID, customerID) =>
      call('POST', 'flype_billing_customers?on_conflict=user_id',
        { user_id: userID, stripe_customer_id: customerID, updated_at: new Date().toISOString() },
        'resolution=merge-duplicates'),
    markTrialUsed: (userID, at) =>
      call('PATCH', `flype_billing_customers?user_id=eq.${userID}&trial_used_at=is.null`,
        { trial_used_at: at, updated_at: new Date().toISOString() }),
    entitlement: async (userID, source) =>
      (await call('GET', `flype_entitlements?user_id=eq.${userID}&source=eq.${source}&select=expires_at,external_id`))[0] ?? null,
    saveEntitlement: row =>
      call('POST', 'flype_entitlements?on_conflict=user_id,source',
        { ...row, plan: 'pro', updated_at: new Date().toISOString() }, 'resolution=merge-duplicates'),
  };
}

// The signed-in user behind the caller's token, or null.
export async function authenticatedUser(request, { supabaseURL, fetch }) {
  const response = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      apikey: request.headers.get('apikey') ?? '',
      Authorization: request.headers.get('Authorization') ?? '',
    },
  });
  if (!response.ok) return null;
  const user = await response.json().catch(() => null);
  return typeof user?.id === 'string' ? user : null;
}

function hex(buffer) {
  return [...new Uint8Array(buffer)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

// Checks Stripe's signature header (t=…,v1=…) over the raw body with the endpoint secret.
export async function verifyStripeSignature(payload, header, secret, nowSeconds = Date.now() / 1000) {
  if (!header || !secret) return false;
  const parts = header.split(',').map(part => part.split('='));
  const timestamp = Number(parts.find(([key]) => key === 't')?.[1]);
  const signatures = parts.filter(([key]) => key === 'v1').map(([, value]) => value);
  if (!Number.isFinite(timestamp) || signatures.length === 0) return false;
  if (Math.abs(nowSeconds - timestamp) > SIGNATURE_TOLERANCE_SECONDS) return false;
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const expected = hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${payload}`)));
  // Compare without stopping at the first difference.
  return signatures.some(signature => {
    if (signature.length !== expected.length) return false;
    let difference = 0;
    for (let i = 0; i < expected.length; i += 1) difference |= signature.charCodeAt(i) ^ expected.charCodeAt(i);
    return difference === 0;
  });
}

const iso = seconds => new Date(seconds * 1000).toISOString();

// Turns a Stripe subscription into the entitlement row the quota and the apps read. Returns null for a
// subscription whose first payment never went through, which grants nothing.
// Newer Stripe API versions keep the period on the item, older ones on the subscription; both are read.
export function entitlementFromSubscription(subscription, nowMs = Date.now()) {
  const item = subscription.items?.data?.[0];
  const periodStart = item?.current_period_start ?? subscription.current_period_start;
  const periodEnd = item?.current_period_end ?? subscription.current_period_end;
  const period = item?.price?.recurring?.interval;
  const base = {
    source: 'direct',
    external_id: subscription.id,
    period: period === 'month' || period === 'year' ? period : null,
  };
  switch (subscription.status) {
    case 'trialing':
    case 'active':
      return {
        ...base,
        status: subscription.status,
        expires_at: new Date(periodEnd * 1000 + GRACE_MS).toISOString(),
        period_ends_at: iso(periodEnd),
        will_renew: !subscription.cancel_at_period_end && !subscription.cancel_at,
      };
    // Stripe already moved the period on while it retries the payment, so only the grace counts.
    case 'past_due':
    case 'unpaid':
      return {
        ...base,
        status: 'past_due',
        expires_at: new Date(Math.min(periodStart * 1000 + GRACE_MS, periodEnd * 1000)).toISOString(),
        period_ends_at: iso(periodEnd),
        will_renew: false,
      };
    case 'canceled':
    case 'incomplete_expired':
    case 'paused': {
      const ended = subscription.ended_at ? iso(subscription.ended_at) : new Date(nowMs).toISOString();
      return { ...base, status: 'canceled', expires_at: ended, period_ends_at: ended, will_renew: false };
    }
    default:
      return null;
  }
}

// Fetches the current state from Stripe instead of trusting the event, so the order of events does not matter.
export async function syncSubscription({ stripe, db, subscriptionID, now = Date.now }) {
  const subscription = await stripe('GET', `subscriptions/${subscriptionID}`);
  const userID = subscription.metadata?.user_id;
  if (!userID) return 'unassigned';
  const row = entitlementFromSubscription(subscription, now());
  if (subscription.trial_start) await db.markTrialUsed(userID, iso(subscription.trial_start));
  if (!row) return 'ignored';
  // An older subscription that ends must not replace a newer one that still runs.
  const existing = await db.entitlement(userID, 'direct');
  if (existing && existing.external_id !== subscription.id && row.status === 'canceled'
      && Date.parse(existing.expires_at) > now()) {
    return 'superseded';
  }
  try {
    await db.saveEntitlement({ user_id: userID, ...row });
  } catch (error) {
    // The account was deleted, which also ended its subscriptions. Stripe must not retry this event.
    if (error.status === 409) return 'account deleted';
    throw error;
  }
  return row.status;
}
