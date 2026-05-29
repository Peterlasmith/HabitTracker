const CORS_HEADERS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "GET, POST, OPTIONS",
};

export function withCors(headers = {}) {
  return {
    ...CORS_HEADERS,
    ...headers,
  };
}

export function json(data, init = {}) {
  const headers = withCors({
    "content-type": "application/json; charset=utf-8",
    ...(init.headers ?? {}),
  });

  return new Response(JSON.stringify(data, null, 2), {
    ...init,
    headers,
  });
}

export function errorResponse(status, message, extra = {}) {
  return json(
    {
      error: {
        message,
        status,
        ...extra,
      },
    },
    { status }
  );
}

export function optionsResponse() {
  return new Response(null, {
    status: 204,
    headers: withCors(),
  });
}

export async function parseBody(request) {
  const contentType = request.headers.get("content-type") ?? "";

  if (contentType.includes("application/json")) {
    return await request.json();
  }

  if (contentType.includes("application/x-www-form-urlencoded")) {
    const formData = await request.formData();
    return Object.fromEntries(formData.entries());
  }

  if (!contentType) {
    return {};
  }

  throw new Error(`Unsupported content type: ${contentType}`);
}

export function requiredEnv(name) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export function normalizePath(url, baseSuffix) {
  const pathname = new URL(url).pathname.replace(/\/+$/, "");
  return pathname.endsWith(baseSuffix) ? baseSuffix : pathname;
}
