/* INSURE QUEST｜Worker 入口：API 路由；其他路徑由 Workers Static Assets 提供 Godot 網頁版。 */
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
  /** Workers AI 繫結 */
  AI?: Ai;
  /** workers-ai（預設）｜claude｜mock｜rules */
  AI_PROVIDER?: string;
  WORKERS_AI_MODEL?: string;
  /** 每個帳號每日 AI 呼叫上限（預設 10，台北時間午夜重置） */
  AI_DAILY_LIMIT?: string;
  ANTHROPIC_API_KEY?: string;
  AI_MODEL?: string;
  /** NVIDIA NIM 設定（有填寫且連線正常時優先使用） */
  NVIDIA_API_KEY?: string;
  NVIDIA_MODEL?: string;
  NVIDIA_FALLBACK_MODEL?: string;
  NVIDIA_BASE_URL?: string;
  GOOGLE_CLIENT_ID?: string;
  GOOGLE_CLIENT_SECRET?: string;
  /** 可查看全部學員紀錄的講師 Email，逗號分隔 */
  TRAINER_EMAILS?: string;
  /** 本機測試登入（只在 .dev.vars 設定 1，且僅限 localhost） */
  DEV_LOGIN?: string;
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

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
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
      if (!env.AI) {
        return json({ error: 'Workers AI (env.AI) 未設定' }, 500);
      }
      try {
        const res = await (env.AI as unknown as { run: (model: string, input: unknown) => Promise<any> }).run(
          '@cf/black-forest-labs/flux-1-schnell',
          { prompt, steps: 8 },
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
        return new Response(bytes, {
          status: 200,
          headers: {
            'Content-Type': 'image/jpeg',
            ...CORS,
          },
        });
      } catch (err: any) {
        console.error('FLUX 生圖失敗', err);
        return json({ error: err?.message || '生圖失敗' }, 500);
      }
    }

    if (url.pathname.startsWith('/api/auth/')) {
      const r = await handleAuth(req, env, url);
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
      // 等級：優先讀個人切片；舊資料只在全域實例時退回全域
      let xp = await userRecords(env, user.id).xpSummary(user.id);
      if (xp.games === 0) xp = await globalRecords(env).xpSummary(user.id);
      return Response.json({
        user: { id: user.id, name: user.name, email: user.email, picture: user.picture, trainer: isTrainer(env, user) },
        ai: { used, limit: Math.max(0, Number(env.AI_DAILY_LIMIT) || 10), provider },
        level: levelFor(xp.xp, xp.games),
      });
    }

    // AI 使用紀錄頁：今日額度（Workers AI 計次）、各供應者實際呼叫次數、近 7 天
    if (url.pathname === '/api/ai-usage' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看 AI 使用紀錄' }, { status: 401 });
      const stub = userRecords(env, user.id);
      const limit = Math.max(0, Number(env.AI_DAILY_LIMIT) || 10);
      const used = await stub.aiUsage(user.id);
      // 台北時間下一個午夜（UTC+8）
      const now = Date.now();
      const resetAt = Math.floor((now + 8 * 3600_000) / 86_400_000 + 1) * 86_400_000 - 8 * 3600_000;
      return Response.json({
        provider: detectProvider(env), limit, used, remaining: Math.max(0, limit - used), resetAt, now,
        nimUnmetered: !!env.NVIDIA_API_KEY, history: await stub.aiHistory(user.id, 7),
      });
    }

    if (url.pathname === '/api/rooms' && req.method === 'POST') {
      for (let i = 0; i < 5; i++) {
        const code = newCode();
        const stub = env.ROOM.get(env.ROOM.idFromName(code));
        const r = await stub.fetch('https://room/init', { method: 'POST', body: JSON.stringify({ code }) });
        if (r.ok) return json({ code });
      }
      return json({ error: '無法建立房間' }, 500);
    }

    const m = url.pathname.match(/^\/api\/rooms\/([A-Za-z0-9]+)\/(ws|info)$/);
    if (m) {
      const code = m[1].toUpperCase();
      if (!validCode(code)) return json({ error: '房間代碼格式錯誤' }, 400);
      const stub = env.ROOM.get(env.ROOM.idFromName(code));
      const fwd = new Request(`https://room/${m[2]}`, req);
      fwd.headers.delete(ACCOUNT_HEADER);
      if (m[2] === 'ws') {
        // 只有同源的 WebSocket 才帶入登入身分（防止跨站 WebSocket 劫持）
        const origin = req.headers.get('Origin');
        let sameOrigin = !origin;
        try { if (origin) sameOrigin = new URL(origin).host === url.host; } catch { sameOrigin = false; }
        const user = sameOrigin ? await currentUser(req, env) : null;
        // 標頭只能放 ASCII，中文姓名先編碼
        if (user) fwd.headers.set(ACCOUNT_HEADER, encodeURIComponent(JSON.stringify({ id: user.id, name: user.name } satisfies AccountHeader)));
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
        // 講師查詢全體學員紀錄：由全域 DO 提供輕量摘要（不跨切片 Fan-out，極速回應）
        recordsList = await globalRecords(env).list(null, limit);
      } else {
        const targetId = target || user.id;
        // 個人紀錄：優先由個人獨立 DO 切片讀取完整遊戲決策軌跡
        recordsList = await userRecords(env, targetId).list(targetId, limit);
        if (recordsList.length === 0) {
          recordsList = await globalRecords(env).list(targetId, limit);
        }
      }
      // 弱點標籤的中文名稱與建議，供紀錄重播顯示
      const tagInfo = Object.fromEntries(Object.entries(TAG_INFO).map(([k, v]) => [k, v.label]));
      return Response.json({ records: recordsList, tagInfo });
    }

    if (url.pathname === '/api/profile' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看學習檔案' }, { status: 401 });
      const target = url.searchParams.get('user');
      if (target && target !== user.id && !isTrainer(env, user)) return Response.json({ error: '只有講師可以查看其他學員' }, { status: 403 });
      const targetId = target || user.id;
      // 個人學習檔案：優先由個人獨立 DO 切片計算
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
      // 講師學員清單：由全域 DO 提供聚合清單
      return Response.json({ learners: await globalRecords(env).learners() });
    }

    if (url.pathname.startsWith('/api/')) return json({ error: 'not found' }, 404);
    if (env.ASSETS) return env.ASSETS.fetch(req);
    return new Response('INSURE QUEST server', { status: 200 });
  },
} satisfies ExportedHandler<Env>;
