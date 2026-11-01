import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

// Execute the actual Deno handler with isolated HTTP/environment dependencies; no real accounts or tokens.
const source = readFileSync(new URL('./index.ts', import.meta.url), 'utf8');
function fixture({ configured = true, authenticated = true, appleStatus = 200 } = {}) {
  let handler;
  const calls = [];
  runInNewContext(source, {
    Deno: {
      serve: value => { handler = value; },
      env: { get: key => key === 'SUPABASE_URL' ? 'https://example.invalid' : configured ? 'test-only' : undefined },
    },
    Response, URLSearchParams,
    fetch: async (url, options) => {
      calls.push({ url, options });
      return new Response('{}', { status: url.endsWith('/auth/v1/user') ? authenticated ? 200 : 401 : appleStatus });
    },
  });
  return {
    calls,
    invoke: (body, method = 'POST') => handler(new Request('https://example.invalid/revoke', {
      method, headers: { apikey: 'public-test', Authorization: 'Bearer test-user' },
      ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
    })),
  };
}
test('auth, configuration, method and token validation fail without contacting Apple', async () => {
  for (const [options, body, method, expected] of [
    [{ authenticated: false }, {}, 'POST', 401],
    [{ configured: false }, {}, 'POST', 503],
    [{}, {}, 'POST', 400],
    [{}, { provider_token: 'test', token_type_hint: 'id_token' }, 'POST', 400],
    [{}, {}, 'GET', 405],
  ]) {
    const f = fixture(options);
    assert.equal((await f.invoke(body, method)).status, expected);
    assert.ok(f.calls.every(call => !call.url.startsWith('https://appleid.apple.com')));
  }
});
test('refresh/access tokens and installed legacy clients use the correct Apple hint', async () => {
  for (const [body, hint] of [
    [{ provider_refresh_token: 'legacy-test' }, 'refresh_token'],
    [{ provider_token: 'refresh-test', token_type_hint: 'refresh_token' }, 'refresh_token'],
    [{ provider_token: 'access-test', token_type_hint: 'access_token' }, 'access_token'],
  ]) {
    const f = fixture();
    assert.equal((await f.invoke(body)).status, 200);
    const call = f.calls[1];
    assert.equal(call.url, 'https://appleid.apple.com/auth/revoke');
    assert.equal(call.options.body.get('token_type_hint'), hint);
    assert.equal(call.options.body.get('token'), body.provider_token ?? body.provider_refresh_token);
  }
});
test('Apple failure is never returned as a successful revocation', async () => {
  const f = fixture({ appleStatus: 503 });
  assert.equal((await f.invoke({ provider_refresh_token: 'test' })).status, 502);
});
