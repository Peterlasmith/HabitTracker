// @ts-nocheck
import {
  errorResponse,
  json,
  normalizePath,
  optionsResponse,
  requiredEnv,
} from "../_shared/http.js";
import { buildCompletionResponse, buildHabitResponse, buildProfileResponse } from "../_shared/assistantDomain.js";
import { DEFAULT_SCOPE, normalizeScopes, sha256Hex } from "../_shared/security.js";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return optionsResponse();
  }

  if (request.method !== "GET") {
    return errorResponse(405, "This assistant API is read-only in v1.");
  }

  try {
    const token = await authenticateAssistantToken(request, DEFAULT_SCOPE);
    if (!token) {
      return errorResponse(401, "A valid assistant access token is required.");
    }

    const url = new URL(request.url);
    const timeZone = url.searchParams.get("timezone") ?? "UTC";
    const path = normalizePath(request.url, "/assistant-api");
    const [habits, completions] = await Promise.all([
      fetchHabits(token.user_id),
      fetchCompletions(token.user_id),
    ]);

    if (path.endsWith("/me")) {
      const user = await fetchUser(token.user_id);
      return json({
        data: buildProfileResponse(user, habits, completions),
        meta: {
          scopes: token.scope,
        },
      });
    }

    if (path.endsWith("/habits")) {
      const historyDays = Number(url.searchParams.get("history_days") ?? "14");
      const data = habits.map((habit) =>
        buildHabitResponse(
          habit,
          completionsForHabit(completions, habit.id),
          { timeZone, recentWindowDays: historyDays }
        )
      );

      return json({
        data,
        meta: {
          count: data.length,
        },
      });
    }

    if (path.includes("/habits/")) {
      const habitId = path.split("/habits/")[1];
      const habit = habits.find((candidate) => candidate.id === habitId);
      if (!habit) {
        return errorResponse(404, "Habit not found.");
      }

      return json({
        data: buildHabitResponse(habit, completionsForHabit(completions, habit.id), {
          timeZone,
          recentWindowDays: 30,
        }),
      });
    }

    if (path.endsWith("/completions")) {
      const habitId = url.searchParams.get("habit_id");
      const startDate = url.searchParams.get("start_date");
      const endDate = url.searchParams.get("end_date");
      const filtered = completions.filter((completion) => {
        if (habitId && completion.habit_id !== habitId) {
          return false;
        }
        if (startDate && completion.date < startDate) {
          return false;
        }
        if (endDate && completion.date > endDate) {
          return false;
        }
        return true;
      });

      const habitsById = new Map(habits.map((habit) => [habit.id, habit]));
      return json({
        data: filtered.map((completion) =>
          buildCompletionResponse(completion, habitsById.get(completion.habit_id) ?? null)
        ),
        meta: {
          count: filtered.length,
        },
      });
    }

    return errorResponse(404, "Assistant API route not found.");
  } catch (error) {
    return errorResponse(500, error instanceof Error ? error.message : "Unexpected error.");
  }
});

async function authenticateAssistantToken(request: Request, requiredScope: string) {
  const authHeader = request.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return null;
  }

  const rawToken = authHeader.replace("Bearer ", "").trim();
  const tokenHash = await sha256Hex(rawToken);
  const rows = await supabaseRest("assistant_access_tokens", {
    query: {
      select: "*",
      token_hash: `eq.${tokenHash}`,
      revoked_at: "is.null",
    },
  });
  const token = rows[0];

  if (!token) {
    return null;
  }

  if (new Date(token.expires_at).getTime() <= Date.now()) {
    return null;
  }

  if (!normalizeScopes(token.scope).includes(requiredScope)) {
    return null;
  }

  await supabaseRest(`assistant_access_tokens?id=eq.${token.id}`, {
    method: "PATCH",
    body: {
      last_used_at: new Date().toISOString(),
    },
  });

  return token;
}

async function fetchUser(userId: string) {
  const response = await fetch(`${requiredEnv("SUPABASE_URL")}/auth/v1/admin/users/${userId}`, {
    method: "GET",
    headers: {
      apikey: requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      authorization: `Bearer ${requiredEnv("SUPABASE_SERVICE_ROLE_KEY")}`,
    },
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Unable to load user profile: ${response.status} ${text}`);
  }

  const payload = await response.json();
  return payload.user ?? payload;
}

async function fetchHabits(userId: string) {
  return await supabaseRest("habits", {
    query: {
      select: "*",
      user_id: `eq.${userId}`,
      order: "created_at.asc",
    },
  });
}

async function fetchCompletions(userId: string) {
  return await supabaseRest("habit_completions", {
    query: {
      select: "*",
      user_id: `eq.${userId}`,
      order: "date.desc,created_at.desc",
    },
  });
}

function completionsForHabit(completions: Array<Record<string, unknown>>, habitId: string) {
  return completions.filter((completion) => completion.habit_id === habitId);
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
