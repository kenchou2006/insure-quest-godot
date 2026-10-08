/* INSURE QUEST｜Room Durable Object：一個房間＝一場遊戲。
 * - 伺服器權威：所有規則在 game.ts 執行，客戶端只送動作。
 * - Hibernatable WebSocket：閒置時 DO 可休眠，狀態存在 storage。
 * - 電腦顧問與斷線代打由 alarm 驅動，間隔讓真人看得到每一步。
 */
import { DurableObject } from 'cloudflare:workers';
import type { Action, BotLevel, GameState, PlayerState } from './game/types.ts';
import { addPlayer, applyAction, createGame, enrichCoach, injectClient, log, predict, publicView, removePlayer, startGame, type Ctx } from './game/game.ts';
import { botAction } from './game/bots.ts';
import { BOARD, CARDS, QUESTIONS } from './game/data.ts';
import { makeAI, MeteredAI, type AIService, type Meter, type RawAI } from './ai.ts';
import type { Env } from './index.ts';

const BOT_DELAY_MS = 1300;
/** 結果與事件畫面多停一下，讓旁觀的真人看得到內容 */
const BOT_READ_DELAY_MS = 4500;
const AFK_TAKEOVER_MS = 45_000;

type ClientMsg =
  | { t: 'hello'; playerId?: string; name?: string }
  | { t: 'add_bot'; level?: BotLevel }
  | { t: 'remove_player'; id: string }
  | { t: 'settings'; rounds?: number; aiClients?: boolean }
  | { t: 'start' }
  | { t: 'action'; action: Action }
  | { t: 'react'; emoji: string }
  | { t: 'predict'; grade: string }
  | { t: 'ping' };

/** 每條連線綁定的身分：accountId 由 Worker 依登入 Cookie 解析後傳入，客戶端無法偽造 */
interface Attachment { playerId: string | null; accountId: string | null; accountName: string | null }

export interface AccountHeader { id: string; name: string }
export const ACCOUNT_HEADER = 'X-IQ-Account';

const BOT_NAMES = ['電腦顧問・安安', '電腦顧問・小賴', '電腦顧問・阿哲'];

