/* INSURE QUEST | LocalRoom: in-browser solo room running the same TypeScript engine.
 * - Handles guest solo play entirely in the browser without server Room Durable Objects.
 * - Reuses shared game logic and data (createGame, addPlayer, startGame, applyAction, etc.).
 * - Employs RuleAI only (no LLM, no quotas, no remote AI).
 */
import type { Action, BotLevel, GameState, PlayerState } from '../game/types.ts';
import {
  addPlayer,
  applyAction,
  createGame,
  enrichCoach,
  log,
  mulberry32,
  predict,
  publicView,
  startGame,
  type Ctx,
} from '../game/game.ts';
import { botAction } from '../game/bots.ts';
import { BOARD, CARDS, QUESTIONS } from '../game/data.ts';
import { RuleAI } from '../rule-ai.ts';

const BOT_DELAY_MS = 1300;
const BOT_READ_DELAY_MS = 4500;
const BOT_NAMES = ['電腦顧問・安安', '電腦顧問・小賴', '電腦顧問・阿哲'];

type ClientMsg =
  | { t: 'hello'; playerId?: string; name?: string }
  | { t: 'add_bot'; level?: BotLevel }
  | { t: 'settings'; rounds?: number; aiClients?: boolean; demo?: string }
  | { t: 'start' }
  | { t: 'action'; action: Action }
  | { t: 'predict'; grade: string }
  | { t: 'react'; emoji: string }
  | { t: 'abandon' }
  | { t: 'ping' };

export class LocalRoom {
  private game: GameState | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private outbox: unknown[] = [];
  private playerId: string | null = null;
  private botTimer: ReturnType<typeof setTimeout> | null = null;
  private demoRng: (() => number) | null = null;

  constructor(code = 'LOCAL') {
    this.game = createGame(code);
    this.game.settings.aiClients = false;
    this.game.solo = true;
  }

  private makeCtx(actor?: PlayerState | null): Ctx {
    let last = 0;
    let pending: string | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const flush = () => {
      timer = null;
      if (pending !== null) {
        last = Date.now();
        this.send({ t: 'stream', text: pending });
        pending = null;
      }
    };
    const onStream = (text: string) => {
      pending = text;
      const wait = 120 - (Date.now() - last);
      if (wait <= 0) flush();
      else if (!timer) timer = setTimeout(flush, wait);
    };
    const endStream = () => {
      if (timer) clearTimeout(timer);
      timer = null;
      pending = null;
    };
    const rng = this.game?.demo && this.demoRng ? this.demoRng : Math.random;
    return {
      ai: new RuleAI(),
      rng,
      now: Date.now,
      onStream,
      endStream,
    };
  }

