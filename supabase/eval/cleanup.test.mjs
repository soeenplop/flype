import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { evaluate } from './cleanup.mjs';

const cases = JSON.parse(await readFile(new URL('./cleanup-cases.json', import.meta.url), 'utf8'));

test('every example has a unique id, a supported language and an expected text', () => {
  assert.equal(new Set(cases.map(example => example.id)).size, cases.length);
  for (const example of cases) {
    assert.ok(['de', 'en', 'fr', 'it', 'es', 'nl'].includes(example.language), example.id);
    assert.ok(example.text.trim().length > 0 && example.expected.length > 0, example.id);
  }
});

test('the check sends the real prompt, reads the answer and compares it loosely', async () => {
  const sent = [];
  const answers = ['Ich glaube, dass wir das schaffen.', 'Wir treffen uns im Konferenz Raum.'];
  const fetch = async (url, options) => {
    sent.push({ url, options, body: JSON.parse(options.body) });
    const text = answers[sent.length - 1];
    return new Response(JSON.stringify({
      status: 'completed',
      output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ text: `  ${text} ` }) }] }],
    }));
  };
  const log = console.log;
  console.log = () => {};
  const results = await evaluate({
    cases: cases.filter(example => ['de-dass', 'de-compound'].includes(example.id)),
    apiKey: 'test-key', fetch, model: 'other-model', tier: 'default',
  });
  console.log = log;

  assert.deepEqual(results.map(result => [result.id, result.passed]), [['de-dass', true], ['de-compound', false]]);
  assert.equal(sent[0].url, 'https://api.openai.com/v1/responses');
  assert.equal(sent[0].options.headers.Authorization, 'Bearer test-key');
  assert.equal(sent[0].body.model, 'other-model');
  assert.equal(sent[0].body.service_tier, 'default');
  assert.equal(sent[0].body.prompt_cache_key, 'flype-cleanup-de');
  assert.match(sent[0].body.instructions, /gesprochener Sprache \(Deutsch\)/);
  assert.equal(JSON.parse(sent[0].body.input).transcription, 'Ich glaube das wir das schaffen');
});
