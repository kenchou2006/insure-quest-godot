/* INSURE QUEST｜伺服器權威遊戲狀態機。
 * 純邏輯（除了透過 ctx.ai 的非同步 AI 呼叫），Durable Object 與單元測試共用。
 */
import type {
  Action, Alloc, Announcement, BookEntry, BotLevel, CardId, ClientProfile, Decision, FinalRow, GameState, LogLine,
  MarketEvent, Metrics, PendingEvent, PlayerState, Quality, QuestionId, SessionLog, SessionState,
} from './types.ts';
import { apply, clamp, commissionFor, evaluatePlan, finalScore, marketOne, METRICS, runStress, START, STEP, stressOne, validPlan } from './engine.ts';
import { BOARD, CLIENTS, DECOYS, MARKET_EVENTS, QUESTIONS, QUIZ } from './data.ts';
import type { AIService } from '../ai.ts';
import { computeAwards, DILEMMAS, DILEMMA_EFFECT, emptyStats, pickLifeChange, reviewOutcome, rollQuests, updateQuests, type ReviewPick } from './extras.ts';

export interface Ctx { ai: AIService; rng: () => number; now: () => number }

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
    session: null, event: null, log: [], final: null, version: 0,
  };
}

export function addPlayer(s: GameState, p: { id: string; name: string; isBot?: boolean; botLevel?: BotLevel; accountId?: string | null }): string | null {
  if (s.phase !== 'lobby') return '遊戲已開始';
  if (s.players.length >= MAX_PLAYERS) return `房間已滿（最多 ${MAX_PLAYERS} 人）`;
  if (s.players.some(x => x.id === p.id)) return null;
  const name = (p.name || '顧問').trim().slice(0, 12) || '顧問';
  s.players.push({
    id: p.id, name, isBot: !!p.isBot, botLevel: p.isBot ? (p.botLevel || 'pro') : null, accountId: p.isBot ? null : (p.accountId ?? null),
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

/** 加入 AI 生成的客戶，排在牌堆最前面 */
export function injectClient(s: GameState, c: ClientProfile) {
  if (s.clients[c.id]) return;
  s.clients[c.id] = c;
  s.deck.unshift(c.id);
}

function drawClient(s: GameState, ctx: Ctx): ClientProfile {
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
  // 有場景插圖的客戶用專屬干擾物（含熱點座標），其餘隨機挑一個通用干擾物
  const decoy = c.decoy ?? DECOYS[Math.floor(ctx.rng() * DECOYS.length)];
  const clues = shuffle([...c.facts.map(f => ({ ...f, real: true })), { ...decoy, fact: '', real: false }], ctx.rng);
  s.session = {
    playerId: p.id, clientId: c.id, referral, step: 'discover', asked: [], freeLeft: 1, freeHits: [], clues, observed: [], m,
    objectionOrder: shuffle([0, 1, 2, 3], ctx.rng), predictions: {},
  };
  s.turnStage = 'session';
  log(s, `${p.name} 在${BOARD[p.pos].name}遇見了${c.name}（${c.job}）${referral ? '——轉介紹客戶，信任 +10' : ''}`, 'info', ctx.now());
}

function setEvent(s: GameState, ev: PendingEvent) { s.event = ev; s.turnStage = 'event'; }

/** 經過或停在起點：季度結算 */
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
      // 已簽約至少一回合、尚未回訪的客戶，有一半機率出現人生變化與保單健檢
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
      const tone = r.result === 'held' ? 'good' : r.result === 'partial' ? 'ok' : 'bad';
      const label = r.result === 'held' ? '承接' : r.result === 'partial' ? '部分承接' : '擊穿';
      log(s, `${c.name}：${se.title} → ${label}`, tone, ctx.now());
      return ev('life', `${c.name}｜${se.title}`, se.body, [
        { text: `防線承接力 ${r.defense} / 需求 ${se.need} → ${label}`, tone },
        { text: r.result === 'broken' ? se.hit : se.held, tone },
        { text: `客戶滿意度 ${satDelta[r.result] > 0 ? '+' : ''}${satDelta[r.result]}，聲望 ${repDelta[r.result] >= 0 ? '+' : ''}${repDelta[r.result]}${r.result === 'held' ? '，加保業績 +4' : ''}`, tone },
      ]);
    }
    case 'market': {
      const me = draw(s.marketDeck, MARKET_EVENTS, ctx.rng);
      const headline = await ctx.ai.marketNews(me).catch(() => null);
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
      // 一半機率出現情境抉擇卡（合規 vs 業績），一半是合規測驗
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
      // 每次出題都打亂選項，避免正確答案固定在同一個位置
      const order = shuffle(q.options.map((_, i) => i), ctx.rng);
      return setEvent(s, { kind: 'quiz', playerId: p.id, title: '合規訓練', body: q.q, lines: passLines, quiz: { id: q.id, q: q.q, options: order.map(i => q.options[i]), order } });
    }
    case 'audit': {
      const lines: PendingEvent['lines'] = [];
      for (const b of p.book) {
        if (b.mis) { p.reputation = clamp(p.reputation - 6); lines.push({ text: `${b.name}：發現不適合的配置或不當說法，聲望 -6`, tone: 'bad' }); }
        else { p.reputation = clamp(p.reputation + 1); lines.push({ text: `${b.name}：紀錄完整、配置適合，聲望 +1`, tone: 'good' }); }
      }
      if (!lines.length) lines.push({ text: '沒有可稽核的案件。', tone: 'info' });
      return ev('audit', '合規稽核', '稽核人員抽查你的客戶紀錄：適合度、說明是否完整、是否有誇大或保證。', lines);
    }
    case 'seminar': {
      const tip = await ctx.ai.coachTip(p).catch(() => null);
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

function finishSession(s: GameState, p: PlayerState, sess: SessionState, ctx: Ctx) {
  const c = s.clients[sess.clientId];
  const pe = evaluatePlan(c, sess.plan!.alloc, sess.plan!.cards);
  // 90 天壓力預演：讓學員立刻看見配置在三個事件下的承接結果
  const st = runStress(c, sess.plan!.alloc, sess.plan!.cards);
  for (const e of st.events) apply(sess.m, STEP.stressEvent(e.result));
  apply(sess.m, STEP.stressFinal(st.quality));
  sess.stress = st.events.map(e => ({ title: e.ev.title, tag: e.ev.tag, result: e.result, defense: e.defense, need: e.ev.need, text: e.result === 'broken' ? e.ev.hit : e.ev.held }));
  const fs = finalScore(sess.m, { overCards: pe.over.length > 0, plan: pe.quality });
  const signed = sess.m.trust >= SIGN_TRUST;
  const commission = signed ? commissionFor(sess.plan!.alloc, sess.plan!.cards) : 0;
  const mis = pe.over.length > 0 || sess.m.compliance < 70 || pe.quality === 'bad';
  if (signed) {
    const baseSat = { S: 82, A: 72, B: 60, C: 45 }[fs.grade] ?? 50;
    const entry: BookEntry = {
      clientId: c.id, name: c.name, alloc: sess.plan!.alloc, cards: sess.plan!.cards,
      satisfaction: clamp(baseSat + (sess.referral ? 5 : 0)), planQuality: pe.quality,
      compliance: sess.m.compliance, stressUsed: 0, signedRound: s.round, mis,
    };
    p.book.push(entry);
    p.commission += commission;
  }
  for (const k of METRICS) p.skillSum[k] += sess.m[k];
  p.sessions++;
  const summary = signed
    ? `${c.name} 決定採納你的建議${mis ? '，但方案或說法有適合度疑慮，可能在稽核時被發現' : ''}。`
    : `${c.name} 對你還不夠信任，決定再考慮看看。`;
  // 旁觀者預測：猜中評級的玩家聲望 +2
  const predictionHits: string[] = [];
  for (const [pid, guess] of Object.entries(sess.predictions)) {
    const who = playerById(s, pid);
    if (who && guess === fs.grade) { who.reputation = clamp(who.reputation + 2); predictionHits.push(who.name); }
  }
  if (predictionHits.length) log(s, `${predictionHits.join('、')} 準確預測了評級 ${fs.grade}（聲望 +2）`, 'good', ctx.now());
  sess.result = { signed, score: fs.score, grade: fs.grade, caps: fs.caps, commission, summary, predictionHits, epilogue: epilogueFor(c, st.quality, st.events) };
  sess.step = 'result';
  p.sessionLogs = [...(p.sessionLogs ?? []), buildSessionLog(s, c, sess, pe, st.events, fs, signed)];
  // 任務統計與合規連擊：連續 3 場以上合規 100，每場額外聲望 +2
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

/** 專屬結局：原型五位用手寫文案；其餘客戶由壓力事件組成通用文案 */
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

/** 弱點標籤：保存到培訓紀錄，供個人化回饋與講師統計 */
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
  if (sess.m.compliance < 100) tags.push('non_compliant');
  if (reply.quality !== 'good') tags.push('objection_weak');
  if (events.some(e => e.result === 'broken')) tags.push('stress_broken');
  if (!signed) tags.push('not_signed');
  return {
    clientId: c.id, clientName: c.name, job: c.job, round: s.round, grade: fs.grade, score: fs.score, signed,
    referral: sess.referral, hintUsed: !!sess.hintUsed,
    clues: { found: realFound, decoy: decoySeen },
    questions: sess.asked.filter(a => a.qid !== 'free').map(a => ({ qid: String(a.qid), text: a.question, key: a.key })),
    freeQuestion: free ? { text: free.question, note: free.note ?? '' } : null,
    plan: { alloc: sess.plan!.alloc, cards: sess.plan!.cards, quality: pe.quality, notes: pe.notes },
    objection: { mode: sess.objectionMode ?? 'choice', text: reply.text, quality: reply.quality, title: reply.title },
    stress: events.map(e => ({ title: e.ev.title, result: e.result })),
    tags,
  };
}

/** 終局大事件：最後一回合開始時，全體顧問的客戶同時面對市場重挫 */
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

/** 旁觀者預測評級（別人的面談進行中，每場一次） */
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

/** 已涵蓋的標準題：直接問過的，加上自由提問命中的 */
function coveredQuestions(sess: SessionState): Set<string> {
  return new Set<string>([...sess.asked.filter(a => a.qid !== 'free').map(a => a.qid), ...sess.freeHits]);
}

function interviewReady(sess: SessionState) {
  return coveredQuestions(sess).size >= STANDARD_ASKS;
}

/** 套用玩家動作。回傳錯誤訊息或 null。 */
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
    const roll = 1 + Math.floor(ctx.rng() * 6);
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
      if (sess.freeLeft <= 0) return '自由提問次數已用完';
      const text = (a.text || '').trim().slice(0, 120);
      if (text.length < 2) return '請輸入問題';
      sess.freeLeft--;
      const r = await ctx.ai.freeQuestion(c, text, sess.asked);
      apply(sess.m, { trust: r.trust, insight: r.insight, compliance: r.compliance });
      sess.asked.push({ qid: 'free', question: text, answer: r.answer, key: r.key, note: r.note });
      // 命中尚未涵蓋的標準題才計入，避免同一題的標準答案再出現一次
      if (r.matched && !coveredQuestions(sess).has(r.matched)) sess.freeHits.push(r.matched);
      if (r.compliance < 0) decide(p, s, c.name, '需求訪談', 'bad', '提問出現不當說法', r.note || '提問時避免保證或恐嚇式用語。');
      return null;
    }
    case 'to_plan': {
      if (sess.step !== 'discover') return '訪談已結束';
      if (!interviewReady(sess)) return `請先完成 ${STANDARD_ASKS} 個訪談問題`;
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
      const err = validPlan(alloc, cards, c);
      if (err) return err;
      const pe = evaluatePlan(c, alloc, cards);
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
      decide(p, s, c.name, '異議處理', opt.quality, opt.title, opt.body);
      finishSession(s, p, sess, ctx);
      return null;
    }
    case 'objection_free': {
      if (sess.step !== 'objection') return '現在不是異議處理階段';
      const text = (a.text || '').trim().slice(0, 200);
      if (text.length < 4) return '請輸入你的回應';
      sess.aiBusy = true;
      const g = await ctx.ai.gradeObjection(c, text);
      sess.aiBusy = false;
      apply(sess.m, { trust: g.trust, fit: g.fit, risk: g.risk, compliance: g.compliance });
      sess.objectionReply = { text, title: g.title, body: g.body, quality: g.quality };
      sess.objectionMode = 'free';
      decide(p, s, c.name, '異議處理', g.quality, g.title, g.body);
      finishSession(s, p, sess, ctx);
      return null;
    }
    case 'hint': {
      if (sess.step === 'result') return '面談已結束';
      if (sess.hintUsed) return '這場面談已經用過教練提示';
      sess.hintUsed = true;
      p.reputation = clamp(p.reputation - 2);
      sess.hint = await ctx.ai.hint(c, sess);
      log(s, `${p.name} 向教練求助（聲望 -2）`, 'info', ctx.now());
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
  const score = Math.round(0.5 * skillScore + 0.25 * service + 0.15 * p.reputation + 0.1 * Math.min(100, p.commission));
  let grade = score >= 85 ? 'S' : score >= 72 ? 'A' : score >= 60 ? 'B' : 'C';
  const caps: string[] = [];
  const order = ['C', 'B', 'A', 'S'];
  const cap = (g: string, why: string) => { if (order.indexOf(grade) > order.indexOf(g)) grade = g; caps.push(why); };
  if (!p.sessions) cap('C', '沒有完成任何客戶面談');
  if (p.sessions && skill.compliance < 70) cap('B', '平均合規表達低於 70');
  if (p.book.some(b => b.mis)) cap('A', '客戶簿中有不適合的銷售');
  return {
    playerId: p.id, name: p.name, isBot: p.isBot, score, grade, caps, skill, service,
    reputation: p.reputation, commission: p.commission, clients: p.book.length,
  };
}

function endGame(s: GameState, ctx: Ctx) {
  s.phase = 'ended'; s.turnStage = 'done';
  s.final = s.players.map(p => ({ ...scorePlayer(p), coach: fallbackTip(p) })).sort((x, y) => y.score - x.score);
  s.awards = computeAwards(s, p => scorePlayer(p).score);
  log(s, `遊戲結束！最佳顧問：${s.final[0].name}（${s.final[0].grade}）`, 'good', ctx.now());
}

/** 結束後以 AI 產生個人化教練回饋（失敗時保留規則版） */
export async function enrichCoach(s: GameState, aiFor: (p: PlayerState) => AIService) {
  if (!s.final) return;
  await Promise.all(s.final.map(async row => {
    const p = playerById(s, row.playerId);
    if (!p || p.isBot) return;
    const text = await aiFor(p).debrief(p, row).catch(() => null);
    if (text) row.coach = text;
  }));
}

/** 傳給客戶端的公開狀態：隱藏客戶答案、理想配置、題庫答案 */
/** viewerId：為該連線個人化的欄位（目前只有自己的預測） */
export function publicView(s: GameState, viewerId: string | null = null) {
  const sess = s.session;
  const c = sess ? s.clients[sess.clientId] : null;
  return {
    code: s.code, phase: s.phase, hostId: s.hostId, settings: s.settings,
    players: s.players.map(p => ({
      id: p.id, name: p.name, isBot: p.isBot, botLevel: p.botLevel, connected: p.connected, loggedIn: !!p.accountId, complianceStreak: p.complianceStreak ?? 0,
      pos: p.pos, reputation: p.reputation, commission: p.commission, sessions: p.sessions,
      book: p.book.map(b => ({ clientId: b.clientId, name: b.name, satisfaction: b.satisfaction, alloc: b.alloc, cards: b.cards, mis: b.mis })),
      decisions: p.decisions.slice(-12),
      quizCorrect: p.quizCorrect, quizTotal: p.quizTotal,
    })),
    turn: s.turn, round: s.round, turnStage: s.turnStage, lastRoll: s.lastRoll,
    deckLeft: s.deck.length,
    session: sess && c ? {
      playerId: sess.playerId, referral: sess.referral, step: sess.step, asked: sess.asked, freeLeft: sess.freeLeft,
      metrics: sess.m, aiBusy: !!sess.aiBusy,
      // 熱點座標對真線索與干擾物都提供，不洩漏真假
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
    final: s.final,
    announcement: s.announcement ?? null,
    version: s.version,
  };
}
