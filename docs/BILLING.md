# Flype Pro

Pro lifts the weekly cleanup allowance ([account and sync](ACCOUNT-AND-SYNC.md), cloud cleanup). One subscription covers the whole account: bought on the Mac through Stripe or on iPhone and iPad through the App Store, it counts on every device signed in with that account.

| Plan | Price | Trial |
| --- | --- | --- |
| Monthly | 5.95 € | none |
| Yearly | 59.95 € | 7 days, once per account |

Prices are gross amounts. Stripe Tax is not used; VAT is reported by binda UG itself.

## Data

Migration `202611100001_subscriptions.sql`:

- `flype_entitlements` has one row per account and source (`direct` for Stripe, `app_store`, `manual`). Only `expires_at` decides Pro. `status`, `period`, `will_renew`, `period_ends_at` (the period end without grace, for the dates the apps show) and `external_id` describe the subscription to the apps.
- `flype_billing_customers` holds the Stripe customer and `trial_used_at`. Only the service role reads it.
- `flype_subscription_status()` tells the signed-in person the longest active subscription and whether the yearly trial is still open. A recorded trial or any earlier purchase on either platform uses it up; Pro granted by hand does not.

## Stripe (Mac)

The Mac app never sees a Stripe key. It calls the Edge Function `billing` with the user's token and opens the returned Stripe page in the browser:

- `{"action":"checkout","period":"month"|"year"}` creates the Stripe customer on first use (metadata `user_id`) and a Checkout Session for the matching price. The yearly plan gets `trial_period_days: 7` while `flype_subscription_status()` still offers the trial. A payment method is always collected, so the trial turns into the subscription on its own. If a subscription already runs, the answer is the customer portal instead, so nobody pays twice.
- `{"action":"portal"}` opens the customer portal to change plan, payment method or cancel.
- `{"action":"cancel"}` ends every running subscription immediately. The apps call it right before deleting the account and stop if it fails, so a deleted account is never billed again.

After checkout or the portal, Stripe returns to `billing.html` on the website (`?result=success|cancel|portal`), which leads back to the app.

In the app, Flype Pro appears under **Dein Konto** once signed in (`shared/App/SubscriptionView.swift`, Mac only for now). Without Pro, it offers the yearly plan (preselected, with the trial while it is open) and the monthly plan; with Pro, it shows the plan, the trial end, the renewal or end date (`period_ends_at`), a failed payment, and "Abo verwalten" for Stripe. The app asks `flype_subscription_status()` once a minute with the sync, and on every sync for ten minutes after it opened a Stripe page or the website sent it back through `flype-mac://billing/done`. Deleting the account calls `cancel` first, and the confirmation says that a Stripe subscription ends and an App Store subscription does not.

The Edge Function `stripe-webhook` keeps `flype_entitlements` in step. It checks the `Stripe-Signature` header itself, so it runs without a Supabase token. For `checkout.session.completed` and every `customer.subscription.*` event it fetches the subscription from Stripe and writes its current state, so the order of events does not matter:

| Stripe status | Entitlement |
| --- | --- |
| `trialing`, `active` | until the period end plus 3 days of grace |
| `past_due`, `unpaid` | until 3 days after the period start, while Stripe retries the payment |
| `canceled`, `incomplete_expired`, `paused` | ends when the subscription ended |
| `incomplete` | nothing, the first payment did not go through |

A trial records `trial_used_at`. An ending older subscription never replaces a newer one that still runs. Events for a deleted account are acknowledged and dropped.

Logs name only the event type, the step and the outcome, never an account, customer or amount.

### Setting up Stripe

1. In the Stripe dashboard, create the product "Flype Pro" with two recurring EUR prices: 5.95 € monthly and 59.95 € yearly, tax behaviour inclusive. The trial is set by the function, not on the price.
2. Optional: create a tax rate "USt. 19 %", inclusive, so invoices show the VAT.
3. Configure the customer portal: cancel at period end, switch between the two prices, update the payment method. The default return URL is `https://soeenplop.github.io/flype/billing.html?result=portal`.
4. Add the webhook endpoint `https://leystmzdybimmbaruywp.supabase.co/functions/v1/stripe-webhook` with the events `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated` and `customer.subscription.deleted`.
5. Set the secrets and deploy:

   ```sh
   supabase secrets set STRIPE_SECRET_KEY=… STRIPE_WEBHOOK_SECRET=… \
     STRIPE_PRICE_MONTH=price_… STRIPE_PRICE_YEAR=price_… STRIPE_TAX_RATE_ID=txr_…
   supabase functions deploy billing
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```

   `STRIPE_TAX_RATE_ID` is optional. `BILLING_RETURN_URL` overrides the return page.

