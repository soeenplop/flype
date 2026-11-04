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

Cleanup can optionally run on the OpenAI model `gpt-6-luna`. The opt-in is per device, needs a signed-in account and is off by default.

1. The app calls the Edge Function `cloud-cleanup` with the user's token. The OpenAI key is only a server-side function secret, `OPENAI_API_KEY`.
2. The function takes quota through `flype_take_cleanup_quota`, which also verifies the token. Per account: 10 requests a minute, 200 a day, 50,000 characters a day. For all users together: 20,000 requests a day. The values are in migration `202611040001_cloud_cleanup.sql`.
3. The apps send up to 200 characters before the cursor, so a transcription can continue a typed sentence. On iPhone, the keyboard passes them to the app per transcription, and the app deletes them after reading.
4. Neither the function nor the database stores or logs text. The app checks the answer like local cleanup and keeps the original text when in doubt.

To deploy: apply the migration, run `supabase secrets set OPENAI_API_KEY=…`, then `supabase functions deploy cloud-cleanup`. Also set a spending limit in the OpenAI project. Requests set `store: false`.

If the function is unreachable, offline, overloaded or over the limit, Apple's on-device model takes over with the same prompt (`shared/FlypeCore/Sources/FlypeCore/CleanupPrompt.swift`). Without that model, the original text stays.

## Checks

`./scripts/check.sh database` tests the migrations, user separation, anonymous blocking, revision conflicts, deletions and invalid words or settings in a temporary local PostgreSQL container.

The full integration test needs real Apple and Google sign-ins on iPhone and Mac: change words and all settings in both directions, and test offline changes, concurrent edits, signing out and switching accounts.