  private run<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.queue.then(fn, fn);
    this.queue = next.catch(() => undefined);
    return next;
  }

  private send(msg: unknown): void {
    this.outbox.push(msg);
  }

  private err(message: string): void {
    this.send({ t: 'error', message });
  }

  private pushState(): void {
    if (!this.game) return;
    this.send({ t: 'state', state: publicView(this.game, this.playerId) });
  }

  receive(raw: string): void {
    let msg: ClientMsg;
    try {
      msg = typeof raw === 'string' ? JSON.parse(raw) : raw;
    } catch {
      return;
    }
    if (msg.t === 'ping') {
      this.send({ t: 'pong' });
      return;
    }
    this.run(() => this.handle(msg));
  }

  private async handle(msg: ClientMsg): Promise<void> {
    const g = this.game;
    if (!g) return this.err('房間不存在');
    const me = this.playerId;
    const isHost = !!me && g.hostId === me;
    const ctx = this.makeCtx(g.players.find(x => x.id === me));

    switch (msg.t) {
      case 'hello': {
        const seat = msg.playerId ? g.players.find(p => p.id === msg.playerId && !p.isBot) : undefined;
        let id = seat ? seat.id : null;
        if (!id && g.solo && g.players.some(p => !p.isBot)) return this.err('這是單人練習房間，無法加入');
        if (!id && g.phase === 'lobby') {
          id = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : 'p_' + Math.random().toString(36).slice(2);
          const typed = (msg.name || '').trim();
          const name = typed && typed !== '顧問' ? typed : '顧問';
          const e = addPlayer(g, { id, name, accountId: null, avatar: null });
          if (e) {
            id = null;
            this.err(e);
          } else {
            log(g, `${g.players.at(-1)!.name} 加入了房間`);
          }
        }
        this.playerId = id;
        const p = id ? g.players.find(x => x.id === id) : null;
        if (p) {
          p.connected = true;
          p.disconnectedAt = null;
        }
        this.send({
          t: 'welcome',
          playerId: id,
          spectator: false,
          static: {
            board: BOARD,
            questions: QUESTIONS.map(q => ({ id: q.id, text: q.text, coach: q.coach })),
            cards: CARDS,
          },
          ai: false,
          me: null,
        });
        break;
      }
      case 'add_bot': {
        if (!isHost) return this.err('只有房主可以加入電腦顧問');
        const n = g.players.filter(p => p.isBot).length;
        const botId = typeof crypto !== 'undefined' && crypto.randomUUID ? crypto.randomUUID() : 'bot_' + Math.random().toString(36).slice(2);
        const e = addPlayer(g, {
          id: botId,
          name: BOT_NAMES[n % BOT_NAMES.length] + (msg.level === 'novice' ? '（新人）' : '（資深）'),
          isBot: true,
          botLevel: msg.level === 'novice' ? 'novice' : 'pro',
        });
        if (e) return this.err(e);
        break;
      }
      case 'settings': {
        if (!isHost || g.phase !== 'lobby') return this.err('只有房主可以在大廳調整設定');
        if (msg.rounds !== undefined) g.settings.rounds = Math.max(2, Math.min(12, Math.round(Number(msg.rounds)) || 6));
        g.settings.aiClients = false;
        if (typeof msg.demo === 'string') {
          const target = msg.demo === '1' ? 'jiahao' : msg.demo;
          if (g.clients[target]) {
            g.demo = target;
            g.demoFirstRoll = true;
            g.demoFirstSession = true;
            this.demoRng = mulberry32(20261106);
          }
        }
        break;
      }
      case 'start': {
        if (!isHost) return this.err('只有房主可以開始遊戲');
        const e = startGame(g, ctx);
        if (e) return this.err(e);
        break;
      }
      case 'action': {
        if (!me) return this.err('旁觀者無法操作');
        const e = await applyAction(g, me, msg.action, ctx);
        ctx.endStream?.();
        if (e) return this.err(e);
        if (g.phase === 'ended') await this.finish();
        break;
      }
      case 'predict': {
        if (!me) return this.err('旁觀者無法預測');
        const e = predict(g, me, String(msg.grade));
        if (e) return this.err(e);
        break;
      }
      case 'react': {
        const p = g.players.find(x => x.id === me);
        if (p && typeof msg.emoji === 'string') {
          this.send({ t: 'react', from: p.name, emoji: msg.emoji.slice(0, 4) });
        }
        return;
      }
      case 'abandon': {
        const humans = g.players.filter(x => !x.isBot);
        if (!me || humans.length !== 1 || humans[0].id !== me) return this.err('只有單人練習可以放棄本局');
        this.closeRoom('已放棄本局');
        return;
      }
    }
    this.pushState();
    this.scheduleBot();
  }

  private closeRoom(message: string): void {
    this.send({ t: 'closed', message });
    if (this.botTimer) {
      clearTimeout(this.botTimer);
      this.botTimer = null;
    }
    this.game = null;
  }

  private scheduleBot(): void {
    if (this.botTimer) {
      clearTimeout(this.botTimer);
      this.botTimer = null;
    }
    const g = this.game;
    if (!g || g.phase !== 'playing') return;
    const p = g.players[g.turn];
    if (p?.isBot) {
      const reading = g.turnStage === 'event' || g.session?.step === 'result';
      const delay = reading ? BOT_READ_DELAY_MS : BOT_DELAY_MS;
      this.botTimer = setTimeout(() => {
        this.run(() => this.botStep());
      }, delay);
    }
  }

  private async botStep(): Promise<void> {
    this.botTimer = null;
    const g = this.game;
    if (!g || g.phase !== 'playing') return;
    const p = g.players[g.turn];
    if (!p || !p.isBot) return;
    const action = botAction(g, Math.random);
    if (!action) return;
    const ctx = this.makeCtx(null);
    const e = await applyAction(g, p.id, action, ctx);
    ctx.endStream?.();
    if (e) {
      console.warn('bot action rejected', e, action);
      if (g.session?.step === 'discover') {
        await applyAction(g, p.id, { type: 'to_plan' }, ctx);
      }
    }
    if ((g.phase as GameState['phase']) === 'ended') {
      await this.finish();
    }
    this.pushState();
    this.scheduleBot();
  }

  private async finish(): Promise<void> {
    const g = this.game;
    if (!g) return;
    g.aiPending = true;
    this.pushState();
    try {
      await enrichCoach(g, () => new RuleAI());
    } finally {
      g.aiPending = false;
    }
    this.pushState();
  }

  drain(): string {
    const items = this.outbox;
    this.outbox = [];
    return JSON.stringify(items);
  }

  close(): void {
    if (this.botTimer) {
      clearTimeout(this.botTimer);
      this.botTimer = null;
    }
    this.game = null;
    this.outbox = [];
  }
}

export interface IqLocal {
  open(): void;
  send(text: string): void;
  drain(): string;
  close(): void;
}


export function installLocalRoom(): void {
  // globalThis is `window` in the browser; the server tsconfig has no DOM lib.
  const host = globalThis as typeof globalThis & { iqLocal?: IqLocal; window?: unknown };
  if (typeof host.window === 'undefined') return;

  let activeRoom: LocalRoom | null = null;

  host.iqLocal = {
    open(): void {
      if (activeRoom) {
        activeRoom.close();
      }
      activeRoom = new LocalRoom('LOCAL');
    },
    send(text: string): void {
      activeRoom?.receive(text);
    },
    drain(): string {
      return activeRoom ? activeRoom.drain() : '[]';
    },
    close(): void {
      if (activeRoom) {
        activeRoom.close();
        activeRoom = null;
      }
    },
  };
}

installLocalRoom();
