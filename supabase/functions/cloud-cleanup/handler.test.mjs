import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandler } from './handler.mjs';

const valid = { text: 'Wir bauen ähm zwei Häuser', terms: ['Flype'], language: 'de' };
function fixture({ quotaStatus = 200, quota = { allowed: true }, reply, failure, configured = true } = {}) {
  const calls = { quota: [], openAI: [] };
  const logs = [];
  const originalError = console.error;
  const originalLog = console.log;
  console.error = (...values) => logs.push(values.join(' '));
  console.log = (...values) => logs.push(values.join(' '));
  let clock = 0;
  const handler = createHandler({
    supabaseURL: 'https://example.invalid',
    now: () => (clock += 40),
    fetch: async (url, options) => {
      calls.quota.push({ url, options });
      return new Response(JSON.stringify(quota), { status: quotaStatus });
    },
    createResponse: configured ? async params => {
      calls.openAI.push(params);
      if (failure) throw failure;
      return reply ?? { status: 'completed', output_text: '{"text":"Wir bauen zwei Häuser."}' };
    } : null,
  });
  return {
    calls,
    logs,
    restore: () => { console.error = originalError; console.log = originalLog; },
    invoke: (body = valid, method = 'POST') => handler(new Request('https://example.invalid/cleanup', {
      method,
      headers: { apikey: 'public-test', Authorization: 'Bearer test-user' },
      ...(method === 'POST' ? { body: typeof body === 'string' ? body : JSON.stringify(body) } : {}),
    })),
  };
}

test('invalid requests, missing configuration and failed auth never reach OpenAI', async () => {
  const oversized = { ...valid, text: 'ä'.repeat(2_501) };
  for (const [options, body, method, expected] of [
    [{}, valid, 'GET', 405],
    [{ configured: false }, valid, 'POST', 503],
    [{}, 'not json', 'POST', 400],
    [{}, 'null', 'POST', 400],
    [{}, { ...valid, text: '   ' }, 'POST', 400],
    [{}, { ...valid, language: 'constructor' }, 'POST', 400],
    [{}, { ...valid, terms: [1] }, 'POST', 400],
    [{}, { ...valid, context: 7 }, 'POST', 400],
    [{}, { ...valid, context: 'x'.repeat(401) }, 'POST', 400],
    [{}, { ...valid, following: 7 }, 'POST', 400],
    [{}, { ...valid, following: 'x'.repeat(401) }, 'POST', 400],
    [{}, oversized, 'POST', 400],
    [{ quotaStatus: 401 }, valid, 'POST', 401],
    [{ quotaStatus: 403 }, valid, 'POST', 401],
    [{ quotaStatus: 500 }, valid, 'POST', 503],
  ]) {
    const f = fixture(options);
    assert.equal((await f.invoke(body, method)).status, expected);
    assert.equal(f.calls.openAI.length, 0);
    f.restore();
  }
});

test('limits answer without contacting OpenAI', async () => {
  let f = fixture({ quota: { allowed: false, scope: 'minute', retry_after: 12 } });
  const limited = await f.invoke();
  assert.equal(limited.status, 429);
  assert.equal(limited.headers.get('Retry-After'), '12');
  assert.equal(f.calls.openAI.length, 0);
  f.restore();

  f = fixture({ quota: { allowed: false, scope: 'service' } });
  assert.equal((await f.invoke()).status, 503);
  assert.equal(f.calls.openAI.length, 0);
  f.restore();
});

test('a permitted request forwards the token, counts bytes and asks Luna for structured text', async () => {
  const f = fixture();
  const response = await f.invoke();
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: 'Wir bauen zwei Häuser.' });

  const quota = f.calls.quota[0];
  assert.equal(quota.url, 'https://example.invalid/rest/v1/rpc/flype_take_cleanup_quota');
  assert.equal(quota.options.headers.Authorization, 'Bearer test-user');
  const size = new TextEncoder().encode(valid.text + 'Flype').length;
  assert.deepEqual(JSON.parse(quota.options.body), { p_characters: size });

  const params = f.calls.openAI[0];
  assert.equal(params.model, 'gpt-6-luna');
  assert.equal(params.store, false);
  assert.equal(params.service_tier, 'fast');
  assert.equal(params.text.format.type, 'json_schema');
  assert.equal(params.text.format.strict, true);
  assert.match(params.instructions, /gesprochener Sprache \(Deutsch\)/);
  assert.deepEqual(JSON.parse(params.input), { transcription: valid.text, preferredSpellings: ['Flype'] });
  f.restore();
});

