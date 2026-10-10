/* INSURE QUEST | Authoritative server game state machine.
 * Pure logic (except asynchronous AI calls via ctx.ai), shared between Durable Objects and unit tests.
 */
import type {
  Action, Alloc, Announcement, BookEntry, BotLevel, CardId, ClientProfile, Decision, FinalRow, GameState, LogLine,
  MarketEvent, Metrics, PendingEvent, PlayerState, Quality, QuestionId, SessionLog, SessionState,
} from './types.ts';
import { apply, clamp, commissionFor, evaluatePlan, finalScore, marketOne, METRICS, runStress, START, STEP, stressOne, validPlan } from './engine.ts';
import { BOARD, CLIENTS, DECOYS, MARKET_EVENTS, QUESTIONS, QUIZ } from './data.ts';
import type { AIService } from '../ai.ts';
import { computeAwards, DILEMMAS, DILEMMA_EFFECT, emptyStats, pickLifeChange, reviewOutcome, rollQuests, updateQuests, type ReviewPick } from './extras.ts';
import { LIFE_TWISTS, applyTwist, type LifeTwist } from './twists.ts';
import { ruleCompliance, mergeCompliance } from './compliance.ts';
import { determineLetter, generateTemplateLetter, type LetterFacts, type ClientLetter } from './letters.ts';
import { calculateClaim, formatWan, simulateTimeline } from './finance.ts';

