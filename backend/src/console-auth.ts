import { timingSafeEqual } from 'node:crypto';
import { sha256 } from './http.ts';

/** Browser-managed Basic authentication over HTTPS; never put the password in a URL. */
export async function authorizeConsole(request: Request, secret: string | undefined): Promise<boolean> {
  if (!secret) return false;
  const token = request.headers.get('authorization')?.match(/^Basic\s+(\S+)$/i)?.[1];
  if (!token) return false;
  let credentials: string;
  try { credentials = atob(token); } catch { return false; }
  if (!credentials.startsWith('admin:')) return false;
  return timingSafeEqual(new TextEncoder().encode(await sha256(credentials.slice(6))),
    new TextEncoder().encode(await sha256(secret)));
}
