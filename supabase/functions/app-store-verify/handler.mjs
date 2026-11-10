import { authenticatedUser } from '../_shared/billing.mjs';
import { syncAppStore } from '../_shared/appstore.mjs';

// The iPhone and iPad app reports a purchase or restore here with { transactionId }. The function asks Apple
// for the subscription, writes it for the signed-in account and answers with flype_subscription_status().
export function createHandler({ supabaseURL, fetch, appStore, db }) {
  return async request => {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    if (!appStore || !db) return new Response(null, { status: 503 });
    const input = await request.json().catch(() => null);
    const transactionID = input?.transactionId;
    if (typeof transactionID !== 'string' || !/^\d{1,20}$/.test(transactionID)) return new Response(null, { status: 400 });
    const user = await authenticatedUser(request, { supabaseURL, fetch });
    if (!user) return new Response(null, { status: 401 });

    let outcome;
    try {
      outcome = await syncAppStore({ appStore, db, transactionID, userID: user.id });
    } catch (error) {
      console.error('app-store-verify:', error?.message ?? 'failed', error?.status ?? '');
      return new Response(null, { status: 502 });
    }
    console.log('app-store-verify:', outcome);
    // The subscription belongs to another Flype account, for example after a restore with the same Apple ID.
    if (outcome === 'foreign' || outcome === 'conflict') return new Response(null, { status: 409 });
    if (outcome === 'unknown') return new Response(null, { status: 404 });

    const status = await fetch(`${supabaseURL}/rest/v1/rpc/flype_subscription_status`, {
      method: 'POST',
      headers: {
        apikey: request.headers.get('apikey') ?? '',
        Authorization: request.headers.get('Authorization') ?? '',
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!status.ok) return new Response(null, { status: 502 });
    return new Response(await status.text(), { status: 200, headers: { 'Content-Type': 'application/json' } });
  };
}