Use test mode keys first. `stripe listen --forward-to <local function URL>` and `stripe trigger customer.subscription.updated` exercise the webhook without real payments.

## App Store (iPhone and iPad)

Both plans are auto-renewable subscriptions in the group "Flype Pro": `one.binda.flype.pro.yearly` (level 1, introductory offer free for one week) and `one.binda.flype.pro.monthly` (level 2, no offer). Apple decides who still gets the introductory offer, once per Apple ID and group.

The app buys with `appAccountToken` set to the Supabase user ID and reports every verified transaction to the Edge Function `app-store-verify` (`{"transactionId":"…"}`, with the user's token). The function asks the App Store Server API (`/inApps/v1/subscriptions/{transactionId}`, production first, then the sandbox) for the current state and writes it with `source = 'app_store'` and `external_id` = the original transaction ID. It answers with `flype_subscription_status()`. A purchase whose token names another account, or that already belongs to one, answers 409 and changes nothing. A transaction without a token, such as a redeemed offer code, goes to the reporting account if no account has it yet.

The Edge Function `app-store-notifications` receives App Store Server Notifications V2. It reads only the transaction ID and environment from the payload and fetches the state from Apple, so a forged notification grants nothing; the payload signature is therefore not checked. Test notifications and other apps are acknowledged.

| Apple status | Entitlement |
| --- | --- |
| 1 active | until the expiry plus 3 days of grace; `trialing` during the introductory offer |
| 4 billing grace period | until Apple's grace period ends |
| 3 billing retry | ends at the expiry |
| 2 expired, 5 revoked | ends at the expiry or refund |

An introductory offer records `trial_used_at`, so the Stripe trial on the Mac is no longer offered either.

In the app, Flype Pro appears under **Dein Konto** like on the Mac (`shared/App/SubscriptionView.swift`). "Flype Pro ansehen" opens Apple's `SubscriptionStoreView` with both plans, the introductory offer, the privacy policy and Apple's standard EULA; "Käufe wiederherstellen" runs `AppStore.sync()` and reports the active transactions. `ios/App/AppStoreSubscriptions.swift` listens to `Transaction.updates` from launch, reports unfinished transactions again at every sign-in and finishes a transaction only after the server recorded it or said it belongs to another account. A Pro from Stripe shows without a link to Stripe.

For the simulator, the scheme uses `ios/Flype.storekit` with both products. Purchases there are signed locally and unknown to Apple, so the server cannot record them and the transaction stays unfinished; the whole flow needs a sandbox account on a device.

### Setting up the App Store

1. In App Store Connect, create the subscription group and both subscriptions with the IDs above, prices 5.95 € and 59.95 € with Germany as the base country, and the free one-week introductory offer on the yearly plan only.
2. Under Users and Access > Integrations > In-App Purchase, generate a key. Set its contents and IDs as secrets and deploy:

   ```sh
   supabase secrets set APP_STORE_ISSUER_ID=… APP_STORE_KEY_ID=… APP_STORE_PRIVATE_KEY="$(cat SubscriptionKey_….p8)"
   supabase functions deploy app-store-verify
   supabase functions deploy app-store-notifications --no-verify-jwt
   ```
3. Under App Information > App Store Server Notifications, set `https://leystmzdybimmbaruywp.supabase.co/functions/v1/app-store-notifications`, version 2, for production and sandbox.

## Checks

`./scripts/check.sh backend` tests the App Store token, ownership and status mapping, the Stripe signature check, the mapping of every subscription state, the trial rules, the double-checkout guard and cancellation with fake Stripe and database answers. `./scripts/check.sh database` tests the tables and `flype_subscription_status()`.
