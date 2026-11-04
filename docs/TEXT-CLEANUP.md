# Text cleanup

Cleaned is the default on both platforms. A one-time startup migration also turned it on for existing installs, and a later explicit choice of Verbatim stays saved. If cleanup is unavailable, times out or looks unsafe, the full recognized text is kept and insertion continues without asking for confirmation.

## Self-corrections

The recognized text stays available as the original. Cleanup uses Apple's local FoundationModels model, or [OpenAI if the user opted in](ACCOUNT-AND-SYNC.md#cloud-cleanup-with-openai). It must replace only the smallest revoked passage and keep everything around it, including other sentences. A real negative answer must stay negative, and ambiguous corrections stay literal. This is a model instruction, not a guarantee of equal meaning.

The instructions apply generally to quantities, attributes, dates and clauses, without greeting-specific rules or replacement lists. Language-specific examples go with the shared instructions. Very long input keeps the original instead of being truncated.

Explicit quantity corrections (a number, optional filler, a correction signal and a replacement number) are resolved directly from the source words first. Ambiguous decimals and sentence boundaries are left alone. The model cannot rewrite quantities or drop other words when no correction signals remain.

Examples:

- "Wir bauen hier ein ähm nein zwei Häuser." → "Wir bauen hier zwei Häuser."
- "Hallo, das ist ein nein das sind zwei Tests." → "Hallo, das sind zwei Tests."
- "Nein, das sind zwei Tests." → unchanged

## Unfinished clause restarts

A repeated subject followed by a different form of "to be" can revoke an unfinished clause, as in "Hallo, das ist Nein, das war ein Test." A local step removes only the unfinished clause and the correction signal, leaving "Hallo, das war ein Test." It supports the chosen language's forms of "to be" and keeps surrounding sentences. It does not cross sentence boundaries or quotation marks, change the subject, or remove negated or complete clauses. Other corrections are up to the model.

## Testing with the real model

On a Mac with Apple Intelligence, run `./macos/scripts/check-cleanup.sh`. It compiles the production cleanup service with FlypeCore and sends only synthetic sentences to the local model. It fails on unavailable models, unexpected content (ignoring case and punctuation) or a review flag. It is separate from the deterministic core tests and the normal checks.

The fixtures cover German only. Other languages have not been checked with the real model.
