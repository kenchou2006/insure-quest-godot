/* INSURE QUEST｜Google 登入（OAuth 2.0 授權碼流程，全部在 Worker 處理）。
 * - 工作階段存在 HttpOnly Cookie，Godot 的 HTTPRequest／WebSocket 同源會自動帶上，前端不接觸 token。
 * - state 參數放在短效 Cookie，回呼時比對，防止 CSRF。
 * - 兩種登入方式：FedCM／One Tap（瀏覽器取得 ID Token 後 POST 給我們）與授權碼重新導向（退路）；兩者都驗證 RS256 簽章、iss／aud／exp／email_verified，FedCM 另外檢查 nonce。
 */
import type { Env } from './index.ts';
import type { User } from './records.ts';
import { verifyGoogleIdToken, type GoogleClaims } from './google-jwt.ts';

export const SESSION_COOKIE = 'iq_session';
const STATE_COOKIE = 'iq_oauth_state';
const NONCE_COOKIE = 'iq_gnonce';
const GOOGLE_AUTH = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN = 'https://oauth2.googleapis.com/token';

export function googleEnabled(env: Env) { return !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET); }

function isLocalHost(url: URL) { return ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname); }

/** 本機開發專用的測試登入：必須同時設定 DEV_LOGIN=1 且請求來自 localhost */
export function devLoginEnabled(env: Env, url: URL) { return env.DEV_LOGIN === '1' && isLocalHost(url); }

export function readCookie(req: Request, name: string): string | null {
  const header = req.headers.get('Cookie') || '';
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return null;
}