test('requests share a prompt cache per language, never per person', async () => {
  const f = fixture();
  await f.invoke();
  await f.invoke({ ...valid, language: 'en' });
  assert.deepEqual(f.calls.openAI.map(params => params.prompt_cache_key), ['flype-cleanup-de', 'flype-cleanup-en']);
  assert.ok(f.calls.openAI.every(params => !JSON.stringify(params).includes('test-user')));
  f.restore();
});

test('timings reach the response header and the log as numbers only', async () => {
  const f = fixture({
    reply: {
      status: 'completed',
      service_tier: 'priority',
      output_text: '{"text":"Wir bauen zwei Häuser."}',
      usage: {
        input_tokens: 1300, input_tokens_details: { cached_tokens: 1152 },
        output_tokens: 90, output_tokens_details: { reasoning_tokens: 60 },
      },
    },
  });
  const response = await f.invoke();
  assert.equal(response.headers.get('Server-Timing'), 'quota;dur=40, openai;dur=40');
  const line = f.logs.find(entry => entry.startsWith('cloud-cleanup: timing'));
  assert.deepEqual(JSON.parse(line.slice('cloud-cleanup: timing '.length)), {
    quotaMs: 40, openaiMs: 40, inputTokens: 1300, cachedTokens: 1152, outputTokens: 90, reasoningTokens: 60,
    serviceTier: 'priority',
  });
  assert.ok(f.logs.every(entry => !entry.includes(valid.text) && !entry.includes('Häuser')));
  f.restore();
});

test('the text before the cursor reaches OpenAI as data and counts toward the quota', async () => {
  const f = fixture();
  assert.equal((await f.invoke({ ...valid, context: 'Ich gehe heute' })).status, 200);
  const size = new TextEncoder().encode(valid.text + 'Flype' + 'Ich gehe heute').length;
  assert.deepEqual(JSON.parse(f.calls.quota[0].options.body), { p_characters: size });
  assert.equal(JSON.parse(f.calls.openAI[0].input).precedingText, 'Ich gehe heute');
  assert.match(f.calls.openAI[0].instructions, /‹Das› \+ ‹Klappt ja schon mal\.› → ‹klappt ja schon mal\.›/);
  f.restore();
});

test('the text after the cursor reaches OpenAI as data and counts toward the quota', async () => {
  const f = fixture();
  assert.equal((await f.invoke({ ...valid, context: 'Ich komme', following: 'zum Essen.' })).status, 200);
  const size = new TextEncoder().encode(valid.text + 'Flype' + 'Ich komme' + 'zum Essen.').length;
  assert.deepEqual(JSON.parse(f.calls.quota[0].options.body), { p_characters: size });
  const input = JSON.parse(f.calls.openAI[0].input);
  assert.equal(input.precedingText, 'Ich komme');
  assert.equal(input.followingText, 'zum Essen.');
  assert.match(f.calls.openAI[0].instructions, /‹Ich komme› \+ ‹Morgen\.› \+ ‹zum Essen\.› → ‹morgen›/);
  f.restore();
});

test('OpenAI failures keep dictated text out of responses and logs', async () => {
  const secret = 'Wir bauen ähm zwei Häuser';
  for (const [options, expected] of [
    [{ failure: Object.assign(new Error(secret), { status: 529 }) }, 503],
    [{ reply: { status: 'completed', output_text: '' } }, 502],
    [{ reply: { status: 'incomplete', output_text: '{"text":"abge' } }, 502],
    [{ reply: { status: 'failed', output_text: '' } }, 502],
    [{ reply: { status: 'completed', output_text: 'kein JSON' } }, 502],
    [{ reply: { status: 'completed', output_text: '{"text":" "}' } }, 502],
  ]) {
    const f = fixture(options);
    const response = await f.invoke();
    assert.equal(response.status, expected);
    assert.equal(await response.text(), '');
    assert.ok(f.logs.every(line => !line.includes(secret)));
    f.restore();
  }
});
