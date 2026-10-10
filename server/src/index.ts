/* INSURE QUEST | Worker entry: API routing; other paths serve Godot web export via Workers Static Assets. */
import { Buffer } from 'node:buffer';
import { Room, ACCOUNT_HEADER, type AccountHeader } from './room.ts';
import { Records, globalRecords, userRecords } from './records.ts';
import { currentUser, handleAuth, isTrainer } from './auth.ts';
import { TAG_INFO } from './game/game.ts';
import { detectProvider } from './ai.ts';
import { levelFor } from './game/level.ts';

export { Room, Records };

export interface Env {
  ROOM: DurableObjectNamespace<Room>;
  RECORDS: DurableObjectNamespace<Records>;
  ASSETS?: Fetcher;
  /** URL prefix when mounted under a Route such as example.com/insure-quest* (empty = served from root). Stripped before routing. */
  BASE_PATH?: string;
  /** Workers AI binding */
  AI?: Ai;
  /** default chain NVIDIA NIM -> Workers AI | nvidia-only | workers-ai-only | mock | rules */
  AI_PROVIDER?: string;
  WORKERS_AI_MODEL?: string;
  /** Daily AI call quota per account (default 10, resets at Taipei midnight) */
  AI_DAILY_LIMIT?: string;
  /** NVIDIA NIM configuration (preferred when filled and connected normally) */
  NVIDIA_API_KEY?: string;
  NVIDIA_MODEL?: string;
  NVIDIA_FALLBACK_MODEL?: string;
  NVIDIA_BASE_URL?: string;
  /** NIM image model for the local-only /api/dev/gen-img (default black-forest-labs/flux.1-dev) */
  NVIDIA_IMAGE_MODEL?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  /** Trainer emails allowed to view all learner records, comma-separated */
  TRAINER_EMAILS?: string;
  /** Local dev test login (set to 1 in .dev.vars only, localhost only) */
  DEV_LOGIN?: string;
  /** Comma-separated demo codes (each >= 8 chars) for judge guest experience */
  DEMO_CODES?: string;
  DEMO_AI_LIMIT?: string;
  DEMO_MAX_ACCOUNTS?: string;
}

/** Daily AI quota: judge demo accounts use DEMO_AI_LIMIT, everyone else AI_DAILY_LIMIT */
export function aiLimitFor(env: Env, userId: string): number {
  if (userId.startsWith('demo:')) return Math.max(0, Number(env.DEMO_AI_LIMIT) || 30);
  return Math.max(0, Number(env.AI_DAILY_LIMIT) || 10);
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};
const json = (data: unknown, status = 200) => Response.json(data, { status, headers: CORS });

const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function newCode() {
  const b = crypto.getRandomValues(new Uint8Array(5));
  return Array.from(b, x => CODE_CHARS[x % CODE_CHARS.length]).join('');
}
const validCode = (c: string) => /^[A-Z0-9]{5}$/.test(c);

