import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GRACE_MS } from './billing.mjs';
import { createAppStore, decodeJWS, entitlementFromStatus, signToken, syncAppStore } from './appstore.mjs';
import { DAY, NOW, OTHER, USER, database, jws, statusResponse, transaction } from './appstore.fixtures.mjs';

const fromBase64url = text => Buffer.from(text, 'base64url');

test('the API token is an ES256 JWT for the App Store Server API that the public key verifies', async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const token = await signToken({ key: pair.privateKey, keyID: 'KEY123', issuerID: 'issuer-uuid', nowSeconds: 1_800_000_000 });
  const [header, claims, signature] = token.split('.');
  assert.deepEqual(JSON.parse(fromBase64url(header)), { alg: 'ES256', kid: 'KEY123', typ: 'JWT' });
  assert.deepEqual(JSON.parse(fromBase64url(claims)), {
    iss: 'issuer-uuid', iat: 1_800_000_000, exp: 1_800_000_600, aud: 'appstoreconnect-v1', bid: 'one.binda.flype.app',
  });
  assert.equal(fromBase64url(signature).length, 64);
  assert.ok(await crypto.subtle.verify(
    { name: 'ECDSA', hash: 'SHA-256' }, pair.publicKey, fromBase64url(signature), new TextEncoder().encode(`${header}.${claims}`)));
});

test('the .p8 key is read with PEM lines and escaped line breaks, and production falls back to the sandbox', async () => {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  const pem = `-----BEGIN PRIVATE KEY-----\\n${der.match(/.{1,64}/g).join('\\n')}\\n-----END PRIVATE KEY-----`;
  const requested = [];
  const appStore = createAppStore({
    privateKey: pem, keyID: 'KEY123', issuerID: 'issuer', fetch: async (url, options) => {
      requested.push(url);
      assert.match(options.headers.Authorization, /^Bearer [\w-]+\.[\w-]+\.[\w-]+$/);
      return url.includes('sandbox') ? new Response('{"data":[]}') : new Response(null, { status: 404 });
    },
  });
  assert.deepEqual(await appStore('2000000000000002'), { data: [] });
  assert.deepEqual(requested, [
    'https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/2000000000000002',
    'https://api.storekit-sandbox.itunes.apple.com/inApps/v1/subscriptions/2000000000000002',
  ]);
  requested.length = 0;
  assert.equal(await appStore('2000000000000002', 'Production'), null);
  assert.equal(requested.length, 1);
});

test('a JWS payload is read and anything else is rejected', () => {
  assert.deepEqual(decodeJWS(jws({ productId: 'ä' })), { productId: 'ä' });
  for (const value of [undefined, '', 'abc', 'a.!!!.c', 42]) assert.equal(decodeJWS(value), null);
});

test('subscription states map to entitlements', () => {
  const trial = entitlementFromStatus(1, transaction(), { autoRenewStatus: 1 });
  assert.deepEqual(trial, {
    source: 'app_store', external_id: '2000000000000001', period: 'year', status: 'trialing', will_renew: true,
    expires_at: new Date(NOW + 6 * DAY + GRACE_MS).toISOString(), period_ends_at: new Date(NOW + 6 * DAY).toISOString(),
  });
  const monthly = entitlementFromStatus(1, transaction({ productId: 'one.binda.flype.pro.monthly', offerType: undefined }), { autoRenewStatus: 0 });
  assert.equal(monthly.status, 'active');
  assert.equal(monthly.period, 'month');
  assert.equal(monthly.will_renew, false);

  const grace = entitlementFromStatus(4, transaction({ offerType: undefined }), { gracePeriodExpiresDate: NOW + 2 * DAY });
  assert.equal(grace.status, 'past_due');
  assert.equal(grace.expires_at, new Date(NOW + 2 * DAY).toISOString());

  const retry = entitlementFromStatus(3, transaction({ expiresDate: NOW - DAY }), {}, NOW);
  assert.equal(retry.status, 'past_due');
  assert.equal(retry.expires_at, new Date(NOW - DAY).toISOString());

  const refunded = entitlementFromStatus(5, transaction({ revocationDate: NOW - 2 * DAY }), {}, NOW);
  assert.equal(refunded.status, 'canceled');
  assert.equal(refunded.expires_at, new Date(NOW - 2 * DAY).toISOString());

  assert.equal(entitlementFromStatus(1, transaction({ productId: 'com.other.pro' }), {}), null);
  assert.equal(entitlementFromStatus(1, transaction({ bundleId: 'com.other.app' }), {}), null);
});

test('a purchase is written for the account in its app account token and records the trial', async () => {
  const db = database();
  const outcome = await syncAppStore({ appStore: async () => statusResponse(), db, transactionID: '2000000000000002', userID: USER, now: () => NOW });
  assert.equal(outcome, 'trialing');
  assert.equal(db.calls.saved[0].user_id, USER);
  assert.deepEqual(db.calls.trials, [{ userID: USER, at: new Date(NOW - DAY).toISOString() }]);
});

test('nobody can claim another account\'s purchase, and notifications follow the known owner', async () => {
  const now = () => NOW;
  let db = database();
  assert.equal(await syncAppStore({ appStore: async () => statusResponse(), db, transactionID: '2', userID: OTHER, now }), 'foreign');
  assert.equal(db.calls.saved.length, 0);

  // Without a token, a purchase that already belongs to an account stays there.
  const untokened = statusResponse({ tx: transaction({ appAccountToken: undefined }) });
  db = database({ owner: USER });
  assert.equal(await syncAppStore({ appStore: async () => untokened, db, transactionID: '2', userID: OTHER, now }), 'foreign');
  db = database({ owner: null });
  assert.equal(await syncAppStore({ appStore: async () => untokened, db, transactionID: '2', userID: OTHER, now }), 'trialing');
  assert.equal(db.calls.saved[0].user_id, OTHER);

  db = database({ owner: USER });
  assert.equal(await syncAppStore({ appStore: async () => untokened, db, transactionID: '2', now }), 'trialing');
  assert.equal(db.calls.saved[0].user_id, USER);
  db = database();
  assert.equal(await syncAppStore({ appStore: async () => untokened, db, transactionID: '2', now }), 'unassigned');

  db = database({ saveStatus: 409 });
  assert.equal(await syncAppStore({ appStore: async () => statusResponse(), db, transactionID: '2', userID: USER, now }), 'conflict');
});

test('unknown transactions, other apps and ending older subscriptions change nothing', async () => {
  const now = () => NOW;
  const db = database({ existing: { external_id: '9', expires_at: new Date(NOW + DAY).toISOString() } });
  assert.equal(await syncAppStore({ appStore: async () => null, db, transactionID: '2', userID: USER, now }), 'unknown');
  assert.equal(await syncAppStore({ appStore: async () => ({ ...statusResponse(), bundleId: 'com.other.app' }), db, transactionID: '2', userID: USER, now }), 'foreign');
  assert.equal(await syncAppStore({ appStore: async () => statusResponse({ status: 2, tx: transaction({ expiresDate: NOW - DAY }) }), db, transactionID: '2', userID: USER, now }), 'superseded');
  assert.equal(db.calls.saved.length, 0);
});
