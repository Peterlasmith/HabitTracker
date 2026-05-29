// @ts-nocheck
import {
  errorResponse,
  json,
  optionsResponse,
  parseBody,
  requiredEnv,
} from "../_shared/http.js";

class HttpError extends Error {
  status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return optionsResponse();
  }

  if (request.method !== "POST") {
    return errorResponse(405, "Use POST to permanently delete an account.");
  }

  try {
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return errorResponse(401, "A signed-in HabitClaw session is required.");
    }

    const user = await authenticatedSupabaseUser(authHeader);
    if (!user) {
      return errorResponse(401, "Your session is no longer valid. Sign in again before deleting your account.");
    }

    const body = await parseBody(request);
    const currentPassword = String(body.current_password ?? "").trim();
    if (!currentPassword) {
      return errorResponse(400, "current_password is required.");
    }

    await verifyCurrentPassword(user.email, currentPassword);

    const deleted = {
      habits: await deleteRows("habits", user.id),
      habit_completions: await deleteRows("habit_completions", user.id),
      assistant_authorization_codes: await deleteRows("assistant_authorization_codes", user.id),
      assistant_access_tokens: await deleteRows("assistant_access_tokens", user.id),
    };

    await deleteAuthUser(user.id);

    const verification = {
      auth_user_deleted: !(await authUserExists(user.id)),
      habits_remaining: await countRows("habits", user.id),
      habit_completions_remaining: await countRows("habit_completions", user.id),
      assistant_authorization_codes_remaining: await countRows("assistant_authorization_codes", user.id),
      assistant_access_tokens_remaining: await countRows("assistant_access_tokens", user.id),
    };

    if (
      !verification.auth_user_deleted ||
      verification.habits_remaining > 0 ||
      verification.habit_completions_remaining > 0 ||
      verification.assistant_authorization_codes_remaining > 0 ||
      verification.assistant_access_tokens_remaining > 0
    ) {
      throw new Error("Account deletion verification failed.");
    }

    return json({
      data: {
        deleted,
        verification,
      },
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return errorResponse(error.status, error.message);
    }

    return errorResponse(500, error instanceof Error ? error.message : "Unexpected account deletion error.");
  }
});

async function authenticatedSupabaseUser(authHeader: string) {
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

async function verifyCurrentPassword(email: string, password: string) {
  if (!email) {
    throw new HttpError(400, "Re-authenticate with your sign-in provider before deleting this account.");
  }

  const url = new URL(`${requiredEnv("SUPABASE_URL")}/auth/v1/token`);
  url.searchParams.set("grant_type", "password");

  const response = await fetch(url, {
    method: "POST",
    headers: {
      apikey: requiredEnv("SUPABASE_ANON_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_ANON_KEY")}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      email,
      password,
    }),
  });

  if (!response.ok) {
    throw new HttpError(401, "Password confirmation failed. Double-check it and try again.");
  }
}

async function deleteRows(table: string, userId: string) {
  const url = new URL(`${requiredEnv("SUPABASE_URL")}/rest/v1/${table}`);
  url.searchParams.set("user_id", `eq.${userId}`);
  url.searchParams.set("select", "id");

  const response = await fetch(url, {
    method: "DELETE",
    headers: {
      apikey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
      "content-type": "application/json",
      accept: "application/json",
      prefer: "return=representation",
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to delete ${table}: ${response.status} ${text}`);
  }

  const rows = await response.json();
  return Array.isArray(rows) ? rows.length : 0;
}

async function countRows(table: string, userId: string) {
  const rows = await supabaseRest(table, {
    query: {
      select: "id",
      user_id: `eq.${userId}`,
    },
  });

  return Array.isArray(rows) ? rows.length : 0;
}

async function deleteAuthUser(userId: string) {
  const response = await fetch(`${requiredEnv("SUPABASE_URL")}/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
    headers: {
      apikey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify({
      should_soft_delete: false,
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to delete auth user: ${response.status} ${text}`);
  }
}

async function authUserExists(userId: string) {
  const response = await fetch(`${requiredEnv("SUPABASE_URL")}/auth/v1/admin/users/${userId}`, {
    method: "GET",
    headers: {
      apikey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
    },
  });

  if (response.status === 404) {
    return false;
  }

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Failed to verify auth user deletion: ${response.status} ${text}`);
  }

  return true;
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