function cookie(name: string, value: string, url: URL, maxAge: number, path = '/') {
  const secure = url.protocol === 'https:' ? '; Secure' : '';
  return `${name}=${encodeURIComponent(value)}; Path=${path}; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

/** 只允許站內相對路徑，避免開放重新導向 */
function safeReturn(raw: string | null): string {
  return raw && raw.startsWith('/') && !raw.startsWith('//') && !raw.includes('\\') ? raw : '/';
}

function randomHex(bytes: number) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), b => b.toString(16).padStart(2, '0')).join('');
}

function records(env: Env) { return env.RECORDS.get(env.RECORDS.idFromName('global')); }

export async function currentUser(req: Request, env: Env): Promise<User | null> {
  const token = readCookie(req, SESSION_COOKIE);
  return token ? records(env).getSessionUser(token) : null;
}

export function isTrainer(env: Env, user: User | null) {
  if (!user) return false;
  const list = (env.TRAINER_EMAILS || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  return list.includes(user.email.toLowerCase());
}

async function startSession(env: Env, url: URL, user: User, returnTo: string): Promise<Response> {
  await records(env).upsertUser(user);
  const token = await records(env).createSession(user.id);
  const headers = new Headers({ Location: returnTo });
  headers.append('Set-Cookie', cookie(SESSION_COOKIE, token, url, 30 * 86400));
  headers.append('Set-Cookie', cookie(STATE_COOKIE, '', url, 0, '/api/auth'));
  return new Response(null, { status: 302, headers });
}

function userFromClaims(c: GoogleClaims): User {
  return { id: `g:${c.sub}`, email: String(c.email || ''), name: String(c.name || c.email || 'Google 使用者'), picture: c.picture ? String(c.picture) : null };
}

/** POST 請求必須同源（搭配 SameSite=Lax Cookie 防 CSRF） */
function sameOriginPost(req: Request, url: URL) {
  const origin = req.headers.get('Origin');
  if (!origin) return false;
  try { return new URL(origin).host === url.host; } catch { return false; }
}

/** 處理 /api/auth/*；不屬於登入路由時回傳 null */
export async function handleAuth(req: Request, env: Env, url: URL): Promise<Response | null> {
  const redirectUri = `${url.origin}/api/auth/google/callback`;

  if (url.pathname === '/api/auth/config') {
    return Response.json({ google: googleEnabled(env), googleClientId: googleEnabled(env) ? env.GOOGLE_CLIENT_ID : null, dev: devLoginEnabled(env, url) });
  }

  // FedCM／One Tap：先取一次性 nonce（綁在短效 Cookie），Google 會把它放進 ID Token
  if (url.pathname === '/api/auth/google/nonce') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    const nonce = randomHex(16);
    return new Response(JSON.stringify({ nonce }), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Set-Cookie': cookie(NONCE_COOKIE, nonce, url, 600, '/api/auth') } });
  }

  // FedCM／One Tap 回傳的 ID Token：驗證簽章與 nonce 後建立工作階段
  if (url.pathname === '/api/auth/google/credential' && req.method === 'POST') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    if (!sameOriginPost(req, url)) return Response.json({ error: 'forbidden' }, { status: 403 });
    const { credential } = await req.json<{ credential?: string }>().catch(() => ({ credential: undefined }));
    const nonce = readCookie(req, NONCE_COOKIE) || '';
    const claims = credential ? await verifyGoogleIdToken(credential, env.GOOGLE_CLIENT_ID!, nonce) : null;
    if (!claims) return Response.json({ error: '登入驗證失敗' }, { status: 401 });
    const user = userFromClaims(claims);
    await records(env).upsertUser(user);
    const token = await records(env).createSession(user.id);
    const headers = new Headers({ 'Content-Type': 'application/json' });
    headers.append('Set-Cookie', cookie(SESSION_COOKIE, token, url, 30 * 86400));
    headers.append('Set-Cookie', cookie(NONCE_COOKIE, '', url, 0, '/api/auth'));
    return new Response(JSON.stringify({ ok: true, name: user.name }), { headers });
  }

  if (url.pathname === '/api/auth/google/start') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    const state = randomHex(16);
    const returnTo = safeReturn(url.searchParams.get('return'));
    const target = new URL(GOOGLE_AUTH);
    target.search = new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID!, redirect_uri: redirectUri, response_type: 'code',
      scope: 'openid email profile', state, prompt: 'select_account',
    }).toString();
    const headers = new Headers({ Location: target.toString() });
    headers.append('Set-Cookie', cookie(STATE_COOKIE, `${state}|${returnTo}`, url, 600, '/api/auth'));
    return new Response(null, { status: 302, headers });
  }

  if (url.pathname === '/api/auth/google/callback') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    const [expected, returnTo] = (readCookie(req, STATE_COOKIE) || '').split('|');
    const state = url.searchParams.get('state');
    const code = url.searchParams.get('code');
    if (!expected || !state || state !== expected || !code) return Response.redirect(`${url.origin}/?login=failed`, 302);
    const tokenRes = await fetch(GOOGLE_TOKEN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!, redirect_uri: redirectUri, grant_type: 'authorization_code' }),
    });
    if (!tokenRes.ok) { console.warn('Google token exchange failed', tokenRes.status); return Response.redirect(`${url.origin}/?login=failed`, 302); }
    const { id_token } = await tokenRes.json<{ id_token?: string }>();
    // 一併驗證簽章（縱深防禦）
    const claims = id_token ? await verifyGoogleIdToken(id_token, env.GOOGLE_CLIENT_ID!) : null;
    if (!claims) return Response.redirect(`${url.origin}/?login=failed`, 302);
    return startSession(env, url, userFromClaims(claims), safeReturn(returnTo));
  }

  if (url.pathname === '/api/auth/dev-login') {
    if (!devLoginEnabled(env, url)) return new Response('not found', { status: 404 });
    const name = (url.searchParams.get('name') || '測試顧問').slice(0, 20);
    const user: User = { id: `dev:${name}`, email: `${encodeURIComponent(name)}@dev.local`, name, picture: null };
    return startSession(env, url, user, safeReturn(url.searchParams.get('return')));
  }

  if (url.pathname === '/api/auth/logout' && req.method === 'POST') {
    if (!sameOriginPost(req, url)) return Response.json({ error: 'forbidden' }, { status: 403 });
    const token = readCookie(req, SESSION_COOKIE);
    if (token) await records(env).deleteSession(token);
    return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json', 'Set-Cookie': cookie(SESSION_COOKIE, '', url, 0) } });
  }

  return null;
}
