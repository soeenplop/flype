# Text cleanup

Cleanup runs only in the cloud, with [OpenAI through a Supabase function](ACCOUNT-AND-SYNC.md#cloud-cleanup-with-openai). It is active when the mode is Cleaned, the person agreed on this device and is signed in. Choosing Cleaned asks for that consent, and choosing Verbatim withdraws it. Without all three, Flype inserts the recognized text verbatim. If the cloud fails, times out or hits the limit, the full recognized text is kept with a notice.

The cleanup corrects punctuation, capitalization, spelling, compounds, grammar and words the recognition clearly got wrong, because the model knows the language better than the recognition does. It also sees up to 200 characters before and after the cursor, so a dictation can continue a sentence and end without a period when the sentence goes on.

## Self-corrections

The recognized text stays available as the original. It must replace only the smallest revoked passage and keep everything around it, including other sentences. A real negative answer must stay negative, and ambiguous corrections stay literal. This is a model instruction, not a guarantee of equal meaning.

The instructions apply generally to quantities, attributes, dates and clauses, without replacement lists. Language-specific examples and the rule for continuing after a letter's salutation go with the instructions in `supabase/functions/cloud-cleanup/handler.mjs`. Very long input keeps the original instead of being truncated.

Numbers become digits when they have decimals, are greater than twelve or go with a percentage, amount, measure, time or date, in the usual form of the language: "drei Komma fünf Prozent" becomes "3,5 %", "sieben Millionen Euro" becomes "7 Millionen Euro". Smaller numbers in running text stay words ("zwei Häuser"), and dictated digits stay digits. Spoken punctuation such as "Komma" or "Punkt" becomes the mark only when it is clearly meant as one; between numbers it is part of the number, and as a word in the sentence it stays. Dictated email and web addresses are written in their usual form.

Explicit quantity corrections (a number, optional filler, a correction signal and a replacement number) are resolved directly from the source words first. Ambiguous decimals and sentence boundaries are left alone. The model cannot rewrite quantities or drop other words when no correction signals remain.

Examples:

- "Wir bauen hier ein ähm nein zwei Häuser." → "Wir bauen hier zwei Häuser."
- "Hallo, das ist ein nein das sind zwei Tests." → "Hallo, das sind zwei Tests."
- "Nein, das sind zwei Tests." → unchanged

## Unfinished clause restarts

A repeated subject followed by a different form of "to be" can revoke an unfinished clause, as in "Hallo, das ist Nein, das war ein Test." A local step removes only the unfinished clause and the correction signal, leaving "Hallo, das war ein Test." It supports the chosen language's forms of "to be" and keeps surrounding sentences. It does not cross sentence boundaries or quotation marks, change the subject, or remove negated or complete clauses. Other corrections are up to the model.

## Speed

Both apps log the duration of each step after the recording (recognition, dictionary check, cleanup, on the Mac also inserting) with the log category `timing`, as numbers only. The cleanup function logs its own split into quota check and OpenAI call, with input, cached, output and reasoning tokens. Together they show where the wait comes from before the model, its reasoning effort or the prompt change.

## Testing with the real model

The handler tests in `supabase/functions/cloud-cleanup/handler.test.mjs` cover the request, quota and prompt wiring with a fake OpenAI client.

`supabase/eval/cleanup.mjs` checks the real model against made-up example dictations in `supabase/eval/cleanup-cases.json`: punctuation, spelling, fillers, self-corrections, kept answers and negations, numbers, instructions that stay text, preferred spellings and the text around the cursor. It builds each request through the same handler as the function, so it tests the prompt as deployed, and it reports the time per example. Run it before and after changing the prompt, the model or the service tier:

```bash
OPENAI_API_KEY=… node supabase/eval/cleanup.mjs
```

`--model`, `--tier` and `--only <id>` try another model, service tier or a single example. A run costs a fraction of a cent. It is not part of `./scripts/check.sh`, which only tests its wiring. An example lists every acceptable answer; a failure shows what the model returned.

Apple's on-device model was removed from cleanup on 2026-11-06: with broader corrections it copied words from examples, lowercased nouns and copied text after the cursor. The dictionary check still uses it, see [DICTIONARY-CORRECTION.md](DICTIONARY-CORRECTION.md).
