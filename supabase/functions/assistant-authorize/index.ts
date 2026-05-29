// @ts-nocheck
import {
  errorResponse,
  json,
  normalizePath,
  optionsResponse,
  parseBody,
  requiredEnv,
} from "../_shared/http.js";
import {
  DEFAULT_SCOPE,
  createOpaqueToken,
  ensureScopesAllowed,
  normalizeScopes,
  sha256Hex,
  verifyPkce,
} from "../_shared/security.js";

const AUTH_CODE_TTL_SECONDS = 10 * 60;
const ACCESS_TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return optionsResponse();
  }

  try {
    const path = normalizePath(request.url, "/assistant-authorize");

    if (request.method === "POST" && path.endsWith("/authorize")) {
      return await handleAuthorize(request);
    }

    if (request.method === "POST" && path.endsWith("/token")) {
      return await handleToken(request);
    }

    return errorResponse(404, "Assistant auth route not found.");
  } catch (error) {
    return errorResponse(500, error instanceof Error ? error.message : "Unexpected error.");
  }
});

async function handleAuthorize(request: Request) {
  const user = await authenticatedSupabaseUser(request);
  if (!user) {
    return errorResponse(401, "A signed-in HabitClaw user session is required.");
  }

  const body = await parseBody(request);
  const clientIdentifier = String(body.client_id ?? "").trim();
  const redirectUri = String(body.redirect_uri ?? "").trim();
  const requestedScopes = normalizeScopes(body.scope ?? [DEFAULT_SCOPE]);
  const approve = body.approve !== false && body.approve !== "false";

  if (!clientIdentifier || !redirectUri) {
    return errorResponse(400, "client_id and redirect_uri are required.");
  }

  if (!approve) {
    return errorResponse(400, "The authorization request was not approved.");
  }

  const client = await fetchAssistantClient(clientIdentifier);
  if (!client || client.revoked_at) {
    return errorResponse(404, "Assistant client not found.");
  }

  if (!client.redirect_uris.includes(redirectUri)) {
    return errorResponse(400, "Redirect URI is not registered for this assistant client.");
  }

  if (!ensureScopesAllowed(requestedScopes, client.allowed_scopes)) {
    return errorResponse(400, "Requested scopes are not allowed for this assistant client.");
  }

  const rawCode = createOpaqueToken(24);
  const codeHash = await sha256Hex(rawCode);
  const expiresAt = new Date(Date.now() + AUTH_CODE_TTL_SECONDS * 1000).toISOString();
  const payload = {
    code_hash: codeHash,
    client_id: client.id,
    user_id: user.id,
    redirect_uri: redirectUri,
    scope: requestedScopes,
    code_challenge: body.code_challenge ? String(body.code_challenge) : null,
    code_challenge_method: body.code_challenge_method ? String(body.code_challenge_method) : null,
    expires_at: expiresAt,
  };

  await supabaseRest("assistant_authorization_codes", {
    method: "POST",
    body: payload,
  });

  return json({
    data: {
      code: rawCode,
      redirect_uri: redirectUri,
      scope: requestedScopes,
      expires_at: expiresAt,
      state: body.state ?? null,
    },
  });
}

async function handleToken(request: Request) {
  const body = await parseBody(request);
  const clientIdentifier = String(body.client_id ?? "").trim();
  const clientSecret = String(body.client_secret ?? "").trim();
  const redirectUri = String(body.redirect_uri ?? "").trim();
  const rawCode = String(body.code ?? "").trim();
  const grantType = String(body.grant_type ?? "").trim();

  if (grantType !== "authorization_code") {
    return errorResponse(400, "Only authorization_code grant_type is supported.");
  }

  if (!clientIdentifier || !clientSecret || !redirectUri || !rawCode) {
    return errorResponse(400, "client_id, client_secret, redirect_uri, and code are required.");
  }

  const client = await fetchAssistantClient(clientIdentifier);
  if (!client || client.revoked_at) {
    return errorResponse(404, "Assistant client not found.");
  }

  const secretHash = await sha256Hex(clientSecret);
  if (secretHash !== client.client_secret_hash) {
    return errorResponse(401, "Assistant client credentials are invalid.");
  }

  const codeHash = await sha256Hex(rawCode);
  const codeRows = await supabaseRest("assistant_authorization_codes", {
    query: {
      select: "*",
      code_hash: `eq.${codeHash}`,
      client_id: `eq.${client.id}`,
      revoked_at: "is.null",
    },
  });
  const authorizationCode = codeRows[0];

  if (!authorizationCode) {
    return errorResponse(400, "Authorization code is invalid.");
  }

  if (authorizationCode.redirect_uri !== redirectUri) {
    return errorResponse(400, "Redirect URI did not match the original authorization request.");
  }

  if (authorizationCode.consumed_at) {
    return errorResponse(400, "Authorization code has already been used.");
  }

  if (new Date(authorizationCode.expires_at).getTime() <= Date.now()) {
    return errorResponse(400, "Authorization code has expired.");
  }

  const pkceValid = await verifyPkce(
    body.code_verifier ? String(body.code_verifier) : null,
    authorizationCode.code_challenge,
    authorizationCode.code_challenge_method ?? "plain"
  );

  if (!pkceValid) {
    return errorResponse(400, "PKCE verification failed.");
  }

  await supabaseRest(`assistant_authorization_codes?id=eq.${authorizationCode.id}`, {
    method: "PATCH",
    body: {
      consumed_at: new Date().toISOString(),
    },
  });

  const rawAccessToken = createOpaqueToken(32);
  const accessTokenHash = await sha256Hex(rawAccessToken);
  const expiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_SECONDS * 1000).toISOString();
  await supabaseRest("assistant_access_tokens", {
    method: "POST",
    body: {
      token_hash: accessTokenHash,
      client_id: client.id,
      user_id: authorizationCode.user_id,
      scope: authorizationCode.scope,
      expires_at: expiresAt,
    },
  });

  return json({
    data: {
      access_token: rawAccessToken,
      token_type: "Bearer",
      expires_in: ACCESS_TOKEN_TTL_SECONDS,
      scope: authorizationCode.scope.join(" "),
      user_id: authorizationCode.user_id,
    },
  });
}

async function authenticatedSupabaseUser(request: Request) {
  const authHeader = request.headers.get("authorization");
  if (!authHeader) {
    return null;
  }

  const response = await fetch(`${requiredEnv("SUPABASE_URL")}/auth/v1/user`, {
    method: "GET",
    headers: {
      apikey: requiredEnv("SUPABASE_ANON_KEY"),
      authorization: authHeader,
    },
  });

  if (!response.ok) {
    return null;
  }

  return await response.json();
}

async function fetchAssistantClient(clientIdentifier: string) {
  const rows = await supabaseRest("assistant_clients", {
    query: {
      select: "*",
      client_identifier: `eq.${clientIdentifier}`,
    },
  });
  return rows[0] ?? null;
}

async function supabaseRest(
  path: string,
  options: {
    method?: string;
    body?: Record<string, unknown>;
    query?: Record<string, string>;
  } = {}
) {
  const url = new URL(`${requiredEnv("SUPABASE_URL")}/rest/v1/${path}`);
  Object.entries(options.query ?? {}).forEach(([key, value]) => {
    url.searchParams.set(key, value);
  });

  const response = await fetch(url, {
    method: options.method ?? "GET",
    headers: {
      apikey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
      "content-type": "application/json",
      accept: "application/json",
      prefer: "return=representation",
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase request failed: ${response.status} ${text}`);
  }

  return await response.json();
}