/** Mulberry32 32-bit seeded PRNG for reproducible runs */
export function mulberry32(seed: number): () => number {
  let s = seed >>> 0;
  return function() {
    s = (s + 0x6D2B79F5) >>> 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface Ctx {
  ai: AIService; rng: () => number; now: () => number;
  aiFor?: (p: PlayerState) => AIService;
  /** Streamed partial AI text for a target key (talk, hint, objection, market, seminar:<id>, coach:<id>, letter:<id>:<client>), relayed to all connections */
  onStream?: (key: string, text: string, done?: boolean) => void;
  /** Action processing finished: discard unsent stream chunks (prevents arriving after final state) */
  endStream?: (key?: string) => void;
}

export const MAX_PLAYERS = 4;
const STANDARD_ASKS = 3;
const SIGN_TRUST = 50;

const zero = (): Metrics => ({ trust: 0, insight: 0, fit: 0, risk: 0, compliance: 0 });

export function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

export function createGame(code: string): GameState {
  return {
    code, phase: 'lobby', hostId: null, settings: { rounds: 6, aiClients: true },
    players: [], turn: 0, round: 1, turnStage: 'roll', lastRoll: null,
    deck: [], marketDeck: [], quizDeck: [],
    clients: Object.fromEntries(CLIENTS.map(c => [c.id, structuredClone(c)])),
    session: null, event: null, territory: {}, log: [], final: null, version: 0,
  };
}

export function addPlayer(s: GameState, p: { id: string; name: string; isBot?: boolean; botLevel?: BotLevel; accountId?: string | null; avatar?: string | null }): string | null {
  if (s.phase !== 'lobby') return '遊戲已開始';
  if (s.players.length >= MAX_PLAYERS) return `房間已滿（最多 ${MAX_PLAYERS} 人）`;
  if (s.players.some(x => x.id === p.id)) return null;
  const name = (p.name || '顧問').trim().slice(0, 12) || '顧問';
  s.players.push({
    id: p.id, name, isBot: !!p.isBot, botLevel: p.isBot ? (p.botLevel || 'pro') : null, accountId: p.isBot ? null : (p.accountId ?? null),
    avatar: p.isBot ? null : (p.avatar ?? null),
    connected: !p.isBot, disconnectedAt: null,
    pos: 0, reputation: 50, commission: 0, skillSum: zero(), sessions: 0,
    book: [], decisions: [], quizCorrect: 0, quizTotal: 0, stats: emptyStats(), complianceStreak: 0,
  });
  if (!s.hostId && !p.isBot) s.hostId = p.id;
  return null;
}

export function removePlayer(s: GameState, id: string) {
  if (s.phase !== 'lobby') return;
  s.players = s.players.filter(p => p.id !== id);
  if (s.hostId === id) s.hostId = s.players.find(p => !p.isBot)?.id ?? null;
}

export function log(s: GameState, text: string, tone: LogLine['tone'] = 'info', now = Date.now()) {
  s.log.push({ ts: now, text, tone });
  if (s.log.length > 60) s.log.splice(0, s.log.length - 60);
}

export function startGame(s: GameState, ctx: Ctx): string | null {
  if (s.phase !== 'lobby') return '遊戲已開始';
  if (!s.players.length) return '至少需要一位玩家';
  s.phase = 'playing';
  s.deck = shuffle(Object.keys(s.clients), ctx.rng);
  s.marketDeck = shuffle(MARKET_EVENTS.map(m => m.id), ctx.rng);
  s.quizDeck = shuffle(QUIZ.map(q => q.id), ctx.rng);
  s.quests = rollQuests(ctx.rng);
  s.awards = null;
  updateQuests(s);
  s.turn = 0; s.round = 1; s.turnStage = 'roll';
  log(s, `遊戲開始！共 ${s.settings.rounds} 回合。目標不是賣最多，而是把客戶服務好。`, 'info', ctx.now());
  return null;
}

export const current = (s: GameState): PlayerState => s.players[s.turn];
const playerById = (s: GameState, id: string) => s.players.find(p => p.id === id);

/** Injects AI-generated client at front of draw deck */
export function injectClient(s: GameState, c: ClientProfile) {
  if (s.clients[c.id]) return;
  s.clients[c.id] = c;
  s.deck.unshift(c.id);
}

function drawClient(s: GameState, ctx: Ctx): ClientProfile {
  if (s.demo && s.demoFirstSession) {
    const targetId = s.demo === '1' ? 'jiahao' : s.demo;
    if (s.clients[targetId]) {
      s.deck = s.deck.filter(id => id !== targetId);
      return s.clients[targetId];
    }
  }
  if (!s.deck.length) {
    const signed = new Set(s.players.flatMap(p => p.book.map(b => b.clientId)));
    s.deck = shuffle(Object.keys(s.clients).filter(id => !signed.has(id)), ctx.rng);
    if (!s.deck.length) s.deck = shuffle(Object.keys(s.clients), ctx.rng);
  }
  return s.clients[s.deck.shift()!];
}

function draw<T>(deckIds: string[], all: (T & { id: string })[], rng: () => number): T & { id: string } {
  if (!deckIds.length) deckIds.push(...shuffle(all.map(x => x.id), rng));
  const id = deckIds.shift()!;
  return all.find(x => x.id === id)!;
}

function startSession(s: GameState, p: PlayerState, c: ClientProfile, referral: boolean, ctx: Ctx) {
  const m = { ...START };
  if (referral) m.trust += 10;
  // Randomly draw 1 dynamic life twist attached to interview
  let twist: LifeTwist;
  if (s.demo && s.demoFirstSession) {
    twist = LIFE_TWISTS.find(t => t.id === 'grace_period_end') ?? LIFE_TWISTS[0];
    s.demoFirstSession = false;
  } else {
    twist = LIFE_TWISTS[Math.floor(ctx.rng() * LIFE_TWISTS.length)];
  }
  if (twist.initialTrustDelta) m.trust = clamp(m.trust + twist.initialTrustDelta);

  // Clients with scene illustration use dedicated decoy (with hotspot coords); others pick random generic decoy
  const decoy = c.decoy ?? DECOYS[Math.floor(ctx.rng() * DECOYS.length)];
  const clues = shuffle([...c.facts.map(f => ({ ...f, real: true })), { ...decoy, fact: '', real: false }], ctx.rng);
  s.session = {
    playerId: p.id, clientId: c.id, referral, tileIndex: p.pos, step: 'discover', asked: [], freeLeft: 1, talkLeft: 3, twist, freeHits: [], clues, observed: [], m,
    objectionOrder: shuffle([0, 1, 2, 3], ctx.rng), predictions: {},
  };
  s.turnStage = 'session';
  log(s, `${p.name} 在${BOARD[p.pos].name}遇見了${c.name}（${c.job}）${referral ? '——轉介紹客戶，信任 +10' : ''}【${twist.title}】`, 'info', ctx.now());
}

function setEvent(s: GameState, ev: PendingEvent) { s.event = ev; s.turnStage = 'event'; }

/** Passing or landing on start: quarterly settlement */
function settlement(s: GameState, p: PlayerState): PendingEvent['lines'] {
  const lines: PendingEvent['lines'] = [];
  let renew = 0;
  for (const b of p.book) if (b.satisfaction >= 60) renew += 5;
  if (renew) { p.commission += renew; lines.push({ text: `滿意客戶續約，業績 +${renew}`, tone: 'good' }); }
  const lapsed = p.book.filter(b => b.satisfaction < 30);
  for (const b of lapsed) lines.push({ text: `${b.name} 滿意度過低而解約，聲望 -3`, tone: 'bad' });
  p.reputation = clamp(p.reputation - lapsed.length * 3);
  p.book = p.book.filter(b => b.satisfaction >= 30);
  if (!lines.length) lines.push({ text: '本季沒有續約或解約。', tone: 'info' });
  return lines;
}

const satDelta = { held: 12, partial: -4, broken: -18 } as const;
const repDelta = { held: 3, partial: 0, broken: -4 } as const;

async function resolveTile(s: GameState, p: PlayerState, ctx: Ctx, passLines: PendingEvent['lines']) {
  const tile = BOARD[p.pos];
  const ev = (kind: PendingEvent['kind'], title: string, body: string, lines: PendingEvent['lines']) =>
    setEvent(s, { kind, playerId: p.id, title, body, lines: [...passLines, ...lines] });

  switch (tile.type) {
    case 'client': {
      if (passLines.length) log(s, `${p.name} 經過起點：${passLines.map(l => l.text).join('；')}`, 'info', ctx.now());
      const owned = s.territory?.[p.pos];
      if (owned && owned.playerId === p.id) {
        const bookEntry = p.book.find(b => b.clientId === owned.clientId);
        if (!bookEntry) {
          delete s.territory[p.pos];
          return startSession(s, p, drawClient(s, ctx), false, ctx);
        }
        p.reputation = clamp(p.reputation + 2);
        bookEntry.satisfaction = clamp(bookEntry.satisfaction + 5);
        const referral = bookEntry.satisfaction >= 75 && ctx.rng() < 0.4;
        const lines: PendingEvent['lines'] = [
          { text: `為 ${bookEntry.name} 完成保單健檢，滿意度 +5（目前 ${bookEntry.satisfaction}）`, tone: 'good' },
          { text: '持續服務既有客戶，聲望 +2', tone: 'good' },
        ];
        if (referral) {
          lines.push({ text: `${bookEntry.name} 很滿意你的服務，介紹了一位朋友`, tone: 'good' });
          log(s, `${p.name} 為 ${bookEntry.name} 進行保單健檢（聲望 +2，滿意度 +5），獲得客戶轉介紹`, 'good', ctx.now());
        } else {
          log(s, `${p.name} 為 ${bookEntry.name} 進行保單健檢（聲望 +2，滿意度 +5）`, 'good', ctx.now());
        }
        return setEvent(s, {
          kind: 'checkup',
          playerId: p.id,
          title: `保單健檢｜${bookEntry.name}`,
          body: `定期檢視 ${bookEntry.name} 的保障狀況與生活變化，維持良好關係。`,
          lines: [...passLines, ...lines],
          checkup: { clientId: bookEntry.clientId, clientName: bookEntry.name, referral },
        });
      }
      return startSession(s, p, drawClient(s, ctx), false, ctx);
    }
    case 'referral': {
      const fans = p.book.filter(b => b.satisfaction >= 70);
      if (fans.length) {
        const from = fans[Math.floor(ctx.rng() * fans.length)];
        log(s, `${from.name} 很滿意 ${p.name} 的服務，介紹了一位朋友`, 'good', ctx.now());
        return startSession(s, p, drawClient(s, ctx), true, ctx);
      }
      if (!p.book.length) {
        log(s, `${p.name} 還沒有客戶，主管轉給你一位陌生開發名單`, 'info', ctx.now());
        return startSession(s, p, drawClient(s, ctx), false, ctx);
      }
      return ev('info', '客戶轉介紹', '目前沒有滿意度 ≥ 70 的客戶願意轉介紹。', [{ text: '轉介紹來自被好好服務的客戶，而不是成交數量。', tone: 'info' }]);
    }
    case 'start':
      return ev('settlement', '季度結算', '檢視你的客戶簿：滿意的客戶續約，不滿意的客戶解約。', passLines.length ? passLines : settlement(s, p));
    case 'life': {
      const candidates = p.book.filter(b => b.stressUsed < s.clients[b.clientId].stress.length);
      if (!p.book.length) {
        log(s, `${p.name} 在社區活動中結識了一位潛在客戶`, 'info', ctx.now());
        return startSession(s, p, drawClient(s, ctx), false, ctx);
      }
      // Signed clients for at least 1 round not yet reviewed have 50% chance of life change and policy review
      const reviewable = p.book.filter(b => !b.reviewed && b.signedRound < s.round);
      if (reviewable.length && ctx.rng() < 0.5) {
        const b = reviewable[Math.floor(ctx.rng() * reviewable.length)];
        const c = s.clients[b.clientId];
        const change = pickLifeChange(c, ctx.rng);
        return setEvent(s, {
          kind: 'review', playerId: p.id, title: `${c.name}｜${change.title}`, body: change.body(c), lines: passLines,
          review: { clientId: c.id, clientName: c.name, change: { title: change.title, body: change.body(c) }, current: { alloc: b.alloc, cards: [...b.cards] }, needCard: change.needCard, picked: null, outcome: null },
        });
      }
      if (!candidates.length) {
        return ev('life', '人生事件', p.book.length ? '你的客戶近期一切平安。' : '你還沒有客戶。人生事件會發生在已簽約的客戶身上。', [{ text: '先去客戶格完成一次需求訪談吧！', tone: 'info' }]);
      }
      const b = candidates[Math.floor(ctx.rng() * candidates.length)];
      const c = s.clients[b.clientId];
      const se = c.stress[b.stressUsed++];
      const r = stressOne(se, b.alloc, b.cards);
      b.satisfaction = clamp(b.satisfaction + satDelta[r.result]);
      p.reputation = clamp(p.reputation + repDelta[r.result]);
      if (r.result === 'held') { p.commission += 4; if (p.stats) p.stats.heldEvents++; }
      if (r.result === 'held') b.held = (b.held ?? 0) + 1;
      else if (r.result === 'partial') b.partial = (b.partial ?? 0) + 1;
      else if (r.result === 'broken') b.broken = (b.broken ?? 0) + 1;

      const claimData = calculateClaim(c, b.alloc, b.cards, se);
      const claim = {
        clientId: c.id,
        clientName: c.name,
        event: se.title,
        tag: se.tag,
        result: r.result,
        loss: claimData.loss,
        covered: claimData.covered,
        outOfPocket: claimData.outOfPocket,
      };

      const tone = r.result === 'held' ? 'good' : r.result === 'partial' ? 'ok' : 'bad';
      const label = r.result === 'held' ? '承接' : r.result === 'partial' ? '部分承接' : '擊穿';
      log(s, `${c.name}：${se.title} → ${label}`, tone, ctx.now());

      const claimLineText = r.result === 'held'
        ? `理賠 ${formatWan(claimData.covered)} 萬已撥付，${c.name}：『還好當初有聽你的。』`
        : r.result === 'partial'
        ? `理賠 ${formatWan(claimData.covered)} 萬，仍需自付 ${formatWan(claimData.outOfPocket)} 萬`
        : `保障缺口：${c.name} 自付 ${formatWan(claimData.outOfPocket)} 萬`;

      return setEvent(s, {
        kind: 'life',
        playerId: p.id,
        title: `理賠服務｜${c.name}`,
        body: se.body,
        lines: [
          ...passLines,
          { text: claimLineText, tone },
          { text: `防線承接力 ${r.defense} / 需求 ${se.need} → ${label}`, tone },
          { text: r.result === 'broken' ? se.hit : se.held, tone },
          { text: `客戶滿意度 ${satDelta[r.result] > 0 ? '+' : ''}${satDelta[r.result]}，聲望 ${repDelta[r.result] >= 0 ? '+' : ''}${repDelta[r.result]}${r.result === 'held' ? '，加保業績 +4' : ''}`, tone },
        ],
        claim,
      });
    }
    case 'market': {
      const me = draw(s.marketDeck, MARKET_EVENTS, ctx.rng);
      const headline = await ctx.ai.marketNews(me, (part, done) => ctx.onStream?.('market', part, done)).catch(() => null);
      const lines: PendingEvent['lines'] = [];
      for (const pl of s.players) {
        let held = 0, broken = 0;
        for (const b of pl.book) {
          const r = marketOne(me, b.alloc);
          b.satisfaction = clamp(b.satisfaction + (r === 'held' ? 6 : r === 'partial' ? -2 : -10));
          if (r === 'held') held++; if (r === 'broken') broken++;
        }
        pl.reputation = clamp(pl.reputation - broken * 2);
        if (pl.book.length) lines.push({ text: `${pl.name}：${held} 位客戶穩住、${broken} 位受到重創${broken ? `（聲望 -${broken * 2}）` : ''}`, tone: broken ? 'bad' : held ? 'good' : 'ok' });
      }
      if (!lines.length) lines.push({ text: '目前還沒有任何顧問有客戶受到影響。', tone: 'info' });
      lines.push({ text: `學習重點：${me.lesson}`, tone: 'info' });
      log(s, `市場快訊：${me.title}`, 'info', ctx.now());
      return ev('market', me.title, headline || me.body, lines);
    }
    case 'training': {
      // 50% chance of dilemma card (compliance vs performance), 50% compliance quiz
      if (ctx.rng() < 0.5) {
        const d = DILEMMAS[Math.floor(ctx.rng() * DILEMMAS.length)];
        const order = shuffle(d.choices, ctx.rng);
        const ids = ['A', 'B', 'C'];
        return setEvent(s, {
          kind: 'dilemma', playerId: p.id, title: d.title, body: d.prompt, lines: passLines,
          dilemma: { id: d.id, title: d.title, prompt: d.prompt, choices: order.map((c, i) => ({ id: `${ids[i]}:${c.id}`, text: c.text })), picked: null, outcome: null },
        });
      }
      const q = draw(s.quizDeck, QUIZ, ctx.rng);
      // Shuffle options on each question to prevent correct answer from staying at fixed position
      const order = shuffle(q.options.map((_, i) => i), ctx.rng);
      return setEvent(s, { kind: 'quiz', playerId: p.id, title: '合規訓練', body: q.q, lines: passLines, quiz: { id: q.id, q: q.q, options: order.map(i => q.options[i]), order } });
    }
    case 'audit': {
      const lines: PendingEvent['lines'] = [];
      for (const b of p.book) {
        if (b.violation) {
          p.reputation = clamp(p.reputation - 10);
          lines.push({ text: `${b.name}：出現違規招攬說法（紅燈），聲望 -10`, tone: 'bad' });
        } else if (b.mis) {
          p.reputation = clamp(p.reputation - 6);
          lines.push({ text: `${b.name}：發現不適合的配置或不當說法，聲望 -6`, tone: 'bad' });
        } else {
          p.reputation = clamp(p.reputation + 1);
          lines.push({ text: `${b.name}：紀錄完整、配置適合，聲望 +1`, tone: 'good' });
        }
      }
      if (!lines.length) lines.push({ text: '沒有可稽核的案件。', tone: 'info' });
      return ev('audit', '合規稽核', '稽核人員抽查你的客戶紀錄：適合度、說明是否完整、是否有誇大或保證。', lines);
    }
    case 'seminar': {
      const tip = await ctx.ai.coachTip(p, (part, done) => ctx.onStream?.(`seminar:${p.id}`, part, done)).catch(() => null);
      p.reputation = clamp(p.reputation + 2);
      return ev('seminar', '顧問研討會', '資深顧問針對你目前的表現給予建議。', [{ text: tip || fallbackTip(p), tone: 'info' }, { text: '持續學習，聲望 +2', tone: 'good' }]);
    }
  }
}

export function fallbackTip(p: PlayerState): string {
  const bad = p.decisions.filter(d => d.quality === 'bad');
  if (!p.decisions.length) return '先問收入中斷與人生目標，再談預算——需求先於商品。';
  if (bad.some(d => d.stage === '異議處理')) return '面對異議時，把保障連回客戶自己的目標，避免恐嚇或保證式說法。';
  if (bad.some(d => d.stage === '方案配置')) return '方案配置要先守住緊急預備金，再依核心需求挑選保障卡，避免過度配置。';
  if (bad.some(d => d.stage === '需求訪談')) return '太早問預算會讓客戶覺得你只想成交；先理解生活與目標。';
  return '你的判斷很穩定！試著用自由提問挖掘客戶沒說出口的需求。';
}

function endTurn(s: GameState, ctx: Ctx) {
  s.session = null; s.event = null; s.turnStage = 'roll';
  s.turn = (s.turn + 1) % s.players.length;
  if (s.turn === 0) {
    s.round++;
    if (s.round > s.settings.rounds) return endGame(s, ctx);
    log(s, `第 ${s.round} 回合開始`, 'info', ctx.now());
    if (s.round === s.settings.rounds && s.settings.rounds >= 3) finale(s, ctx);
  }
}

function decide(p: PlayerState, s: GameState, clientName: string, stage: string, quality: Quality, title: string, body: string) {
  const d: Decision = { round: s.round, clientName, stage, quality, title, body };
  p.decisions.push(d);
}

/** Quote of a red-light phrase for the complaint letter: first clause, at most 24 characters */
function quoteOf(text: string): string {
  const clause = text.trim().split(/[，。！？,.!?；;]/)[0] || text.trim();
  return clause.length > 24 ? clause.slice(0, 24) + '…' : clause;
}

function finishSession(s: GameState, p: PlayerState, sess: SessionState, ctx: Ctx) {
  const c = s.clients[sess.clientId];
  const twistedClient = applyTwist(c, sess.twist);
  const pe = evaluatePlan(twistedClient, sess.plan!.alloc, sess.plan!.cards);
  // 90-day stress rehearsal: lets learner immediately see absorption results across 3 events
  const st = runStress(twistedClient, sess.plan!.alloc, sess.plan!.cards);
  for (const e of st.events) apply(sess.m, STEP.stressEvent(e.result));
  apply(sess.m, STEP.stressFinal(st.quality));
  sess.stress = st.events.map(e => ({ title: e.ev.title, tag: e.ev.tag, result: e.result, defense: e.defense, need: e.ev.need, text: e.result === 'broken' ? e.ev.hit : e.ev.held }));
  const violated = sess.asked.some(a => a.compliance === 'violation') || !!sess.objViolation;
  const fs = finalScore(sess.m, { overCards: pe.over.length > 0, plan: pe.quality, violation: violated });
  const signed = sess.m.trust >= SIGN_TRUST;
  const commission = signed ? commissionFor(sess.plan!.alloc, sess.plan!.cards) : 0;
  const mis = pe.over.length > 0 || sess.m.compliance < 70 || pe.quality === 'bad' || violated;
  if (signed) {
    const baseSat = { S: 82, A: 72, B: 60, C: 45 }[fs.grade] ?? 50;
    let held = 0, partial = 0, broken = 0;
    for (const e of st.events) {
      if (e.result === 'held') held++;
      else if (e.result === 'partial') partial++;
      else if (e.result === 'broken') broken++;
    }
    const entry: BookEntry = {
      clientId: c.id, name: c.name, alloc: sess.plan!.alloc, cards: sess.plan!.cards,
      satisfaction: clamp(baseSat + (sess.referral ? 5 : 0)), planQuality: pe.quality,
      compliance: sess.m.compliance, stressUsed: 0, signedRound: s.round, mis,
      violation: violated,
      held, partial, broken,
    };
    p.book.push(entry);
    p.commission += commission;

    const tIndex = sess.tileIndex ?? p.pos;
    if (BOARD[tIndex]?.type === 'client') {
      if (!s.territory) s.territory = {};
      s.territory[tIndex] = { playerId: p.id, clientId: c.id, clientName: c.name };
    }
  }
  for (const k of METRICS) p.skillSum[k] += sess.m[k];
  p.sessions++;
  const summary = signed
    ? (violated
      ? `${c.name} 簽了約，但你的說法已埋下客訴與裁罰風險，稽核時一定會被發現。`
      : `${c.name} 決定採納你的建議${mis ? '，但方案或說法有適合度疑慮，可能在稽核時被發現' : ''}。`)
    : `${c.name} 對你還不夠信任，決定再考慮看看。`;
  // Spectator prediction: player who guesses grade correctly gains +2 reputation
  const predictionHits: string[] = [];
  for (const [pid, guess] of Object.entries(sess.predictions)) {
    const who = playerById(s, pid);
    if (who && guess === fs.grade) { who.reputation = clamp(who.reputation + 2); predictionHits.push(who.name); }
  }
  if (predictionHits.length) log(s, `${predictionHits.join('、')} 準確預測了評級 ${fs.grade}（聲望 +2）`, 'good', ctx.now());

  // 10-year financial timeline
  const timeline = simulateTimeline(twistedClient, sess.plan!.alloc, sess.plan!.cards, twistedClient.stress, signed);

  // Letter from ten years later: rule engine determines outcome, event, and gap
  let violationQuote = sess.violationQuote;
  if (!violationQuote) {
    const vAsk = sess.asked.find(a => a.compliance === 'violation');
    if (vAsk) violationQuote = quoteOf(vAsk.question);
  }
  const letterFacts = determineLetter(twistedClient, signed, st, {
    violated,
    quote: violationQuote,
    timeline,
  });
  const templateLetter = generateTemplateLetter(twistedClient, letterFacts);
  const clientLetter: ClientLetter = { ...letterFacts, content: templateLetter };

  // Template letter used during interview; AI polished in batches at game end by enrichCoach (background promises in DO not preserved/pushed)

  sess.result = {
    signed, score: fs.score, grade: fs.grade, caps: fs.caps, commission, summary, predictionHits,
    epilogue: epilogueFor(c, st.quality, st.events),
    letter: clientLetter,
    timeline,
  };
  sess.step = 'result';
  p.sessionLogs = [...(p.sessionLogs ?? []), buildSessionLog(s, c, sess, pe, st.events, fs, signed)];
  // Quest stats and compliance streak: 3+ consecutive games with 100 compliance grants +2 extra reputation per game
  const covered = coveredQuestions(sess);
  if (!p.stats) p.stats = emptyStats();
  if (sess.m.compliance === 100) p.stats.compliantSessions++;
  if (c.keyQuestions.every(k => covered.has(k))) p.stats.keySessions++;
  if (signed && ['S', 'A', 'B'].includes(fs.grade)) p.stats.goodSigns++;
  p.complianceStreak = sess.m.compliance === 100 ? (p.complianceStreak ?? 0) + 1 : 0;
  if (p.complianceStreak >= 3) {
    p.reputation = clamp(p.reputation + 2);
    log(s, `${p.name} 合規連擊 ×${p.complianceStreak}！聲望 +2`, 'good', ctx.now());
  }
  log(s, `${p.name} × ${c.name}：評級 ${fs.grade}${signed ? `，成交（業績 +${commission}）` : '，未成交'}`, signed ? (mis ? 'ok' : 'good') : 'bad', ctx.now());
}

/** Dedicated epilogue: prototype 5 use handwritten copy; other clients composed from stress events */
function epilogueFor(c: ClientProfile, quality: string, events: ReturnType<typeof runStress>['events']) {
  const q = (quality === 'strong' || quality === 'medium' ? quality : 'weak') as 'strong' | 'medium' | 'weak';
  const noPlan = c.noPlan ?? c.stress.map(e => e.hit);
  if (c.outcomes?.[q]) return { ...c.outcomes[q], noPlan };
  const head = {
    strong: `你沒有賣給${c.short}最多，<br>你替${c.short}保留了選擇。`,
    medium: `危機被縮小了，<br>但${c.short}仍付出了代價。`,
    weak: '成交，<br>不等於完成顧問責任。',
  }[q];
  const title = { strong: `「${c.goal}」得以延續`, medium: `${c.short}的計畫延後了`, weak: `${c.short}的計畫被迫中斷` }[q];
  return { headline: head, title, list: events.map(e => (e.result === 'broken' ? e.ev.hit : e.ev.held)), noPlan };
}

/** Weakness tags: saved to training records for personalized feedback and trainer statistics */
export const TAG_INFO: Record<string, { label: string; advice: string }> = {
  early_premium: { label: '太早問預算', advice: '先理解收入、目標與現有保障，再談預算，客戶才不會覺得你只想成交。' },
  missed_key: { label: '漏問關鍵需求', advice: '每位客戶都有最在意的事；先問收入中斷與人生目標，通常最能挖到核心。' },
  few_clues: { label: '線索觀察不完整', advice: '開口前先看清場景：收入來源、責任與目標資金都藏在生活細節裡。' },
  decoy: { label: '被干擾物吸引', advice: '有故事的物品不一定是需求線索，聚焦和財務風險相關的細節。' },
  over_cards: { label: '過度配置保障', advice: '保障不是越多越好；和客戶需求不符的保障會壓縮預算、降低信任。' },
  no_core_card: { label: '缺少核心保障', advice: '先找出客戶最大的風險（收入、意外、營業中斷…），再挑對應的保障卡。' },
  low_cash: { label: '緊急預備金不足', advice: '預備金是第一道防線，讓客戶不必在低點賣出資產。' },
  low_protect: { label: '風險保障不足', advice: '收入中斷或重大支出時，保障部位決定客戶能不能撐過去。' },
  growth_heavy: { label: '成長部位過高', advice: '短期要用的錢不該承擔大幅波動，成長部位要配合使用期限。' },
  non_compliant: { label: '出現不當說法', advice: '避免「保證」「一定」「後悔」等恐嚇或保證式說法，改用連結客戶目標的說明。' },
  objection_weak: { label: '異議處理不夠到位', advice: '回應異議時，先同理，再說明方案如何保護客戶自己的目標。' },
  stress_broken: { label: '方案被壓力擊穿', advice: '用壓力預演檢查：收入中斷、大額支出、市場下跌，各有一道防線嗎？' },
  not_signed: { label: '未能建立信任', advice: '信任來自理解客戶；多問生活與目標，少談商品。' },
};

function buildSessionLog(s: GameState, c: ClientProfile, sess: SessionState, pe: ReturnType<typeof evaluatePlan>,
  events: ReturnType<typeof runStress>['events'], fs: { grade: string; score: number }, signed: boolean): SessionLog {
  const covered = coveredQuestions(sess);
  const keyHit = c.keyQuestions.filter(k => covered.has(k)).length;
  const realFound = sess.observed.filter(i => sess.clues[i]?.real).length;
  const decoySeen = sess.observed.some(i => !sess.clues[i]?.real);
  const free = sess.asked.find(a => a.qid === 'free');
  const reply = sess.objectionReply!;
  const tags: string[] = [];
  if (sess.asked.some(a => a.qid === 'premium')) tags.push('early_premium');
  if (keyHit < Math.min(2, c.keyQuestions.length)) tags.push('missed_key');
  if (realFound < 3) tags.push('few_clues');
  if (decoySeen) tags.push('decoy');
  if (pe.over.length) tags.push('over_cards');
  if (!pe.core.length) tags.push('no_core_card');
  if (pe.off.cash === 'low') tags.push('low_cash');
  if (pe.off.protect === 'low') tags.push('low_protect');
  if (pe.off.growth === 'high') tags.push('growth_heavy');
  const violated = sess.asked.some(a => a.compliance === 'violation') || !!sess.objViolation;
  if (sess.m.compliance < 100 || violated) tags.push('non_compliant');
  if (reply.quality !== 'good') tags.push('objection_weak');
  if (events.some(e => e.result === 'broken')) tags.push('stress_broken');
  if (!signed) tags.push('not_signed');
  const violations = sess.asked.filter(a => a.compliance === 'violation').length + (sess.objViolation ? 1 : 0);
  const warnings = sess.asked.filter(a => a.compliance === 'warning').length;
  return {
    clientId: c.id, clientName: c.name, job: c.job, round: s.round, grade: fs.grade, score: fs.score, signed,
    referral: sess.referral, hintUsed: !!sess.hintUsed,
    twist: sess.twist ? { id: sess.twist.id, title: sess.twist.title, hint: sess.twist.hint } : null,
    letter: sess.result?.letter ?? null,
    timeline: sess.result?.timeline ?? null,
    violations,
    warnings,
    clues: { found: realFound, decoy: decoySeen },
    questions: sess.asked.filter(a => a.qid !== 'free').map(a => ({ qid: String(a.qid), text: a.question, key: a.key })),
    freeQuestion: free ? { text: free.question, note: free.note ?? '' } : null,
    plan: { alloc: sess.plan!.alloc, cards: sess.plan!.cards, quality: pe.quality, notes: pe.notes },
    objection: { mode: sess.objectionMode ?? 'choice', text: reply.text, quality: reply.quality, title: reply.title },
    stress: events.map(e => ({ title: e.ev.title, result: e.result })),
    tags,
  };
}

/** Endgame major event: at start of final round, all advisors' clients face market crash simultaneously */
const FINALE: MarketEvent = {
  id: 'finale', tag: '終局', title: '終局大事件：全球金融海嘯', body: '全球股市單季重挫三成、企業裁員潮蔓延。所有顧問的客戶同時面臨考驗——當初的配置撐得住嗎？',
  absorb: { cash: 1.6, growth: -0.8 }, need: 3.5, lesson: '真正的壓力測試不會只來一次；預備金與分散，是讓客戶不必在最壞時刻賣出的關鍵。',
};

function finale(s: GameState, ctx: Ctx) {
  const lines: Announcement['lines'] = [];
  for (const pl of s.players) {
    if (!pl.book.length) continue;
    let held = 0, broken = 0;
    for (const b of pl.book) {
      const r = marketOne(FINALE, b.alloc);
      b.satisfaction = clamp(b.satisfaction + (r === 'held' ? 8 : r === 'partial' ? -4 : -15));
      if (r === 'held') held++;
      if (r === 'broken') broken++;
    }
    pl.reputation = clamp(pl.reputation + held * 2 - broken * 3);
    lines.push({ text: `${pl.name}：${held} 位客戶安然度過、${broken} 位受到重創（聲望 ${held * 2 - broken * 3 >= 0 ? '+' : ''}${held * 2 - broken * 3}）`, tone: broken > held ? 'bad' : held ? 'good' : 'ok' });
  }
  if (!lines.length) lines.push({ text: '目前沒有任何顧問有客戶，這次風暴沒有波及任何人。', tone: 'info' });
  lines.push({ text: `學習重點：${FINALE.lesson}`, tone: 'info' });
  s.announcement = { id: `finale-${s.code}-${s.round}`, title: FINALE.title, body: FINALE.body, lines };
  log(s, `${FINALE.title}！最後一回合開始`, 'bad', ctx.now());
}

/** Spectator grade prediction (during another's interview, once per interview) */
export function predict(s: GameState, playerId: string, grade: string): string | null {
  const sess = s.session;
  if (s.phase !== 'playing' || !sess) return '目前沒有進行中的面談';
  if (sess.playerId === playerId) return '不能預測自己的面談';
  if (!['discover', 'plan', 'objection'].includes(sess.step)) return '面談已經結束，無法預測';
  const p = playerById(s, playerId);
  if (!p || p.isBot) return '只有玩家可以預測';
  if (!['S', 'A', 'B', 'C'].includes(grade)) return '評級無效';
  if (sess.predictions[playerId]) return '這場面談已經預測過了';
  sess.predictions[playerId] = grade;
  return null;
}

/** Covered standard questions: directly asked, plus those matched by free-form asking */
function coveredQuestions(sess: SessionState): Set<string> {
  return new Set<string>([...sess.asked.filter(a => a.qid !== 'free').map(a => a.qid), ...sess.freeHits]);
}

function interviewReady(sess: SessionState) {
  if (sess.talkLeft !== undefined && sess.talkLeft <= 0) return true;
  return coveredQuestions(sess).size >= STANDARD_ASKS;
}

/** Applies player action. Returns error message or null. */
export async function applyAction(s: GameState, playerId: string, a: Action, ctx: Ctx): Promise<string | null> {
  const err = await applyActionInner(s, playerId, a, ctx);
  if (!err && s.quests) {
    for (const { player, quest } of updateQuests(s)) log(s, `${player.name} 完成任務「${quest.title}」！聲望 +${quest.reward}`, 'good', ctx.now());
  }
  return err;
}

async function applyActionInner(s: GameState, playerId: string, a: Action, ctx: Ctx): Promise<string | null> {
  if (s.phase !== 'playing') return '遊戲尚未進行中';
  const p = current(s);
  if (!p || p.id !== playerId) return '還沒輪到你';

  if (a.type === 'roll') {
    if (s.turnStage !== 'roll') return '現在不能擲骰';
    let roll = 1 + Math.floor(ctx.rng() * 6);
    if (s.demo && !p.isBot && s.demoFirstRoll) {
      let dist = 1;
      while (dist <= BOARD.length && BOARD[(p.pos + dist) % BOARD.length].type !== 'client') dist++;
      roll = dist;
      s.demoFirstRoll = false;
    }
    s.lastRoll = roll;
    const passed = p.pos + roll >= BOARD.length;
    p.pos = (p.pos + roll) % BOARD.length;
    log(s, `${p.name} 擲出 ${roll} 點，來到「${BOARD[p.pos].name}」`, 'info', ctx.now());
    const passLines = passed ? settlement(s, p) : [];
    await resolveTile(s, p, ctx, passLines);
    return null;
  }

  if (s.turnStage === 'event' && s.event) {
    const ev = s.event;
    if (a.type === 'answer_quiz') {
      if (!ev.quiz || ev.quiz.picked !== undefined) return '沒有待回答的題目';
      const q = QUIZ.find(x => x.id === ev.quiz!.id)!;
      if (!Number.isInteger(a.index) || a.index < 0 || a.index >= q.options.length) return '選項無效';
      ev.quiz.picked = a.index; ev.quiz.answer = ev.quiz.order.indexOf(q.answer); ev.quiz.explain = q.explain;
      p.quizTotal++;
      const ok = ev.quiz.order[a.index] === q.answer;
      if (ok) { p.quizCorrect++; p.reputation = clamp(p.reputation + 3); if (p.stats) p.stats.quizCorrect++; }
      ev.lines.push({ text: ok ? '答對了！聲望 +3' : `答錯了，正確答案是「${q.options[q.answer]}」`, tone: ok ? 'good' : 'bad' });
      ev.lines.push({ text: q.explain, tone: 'info' });
      decide(p, s, '合規訓練', '合規測驗', ok ? 'good' : 'bad', q.q, q.explain);
      return null;
    }
    if (a.type === 'choose_dilemma') {
      const dl = ev.dilemma;
      if (!dl || dl.picked) return '沒有待選擇的情境';
      const choiceId = dl.choices.find(c => c.id === a.choice)?.id;
      if (!choiceId) return '選項無效';
      const def = DILEMMAS.find(d => d.id === dl.id)!.choices.find(c => c.id === choiceId.split(':')[1])!;
      const eff = DILEMMA_EFFECT[def.quality];
      p.reputation = clamp(p.reputation + eff.rep);
      if (def.commission) p.commission += def.commission;
      if (def.quality === 'good' && p.stats) p.stats.dilemmaGood++;
      const effects = `聲望 ${eff.rep >= 0 ? '+' : ''}${eff.rep}${def.commission ? `、業績 +${def.commission}（短期）` : ''}`;
      dl.picked = choiceId;
      dl.outcome = { title: def.title, body: def.body, tone: eff.tone, effects };
      decide(p, s, '情境抉擇', '情境抉擇', def.quality, `${dl.title}：${def.title}`, def.body);
      log(s, `${p.name} 面對「${dl.title}」：${def.title}`, eff.tone, ctx.now());
      return null;
    }
    if (a.type === 'review') {
      const rv = ev.review;
      if (!rv || rv.picked) return '沒有待處理的回訪';
      const valid = ['medical', 'income', 'accident', 'tools', 'legacy', 'care', 'none', 'skip'];
      if (!valid.includes(a.card)) return '選項無效';
      const entry = p.book.find(b => b.clientId === rv.clientId);
      if (!entry) return '找不到這位客戶';
      const out = reviewOutcome(entry, rv.needCard, a.card as ReviewPick, s.clients[rv.clientId].plan.cards);
      entry.reviewed = true;
      entry.satisfaction = clamp(entry.satisfaction + out.sat);
      p.reputation = clamp(p.reputation + out.rep);
      p.commission += out.commission;
      if (out.addCard && !entry.cards.includes(out.addCard)) entry.cards.push(out.addCard);
      if (out.quality === 'bad' && out.addCard) entry.mis = true;
      if (out.quality === 'good' && p.stats) p.stats.goodReviews++;
      rv.picked = a.card;
      rv.outcome = { title: out.title, body: `${out.body}（滿意度 ${out.sat >= 0 ? '+' : ''}${out.sat}${out.commission ? `、業績 +${out.commission}` : ''}）`, tone: out.quality === 'good' ? 'good' : out.quality === 'ok' ? 'ok' : 'bad' };
      decide(p, s, rv.clientName, '保單健檢', out.quality, out.title, out.body);
      log(s, `${p.name} 回訪 ${rv.clientName}（${rv.change.title}）：${out.title}`, rv.outcome.tone, ctx.now());
      return null;
    }
    if (a.type === 'continue') {
      if (ev.quiz && ev.quiz.picked === undefined) return '請先作答';
      if (ev.dilemma && !ev.dilemma.picked) return '請先做出選擇';
      if (ev.review && !ev.review.picked) return '請先決定如何回訪';
      if (ev.kind === 'checkup' && ev.checkup?.referral) {
        s.event = null;
        startSession(s, p, drawClient(s, ctx), true, ctx);
        return null;
      }
      endTurn(s, ctx);
      return null;
    }
    return '請先完成目前的事件';
  }

  const sess = s.session;
  if (s.turnStage !== 'session' || !sess) return '目前沒有進行中的面談';
  const c = s.clients[sess.clientId];

  switch (a.type) {
    case 'observe': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (!Number.isInteger(a.index) || a.index < 0 || a.index >= sess.clues.length) return '線索無效';
      if (sess.observed.includes(a.index)) return '這個線索已經看過了';
      if (sess.observed.length >= 3) return '最多調查 3 個線索';
      sess.observed.push(a.index);
      if (sess.clues[a.index].real) {
        apply(sess.m, STEP.clueFound);
        if (sess.clues.every((cl, i) => !cl.real || sess.observed.includes(i))) {
          apply(sess.m, STEP.clueFinish);
          decide(p, s, c.name, '線索觀察', 'good', '找齊了三個需求線索', '先觀察客戶的生活脈絡，提問才會切中要害。');
        }
      } else {
        decide(p, s, c.name, '線索觀察', 'ok', `「${sess.clues[a.index].title}」不是需求線索`, sess.clues[a.index].detail);
      }
      return null;
    }
    case 'ask': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (sess.aiBusy) return '客戶正在回應中，請稍候';
      if (interviewReady(sess)) return `最多選 ${STANDARD_ASKS} 題，請進入方案配置`;
      const q = QUESTIONS.find(x => x.id === a.qid);
      if (!q) return '題目無效';
      if (sess.asked.some(x => x.qid === a.qid)) return '這題已經問過了';
      if (sess.freeHits.includes(a.qid)) return '這題已經透過自由提問問過了';
      const ans = c.answers[a.qid];
      apply(sess.m, { trust: ans.trust, insight: ans.insight });
      sess.asked.push({ qid: a.qid, question: q.text, answer: ans.text, key: ans.key });
      if (a.qid === 'premium') decide(p, s, c.name, '需求訪談', 'bad', '太早問預算', q.coach);
      return null;
    }
    case 'ask_free': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (sess.aiBusy) return '客戶正在回應中，請稍候';
      if (sess.freeLeft <= 0) return '自由提問次數已用完';
      const text = (a.text || '').trim().slice(0, 120);
      if (text.length < 2) return '請輸入問題';
      sess.freeLeft--;
      const r = await ctx.ai.freeQuestion(c, text, sess.asked);
      apply(sess.m, { trust: r.trust, insight: r.insight, compliance: r.compliance });
      sess.asked.push({ qid: 'free', question: text, answer: r.answer, key: r.key, note: r.note });
      // Counted only if matching uncovered standard question, avoiding duplicate standard answers
      if (r.matched && !coveredQuestions(sess).has(r.matched)) sess.freeHits.push(r.matched);
      if (r.compliance < 0) decide(p, s, c.name, '需求訪談', 'bad', '提問出現不當說法', r.note || '提問時避免保證或恐嚇式用語。');
      return null;
    }
    case 'talk': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (sess.aiBusy) return '客戶正在回應中，請稍候';
      const talkLeft = sess.talkLeft ?? 3;
      if (talkLeft <= 0) return '對話輪數已用完，請進入方案配置';
      const text = (a.text || '').trim().slice(0, 150);
      if (text.length < 2) return '請輸入話語';

      // 1. Run rule-based compliance radar first
      const ruleComp = ruleCompliance(text);

      // 2. Call AI or fall back to rule-based
      sess.aiBusy = true;
      let dialogue;
      try {
        dialogue = await ctx.ai.talk(c, sess.twist, sess.asked, text, a.suggested, (part, done) => ctx.onStream?.('talk', part, done));
      } finally {
        sess.aiBusy = false;
      }

      // 3. Merge compliance results (taking more severe level and larger penalty)
      const mergedComp = mergeCompliance(ruleComp, dialogue.compliance);

      // 4. Clamp metrics
      const trustDelta = Math.max(-15, Math.min(12, dialogue.trustDelta));
      const insightDelta = Math.max(0, Math.min(15, dialogue.insightDelta));
      const penalty = Math.max(-25, Math.min(0, mergedComp.penalty));
      apply(sess.m, { trust: trustDelta, insight: insightDelta, compliance: penalty });

      // 5. Whitelist filter revealedFacts
      const realTitles = new Set(c.facts.map(f => f.title));
      const hits = (dialogue.revealedFacts || []).filter(t => realTitles.has(t));
      for (const h of hits) {
        const idx = sess.clues.findIndex(cl => cl.real && cl.title === h);
        if (idx >= 0 && !sess.observed.includes(idx)) {
          sess.observed.push(idx);
          apply(sess.m, STEP.clueFound);
        }
      }
      if (sess.clues.every((cl, i) => !cl.real || sess.observed.includes(i))) {
        apply(sess.m, STEP.clueFinish);
        decide(p, s, c.name, '線索觀察', 'good', '透過對話找齊了需求線索', '在對話中探詢出真實生活狀況。');
      }
      if (a.suggested && !coveredQuestions(sess).has(a.suggested)) {
        sess.freeHits.push(a.suggested);
      }

      // 6. Decrement talk rounds
      sess.talkLeft = talkLeft - 1;

      // 7. Store in session.asked
      sess.asked.push({
        qid: (a.suggested ?? 'free') as any,
        question: text,
        answer: dialogue.answer,
        key: hits[0] ?? (a.suggested ? c.answers[a.suggested]?.key : null),
        note: dialogue.coachTip,
        compliance: mergedComp.level,
        emotion: dialogue.emotion,
        coachTip: dialogue.coachTip,
        source: ctx.ai.enabled ? 'ai' : 'rule',
      });

      // 8. Log decision
      if (mergedComp.level === 'violation') {
        decide(p, s, c.name, '需求訪談', 'bad', '對話出現違規招攬說法', mergedComp.issues.map(i => i.suggestion).join('；') || '避免保證收益或恐嚇式用語');
      } else if (mergedComp.level === 'warning') {
        decide(p, s, c.name, '需求訪談', 'ok', '對話出現話術瑕疵', mergedComp.issues.map(i => i.suggestion).join('；'));
      } else if (trustDelta > 0) {
        decide(p, s, c.name, '需求訪談', 'good', '合規且切中需求', dialogue.coachTip);
      }

      return null;
    }
    case 'to_plan': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (sess.aiBusy) return '客戶仍在回應中，請稍候';
      if (!interviewReady(sess)) return `請先完成 ${STANDARD_ASKS} 個訪談問題或 3 輪對話`;
      const askedKeys = new Set<string>([...sess.asked.map(x => x.qid), ...sess.freeHits]);
      const keyHit = c.keyQuestions.filter(k => askedKeys.has(k)).length;
      apply(sess.m, STEP.interviewFinish(keyHit));
      decide(p, s, c.name, '需求訪談', keyHit >= 2 ? 'good' : keyHit === 1 ? 'ok' : 'bad',
        keyHit >= 2 ? '問到了關鍵需求' : keyHit === 1 ? '只問到部分關鍵需求' : '沒有問到關鍵需求',
        `${c.short}的關鍵問題：${c.keyQuestions.map(k => QUESTIONS.find(q => q.id === k)!.text).join('／')}`);
      sess.step = 'plan';
      return null;
    }
    case 'plan': {
      if (sess.step !== 'plan') return '現在不是方案配置階段';
      const alloc: Alloc = { cash: Number(a.alloc?.cash), protect: Number(a.alloc?.protect), growth: Number(a.alloc?.growth) };
      const cards = Array.isArray(a.cards) ? a.cards.map(String) as CardId[] : [];
      const twistedClient = applyTwist(c, sess.twist);
      const err = validPlan(alloc, cards, twistedClient);
      if (err) return err;
      const pe = evaluatePlan(twistedClient, alloc, cards);
      apply(sess.m, pe.changes);
      sess.plan = { alloc, cards, quality: pe.quality, notes: pe.notes };
      decide(p, s, c.name, '方案配置', pe.quality,
        pe.quality === 'good' ? '配置與需求相符' : pe.quality === 'ok' ? '配置大致合理' : '配置與需求落差大',
        pe.notes.join(' ') || '預備、保障與成長都在合理區間，核心保障卡到位。');
      sess.step = 'objection';
      return null;
    }
    case 'objection': {
      if (sess.step !== 'objection') return '現在不是異議處理階段';
      if (!Number.isInteger(a.index) || a.index < 0 || a.index > 3) return '選項無效';
      const opt = c.objection.options[sess.objectionOrder[a.index]];
      sess.objectionMode = 'choice';
      apply(sess.m, opt.changes);
      sess.objectionReply = { text: opt.text, title: opt.title, body: opt.body, quality: opt.quality };
      if (opt.changes.compliance !== undefined && opt.changes.compliance <= -15) {
        sess.objViolation = true;
        sess.violationQuote = quoteOf(opt.text);
      }
      decide(p, s, c.name, '異議處理', opt.quality, opt.title, opt.body);
      finishSession(s, p, sess, ctx);
      return null;
    }
    case 'objection_free': {
      if (sess.step !== 'objection') return '現在不是異議處理階段';
      const text = (a.text || '').trim().slice(0, 200);
      if (text.length < 4) return '請輸入你的回應';
      sess.aiBusy = true;
      const g = await ctx.ai.gradeObjection(c, text, (part, done) => ctx.onStream?.('objection', part, done));
      sess.aiBusy = false;
      apply(sess.m, { trust: g.trust, fit: g.fit, risk: g.risk, compliance: g.compliance });
      sess.objectionReply = { text, title: g.title, body: g.body, quality: g.quality };
      sess.objectionMode = 'free';
      if (g.compliance <= -15) {
        sess.objViolation = true;
        sess.violationQuote = quoteOf(text);
      }
      decide(p, s, c.name, '異議處理', g.quality, g.title, g.body);
      finishSession(s, p, sess, ctx);
      return null;
    }
    case 'hint': {
      if (sess.step === 'result') return '面談已結束';
      if (sess.hintUsed) return '這場面談已經用過教練提示';
      sess.hintUsed = true;
      sess.hint = await ctx.ai.hint(c, sess, (part, done) => ctx.onStream?.('hint', part, done));
      log(s, `${p.name} 向教練求助`, 'info', ctx.now());
      return null;
    }
    case 'continue': {
      if (sess.step !== 'result') return '面談尚未結束';
      endTurn(s, ctx);
      return null;
    }
  }
  return '未知的動作';
}

