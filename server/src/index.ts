/* INSURE QUEST｜Worker 入口：API 路由；其他路徑由 Workers Static Assets 提供 Godot 網頁版。 */
import { Room, ACCOUNT_HEADER, type AccountHeader } from './room.ts';
import { Records } from './records.ts';
import { currentUser, handleAuth, isTrainer } from './auth.ts';
import { TAG_INFO } from './game/game.ts';

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
  /** 每個帳號每日 AI 呼叫上限（預設 100，台北時間午夜重置） */
  AI_DAILY_LIMIT?: string;
  ANTHROPIC_API_KEY?: string;
  AI_MODEL?: string;
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

    if (url.pathname.startsWith('/api/auth/')) {
      const r = await handleAuth(req, env, url);
      if (r) return r;
    }

    if (url.pathname === '/api/me') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ user: null });
      const stub = env.RECORDS.get(env.RECORDS.idFromName('global'));
      const provider = env.AI_PROVIDER || (env.AI ? 'workers-ai' : env.ANTHROPIC_API_KEY ? 'claude' : 'rules');
      return Response.json({
        user: { id: user.id, name: user.name, email: user.email, picture: user.picture, trainer: isTrainer(env, user) },
        ai: { used: await stub.aiUsage(user.id), limit: Math.max(0, Number(env.AI_DAILY_LIMIT) || 100), provider },
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
      const stub = env.RECORDS.get(env.RECORDS.idFromName('global'));
      const records = await stub.list(all ? null : (target || user.id), Number(url.searchParams.get('limit')) || 50);
      // 弱點標籤的中文名稱與建議，供紀錄重播顯示
      const tagInfo = Object.fromEntries(Object.entries(TAG_INFO).map(([k, v]) => [k, v.label]));
      return Response.json({ records, tagInfo });
    }

    if (url.pathname === '/api/profile' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!user) return Response.json({ error: '請先登入才能查看學習檔案' }, { status: 401 });
      const target = url.searchParams.get('user');
      if (target && target !== user.id && !isTrainer(env, user)) return Response.json({ error: '只有講師可以查看其他學員' }, { status: 403 });
      const stub = env.RECORDS.get(env.RECORDS.idFromName('global'));
      return Response.json(await stub.profile(target || user.id));
    }

    if (url.pathname === '/api/learners' && req.method === 'GET') {
      const user = await currentUser(req, env);
      if (!isTrainer(env, user)) return Response.json({ error: '只有講師可以查看學員清單' }, { status: 403 });
      const stub = env.RECORDS.get(env.RECORDS.idFromName('global'));
      return Response.json({ learners: await stub.learners() });
    }

    if (url.pathname.startsWith('/api/')) return json({ error: 'not found' }, 404);
    if (env.ASSETS) return env.ASSETS.fetch(req);
    return new Response('INSURE QUEST server', { status: 200 });
  },
} satisfies ExportedHandler<Env>;
