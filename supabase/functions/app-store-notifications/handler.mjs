import { BUNDLE_ID, decodeJWS, syncAppStore } from '../_shared/appstore.mjs';

const MAX_BYTES = 256_000;
const ENVIRONMENTS = new Set(['Production', 'Sandbox']);

// App Store Server Notifications V2. Apple calls this without a Supabase token, so it is deployed with
// --no-verify-jwt. The payload only names a transaction; its state is always fetched from Apple, so a
// forged notification cannot grant anything.
export function createHandler({ appStore, db, now = Date.now }) {
  return async request => {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    if (!appStore || !db) return new Response(null, { status: 503 });
    const raw = await request.text();
    if (raw.length > MAX_BYTES) return new Response(null, { status: 400 });
    let body = null;
    try {
      body = JSON.parse(raw);
    } catch {
      return new Response(null, { status: 400 });
    }
    const notification = decodeJWS(body?.signedPayload);
    if (!notification) return new Response(null, { status: 400 });
    const data = notification.data ?? {};
    const transaction = decodeJWS(data.signedTransactionInfo);
    // Test notifications and other apps carry nothing to sync; they are acknowledged so Apple stops sending.
    if (data.bundleId !== BUNDLE_ID || !transaction?.originalTransactionId) return new Response(null, { status: 200 });
    try {
      const outcome = await syncAppStore({
        appStore,
        db,
        transactionID: String(transaction.transactionId ?? transaction.originalTransactionId),
        environment: ENVIRONMENTS.has(data.environment) ? data.environment : undefined,
        now,
      });
      console.log('app-store-notifications:', notification.notificationType, notification.subtype ?? '', outcome);
      return new Response(null, { status: 200 });
    } catch (error) {
      // Apple retries a failed delivery several times over the next days.
      console.error('app-store-notifications:', notification.notificationType, error?.message ?? 'failed', error?.status ?? '');
      return new Response(null, { status: 500 });
    }
  };
}
