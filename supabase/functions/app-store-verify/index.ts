// Records an App Store purchase for the signed-in account. Set APP_STORE_ISSUER_ID, APP_STORE_KEY_ID and
// APP_STORE_PRIVATE_KEY (the In-App Purchase key's .p8 contents) as function secrets.
import { createDatabase } from "../_shared/billing.mjs";
import { createAppStore } from "../_shared/appstore.mjs";
import { createHandler } from "./handler.mjs";

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const privateKey = Deno.env.get("APP_STORE_PRIVATE_KEY");
const keyID = Deno.env.get("APP_STORE_KEY_ID");
const issuerID = Deno.env.get("APP_STORE_ISSUER_ID");

Deno.serve(createHandler({
  supabaseURL,
  fetch,
  appStore: privateKey && keyID && issuerID ? createAppStore({ privateKey, keyID, issuerID, fetch }) : null,
  db: serviceKey ? createDatabase({ supabaseURL, serviceKey, fetch }) : null,
}));
