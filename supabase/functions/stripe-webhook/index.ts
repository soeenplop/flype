// Keeps flype_entitlements in step with Stripe subscriptions. Set STRIPE_SECRET_KEY and
// STRIPE_WEBHOOK_SECRET as function secrets and deploy with --no-verify-jwt.
import { createDatabase, createStripe } from "../_shared/billing.mjs";
import { createHandler } from "./handler.mjs";

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const secretKey = Deno.env.get("STRIPE_SECRET_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

Deno.serve(createHandler({
  stripe: secretKey ? createStripe({ secretKey, fetch }) : null,
  db: serviceKey ? createDatabase({ supabaseURL, serviceKey, fetch }) : null,
  webhookSecret: Deno.env.get("STRIPE_WEBHOOK_SECRET"),
}));
