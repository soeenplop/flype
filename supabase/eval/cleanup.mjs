// Checks the cleanup prompt against the real OpenAI model with fixed example dictations.
// It builds every request through the same handler as the Edge Function, so it tests the real prompt.
//
//   OPENAI_API_KEY=… node supabase/eval/cleanup.mjs [--model gpt-6-luna] [--tier fast|default] [--only de-dass]
//
// It costs a few tenths of a cent per run and is not part of ./scripts/check.sh. The examples are made up.
import { readFile } from 'node:fs/promises';
import { createHandler } from '../functions/cloud-cleanup/handler.mjs';

const normalize = text => text.trim().replace(/\s+/g, ' ').replace(/[’‘]/g, "'").replace(/[“”„]/g, '"');

// The Responses API returns output items; the SDK's `output_text` joins their text parts.
function outputText(body) {
  return (body.output ?? [])
    .flatMap(item => item.content ?? [])
    .filter(part => part.type === 'output_text')
    .map(part => part.text)
    .join('');
}

export async function evaluate({ cases, apiKey, fetch = globalThis.fetch, model, tier, now = () => performance.now() }) {
  const handler = createHandler({
    supabaseURL: 'https://eval.invalid',
    // The quota belongs to the database, which this check does not use.
    fetch: async () => new Response(JSON.stringify({ allowed: true })),
    createResponse: async params => {
      const response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...params, ...(model ? { model } : {}), ...(tier ? { service_tier: tier } : {}) }),
      });
      const body = await response.json();
      if (!response.ok) throw Object.assign(new Error(body.error?.message ?? 'OpenAI error'), { status: response.status });
      return { ...body, output_text: outputText(body) };
    },
  });
  const results = [];
  for (const example of cases) {
    const started = now();
    const response = await handler(new Request('https://eval.invalid/cloud-cleanup', {
      method: 'POST',
      body: JSON.stringify({
        text: example.text,
        terms: example.terms ?? [],
        language: example.language,
        context: example.context ?? null,
        following: example.following ?? null,
      }),
    }));
    const ms = Math.round(now() - started);
    const got = response.ok ? (await response.json()).text : `HTTP ${response.status}`;
    const passed = response.ok && example.expected.some(expected => normalize(expected) === normalize(got));
    results.push({ id: example.id, passed, got, expected: example.expected, ms });
  }
  return results;
}

function option(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index > 0 ? process.argv[index + 1] : undefined;
}

async function main() {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    console.error('OPENAI_API_KEY fehlt.');
    process.exit(2);
  }
  const all = JSON.parse(await readFile(new URL('./cleanup-cases.json', import.meta.url), 'utf8'));
  const only = option('only');
  const cases = only ? all.filter(example => example.id === only) : all;
  // The handler logs durations per request; the summary below already has them.
  const log = console.log;
  console.log = () => {};
  const results = await evaluate({ cases, apiKey, model: option('model'), tier: option('tier') });
  console.log = log;
  for (const result of results) {
    console.log(`${result.passed ? 'OK    ' : 'FEHLER'} ${String(result.ms).padStart(5)} ms  ${result.id}`);
    if (!result.passed) {
      console.log(`         erhalten: ${result.got}`);
      console.log(`         erwartet: ${result.expected.join('  |  ')}`);
    }
  }
  const times = results.map(result => result.ms).sort((a, b) => a - b);
  const at = share => times[Math.min(times.length - 1, Math.floor(share * times.length))];
  const passed = results.filter(result => result.passed).length;
  console.log(`\n${passed}/${results.length} bestanden, Median ${at(0.5)} ms, 90 % unter ${at(0.9)} ms`);
  process.exit(passed === results.length ? 0 : 1);
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
