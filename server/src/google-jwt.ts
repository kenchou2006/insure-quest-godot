/* INSURE QUEST | Google ID Token verification (RS256, WebCrypto).
 * FedCM / One Tap passes the ID Token to us from the browser; we must verify the signature (not just inspect content),
 * and check iss, aud, exp, email_verified, and nonce (replay attack prevention).
 */

const GOOGLE_CERTS = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];

export interface GoogleClaims {
  sub: string; email: string; email_verified: boolean; name?: string; picture?: string;
  iss: string; aud: string; exp: number; nonce?: string;
}

/** Retrieves Google public keys (JWK); cached in isolate memory according to Cache-Control */
export type KeyFetcher = () => Promise<JsonWebKey[]>;
let cache: { keys: JsonWebKey[]; until: number } | null = null;
export const fetchGoogleKeys: KeyFetcher = async () => {
  if (cache && cache.until > Date.now()) return cache.keys;
  const res = await fetch(GOOGLE_CERTS);
  if (!res.ok) throw new Error(`Google certs ${res.status}`);
  const maxAge = Number(/max-age=(\d+)/.exec(res.headers.get('Cache-Control') || '')?.[1] ?? 3600);
  const { keys } = await res.json<{ keys: JsonWebKey[] }>();
  cache = { keys, until: Date.now() + maxAge * 1000 };
  return keys;
};

function b64urlBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0));
}
function b64urlJson(s: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(b64urlBytes(s)));
}

/**
 * Verifies Google ID Token; returns null if any check fails.
 * When expectedNonce is undefined, nonce is not checked (auth code flow exchanged directly with Google has no nonce).
 */
export async function verifyGoogleIdToken(token: string, clientId: string, expectedNonce?: string, keys: KeyFetcher = fetchGoogleKeys, now = Date.now()): Promise<GoogleClaims | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [h, p, sig] = parts;
    const header = b64urlJson(h) as { alg?: string; kid?: string };
    if (header.alg !== 'RS256' || !header.kid) return null;
    const jwk = (await keys()).find(k => (k as JsonWebKey & { kid?: string }).kid === header.kid);
    if (!jwk) return null;
    const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(sig), new TextEncoder().encode(`${h}.${p}`));
    if (!ok) return null;
    const c = b64urlJson(p) as unknown as GoogleClaims;
    if (!ISSUERS.includes(c.iss)) return null;
    if (c.aud !== clientId) return null;
    if (!c.exp || c.exp * 1000 < now) return null;
    if (c.email_verified !== true || !c.sub) return null;
    if (expectedNonce !== undefined) {
      if (!expectedNonce || !c.nonce || c.nonce !== expectedNonce) {
        if (!c.nonce) console.warn('Google ID token lacked nonce when nonce was expected');
        return null;
      }
    } else if (c.nonce) {
      return null;
    }
    return c;
  } catch {
    return null;
  }
}
