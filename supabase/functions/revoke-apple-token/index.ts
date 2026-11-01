// Revokes the Sign in with Apple token before an account is deleted, as Apple requires.
// Set APPLE_CLIENT_ID and APPLE_CLIENT_SECRET as function secrets; the secret is the same signed
// JWT that the Supabase Apple provider uses.
Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response(null, { status: 405 });

  // The gateway also admits the public key without a user, so check for a signed-in user here.
  const user = await fetch(`${Deno.env.get("SUPABASE_URL")}/auth/v1/user`, {
    headers: {
      apikey: request.headers.get("apikey") ?? "",
      Authorization: request.headers.get("Authorization") ?? "",
    },
  });
  if (!user.ok) return new Response(null, { status: 401 });

  const clientID = Deno.env.get("APPLE_CLIENT_ID");
  const clientSecret = Deno.env.get("APPLE_CLIENT_SECRET");
  if (!clientID || !clientSecret) return new Response(null, { status: 503 });

  const body = await request.json().catch(() => null);
  // Keep compatibility with already installed clients.
  const token = body?.provider_token ?? body?.provider_refresh_token;
  const hint = body?.token_type_hint ?? "refresh_token";
  if (hint !== "refresh_token" && hint !== "access_token") return new Response(null, { status: 400 });
  if (typeof token !== "string" || token.length === 0) return new Response(null, { status: 400 });

  const response = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientID,
      client_secret: clientSecret,
      token,
      token_type_hint: hint,
    }),
  });
  return new Response("{}", {
    status: response.ok ? 200 : 502,
    headers: { "Content-Type": "application/json" },
  });
});
