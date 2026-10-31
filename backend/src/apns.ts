import type { ActivityState } from "./domain.ts";
import { boundedJSON } from "./http.ts";
const b64 = (a: Uint8Array) =>
  btoa(String.fromCharCode(...a))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
const encode = (x: unknown) => b64(new TextEncoder().encode(JSON.stringify(x)));
export async function jwt(env: Env): Promise<string> {
  if (!env.APNS_PRIVATE_KEY || !env.APNS_TEAM_ID || !env.APNS_KEY_ID)
    throw new Error("apns_not_configured");
  const pem = env.APNS_PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(
    /\s/g,
    "",
  );
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(pem), (c) => c.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const input = `${encode({ alg: "ES256", kid: env.APNS_KEY_ID })}.${encode({ iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  return `${input}.${b64(new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input))))}`;
}
export async function sendAPNs(
  env: Env,
  token: string,
  environment: string,
  payload: unknown,
  activity: boolean,
  priority = 5,
): Promise<{ ok: boolean; permanent: boolean; reason?: string }> {
  const host =
    environment === "sandbox"
      ? "api.sandbox.push.apple.com"
      : "api.push.apple.com";
  const body = JSON.stringify(payload);
  if (new TextEncoder().encode(body).length > 4096)
    return { ok: false, permanent: false, reason: "payload_too_large" };
  try {
    const response = await fetch(
      `${env.APNS_PROXY_URL || `https://${host}`}/3/device/${token}`,
      {
        method: "POST",
        signal: AbortSignal.timeout(12000),
        headers: {
          authorization: `bearer ${await jwt(env)}`,
          "content-type": "application/json",
          "apns-topic":
            env.APNS_BUNDLE_ID + (activity ? ".push-type.liveactivity" : ""),
          "apns-push-type": activity ? "liveactivity" : "alert",
          "apns-priority": String(priority),
          "x-apns-environment": environment,
        },
        body,
      },
    );
    if (response.ok) return { ok: true, permanent: false };
    const error = await boundedJSON(response, 4096).catch(() => ({
      reason: "invalid_response",
    }));
    const reason =
      typeof error === "object" && error && "reason" in error
        ? String(error.reason)
        : "unknown";
    return {
      ok: false,
      permanent:
        response.status === 410 ||
        reason === "BadDeviceToken" ||
        reason === "DeviceTokenNotForTopic",
      reason,
    };
  } catch {
    return { ok: false, permanent: false, reason: "transport_failure" };
  }
}
export function activityPayload(
  state: ActivityState,
  timestamp: number,
  end = false,
) {
  return {
    aps: {
      timestamp,
      event: end ? "end" : "update",
      "content-state": state,
      "stale-date": Math.trunc(state.validUntilEpoch),
      ...(end ? { "dismissal-date": timestamp + 3600 } : {}),
    },
  };
}
