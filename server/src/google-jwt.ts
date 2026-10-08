/* INSURE QUEST｜Google ID Token 驗證（RS256，WebCrypto）。
 * FedCM／One Tap 由瀏覽器把 ID Token 交給我們，必須驗證簽章（不能只看內容），
 * 並檢查 iss、aud、exp、email_verified 與 nonce（防重放）。
 */

const GOOGLE_CERTS = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = ['https://accounts.google.com', 'accounts.google.com'];

export interface GoogleClaims {
  sub: string; email: string; email_verified: boolean; name?: string; picture?: string;
  iss: string; aud: string; exp: number; nonce?: string;
}

/** 取得 Google 公鑰（JWK）；依 Cache-Control 快取在 isolate 記憶體 */
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
 * 驗證 Google ID Token；任何一項不符都回傳 null。
 * expectedNonce 為 undefined 時不檢查 nonce（授權碼流程由伺服器直接向 Google 換得，沒有 nonce）。
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
    if (expectedNonce !== undefined && (!expectedNonce || c.nonce !== expectedNonce)) return null;
    return c;
  } catch {
    return null;
  }
}
