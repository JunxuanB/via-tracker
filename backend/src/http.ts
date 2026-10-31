export class APIError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}
export const json = (data: unknown, status = 200, headers?: HeadersInit) =>
  Response.json(data, {
    status,
    headers: { "cache-control": "no-store", ...headers },
  });
export async function boundedJSON(
  request: Request | Response,
  limit = 256_000,
): Promise<unknown> {
  if (!request.body) throw new APIError(400, "empty_body");
  const reader = request.body.getReader(),
    chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) throw new APIError(413, "body_too_large");
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const c of chunks) {
      bytes.set(c, offset);
      offset += c.length;
    }
    try {
      return JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      throw new APIError(400, "invalid_json");
    }
  } finally {
    await reader.cancel();
  }
}
export const sha256 = async (s: string) =>
  [
    ...new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)),
    ),
  ]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("");
export const obj = (v: unknown): Record<string, unknown> => {
  if (!v || typeof v !== "object" || Array.isArray(v))
    throw new APIError(400, "expected_object");
  return v as Record<string, unknown>;
};
export function str(v: unknown, max = 200): string {
  if (typeof v !== "string" || !v.length || v.length > max)
    throw new APIError(400, "invalid_string");
  return v;
}
export function int(v: unknown, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max)
    throw new APIError(400, "invalid_integer");
  return v;
}