export function scorePlayer(p: PlayerState): Omit<FinalRow, 'coach'> {
  const skill = zero();
  if (p.sessions) for (const k of METRICS) skill[k] = Math.round(p.skillSum[k] / p.sessions);
  const skillScore = p.sessions ? finalScore(skill).score : 0;
  const service = p.book.length ? Math.round(p.book.reduce((t, b) => t + b.satisfaction, 0) / p.book.length) : 0;
  let protection = 0;
  if (p.book.length) {
    const totalProt = p.book.reduce((sum, b) => {
      if (b.violation) return sum;
      const h = b.held ?? 0;
      const part = b.partial ?? 0;
      const brk = b.broken ?? 0;
      const total = Math.max(1, h + part + brk);
      return sum + ((h + 0.5 * part) / total) * 100;
    }, 0);
    protection = Math.round(totalProt / p.book.length);
  }
  const score = Math.round(0.5 * skillScore + 0.15 * service + 0.10 * protection + 0.15 * p.reputation + 0.10 * Math.min(100, p.commission));
  let grade = score >= 85 ? 'S' : score >= 72 ? 'A' : score >= 60 ? 'B' : 'C';
  const caps: string[] = [];
  const order = ['C', 'B', 'A', 'S'];
  const cap = (g: string, why: string) => { if (order.indexOf(grade) > order.indexOf(g)) grade = g; caps.push(why); };
  if (!p.sessions) cap('C', '沒有完成任何客戶面談');
  if (p.sessions && skill.compliance < 70) cap('B', '平均合規表達低於 70');
  if (p.book.some(b => b.mis)) cap('A', '客戶簿中有不適合的銷售');
  return {
    playerId: p.id, name: p.name, isBot: p.isBot, score, grade, caps, skill, service,
    protection, reputation: p.reputation, commission: p.commission, clients: p.book.length,
  };
}

