export const DEFAULT_SCOPE = "habits.read";

export function normalizeScopes(input) {
  const values = Array.isArray(input)
    ? input
    : typeof input === "string"
    ? input.split(/[,\s]+/)
    : [];

  return [...new Set(values.map((value) => String(value).trim()).filter(Boolean))];
}

export function ensureScopesAllowed(requestedScopes, allowedScopes) {
  const allowed = new Set(normalizeScopes(allowedScopes));
  return normalizeScopes(requestedScopes).every((scope) => allowed.has(scope));
}

export function createOpaqueToken(bytes = 32) {
  return encodeHex(crypto.getRandomValues(new Uint8Array(bytes)));
}

export async function sha256Hex(value) {
  const encoded = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return encodeHex(new Uint8Array(digest));
}

export async function verifyPkce(verifier, challenge, method = "plain") {
  if (!challenge) {
    return true;
  }

  if (!verifier) {
    return false;
  }

  if (method === "plain") {
    return verifier === challenge;
  }

  if (method === "S256") {
    const encoded = new TextEncoder().encode(verifier);
    const digest = await crypto.subtle.digest("SHA-256", encoded);
    const actual = encodeBase64Url(new Uint8Array(digest));
    return actual === challenge;
  }

  return false;
}

function encodeHex(bytes) {
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
}

function encodeBase64Url(bytes) {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
