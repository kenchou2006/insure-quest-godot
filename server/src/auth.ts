/* INSURE QUEST | Google Login (OAuth 2.0 authorization code flow, handled entirely in Worker).
 * - Sessions are stored in HttpOnly cookies; same-origin Godot HTTPRequest / WebSocket sends them automatically, frontend never touches tokens.
 * - The state parameter is stored in short-lived cookies and verified on callback to prevent CSRF.
 * - Two login modes: FedCM / One Tap (browser retrieves ID Token and POSTs to us) and authorization code redirect (fallback); both verify RS256 signature, iss/aud/exp/email_verified, and FedCM additionally verifies nonce.
 */
import type { Env } from './index.ts';
import { globalRecords, type User } from './records.ts';
import { verifyGoogleIdToken, type GoogleClaims } from './google-jwt.ts';

export const SESSION_COOKIE = 'iq_session';
const STATE_COOKIE = 'iq_oauth_state';
const NONCE_COOKIE = 'iq_gnonce';
const GOOGLE_AUTH = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN = 'https://oauth2.googleapis.com/token';

export function googleEnabled(env: Env) { return !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET); }

function isLocalHost(url: URL) { return ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname); }

/** Test login for local dev only: requires both DEV_LOGIN=1 and request from localhost */
export function devLoginEnabled(env: Env, url: URL) { return env.DEV_LOGIN === '1' && isLocalHost(url); }

export function readCookie(req: Request, name: string): string | null {
  const header = req.headers.get('Cookie') || '';
  for (const part of header.split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k === name) return decodeURIComponent(v.join('='));
  }
  return null;
}

