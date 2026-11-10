# Account, dictionary and settings

Both apps sign in with Apple or Google through Supabase OAuth with PKCE. The public project configuration is in `shared/FlypeCore/Sources/FlypeCore/SupabaseAPI.swift`. No secret or `service_role` keys are used. Credentials are stored only in the main app's Keychain. The iPhone keyboard receives no credentials and never talks to the account database.

Signing in is optional. Without an account, the dictionary and settings stay local. At first sign-in, users can bring their existing words along. Signing out restores the previous local guest dictionary and settings. Each account has its own local archive, and account switches are journaled to a file so an interrupted switch can finish at the next start.

## Apple identifiers

- Team: binda UG, `4K9Y59Z87Y`
- Bundle IDs: `one.binda.flype.app` (iPhone), `one.binda.flype.app.keyboard` (keyboard), `one.binda.flype.mac` (Mac)
- App Group: `group.one.binda.flype.shared`

For Sign in with Apple, set `one.binda.flype.app` as the Primary App ID. A Services ID (for example `one.binda.flype.auth`) is configured at Apple and Supabase, not in the app code.

## Setting up the project

1. Deploy the migrations in order to project `leystmzdybimmbaruywp`. With the Supabase CLI, check the remote migration state first and review `supabase db push --dry-run`. Never reset an existing database. A personal access token belongs in your local CLI login, not in the repository or app.
2. Under Authentication > URL Configuration, allow exactly these redirect URLs:
   - `flype://auth/callback`
   - `flype-mac://auth/callback`
3. Under Authentication > Sign In / Providers, enable Apple and Google with their OAuth credentials.
4. At Apple and Google, register `https://leystmzdybimmbaruywp.supabase.co/auth/v1/callback`. Apple's web OAuth needs the matching Services ID and a valid provider secret. Watch its expiry. Provider secrets live only in Supabase.
5. Sign in with the same provider and account on each device. Different providers with different email addresses can create separate accounts.

## Sync and conflicts

- Entries may carry `learnedFromCorrection` or `learnedFromTyping`, which the database does not check. They never cause a merge conflict, and a word added by hand outranks them. App versions from before these fields drop them when they write. The counts behind them stay on the device and are never synced.
- One JSON dictionary version per `auth.uid()`, at most 1,000 entries and 2 MB. Settings have their own revision and sync independently.
- Synced: writing style (Cleaned or Verbatim), transcription language, interface language, the Mac's microphone key and the speech recognizer choice. Model downloads, permissions, setup progress and device-specific keyboard options stay local.
- Older settings without a model choice keep the local choice. Older apps can change other settings without resetting the synced model choice. Choosing Parakeet does not download a model on another device. The download has to finish there first.
- The server accepts only the allowed settings fields with valid values. Unknown, missing or invalid values are rejected.
- Clients have no direct table access. Functions check the signed-in user, and foreign user IDs are not input parameters. Both tables have RLS enabled.
- Writes check a server revision under a transaction lock, including the first entry.
- Sync is a three-way merge against the last common state. Concurrent changes to different words merge, and deletions stay deleted.
- For contradictory changes, both states are kept. Users choose the local or account dictionary for the whole merge. Both states are saved to a protected local archive first. Settings merge per field, and contradictory changes to one field can be resolved separately from the dictionary.
- Local changes made during a network request are merged again. Local writes also check the file revision under a process lock.
- Local changes trigger sync after 600 ms of quiet. Sync also runs when the app becomes active, and every 15 seconds while the main app runs. iOS does not guarantee periodic sync while suspended. Switching keyboards does not sync.
- Offline, words and settings stay available, and the next connection retries. Expired sessions renew through the refresh token. A revoked session needs a new sign-in.
- Audio and transcribed text are never uploaded for this sync. The keyboard uses local words and language settings without contacting Supabase.

## Cloud cleanup with OpenAI

Cleanup runs only on the OpenAI model `gpt-6.1-terra`. Choosing Cleaned asks for consent, which is stored per device, needs a signed-in account and is off by default. The mode itself syncs, so a new device never starts sending text without its own consent.

1. The app calls the Edge Function `cloud-cleanup` with the user's token. The OpenAI key is only a server-side function secret, `OPENAI_API_KEY`.
2. The function takes quota through `flype_take_cleanup_quota`, which also verifies the token. Every account: 10 requests a minute. Free: 100 requests and 20,000 characters a week (weeks start Monday, UTC), at most 200 requests and 50,000 characters a day. Pro: no weekly allowance, 500 requests and 150,000 characters a day as fair use. The text around the cursor counts toward the characters. For all users together: 20,000 requests a day. A used-up free week answers 429 with scope `week`, and the apps say so. The values are in migration `202611090001_cleanup_plans.sql`, the subscription columns in `202611100001_subscriptions.sql`.

   Pro is a row in `flype_entitlements` per account and source (`direct` for Stripe, `app_store`, `manual`), so a Stripe and an App Store subscription never overwrite each other. Only `expires_at` decides Pro: the end of the paid or trial period plus a short grace period. `status`, `period`, `will_renew` and `external_id` (Stripe subscription or original App Store transaction) only describe it. People can read their own rows but not write them; only the service role does. The apps ask `flype_subscription_status()`, which returns the longest active subscription and whether the yearly trial is still open: once per account, used up by a recorded trial in `flype_billing_customers` or any earlier purchase on either platform. Until the purchase flows exist, Pro is granted by hand:

   ```sql
   insert into public.flype_entitlements(user_id, plan, expires_at, source)
     values ('<user id>', 'pro', now() + interval '1 year', 'manual')
     on conflict (user_id, source) do update set expires_at = excluded.expires_at, updated_at = now();
   ```
3. With the transcription go the dictionary spellings it contains and, in German and English, dictionary terms the local audio check heard but could not check in the sentence ([dictionary correction](DICTIONARY-CORRECTION.md), step 8). The apps send up to 200 characters before and after the cursor, so a transcription can continue a typed sentence and end without a period when the sentence goes on. On iPhone, the keyboard passes them to the app per transcription, and the app deletes them after reading.
4. Neither the function nor the database stores or logs text. The function logs only durations and token counts per request, and returns the durations in a `Server-Timing` header.
5. When a recording starts with cleanup active, the app renews an expiring session and sends a `GET` without token or text to the function. It answers 405 and counts nothing, but the connection and the function are warm when the text follows. A new instance of the function also opens its connections to the database API and to OpenAI once, with HEAD requests that carry no token, key or text; on a cold first request this runs alongside the quota check.
6. Requests set `prompt_cache_key` to `flype-cleanup-<language>`, so OpenAI can reuse the cached instructions. The key names only the language, never the person.
7. Requests use OpenAI's Fast mode (`service_tier: "fast"`, formerly Priority) at twice the standard token price, about 6 instead of 3 US cents per thousand cleanups with a prompt cache hit. The log shows the tier OpenAI actually used.

To deploy: apply the migration, run `supabase secrets set OPENAI_API_KEY=…`, then `supabase functions deploy cloud-cleanup`. Also set a spending limit in the OpenAI project. Requests set `store: false`.

If the function is unreachable, offline, overloaded or over the limit, the original text stays and the app shows a notice.

## Checks

`./scripts/check.sh database` tests the migrations, user separation, anonymous blocking, revision conflicts, deletions and invalid words or settings in a temporary local PostgreSQL container.

The full integration test needs real Apple and Google sign-ins on iPhone and Mac: change words and all settings in both directions, and test offline changes, concurrent edits, signing out and switching accounts.
