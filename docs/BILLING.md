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

## Checks

`./scripts/check.sh backend` tests the signature check, the mapping of every subscription state, the trial rules, the double-checkout guard and cancellation with fake Stripe and database answers. `./scripts/check.sh database` tests the tables and `flype_subscription_status()`.