export function cookie(name: string, value: string, url: URL, maxAge: number, path = '/') {
  const secure = url.protocol === 'https:' ? '; Secure' : '';
  return `${name}=${encodeURIComponent(value)}; Path=${path}; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

/** Only allow internal relative paths to prevent open redirects */
function safeReturn(raw: string | null): string {
  return raw && raw.startsWith('/') && !raw.startsWith('//') && !raw.includes('\\') ? raw : '/';
}

function randomHex(bytes: number) {
  return Array.from(crypto.getRandomValues(new Uint8Array(bytes)), b => b.toString(16).padStart(2, '0')).join('');
}

function records(env: Env) { return globalRecords(env); }

export async function currentUser(req: Request, env: Env): Promise<User | null> {
  const token = readCookie(req, SESSION_COOKIE);
  // Reject malformed tokens here so they never cost a Durable Object request
  return token && /^[0-9a-f]{64}$/.test(token) ? records(env).getSessionUser(token) : null;
}

export function isTrainer(env: Env, user: User | null) {
  if (!user || user.id.startsWith('demo:')) return false;
  const list = (env.TRAINER_EMAILS || '').split(',').map(s => s.trim().toLowerCase()).filter(Boolean);
  return list.includes(user.email.toLowerCase());
}

function timingSafeEqualStr(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

async function startSession(env: Env, url: URL, user: User, returnTo: string, base: string): Promise<Response> {
  await records(env).upsertUser(user);
  const token = await records(env).createSession(user.id);
  const headers = new Headers({ Location: base + returnTo });
  headers.append('Set-Cookie', cookie(SESSION_COOKIE, token, url, 30 * 86400, base || '/'));
  headers.append('Set-Cookie', cookie(STATE_COOKIE, '', url, 0, `${base}/api/auth`));
  return new Response(null, { status: 302, headers });
}

function userFromClaims(c: GoogleClaims): User {
  return { id: `g:${c.sub}`, email: String(c.email || ''), name: String(c.name || c.email || 'Google 使用者'), picture: c.picture ? String(c.picture) : null };
}

/** POST requests must be same-origin (combined with SameSite=Lax cookie to prevent CSRF) */
export function sameOriginPost(req: Request, url: URL) {
  const origin = req.headers.get('Origin');
  if (!origin) return false;
  try { return new URL(origin).host === url.host; } catch { return false; }
}

/** Handle /api/auth/*; returns null if not an auth route */
export async function handleAuth(req: Request, env: Env, url: URL, base = ''): Promise<Response | null> {
  const redirectUri = `${url.origin}${base}/api/auth/google/callback`;

  if (url.pathname === '/api/auth/config') {
    return Response.json({
      google: googleEnabled(env),
      googleClientId: googleEnabled(env) ? env.GOOGLE_CLIENT_ID : null,
      dev: devLoginEnabled(env, url),
      demo: !!(env.DEMO_CODES && env.DEMO_CODES.trim()),
    });
  }

  // FedCM / One Tap: acquire one-time nonce first (bound to short-lived cookie), Google includes it in ID Token
  if (url.pathname === '/api/auth/google/nonce') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    const nonce = randomHex(16);
    return new Response(JSON.stringify({ nonce }), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Set-Cookie': cookie(NONCE_COOKIE, nonce, url, 600, `${base}/api/auth`) } });
  }

  // ID Token returned by FedCM / One Tap: create session after verifying signature and nonce
  if (url.pathname === '/api/auth/google/credential' && req.method === 'POST') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    if (!sameOriginPost(req, url)) return Response.json({ error: 'forbidden' }, { status: 403 });
    let { credential } = await req.json<{ credential?: string | Record<string, unknown> }>().catch(() => ({ credential: undefined }));
    if (typeof credential === 'object' && credential !== null) {
      credential = String(credential.id_token || credential.token || credential.credential || '');
    } else if (typeof credential === 'string') {
      try {
        const parsed = JSON.parse(credential);
        if (parsed && typeof parsed === 'object') {
          credential = String(parsed.id_token || parsed.token || parsed.credential || credential);
        }
      } catch {}
    }
    const nonce = readCookie(req, NONCE_COOKIE);
    if (!nonce) {
      console.warn('Google credential verification failed:', { hasCred: !!credential, noncePresent: false });
      return Response.json({ error: '登入驗證失敗' }, { status: 401 });
    }
    const claims = credential ? await verifyGoogleIdToken(credential, env.GOOGLE_CLIENT_ID!, nonce) : null;
    if (!claims) {
      console.warn('Google credential verification failed:', { hasCred: !!credential, noncePresent: true });
      return Response.json({ error: '登入驗證失敗' }, { status: 401 });
    }
    const user = userFromClaims(claims);
    await records(env).upsertUser(user);
    const token = await records(env).createSession(user.id);
    const headers = new Headers({ 'Content-Type': 'application/json' });
    headers.append('Set-Cookie', cookie(SESSION_COOKIE, token, url, 30 * 86400, base || '/'));
    headers.append('Set-Cookie', cookie(NONCE_COOKIE, '', url, 0, `${base}/api/auth`));
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
    headers.append('Set-Cookie', cookie(STATE_COOKIE, `${state}|${returnTo}`, url, 600, `${base}/api/auth`));
    return new Response(null, { status: 302, headers });
  }

  if (url.pathname === '/api/auth/google/callback') {
    if (!googleEnabled(env)) return new Response('Google 登入尚未設定', { status: 503 });
    const [expected, returnTo] = (readCookie(req, STATE_COOKIE) || '').split('|');
    const state = url.searchParams.get('state');
    const code = url.searchParams.get('code');
    if (!expected || !state || state !== expected || !code) return Response.redirect(`${url.origin}${base}/?login=failed`, 302);
    const tokenRes = await fetch(GOOGLE_TOKEN, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID!, client_secret: env.GOOGLE_CLIENT_SECRET!, redirect_uri: redirectUri, grant_type: 'authorization_code' }),
    });
    if (!tokenRes.ok) { console.warn('Google token exchange failed', tokenRes.status); return Response.redirect(`${url.origin}${base}/?login=failed`, 302); }
    const { id_token } = await tokenRes.json<{ id_token?: string }>();
    // Verify signature as well (defense-in-depth)
    const claims = id_token ? await verifyGoogleIdToken(id_token, env.GOOGLE_CLIENT_ID!) : null;
    if (!claims) return Response.redirect(`${url.origin}${base}/?login=failed`, 302);
    return startSession(env, url, userFromClaims(claims), safeReturn(returnTo), base);
  }

  if (url.pathname === '/api/auth/dev-login') {
    if (!devLoginEnabled(env, url)) return new Response('not found', { status: 404 });
    const name = (url.searchParams.get('name') || '測試顧問').slice(0, 20);
    const user: User = { id: `dev:${name}`, email: `${encodeURIComponent(name)}@dev.local`, name, picture: null };
    return startSession(env, url, user, safeReturn(url.searchParams.get('return')), base);
  }

  if (url.pathname === '/api/auth/demo' && req.method === 'POST') {
    if (!sameOriginPost(req, url)) return Response.json({ error: 'forbidden' }, { status: 403 });
    const ip = req.headers.get('CF-Connecting-IP') || req.headers.get('x-forwarded-for')?.split(',')[0].trim() || 'unknown';
    const rec = records(env);
    const allowed = await rec.checkDemoRateLimit(ip);
    if (!allowed) return Response.json({ error: '嘗試次數過多，請稍後再試' }, { status: 429 });

    const body = await req.json<{ code?: string }>().catch(() => ({ code: '' }));
    const inputCode = String(body.code ?? '').trim();
    const validCodes = (env.DEMO_CODES || '').split(',').map(s => s.trim()).filter(s => s.length >= 8);
    const matchedCode = validCodes.find(c => timingSafeEqualStr(c, inputCode));
    if (!matchedCode) {
      await rec.recordDemoAttempt(ip);
      return Response.json({ error: '體驗碼錯誤' }, { status: 401 });
    }

    const maxAccounts = Math.max(1, Number(env.DEMO_MAX_ACCOUNTS) || 300);
    const currentCount = await rec.demoAccountCount(matchedCode);
    if (currentCount >= maxAccounts) {
      return Response.json({ error: '體驗碼名額已滿' }, { status: 403 });
    }

    const hexId = randomHex(8);
    const userId = `demo:${hexId}`;
    const num = Math.floor(1000 + Math.random() * 9000);
    const name = `評審體驗 ${num}`;
    const user: User = { id: userId, email: `demo+${userId}@demo.local`, name, picture: null };

    await rec.recordDemoAccount(matchedCode, userId);
    await rec.upsertUser(user);
    const token = await rec.createSession(userId, 7);
    const headers = new Headers({ 'Content-Type': 'application/json' });
    headers.append('Set-Cookie', cookie(SESSION_COOKIE, token, url, 7 * 86400, base || '/'));
    return new Response(JSON.stringify({ ok: true, name }), { headers });
  }

  if (url.pathname === '/api/auth/logout' && req.method === 'POST') {
    if (!sameOriginPost(req, url)) return Response.json({ error: 'forbidden' }, { status: 403 });
    const token = readCookie(req, SESSION_COOKIE);
    if (token) await records(env).deleteSession(token);
    return new Response(JSON.stringify({ ok: true }), { headers: { 'Content-Type': 'application/json', 'Set-Cookie': cookie(SESSION_COOKIE, '', url, 0, base || '/') } });
  }

  return null;
}
