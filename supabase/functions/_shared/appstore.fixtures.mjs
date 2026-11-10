// Test data shared by the App Store tests.
export const USER = '0e6c8a5e-1111-4222-8333-944455556666';
export const OTHER = '7f1d2c3b-aaaa-4bbb-8ccc-dddddddddddd';
export const NOW = 1_800_000_000_000;
export const DAY = 86_400_000;

const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
// Apple signs these; the code reads them only after fetching them from Apple, so a dummy signature suffices.
export const jws = payload => `${encode({ alg: 'ES256' })}.${encode(payload)}.signature`;

export function transaction(overrides = {}) {
  return {
    transactionId: '2000000000000002',
    originalTransactionId: '2000000000000001',
    bundleId: 'one.binda.flype.app',
    productId: 'one.binda.flype.pro.yearly',
    purchaseDate: NOW - DAY,
    expiresDate: NOW + 6 * DAY,
    appAccountToken: USER.toUpperCase(),
    offerType: 1,
    offerDiscountType: 'FREE_TRIAL',
    ...overrides,
  };
}

// The answer of GET /inApps/v1/subscriptions/{transactionId}.
export function statusResponse({ status = 1, tx = transaction(), renewal = { autoRenewStatus: 1 } } = {}) {
  return {
    bundleId: 'one.binda.flype.app',
    environment: 'Sandbox',
    data: [{
      subscriptionGroupIdentifier: '21500001',
      lastTransactions: [{
        originalTransactionId: tx.originalTransactionId,
        status,
        signedTransactionInfo: jws(tx),
        signedRenewalInfo: jws(renewal),
      }],
    }],
  };
}

export function database({ owner = null, existing = null, saveStatus = null } = {}) {
  const calls = { saved: [], trials: [] };
  return {
    calls,
    entitlementOwner: async () => owner,
    entitlement: async () => existing,
    recordTrial: async (userID, at) => calls.trials.push({ userID, at }),
    saveEntitlement: async row => {
      if (saveStatus) throw Object.assign(new Error('Database POST failed'), { status: saveStatus });
      calls.saved.push(row);
    },
  };
}
