import { syncSubscription, verifyStripeSignature } from '../_shared/billing.mjs';

const MAX_BYTES = 512_000;

// Stripe calls this without a Supabase token, so it is deployed with --no-verify-jwt and trusts only
// the signature. Every event names a subscription, and its current state is fetched from Stripe.
export function createHandler({ stripe, db, webhookSecret, now = Date.now }) {
  return async request => {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    if (!stripe || !db || !webhookSecret) return new Response(null, { status: 503 });
    const payload = await request.text();
    if (payload.length > MAX_BYTES) return new Response(null, { status: 400 });
    if (!await verifyStripeSignature(payload, request.headers.get('Stripe-Signature'), webhookSecret, now() / 1000)) {
      return new Response(null, { status: 400 });
    }
    const event = JSON.parse(payload);
    const object = event.data?.object ?? {};
    let subscriptionID = null;
    if (event.type === 'checkout.session.completed' && object.mode === 'subscription') subscriptionID = object.subscription;
    else if (event.type?.startsWith('customer.subscription.')) subscriptionID = object.id;
    // Everything else is acknowledged, so Stripe does not retry it.
    if (typeof subscriptionID !== 'string') return new Response(null, { status: 204 });
    try {
      const outcome = await syncSubscription({ stripe, db, subscriptionID, now });
      console.log('stripe-webhook:', event.type, outcome);
      return new Response(null, { status: 204 });
    } catch (error) {
      // A failure answers 500, so Stripe delivers the event again later.
      console.error('stripe-webhook:', event.type, error?.message ?? 'failed', error?.status ?? '');
      return new Response(null, { status: 500 });
    }
  };
}