export class Room extends DurableObject<Env> {
  private game: GameState | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  /** AI 供應者（Workers AI／Claude／模擬）；null 代表只用規則版 */
  private raw: RawAI | null;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.raw = makeAI(env);
    ctx.blockConcurrencyWhile(async () => {
      this.game = (await ctx.storage.get<GameState>('game')) ?? null;
    });
  }

  private get aiLimit() { return Math.max(0, Number(this.env.AI_DAILY_LIMIT) || 100); }
  private records() { return this.env.RECORDS.get(this.env.RECORDS.idFromName('global')); }

  /** 帳號的 AI 額度計量；每次變動都推送給該帳號的連線 */
  private meterFor(accountId: string | null | undefined): Meter | null {
    if (!accountId || !this.raw) return null;
    const limit = this.aiLimit;
    return {
      consume: async () => {
        const r = await this.records().consumeAi(accountId, limit);
        this.sendToAccount(accountId, { t: 'quota', used: r.used, limit, exhausted: !r.ok });
        return r.ok;
      },
      refund: async () => {
        const used = await this.records().refundAi(accountId);
        this.sendToAccount(accountId, { t: 'quota', used, limit, exhausted: false });
      },
    };
  }

  /** 真人玩家用自己的帳號額度；電腦顧問與訪客一律用規則版 */
  private aiFor(p: PlayerState | null | undefined): AIService {
    return new MeteredAI(this.raw, p && !p.isBot ? this.meterFor(p.accountId) : null);
  }

  private makeCtx(actor?: PlayerState | null): Ctx { return { ai: this.aiFor(actor), rng: Math.random, now: Date.now }; }

  private sendToAccount(accountId: string, msg: unknown) {
    const data = JSON.stringify(msg);
    for (const ws of this.ctx.getWebSockets()) {
      if ((ws.deserializeAttachment() as Attachment | null)?.accountId === accountId) { try { ws.send(data); } catch { /* 已關閉 */ } }
    }
  }

  /** 串行化所有狀態變更（AI 呼叫期間 DO 會讓出執行權） */
  private run<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.queue.then(fn, fn);
    this.queue = next.catch(() => undefined);
    return next;
  }

  private async save() {
    if (!this.game) return;
    this.game.version++;
    await this.ctx.storage.put('game', this.game);
  }

  private broadcast(msg: unknown) {
    const data = JSON.stringify(msg);
    for (const ws of this.ctx.getWebSockets()) { try { ws.send(data); } catch { /* 已關閉 */ } }
  }

  /** 每條連線各自產生狀態（預測等個人化欄位） */
  private pushState() {
    if (!this.game) return;
    for (const ws of this.ctx.getWebSockets()) {
      const att = ws.deserializeAttachment() as Attachment | null;
      try { ws.send(JSON.stringify({ t: 'state', state: publicView(this.game, att?.playerId ?? null) })); } catch { /* 已關閉 */ }
    }
  }

  async fetch(req: Request): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname.endsWith('/init') && req.method === 'POST') {
      const { code } = await req.json<{ code: string }>();
      return this.run(async () => {
        if (this.game) return new Response('exists', { status: 409 });
        this.game = createGame(code);
        this.game.settings.aiClients = !!this.raw;
        await this.save();
        return Response.json({ ok: true });
      });
    }
    if (url.pathname.endsWith('/ws')) {
      if (req.headers.get('Upgrade') !== 'websocket') return new Response('expected websocket', { status: 426 });
      if (!this.game) return new Response('room not found', { status: 404 });
      let account: AccountHeader | null = null;
      try { account = JSON.parse(decodeURIComponent(req.headers.get(ACCOUNT_HEADER) || 'null')); } catch { account = null; }
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].serializeAttachment({ playerId: null, accountId: account?.id ?? null, accountName: account?.name ?? null } satisfies Attachment);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname.endsWith('/info')) {
      if (!this.game) return new Response('room not found', { status: 404 });
      return Response.json({ code: this.game.code, phase: this.game.phase, players: this.game.players.length });
    }
    return new Response('not found', { status: 404 });
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer) {
    let msg: ClientMsg;
    try { msg = JSON.parse(typeof raw === 'string' ? raw : new TextDecoder().decode(raw)); } catch { return; }
    if (msg.t === 'ping') { ws.send(JSON.stringify({ t: 'pong' })); return; }
    await this.run(() => this.handle(ws, msg));
  }

  private err(ws: WebSocket, message: string) { ws.send(JSON.stringify({ t: 'error', message })); }

  private async handle(ws: WebSocket, msg: ClientMsg) {
    const g = this.game;
    if (!g) return this.err(ws, '房間不存在');
    const att = ws.deserializeAttachment() as Attachment;
    const me = att.playerId;
    const isHost = !!me && g.hostId === me;
    const ctx = this.makeCtx(g.players.find(x => x.id === me));

    switch (msg.t) {
      case 'hello': {
        // 重新連線：座位綁定帳號時，必須是同一個帳號才能取回
        const seat = msg.playerId ? g.players.find(p => p.id === msg.playerId && !p.isBot) : undefined;
        let id = seat && (!seat.accountId || seat.accountId === att.accountId) ? seat.id : null;
        if (!id && g.phase === 'lobby') {
          id = crypto.randomUUID();
          const typed = (msg.name || '').trim();
          const name = typed && typed !== '顧問' ? typed : (att.accountName || '顧問');
          const e = addPlayer(g, { id, name, accountId: att.accountId });
          if (e) { id = null; this.err(ws, e); }
          else log(g, `${g.players.at(-1)!.name} 加入了房間`);
        }
        ws.serializeAttachment({ ...att, playerId: id } satisfies Attachment);
        const p = id ? g.players.find(x => x.id === id) : null;
        if (p) { p.connected = true; p.disconnectedAt = null; }
        const meInfo = att.accountId
          ? { name: att.accountName, ai: { used: this.raw ? await this.records().aiUsage(att.accountId) : 0, limit: this.aiLimit } }
          : null;
        ws.send(JSON.stringify({ t: 'welcome', playerId: id, spectator: !id, static: { board: BOARD, questions: QUESTIONS.map(q => ({ id: q.id, text: q.text, coach: q.coach })), cards: CARDS }, ai: !!this.raw, me: meInfo }));
        break;
      }
      case 'add_bot': {
        if (!isHost) return this.err(ws, '只有房主可以加入電腦顧問');
        const n = g.players.filter(p => p.isBot).length;
        const e = addPlayer(g, { id: crypto.randomUUID(), name: BOT_NAMES[n % BOT_NAMES.length] + (msg.level === 'novice' ? '（新人）' : '（資深）'), isBot: true, botLevel: msg.level === 'novice' ? 'novice' : 'pro' });
        if (e) return this.err(ws, e);
        break;
      }
      case 'remove_player': {
        if (!isHost) return this.err(ws, '只有房主可以移除玩家');
        if (msg.id === me) return this.err(ws, '不能移除自己');
        removePlayer(g, msg.id);
        break;
      }
      case 'settings': {
        if (!isHost || g.phase !== 'lobby') return this.err(ws, '只有房主可以在大廳調整設定');
        if (msg.rounds !== undefined) g.settings.rounds = Math.max(2, Math.min(12, Math.round(Number(msg.rounds)) || 6));
        if (msg.aiClients !== undefined) g.settings.aiClients = !!msg.aiClients && !!this.raw;
        break;
      }
      case 'start': {
        if (!isHost) return this.err(ws, '只有房主可以開始遊戲');
        const e = startGame(g, ctx);
        if (e) return this.err(ws, e);
        if (g.settings.aiClients && this.raw) this.generateClients(2);
        break;
      }
      case 'action': {
        if (!me) return this.err(ws, '旁觀者無法操作');
        const e = await applyAction(g, me, msg.action, ctx);
        if (e) return this.err(ws, e);
        if (g.phase === 'ended') await this.finish();
        break;
      }
      case 'predict': {
        if (!me) return this.err(ws, '旁觀者無法預測');
        const e = predict(g, me, String(msg.grade));
        if (e) return this.err(ws, e);
        break;
      }
      case 'react': {
        const p = g.players.find(x => x.id === me);
        if (p && typeof msg.emoji === 'string') this.broadcast({ t: 'react', from: p.name, emoji: msg.emoji.slice(0, 4) });
        return;
      }
    }
    await this.save();
    this.pushState();
    await this.scheduleBot();
  }

  /** 背景產生 AI 客戶，不阻塞遊戲進行 */
  private generateClients(n: number) {
    for (let i = 0; i < n; i++) {
      const seed = Date.now() + i * 7919;
      // AI 生成客戶使用房主的額度；房主是訪客時不生成
      const host = this.game?.players.find(p => p.id === this.game?.hostId);
      this.ctx.waitUntil(this.aiFor(host).generateClient(seed).then(c => c && this.run(async () => {
        if (!this.game || this.game.phase !== 'playing') return;
        injectClient(this.game, c);
        log(this.game, `AI 新增了一位客戶：${c.name}（${c.job}）`, 'info');
        await this.save();
        this.pushState();
      })).catch(e => console.warn('generateClient failed', e)));
    }
  }

  private needsAuto(g: GameState): boolean {
    if (g.phase !== 'playing') return false;
    const p = g.players[g.turn];
    if (!p) return false;
    if (p.isBot) return true;
    return !p.connected && !!p.disconnectedAt && Date.now() - p.disconnectedAt >= AFK_TAKEOVER_MS;
  }

  private async scheduleBot() {
    const g = this.game;
    if (!g || g.phase !== 'playing') return;
    const p = g.players[g.turn];
    if (p?.isBot) {
      const reading = g.turnStage === 'event' || g.session?.step === 'result';
      const humans = g.players.some(x => !x.isBot && x.connected);
      await this.ctx.storage.setAlarm(Date.now() + (reading && humans ? BOT_READ_DELAY_MS : BOT_DELAY_MS));
    }
    else if (p && !p.connected && p.disconnectedAt) await this.ctx.storage.setAlarm(p.disconnectedAt + AFK_TAKEOVER_MS);
  }

  async alarm() {
    await this.run(async () => {
      const g = this.game;
      if (!g || !this.needsAuto(g)) return;
      const p = g.players[g.turn];
      // 斷線真人由資深電腦代打一步
      const level = p.botLevel;
      if (!p.isBot) p.botLevel = 'pro';
      const action = botAction(g, Math.random);
      if (!p.isBot) p.botLevel = level;
      if (!action) return;
      // 電腦顧問與斷線代打都不消耗任何人的 AI 額度
      const e = await applyAction(g, p.id, action, this.makeCtx(null));
      if (e) { console.warn('bot action rejected', e, action); return; }
      if (g.phase === 'ended') await this.finish();
      await this.save();
      this.pushState();
    });
    await this.scheduleBot();
  }

  private async finish() {
    const g = this.game!;
    this.pushState();
    await enrichCoach(g, p => this.aiFor(p));
    this.pushState();
    // 只保存已登入玩家的紀錄（訪客不保存）
    for (const row of g.final ?? []) {
      const p = g.players.find(x => x.id === row.playerId)!;
      if (row.isBot || !p.accountId) continue;
      await this.records().add({ room: g.code, name: row.name, ts: Date.now(), score: row.score, grade: row.grade, players: g.players.length, userId: p.accountId, data: { ...row, decisions: p.decisions, book: p.book, sessions: p.sessionLogs ?? [], quizCorrect: p.quizCorrect, quizTotal: p.quizTotal } })
        .catch(e => console.warn('record save failed', e));
    }
  }

  async webSocketClose(ws: WebSocket) { await this.run(() => this.onLeave(ws)); }
  async webSocketError(ws: WebSocket) { await this.run(() => this.onLeave(ws)); }

  private async onLeave(ws: WebSocket) {
    const g = this.game;
    const att = ws.deserializeAttachment() as Attachment | null;
    if (!g || !att?.playerId) return;
    const still = this.ctx.getWebSockets().some(o => o !== ws && (o.deserializeAttachment() as Attachment)?.playerId === att.playerId);
    if (still) return;
    const p = g.players.find(x => x.id === att.playerId);
    if (!p) return;
    if (g.phase === 'lobby') { removePlayer(g, p.id); log(g, `${p.name} 離開了房間`); }
    else { p.connected = false; p.disconnectedAt = Date.now(); log(g, `${p.name} 斷線了，${AFK_TAKEOVER_MS / 1000} 秒後由電腦代打`, 'ok'); }
    await this.save();
    this.pushState();
    await this.scheduleBot();
  }
}