export function endGame(s: GameState, ctx: Ctx) {
  s.phase = 'ended'; s.turnStage = 'done';
  s.final = s.players.map(p => {
    const ai = ctx.aiFor ? ctx.aiFor(p) : (!p.isBot && p.accountId ? ctx.ai : null);
    const aiWillBeUsed = !!ai?.enabled && !p.isBot && !!p.accountId;
    const hasLetters = (p.sessionLogs ?? []).some(l => l.letter);
    const row: FinalRow = {
      ...scorePlayer(p),
      coach: aiWillBeUsed ? '' : fallbackTip(p),
      coachPending: aiWillBeUsed,
      lettersPending: aiWillBeUsed && hasLetters,
    };
    const letters = (p.sessionLogs ?? [])
      .filter(l => l.letter)
      .slice(-3)
      .map(l => ({
        clientId: l.clientId,
        clientName: l.clientName,
        outcome: l.letter!.outcome as 'thanks' | 'regret' | 'mixed' | 'complaint',
        content: l.letter!.content,
      }));
    const timelines = (p.sessionLogs ?? [])
      .filter(l => l.timeline)
      .map(l => ({ clientName: l.clientName, ...l.timeline! }));
    return {
      ...row,
      letters,
      timeline: timelines[timelines.length - 1],
      timelines,
    };
  }).sort((x, y) => y.score - x.score);
  s.awards = computeAwards(s, p => scorePlayer(p).score);
  log(s, `遊戲結束！最佳顧問：${s.final[0].name}（${s.final[0].grade}）`, 'good', ctx.now());
}

