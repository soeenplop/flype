// Cleans dictated text with OpenAI for signed-in users who opted in.
// Set OPENAI_API_KEY as a function secret. It never reaches the apps.
import OpenAI from "npm:openai@7.50.0";
import { createHandler } from "./handler.mjs";

const apiKey = Deno.env.get("OPENAI_API_KEY");
// The app shows the original text after a failure, so a slow retry would only make people wait.
const client = apiKey ? new OpenAI({ apiKey, timeout: 12_000, maxRetries: 0 }) : null;

const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
// HEAD requests without credentials only open the connections that later requests reuse.
const open = (url: string) => fetch(url, { method: "HEAD" }).then((response) => response.body?.cancel());

Deno.serve(createHandler({
  supabaseURL,
  fetch,
  preconnect: () => Promise.all([open(`${supabaseURL}/rest/v1/`), open("https://api.openai.com/v1/")]),
  createResponse: client ? (params) => client.responses.create(params) : null,
}));
