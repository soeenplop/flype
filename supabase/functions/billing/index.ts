// Stripe checkout, customer portal and cancellation before account deletion, for the Mac app.
// Set STRIPE_SECRET_KEY, STRIPE_PRICE_MONTH and STRIPE_PRICE_YEAR as function secrets, and optionally
// STRIPE_TAX_RATE_ID for an inclusive tax rate on the invoices. The apps never see any of them.
import { createDatabase, createStripe } from "../_shared/billing.mjs";
import { createHandler } from "./handler.mjs";

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(createHandler({
  supabaseURL,
  fetch,
  stripe: secretKey ? createStripe({ secretKey, fetch }) : null,
  db: serviceKey ? createDatabase({ supabaseURL, serviceKey, fetch }) : null,
  prices: { month: Deno.env.get("STRIPE_PRICE_MONTH"), year: Deno.env.get("STRIPE_PRICE_YEAR") },
  taxRate: Deno.env.get("STRIPE_TAX_RATE_ID"),
  returnURL: Deno.env.get("BILLING_RETURN_URL") ?? "https://soeenplop.github.io/flype/billing.html",
}));