/** Generates personalized coach feedback via AI upon completion (retains rule-based on failure) */
/** Resolves to null on rejection or after ms; clears its timer so nothing lingers once the AI answers */
async function withTimeout<T>(p: Promise<T>, ms: number): Promise<T | null> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<null>(resolve => { timer = setTimeout(() => resolve(null), ms); });
  try {
    return await Promise.race([p.catch(() => null), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

export async function enrichCoach(s: GameState, aiFor: (p: PlayerState) => AIService, onStream?: (key: string, text: string, done?: boolean) => void) {
  if (!s.final) return;
  await Promise.all(s.final.map(async row => {
    const p = playerById(s, row.playerId);
    if (!p || p.isBot) {
      if (row.coachPending) {
        row.coach = fallbackTip(p ?? { ...row, decisions: [], skillSum: zero(), pos: 0, connected: false, disconnectedAt: null, book: [], quizCorrect: 0, quizTotal: 0, commission: row.commission, reputation: row.reputation, sessions: row.clients } as any);
        row.coachPending = false;
      }
      row.lettersPending = false;
      return;
    }
    const ai = aiFor(p);
    if (!ai.enabled) {
      if (row.coachPending || !row.coach) {
        row.coach = fallbackTip(p);
        row.coachPending = false;
      }
      row.lettersPending = false;
      return;
    }
    try {
      const text = await withTimeout(ai.debrief(p, row, (part, done) => onStream?.(`coach:${row.playerId}`, part, done)), 30000);
      if (text) {
        row.coach = text;
      } else {
        row.coach = fallbackTip(p);
      }
    } catch {
      row.coach = fallbackTip(p);
    } finally {
      row.coachPending = false;
    }
    // Letter from ten years later: outcome and gap determined by rule engine, AI rewrites text (retains template letter on failure/guests)
    if (!ai.enabled || !row.letters?.length) {
      row.lettersPending = false;
      return;
    }
    try {
      const logs = (p.sessionLogs ?? []).filter(l => l.letter).slice(-3);
      await Promise.all(logs.map(async (l, i) => {
        const c = s.clients[l.clientId];
        const row_letter = row.letters?.[i];
        if (!c || !l.letter || !row_letter) return;
        const twist = LIFE_TWISTS.find(t => t.id === l.twist?.id) ?? null;
        const { content: _, ...facts } = l.letter;
        const content = await withTimeout(ai.letter(applyTwist(c, twist), twist, facts, (part, done) => onStream?.(`letter:${row.playerId}:${c.id}`, part, done)), 25000);
        if (content) { row_letter.content = content; l.letter.content = content; }
      }));
    } finally {
      row.lettersPending = false;
    }
  }));
}

/** Public state transmitted to client: hides client answers, ideal allocations, question bank answers */
/** viewerId: field personalized for this connection (currently only one's own prediction) */
export function publicView(s: GameState, viewerId: string | null = null) {
  const sess = s.session;
  const c = sess ? s.clients[sess.clientId] : null;
  return {
    code: s.code, phase: s.phase, hostId: s.hostId, settings: s.settings,
    territory: s.territory ?? {},
    // AI-generated clients share generic portraits: clientId -> portrait key (built-in clients use their own id)
    portraits: Object.fromEntries(Object.values(s.clients).filter(c => c.generated && c.portrait).map(c => [c.id, c.portrait])),
    players: s.players.map(p => ({
      id: p.id, name: p.name, isBot: p.isBot, botLevel: p.botLevel, connected: p.connected, loggedIn: !!p.accountId, complianceStreak: p.complianceStreak ?? 0,
      avatar: p.avatar ?? null,
      pos: p.pos, reputation: p.reputation, commission: p.commission, sessions: p.sessions,
      book: p.book.map(b => ({
        clientId: b.clientId, name: b.name, satisfaction: b.satisfaction, alloc: b.alloc, cards: b.cards, mis: b.mis,
        held: b.held ?? 0, partial: b.partial ?? 0, broken: b.broken ?? 0,
      })),
      decisions: p.decisions.slice(-12),
      quizCorrect: p.quizCorrect, quizTotal: p.quizTotal,
    })),
    turn: s.turn, round: s.round, turnStage: s.turnStage, lastRoll: s.lastRoll,
    deckLeft: s.deck.length,
    session: sess && c ? {
      playerId: sess.playerId, referral: sess.referral, step: sess.step, asked: sess.asked, freeLeft: sess.freeLeft,
      talkLeft: sess.talkLeft ?? 3,
      twist: sess.twist ? { id: sess.twist.id, title: sess.twist.title, hint: sess.twist.hint } : null,
      metrics: sess.m, aiBusy: !!sess.aiBusy,
      // Hotspot coordinates provided for both real clues and decoys without revealing authenticity
      clues: sess.clues.map((cl, i) => sess.observed.includes(i)
        ? { title: cl.title, detail: cl.detail, fact: cl.fact, real: cl.real, observed: true, spot: cl.spot ?? null }
        : { title: cl.title, observed: false, spot: cl.spot ?? null }),
      predictions: { count: Object.keys(sess.predictions).length, mine: viewerId ? sess.predictions[viewerId] ?? null : null },
      stress: sess.stress ?? null,
      ready: interviewReady(sess),
      covered: [...coveredQuestions(sess)],
      client: {
        id: c.id, name: c.name, short: c.short, age: c.age, gender: c.gender, job: c.job, tag: c.tag, difficulty: c.difficulty,
        portrait: c.portrait, goal: c.goal, amount: c.amount, incomeInfo: c.incomeInfo, family: c.family,
        intro: c.intro, quote: c.quote, generated: !!c.generated, scene: c.scene ?? null,
      },
      objection: sess.step === 'objection' || sess.step === 'result' ? {
        text: c.objection.text, options: sess.objectionOrder.map(i => c.objection.options[i].text),
      } : null,
      objectionReply: sess.objectionReply ?? null,
      hintUsed: !!sess.hintUsed,
      hint: sess.hint ?? null,
      plan: sess.plan ?? null,
      result: sess.result ?? null,
    } : null,
    event: s.event ? {
      ...s.event,
      quiz: s.event.quiz ? (({ order: _order, ...rest }) => rest)(s.event.quiz) : undefined,
      review: s.event.review ? (({ needCard: _need, ...rest }) => rest)(s.event.review) : undefined,
    } : null,
    log: s.log.slice(-25),
    quests: s.quests ?? [],
    awards: s.awards ?? null,
    aiPending: !!s.aiPending,
    final: s.final,
    announcement: s.announcement ?? null,
    version: s.version,
  };
}
