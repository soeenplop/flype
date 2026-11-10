// App Store Server API for the iPhone and iPad subscriptions. Every check asks Apple for the current state
// with the In-App Purchase key, so neither an app nor a notification can claim a purchase on its own.
import { GRACE_MS } from './billing.mjs';

export const BUNDLE_ID = 'one.binda.flype.app';
export const PRODUCTS = { 'one.binda.flype.pro.monthly': 'month', 'one.binda.flype.pro.yearly': 'year' };
const HOSTS = {
  Production: 'https://api.storekit.itunes.apple.com',
  Sandbox: 'https://api.storekit-sandbox.itunes.apple.com',
};

const base64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
const encodeJSON = value => base64url(new TextEncoder().encode(JSON.stringify(value)));

// Reads the payload of a JWS. Only for data fetched from Apple over TLS, or for IDs that are checked with
// Apple before anything is written; the signature itself is not verified here.
export function decodeJWS(jws) {
  const part = typeof jws === 'string' ? jws.split('.')[1] : null;
  if (!part) return null;
  try {
    const text = atob(part.replaceAll('-', '+').replaceAll('_', '/'));
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(text, c => c.charCodeAt(0))));
  } catch {
    return null;
  }
}

// The .p8 file from App Store Connect, with or without its PEM lines and with escaped line breaks.
export async function importPrivateKey(pem) {
  const body = pem.replaceAll('\\n', '\n').replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), c => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

// A short-lived ES256 token for the App Store Server API. WebCrypto already signs in the JWS format (r‖s).
export async function signToken({ key, keyID, issuerID, nowSeconds = Math.floor(Date.now() / 1000) }) {
  const header = encodeJSON({ alg: 'ES256', kid: keyID, typ: 'JWT' });
  const claims = encodeJSON({ iss: issuerID, iat: nowSeconds, exp: nowSeconds + 600, aud: 'appstoreconnect-v1', bid: BUNDLE_ID });
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${base64url(signature)}`;
}

export function createAppStore({ privateKey, keyID, issuerID, fetch }) {
  let key = null;
  async function request(environment, transactionID) {
    key ??= await importPrivateKey(privateKey);
    const token = await signToken({ key, keyID, issuerID });
    return fetch(`${HOSTS[environment]}/inApps/v1/subscriptions/${encodeURIComponent(transactionID)}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
  }
  // All subscription states of the transaction's group, or null if Apple does not know the transaction.
  // Without a known environment, production is asked first and the sandbox after a 404, as Apple advises.
  return async (transactionID, environment) => {
    for (const name of environment ? [environment] : ['Production', 'Sandbox']) {
      const response = await request(name, transactionID);
      if (response.status === 404) continue;
      if (!response.ok) {
        const error = new Error(`App Store ${name} request failed`);
        error.status = response.status;
        throw error;
      }
      return response.json();
    }
    return null;
  };
}

const iso = ms => new Date(ms).toISOString();

// Turns Apple's subscription status into the entitlement row. Status codes: 1 active, 2 expired,
// 3 billing retry, 4 billing grace period, 5 revoked.
export function entitlementFromStatus(status, transaction, renewal, nowMs = Date.now()) {
  const period = PRODUCTS[transaction.productId];
  if (!period || transaction.bundleId !== BUNDLE_ID) return null;
  const base = { source: 'app_store', external_id: String(transaction.originalTransactionId), period };
  const ends = transaction.expiresDate;
  const willRenew = renewal?.autoRenewStatus === 1;
  switch (status) {
    case 1: {
      const trial = transaction.offerType === 1 && (transaction.offerDiscountType ?? 'FREE_TRIAL') === 'FREE_TRIAL';
      return { ...base, status: trial ? 'trialing' : 'active', expires_at: iso(ends + GRACE_MS), period_ends_at: iso(ends), will_renew: willRenew };
    }
    // Apple keeps Pro during its own grace period while it retries the payment, but not during a plain retry.
    case 4:
      return { ...base, status: 'past_due', expires_at: iso(renewal?.gracePeriodExpiresDate ?? ends), period_ends_at: iso(ends), will_renew: false };
    case 3:
      return { ...base, status: 'past_due', expires_at: iso(Math.min(ends, nowMs)), period_ends_at: iso(ends), will_renew: false };
    case 2:
    case 5: {
      const ended = iso(Math.min(transaction.revocationDate ?? ends, ends, nowMs));
      return { ...base, status: 'canceled', expires_at: ended, period_ends_at: ended, will_renew: false };
    }
    default:
      return null;
  }
}

// Fetches the subscription behind a transaction from Apple and writes it for the account. `userID` is the
// signed-in caller when the app reports a purchase, and null for a notification from Apple.
export async function syncAppStore({ appStore, db, transactionID, environment, userID = null, now = Date.now }) {
  const response = await appStore(transactionID, environment);
  if (!response) return 'unknown';
  if (response.bundleId && response.bundleId !== BUNDLE_ID) return 'foreign';
  const entries = (response.data ?? []).flatMap(group => group.lastTransactions ?? []);
  const known = entries
    .map(entry => ({ status: entry.status, transaction: decodeJWS(entry.signedTransactionInfo), renewal: decodeJWS(entry.signedRenewalInfo) }))
    .filter(entry => entry.transaction && PRODUCTS[entry.transaction.productId]);
  if (known.length === 0) return 'unknown';
  // One group holds both plans, so there is one subscription; the latest expiry wins if Apple lists more.
  const { status, transaction, renewal } = known.sort((a, b) => b.transaction.expiresDate - a.transaction.expiresDate)[0];

  const originalID = String(transaction.originalTransactionId);
  const token = transaction.appAccountToken?.toLowerCase() ?? null;
  const owner = token ?? (await db.entitlementOwner('app_store', originalID));
  // A purchase belongs to the account that made it. Another account may only claim one without a token
  // (an offer code redeemed in the App Store) that no account has yet.
  if (userID && owner && owner !== userID.toLowerCase()) return 'foreign';
  const account = owner ?? userID;
  if (!account) return 'unassigned';

  const row = entitlementFromStatus(status, transaction, renewal, now());
  if (!row) return 'ignored';
  if (transaction.offerType === 1) await db.recordTrial(account, iso(transaction.purchaseDate));
  const existing = await db.entitlement(account, 'app_store');
  if (existing && existing.external_id !== originalID && row.status === 'canceled' && Date.parse(existing.expires_at) > now()) {
    return 'superseded';
  }
  try {
    await db.saveEntitlement({ user_id: account, ...row });
  } catch (error) {
    if (error.status === 409) return 'conflict';
    throw error;
  }
  return row.status;
}