/** Normalised BASE_PATH: '' or '/prefix' (leading slash, no trailing slash) */
function basePrefix(env: Env): string {
  const p = (env.BASE_PATH || '').trim().replace(/\/+$/, '');
  return p ? (p.startsWith('/') ? p : `/${p}`) : '';
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    // Mounted under a Route prefix: strip it so the rest of the routing (and static assets) see root-relative paths.
    // Requests that do not carry the prefix (e.g. workers.dev) are served as-is with base ''.
    const prefix = basePrefix(env);
    let base = '';
    if (prefix && url.pathname === prefix) { url.pathname = `${prefix}/`; return Response.redirect(url.toString(), 301); }
    if (prefix && url.pathname.startsWith(`${prefix}/`)) {
      base = prefix;
      url.pathname = url.pathname.slice(prefix.length);
      req = new Request(url, req);
    }
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });

    if (url.pathname === '/api/health') return json({ ok: true });

    if (url.pathname === '/api/dev/gen-img') {
      const isLocal = env.DEV_LOGIN === '1' && (url.hostname === 'localhost' || url.hostname === '127.0.0.1');
      if (!isLocal || req.method !== 'GET') {
        return json({ error: 'not found' }, 404);
      }
      const prompt = url.searchParams.get('prompt');
      if (!prompt) {
        return json({ error: '缺少 prompt 參數' }, 400);
      }
      const clampDim = (val: string | null) => {
        if (!val) return undefined;
        const n = parseInt(val, 10);
        return Number.isFinite(n) ? Math.max(256, Math.min(1536, Math.round(n))) : undefined;
      };
      const width = clampDim(url.searchParams.get('w') ?? url.searchParams.get('width'));
      const height = clampDim(url.searchParams.get('h') ?? url.searchParams.get('height'));
      const jpeg = (bytes: Uint8Array, provider: string) => new Response(bytes, {
        status: 200,
        headers: { 'Content-Type': 'image/jpeg', 'X-Image-Provider': provider, ...CORS },
      });

      // 1. NVIDIA NIM (preferred): hosted FLUX.1-dev; sizes must be multiples of 64
      if (env.NVIDIA_API_KEY) {
        const snap = (n: number | undefined) => n ? Math.max(768, Math.min(1344, Math.round(n / 64) * 64)) : 1024;
        const model = env.NVIDIA_IMAGE_MODEL || 'black-forest-labs/flux.1-dev';
        // NIM's content filter is sensitive to some wordings (e.g. numeric ages, clothing terms): retry with the short `alt` prompt before Workers AI
        const alt = url.searchParams.get('alt');
        for (const p of alt ? [prompt, alt] : [prompt]) try {
          const r = await fetch(`https://ai.api.nvidia.com/v1/genai/${model}`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${env.NVIDIA_API_KEY}`, 'Content-Type': 'application/json', Accept: 'application/json' },
            body: JSON.stringify({ prompt: p, width: snap(width), height: snap(height), seed: 0, steps: 28 }),
            signal: AbortSignal.timeout(60_000),
          });
          const data = r.ok ? await r.json<{ artifacts?: { base64?: string; finishReason?: string }[] }>() : null;
          const art = data?.artifacts?.[0];
          if (art?.base64 && (!art.finishReason || art.finishReason === 'SUCCESS')) {
            return jpeg(Buffer.from(art.base64, 'base64'), 'nvidia-nim');
          }
          console.warn('NIM image attempt failed', r.status, art?.finishReason);
        } catch (err) {
          console.warn('NIM image attempt error', err);
        }
      }

      // 2. Workers AI FLUX schnell (fallback)
      if (!env.AI) {
        return json({ error: 'NVIDIA NIM 失敗且 Workers AI (env.AI) 未設定' }, 502);
      }
      // Workers AI flux-1-schnell rejects width/height (always square)
      const modelInput = { prompt, steps: 8 };
      try {
        const res = await (env.AI as unknown as { run: (model: string, input: unknown) => Promise<any> }).run(
          '@cf/black-forest-labs/flux-1-schnell',
          modelInput,
        );
        let bytes: Uint8Array;
        const b64 = (res as any)?.image ?? (res as any)?.response?.image;
        if (typeof b64 === 'string') {
          bytes = Buffer.from(b64, 'base64');
        } else if (res instanceof Uint8Array) {
          bytes = res;
        } else if (res instanceof ArrayBuffer) {
          bytes = new Uint8Array(res);
        } else if (typeof res === 'string') {
          bytes = Buffer.from(res, 'base64');
        } else {
          return json({ error: 'Workers AI 回傳圖片格式無效' }, 500);
        }
        return jpeg(bytes, 'workers-ai');
      } catch (err: any) {
        console.error('FLUX 生圖失敗', err);
        return json({ error: err?.message || '生圖失敗' }, 500);
      }
    }

    if (url.pathname.startsWith('/api/auth/')) {
      const r = await handleAuth(req, env, url, base);
      if (r) return r;
    }

    if (url.pathname === '/api/me') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ user: null });
      const provider = detectProvider(env);
      let used = await userRecords(env, user.id).aiUsage(user.id);
      if (used === 0) {
        const gUsed = await globalRecords(env).aiUsage(user.id);
        if (gUsed > 0) used = gUsed;
      }
      // Level: read personal shard first; fall back to global instance only for legacy data
      let xp = await userRecords(env, user.id).xpSummary(user.id);
      if (xp.games === 0) xp = await globalRecords(env).xpSummary(user.id);
      return Response.json({
        user: { id: user.id, name: user.name, email: user.email, picture: user.picture, trainer: isTrainer(env, user) },
        ai: { used, limit: aiLimitFor(env, user.id), provider },
        level: levelFor(xp.xp, xp.games),
      });
    }

    // AI usage history page: today's quota (Workers AI counted), actual call counts per provider, past 7 days
    if (url.pathname === '/api/ai-usage' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看 AI 使用紀錄' }, { status: 401 });
      const stub = userRecords(env, user.id);
      const limit = aiLimitFor(env, user.id);
      const used = await stub.aiUsage(user.id);
      // Next midnight in Taipei time (UTC+8)
      const now = Date.now();
      const resetAt = Math.floor((now + 8 * 3600_000) / 86_400_000 + 1) * 86_400_000 - 8 * 3600_000;
      return Response.json({
        provider: detectProvider(env), limit, used, remaining: Math.max(0, limit - used), resetAt, now,
        nimUnmetered: !!env.NVIDIA_API_KEY, history: await stub.aiHistory(user.id, 7),
      });
    }

    if (url.pathname === '/api/rooms' && req.method === 'POST') {
      // Multiplayer rooms require login; guests may only create solo practice rooms.
      let solo = false;
      try { solo = !!(await req.json<{ solo?: boolean }>())?.solo; } catch { solo = false; }
      if (!solo && !(await currentUser(req, env))) return json({ error: '多人連線需先登入' }, 401);
      for (let i = 0; i < 5; i++) {
        const code = newCode();
        const stub = env.ROOM.get(env.ROOM.idFromName(code));
        const r = await stub.fetch('https://room/init', { method: 'POST', body: JSON.stringify({ code, solo }) });
        if (r.ok) return json({ code });
      }
      return json({ error: '無法建立房間' }, 500);
    }

    const m = url.pathname.match(/^\/api\/rooms\/([A-Za-z0-9]+)\/(ws|info)$/);
    if (m) {
      const code = m[1].toUpperCase();
      if (!validCode(code)) return json({ error: '房間代碼格式錯誤' }, 400);
      const stub = env.ROOM.get(env.ROOM.idFromName(code));
      const fwd = new Request(`https://room/${m[2]}${url.search}`, req);
      fwd.headers.delete(ACCOUNT_HEADER);
      if (m[2] === 'ws') {
        // Only same-origin WebSockets carry login identity (prevents cross-site WebSocket hijacking)
        const origin = req.headers.get('Origin');
        let sameOrigin = !origin;
        try { if (origin) sameOrigin = new URL(origin).host === url.host; } catch { sameOrigin = false; }
        const user = sameOrigin ? await currentUser(req, env) : null;
        // Headers only accept ASCII, encode Chinese name first
        if (user) {
          const pic = typeof user.picture === 'string' && user.picture.startsWith('https://') ? user.picture : undefined;
          fwd.headers.set(ACCOUNT_HEADER, encodeURIComponent(JSON.stringify({ id: user.id, name: user.name, ...(pic ? { picture: pic } : {}) } satisfies AccountHeader)));
        }
      }
      const res = await stub.fetch(fwd);
      if (m[2] === 'ws') return res;
      return new Response(res.body, { status: res.status, headers: { ...Object.fromEntries(res.headers), ...CORS } });
    }

    if (url.pathname === '/api/records' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看培訓紀錄' }, { status: 401 });
      const all = url.searchParams.get('scope') === 'all';
      const target = url.searchParams.get('user');
      if ((all || (target && target !== user.id)) && !isTrainer(env, user)) return Response.json({ error: '只有講師可以查看其他學員紀錄' }, { status: 403 });
      const limit = Number(url.searchParams.get('limit')) || 50;
      let recordsList;
      if (all) {
        // Trainer queries all learner records: lightweight summary from global DO (no cross-shard fan-out, fast response)
        recordsList = await globalRecords(env).list(null, limit);
      } else {
        const targetId = target || user.id;
        // Personal records: read full gameplay decision history from personal standalone DO shard first
        recordsList = await userRecords(env, targetId).list(targetId, limit);
        if (recordsList.length === 0) {
          recordsList = await globalRecords(env).list(targetId, limit);
        }
      }
      // Weakness tag Chinese labels and suggestions for record replay display
      const tagInfo = Object.fromEntries(Object.entries(TAG_INFO).map(([k, v]) => [k, v.label]));
      return Response.json({ records: recordsList, tagInfo });
    }

    if (url.pathname === '/api/profile' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看學習檔案' }, { status: 401 });
      const target = url.searchParams.get('user');
      if (target && target !== user.id && !isTrainer(env, user)) return Response.json({ error: '只有講師可以查看其他學員' }, { status: 403 });
      const targetId = target || user.id;
      // Personal learning profile: computed from personal standalone DO shard first
      let prof = await userRecords(env, targetId).profile(targetId);
      if (prof.games === 0) {
        const gProf = await globalRecords(env).profile(targetId);
        if (gProf.games > 0) prof = gProf;
      }
      return Response.json(prof);
    }

    if (url.pathname === '/api/learners' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!isTrainer(env, user)) return Response.json({ error: '只有講師可以查看學員清單' }, { status: 403 });
      // Trainer learner list: aggregated list provided by global DO
      return Response.json({ learners: await globalRecords(env).learners() });
    }

    if (url.pathname === '/api/insights' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!isTrainer(env, user)) return Response.json({ error: '只有講師可以查看培訓洞察' }, { status: 403 });
      return Response.json(await globalRecords(env).insights());
    }

    if (url.pathname.startsWith('/api/')) return json({ error: 'not found' }, 404);
    if (env.ASSETS) {
      const res = await env.ASSETS.fetch(req);
      // Asset redirects (e.g. /index.html -> /) are root-relative to the stripped path: put the prefix back
      const loc = res.headers.get('Location');
      if (base && loc && loc.startsWith('/') && !loc.startsWith('//')) {
        const out = new Response(res.body, res);
        out.headers.set('Location', base + loc);
        return out;
      }
      return res;
    }
    return new Response('INSURE QUEST server', { status: 200 });
  },
} satisfies ExportedHandler<Env>;
