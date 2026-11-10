// Test data shared by the billing tests.
import { createHmac } from 'node:crypto';

export const DAY = 86_400;
export const NOW = 1_800_000_000;

export function sign(payload, secret, timestamp = NOW) {
  const signature = createHmac('sha256', secret).update(`${timestamp}.${payload}`).digest('hex');
  return `t=${timestamp},v1=${signature}`;
}

export function subscription(overrides = {}) {
  return {
    id: 'sub_1',
    status: 'active',
    metadata: { user_id: 'user-1' },
    cancel_at_period_end: false,
    cancel_at: null,
    ended_at: null,
    trial_start: null,
    items: { data: [{ current_period_start: NOW - DAY, current_period_end: NOW + 29 * DAY, price: { recurring: { interval: 'month' } } }] },
    ...overrides,
  };
}
