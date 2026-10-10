import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BOARD, CLIENTS } from '../src/game/data.ts';
import { evaluatePlan, runStress, TOTAL_COINS } from '../src/game/engine.ts';
import { addPlayer, applyAction, createGame, endGame, enrichCoach, fallbackTip, publicView, scorePlayer, startGame, type Ctx } from '../src/game/game.ts';
import { botAction } from '../src/game/bots.ts';
import { RuleAI, ruleGrade, buildGeneratedClient, MeteredAI, MockAI, extractJson, FallbackRawAI, makeAI, detectProvider, partialJsonStringDone, type AIService, type RawAI } from '../src/ai.ts';
import { buildProfile } from '../src/game/profile.ts';
import { predict } from '../src/game/game.ts';
import { calculateClaim, formatWan } from '../src/game/finance.ts';
import type { Alloc, CardId, GameState, PlayerState } from '../src/game/types.ts';

function seeded(seed: number) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const ctxFor = (seed: number): Ctx => ({ ai: new RuleAI(), rng: seeded(seed), now: () => 0 });

test('客戶名冊至少 18 位，且 id 不重複', () => {
  assert.ok(CLIENTS.length >= 18, `only ${CLIENTS.length}`);
  assert.equal(new Set(CLIENTS.map(c => c.id)).size, CLIENTS.length);
  for (const c of CLIENTS) {
    assert.ok(c.keyQuestions.length >= 2, c.id);
    assert.equal(c.objection.options.length, 4, c.id);
    assert.equal(c.stress.length, 3, c.id);
    for (const ev of c.stress) assert.ok(ev.need > 0, `${c.id} ${ev.title} need`);
  }
});

test('每位客戶：資深電腦的配置判定為 good 並通過壓力測試', () => {
  for (const c of CLIENTS) {
    const g = createGame('T');
    addPlayer(g, { id: 'b', name: 'bot', isBot: true, botLevel: 'pro' });
    startGame(g, ctxFor(1));
    g.session = { playerId: 'b', clientId: c.id, referral: false, step: 'plan', asked: [], freeLeft: 0, freeHits: [], clues: [], observed: [], m: { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 }, objectionOrder: [0, 1, 2, 3], predictions: {} };
    g.turnStage = 'session';
    const a = botAction(g, seeded(2));
    assert.ok(a && a.type === 'plan');
    const pe = evaluatePlan(c, a.alloc, a.cards);
    assert.equal(pe.quality, 'good', `${c.id}: ${pe.notes.join(' ')}`);
    const st = runStress(c, a.alloc, a.cards);
    assert.equal(st.quality, 'strong', `${c.id}: ${st.events.map(e => `${e.ev.title}=${e.result}(${e.defense}/${e.ev.need})`).join(', ')}`);
  }
});

test('隨機配置大多無法完整通過壓力測試', () => {
  const rng = seeded(7);
  let strong = 0, n = 0;
  const cardIds: CardId[] = ['medical', 'income', 'accident', 'tools', 'legacy', 'care'];
  for (const c of CLIENTS) {
    for (let i = 0; i < 300; i++) {
      const cuts = [Math.floor(rng() * (TOTAL_COINS + 1)), Math.floor(rng() * (TOTAL_COINS + 1))].sort((x, y) => x - y);
      const alloc: Alloc = { cash: cuts[0], protect: cuts[1] - cuts[0], growth: TOTAL_COINS - cuts[1] };
      const cards = cardIds.slice().sort(() => rng() - 0.5).slice(0, 2 + Math.floor(rng() * 2));
      if (runStress(c, alloc, cards).quality === 'strong') strong++;
      n++;
    }
  }
  assert.ok(strong / n < 0.35, `random strong rate ${(strong / n * 100).toFixed(1)}%`);
});

async function playOut(g: GameState, seed: number) {
  const ctx = ctxFor(seed);
  let guard = 0;
  while (g.phase === 'playing' && guard++ < 5000) {
    const a = botAction(g, ctx.rng);
    assert.ok(a, `bot stuck at ${g.turnStage}/${g.session?.step}`);
    const e = await applyAction(g, g.players[g.turn].id, a, ctx);
    assert.equal(e, null, `action ${JSON.stringify(a)} rejected: ${e}`);
  }
  assert.equal(g.phase, 'ended');
}

test('四位電腦顧問可以完整跑完一場，資深平均分數高於新人', async () => {
  let pro = 0, novice = 0;
  const GAMES = 40;
  for (let i = 0; i < GAMES; i++) {
    const g = createGame('SIM');
    addPlayer(g, { id: 'p1', name: '資深A', isBot: true, botLevel: 'pro' });
    addPlayer(g, { id: 'n1', name: '新人A', isBot: true, botLevel: 'novice' });
    addPlayer(g, { id: 'p2', name: '資深B', isBot: true, botLevel: 'pro' });
    addPlayer(g, { id: 'n2', name: '新人B', isBot: true, botLevel: 'novice' });
    startGame(g, ctxFor(100 + i));
    await playOut(g, 100 + i);
    assert.equal(g.final!.length, 4);
    for (const r of g.final!) (r.playerId.startsWith('p') ? (pro += r.score) : (novice += r.score));
    JSON.stringify(publicView(g));
  }
  pro /= GAMES * 2; novice /= GAMES * 2;
  assert.ok(pro > novice + 10, `pro ${pro.toFixed(1)} vs novice ${novice.toFixed(1)}`);
});

test('單人模式（一位玩家）也能跑完', async () => {
  const g = createGame('SOLO');
  addPlayer(g, { id: 'p1', name: '練習', isBot: true, botLevel: 'pro' });
  g.settings.rounds = 4;
  startGame(g, ctxFor(5));
  await playOut(g, 5);
  assert.equal(g.round, 5);
});

test('動作防護：非當前玩家、錯誤階段、無效配置都會被拒絕', async () => {
  const ctx = ctxFor(9);
  const g = createGame('G');
  addPlayer(g, { id: 'a', name: 'A' });
  addPlayer(g, { id: 'b', name: 'B' });
  assert.equal(addPlayer(g, { id: 'c', name: 'C' }), null);
  assert.equal(addPlayer(g, { id: 'd', name: 'D' }), null);
  assert.match(addPlayer(g, { id: 'e', name: 'E' })!, /已滿/);
  startGame(g, ctx);
  assert.match((await applyAction(g, 'b', { type: 'roll' }, ctx))!, /還沒輪到你/);
  assert.match((await applyAction(g, 'a', { type: 'continue' }, ctx))!, /面談|事件/);
  // Force enter interview
  g.session = { playerId: 'a', clientId: CLIENTS[0].id, referral: false, step: 'discover', asked: [], freeLeft: 1, freeHits: [], clues: [], observed: [], m: { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 }, objectionOrder: [0, 1, 2, 3], predictions: {} };
  g.turnStage = 'session';
  assert.match((await applyAction(g, 'a', { type: 'to_plan' }, ctx))!, /3 個/);
  assert.equal(await applyAction(g, 'a', { type: 'ask', qid: 'income' }, ctx), null);
  assert.match((await applyAction(g, 'a', { type: 'ask', qid: 'income' }, ctx))!, /問過/);
  assert.equal(await applyAction(g, 'a', { type: 'ask_free', text: '你最不想犧牲的目標是什麼？' }, ctx), null);
  assert.match((await applyAction(g, 'a', { type: 'ask_free', text: '再問一題' }, ctx))!, /用完/);
  await applyAction(g, 'a', { type: 'ask', qid: 'goal' }, ctx);
  await applyAction(g, 'a', { type: 'ask', qid: 'coverage' }, ctx);
  assert.match((await applyAction(g, 'a', { type: 'ask', qid: 'risk' }, ctx))!, /最多/);
  assert.equal(await applyAction(g, 'a', { type: 'to_plan' }, ctx), null);
  assert.match((await applyAction(g, 'a', { type: 'plan', alloc: { cash: 5, protect: 5, growth: 5 }, cards: ['income', 'medical'] }, ctx))!, /總和/);
  assert.match((await applyAction(g, 'a', { type: 'plan', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income'] }, ctx))!, /2–3/);
  assert.equal(await applyAction(g, 'a', { type: 'plan', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income', 'medical'] }, ctx), null);
  assert.equal(await applyAction(g, 'a', { type: 'objection_free', text: '投資照樣保留，保障是讓工作室的目標不必在低點被犧牲。' }, ctx), null);
  assert.equal(g.session!.step, 'result');
  assert.equal(await applyAction(g, 'a', { type: 'continue' }, ctx), null);
  assert.equal(g.turn, 1);
  // Public state does not reveal answers or ideal allocation
  const view = JSON.stringify(publicView(g));
  assert.ok(!view.includes('keyQuestions') && !view.includes('"ideal"'));
});

test('規則版 AI：保證／恐嚇字眼一律判為不合規', () => {
  const c = CLIENTS[0];
  assert.equal(ruleGrade(c, '照我說的做，保證你一定賺').quality, 'bad');
  assert.ok(ruleGrade(c, '照我說的做，保證你一定賺').compliance <= -15);
  assert.equal(ruleGrade(c, '我理解你的顧慮，保障是讓工作室的目標不必在低點被犧牲，投資照樣保留。').quality, 'good');
});

test('AI 生成客戶：不合理的理想區間會被拒絕，合理者會被校準', () => {
  const base = {
    name: '測試', short: '測', age: 30, gender: '女性', job: '花藝師', tag: '測試型', goal: '開花店', amount: 'NT$ 1', incomeInfo: 'x', family: 'x', intro: 'x', quote: 'x',
    facts: [{ title: 'a', detail: 'b', fact: 'c' }, { title: 'a', detail: 'b', fact: 'c' }, { title: 'a', detail: 'b', fact: 'c' }],
    answers: { income: { text: 'a', trust: 8, insight: 12, key: 'k' }, goal: { text: 'a', trust: 8, insight: 12, key: 'k' }, coverage: { text: 'a', trust: 8, insight: 12, key: 'k' }, risk: { text: 'a', trust: 8, insight: 12, key: 'k' }, premium: { text: 'a', trust: -8, insight: 1 } },
    keyQuestions: ['income', 'goal'] as ('income' | 'goal')[],
    ideal: { cash: [3, 4] as [number, number], protect: [3, 4] as [number, number], growth: [2, 4] as [number, number] },
    cards: { medical: 2, income: 3, accident: 1, tools: 2, legacy: -2, care: -1 },
    objection: { text: 'x', good: 'g', ok: 'o', fear: 'f', promise: 'p' },
    stress: [
      { kind: 'income' as const, tag: 't', title: 't', body: 'b', cards: ['income' as const], held: 'h', hit: 'x' },
      { kind: 'cash' as const, tag: 't', title: 't', body: 'b', cards: ['medical' as const], held: 'h', hit: 'x' },
      { kind: 'market' as const, tag: 't', title: 't', body: 'b', cards: [], held: 'h', hit: 'x' },
    ],
  };
  const ok = buildGeneratedClient(base, 1)!;
  assert.ok(ok && ok.stress.every(s => s.need > 0));
  assert.equal(buildGeneratedClient({ ...base, ideal: { cash: [6, 7], protect: [4, 5], growth: [2, 3] } }, 2), null);
  assert.equal(buildGeneratedClient({ ...base, cards: { ...base.cards, income: 2 } }, 3), null);
});

test('沒有完成面談的玩家最高 C', () => {
  const g = createGame('X');
  addPlayer(g, { id: 'a', name: 'A' });
  assert.equal(scorePlayer(g.players[0]).grade, 'C');
});

test('合規測驗：選項會打亂，正確位置不固定，作答前不洩漏答案與對照表', async () => {
  const positions = new Set<number>();
  for (let seed = 1; seed <= 30; seed++) {
    const ctx = ctxFor(seed);
    const g = createGame('Q');
    addPlayer(g, { id: 'a', name: 'A' });
    startGame(g, ctx);
    g.players[0].pos = 1; // Rolling 1 lands on tile 2 (compliance training)
    const rest = seeded(seed * 7);
    const fixed = [0, 0.9]; // Dice roll 1, compliance training tile selects quiz (>= 0.5)
    ctx.rng = () => (fixed.length ? fixed.shift()! : rest());
    await applyAction(g, 'a', { type: 'roll' }, ctx);
    assert.equal(g.event?.kind, 'quiz');
    const view = publicView(g) as { event: { quiz: Record<string, unknown> } };
    assert.ok(!('order' in view.event.quiz) && view.event.quiz.answer === undefined);
    const quiz = g.event!.quiz!;
    const right = quiz.order.indexOf(1);
    positions.add(right);
    ctx.rng = seeded(seed);
    assert.equal(await applyAction(g, 'a', { type: 'answer_quiz', index: right }, ctx), null);
    assert.equal(g.players[0].quizCorrect, 1);
    assert.equal(g.event!.quiz!.answer, right);
  }
  assert.ok(positions.size >= 3, `answer positions ${[...positions]}`);
});

test('教練提示：每場面談限一次、不扣聲望、結果階段不可用', async () => {
  const ctx = ctxFor(3);
  const g = createGame('H');
  addPlayer(g, { id: 'a', name: 'A' });
  startGame(g, ctx);
  g.session = { playerId: 'a', clientId: CLIENTS[0].id, referral: false, step: 'discover', asked: [], freeLeft: 1, freeHits: [], clues: [], observed: [], m: { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 }, objectionOrder: [0, 1, 2, 3], predictions: {} };
  g.turnStage = 'session';
  const rep = g.players[0].reputation;
  assert.equal(await applyAction(g, 'a', { type: 'hint' }, ctx), null);
  assert.equal(g.players[0].reputation, rep);
  assert.ok((g.session!.hint ?? '').length > 5);
  assert.match((await applyAction(g, 'a', { type: 'hint' }, ctx))!, /用過/);
  const view = publicView(g) as { session: { hint: string; hintUsed: boolean } };
  assert.ok(view.session.hintUsed && view.session.hint);
  g.session!.step = 'result';
  g.session!.hintUsed = false;
  assert.match((await applyAction(g, 'a', { type: 'hint' }, ctx))!, /結束/);
});

test('AI 計量：扣額度、失敗退還、用完或訪客改用規則版', async () => {
  const c = CLIENTS[0];
  let used = 0; const limit = 2; let refunds = 0;
  const meter = { consume: async () => (used < limit ? (used++, true) : false), refund: async () => { used--; refunds++; } };
  const ai = new MeteredAI(new MockAI(), meter);
  assert.match((await ai.marketNews({ id: 'x', tag: '', title: 'T', body: '', absorb: {}, need: 1, lesson: '' })) ?? "", /模擬/);
  assert.equal(used, 1);
  // Provider failure (returns null) -> refund and fall back to rule-based
  const failing = { ...new MockAI(), provider: 'fail', hint: async () => null } as unknown as RawAI;
  const ai2 = new MeteredAI(failing, meter);
  const h = await ai2.hint(c, { step: 'objection', asked: [], freeHits: [], observed: [] } as never);
  assert.ok(h.length > 5 && refunds === 1 && used === 1);
  await ai.coachTip({} as never); // used → 2
  assert.equal(used, 2);
  assert.equal(await ai.marketNews({ id: 'x', tag: '', title: 'T', body: '', absorb: {}, need: 1, lesson: '' }), null); // Exhausted -> rule-based
  assert.equal(used, 2);
  const guest = new MeteredAI(new MockAI(), null);
  assert.equal(guest.enabled, false);
  assert.equal(await guest.marketNews({ id: 'x', tag: '', title: 'T', body: '', absorb: {}, need: 1, lesson: '' }), null);
});

test('extractJson：可從程式碼區塊、think 標記與雜訊中取出 JSON', () => {
  assert.deepEqual(extractJson('<think>嗯</think>好的```json\n{"a":1}\n```'), { a: 1 });
  assert.deepEqual(extractJson({ b: 2 }), { b: 2 });
  assert.equal(extractJson('沒有 JSON'), null);
});

test('FallbackRawAI：支援 NVIDIA NIM 優先並在失敗/未配置時切換至備援供應者', async () => {
  let primaryCalls = 0;
  let secondaryCalls = 0;
  const primary: RawAI = Object.assign(new MockAI(), {
    provider: 'primary-nim',
    marketNews: async () => {
      primaryCalls++;
      return null; // Simulate connection failure or returning empty value
    },
    coachTip: async () => {
      primaryCalls++;
      return 'NVIDIA 建議';
    },
  });
  const secondary: RawAI = Object.assign(new MockAI(), {
    provider: 'secondary-workers',
    marketNews: async () => {
      secondaryCalls++;
      return '備援 Workers 快訊';
    },
    coachTip: async () => {
      secondaryCalls++;
      return '備援建議';
    },
  });

  const chained = new FallbackRawAI([primary, secondary]);
  assert.equal(chained.provider, 'primary-nim -> secondary-workers');

  // 1. When primary succeeds, secondary is not called
  const tip = await chained.coachTip({} as never);
  assert.equal(tip, 'NVIDIA 建議');
  assert.equal(primaryCalls, 1);
  assert.equal(secondaryCalls, 0);

  // 2. When primary fails (returns null), fall back to secondary
  const news = await chained.marketNews({ id: '1', title: 'T' } as never);
  assert.equal(news, '備援 Workers 快訊');
  assert.equal(primaryCalls, 2);
  assert.equal(secondaryCalls, 1);

  // 3. Combined behavior of makeAI and detectProvider
  const envBoth = { NVIDIA_API_KEY: 'nvapi-test', AI: {} as never };
  assert.equal(detectProvider(envBoth), 'nvidia-nim (fallback: nvidia-nim-backup -> workers-ai)');
  const aiBoth = makeAI(envBoth);
  assert.ok(aiBoth instanceof FallbackRawAI);
  assert.equal(aiBoth.provider, 'nvidia-nim -> nvidia-nim-backup -> workers-ai');
  // Disable NIM backup model
  assert.equal(makeAI({ ...envBoth, NVIDIA_FALLBACK_MODEL: 'none' })!.provider, 'nvidia-nim -> workers-ai');

  const envWorkersOnly = { AI: {} as never };
  assert.equal(detectProvider(envWorkersOnly), 'workers-ai');
  const aiWorkers = makeAI(envWorkersOnly);
  assert.equal(aiWorkers?.provider, 'workers-ai');

  const envNone = {};
  assert.equal(detectProvider(envNone), 'rules');
  assert.equal(makeAI(envNone), null);
});

test('MeteredAI 容錯計量：走 unmetered（如 NVIDIA NIM）不扣次數，只有 fallback 到 metered 時才扣額度', async () => {
  let used = 0; const limit = 1;
  const meter = {
    consume: async () => (used < limit ? (used++, true) : false),
    refund: async () => { used--; },
  };

  const nim: RawAI = Object.assign(new MockAI(), {
    provider: 'nvidia-nim',
    unmetered: true,
    coachTip: async () => 'NIM 成功回答',
    hint: async () => null, // Intentionally fail
  });

  const workers: RawAI = Object.assign(new MockAI(), {
    provider: 'workers-ai',
    unmetered: false,
    coachTip: async () => 'Workers 備援回答',
    hint: async () => 'Workers 提示',
  });

  const chained = new FallbackRawAI([nim, workers]);
  const ai = new MeteredAI(chained, meter);

  // 1. NIM succeeds -> quota not deducted
  const tip1 = await ai.coachTip({} as never);
  assert.equal(tip1, 'NIM 成功回答');
  assert.equal(used, 0, '走 NVIDIA NIM 不應計入 AI 次數');

  // 2. NIM fails -> fallback to Workers AI -> deducts 1 on success
  const h1 = await ai.hint(CLIENTS[0], { step: 'objection', asked: [], freeHits: [], observed: [] } as never);
  assert.equal(h1, 'Workers 提示');
  assert.equal(used, 1, 'fallback 到 Workers AI 需計入 1 次額度');

  // 3. Workers AI quota exhausted (used=1, limit=1), but NIM continues serving unblocked
  const tip2 = await ai.coachTip({} as never);
  assert.equal(tip2, 'NIM 成功回答');
  assert.equal(used, 1);

  // 4. Quota exhausted and NIM fails -> Workers quota blocked -> fallback to rule-based
  const h2 = await ai.hint(CLIENTS[0], { step: 'objection', asked: [], freeHits: [], observed: [] } as never);
  assert.ok(h2.length > 0 && h2 !== 'Workers 提示', '應退回規則版提示');
  assert.equal(used, 1);
});

test('旁觀者預測、專屬結局、面談紀錄標籤、終局大事件', async () => {
  const ctx = ctxFor(11);
  const g = createGame('P');
  addPlayer(g, { id: 'a', name: 'A' });
  addPlayer(g, { id: 'b', name: 'B' });
  g.settings.rounds = 3;
  startGame(g, ctx);
  const yuqing = CLIENTS.find(c => c.id === 'yuqing')!;
  g.session = { playerId: 'a', clientId: 'yuqing', referral: false, step: 'discover', asked: [], freeLeft: 1, freeHits: [], clues: [], observed: [], m: { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 }, objectionOrder: [0, 1, 2, 3], predictions: {} };
  g.turnStage = 'session';
  assert.match(predict(g, 'a', 'S')!, /自己/);
  assert.equal(predict(g, 'b', 'C'), null);
  assert.match(predict(g, 'b', 'S')!, /預測過/);
  const view = publicView(g, 'b') as { session: { predictions: { count: number; mine: string } } };
  assert.deepEqual(view.session.predictions, { count: 1, mine: 'C' });
  await applyAction(g, 'a', { type: 'ask', qid: 'premium' }, ctx);
  await applyAction(g, 'a', { type: 'ask', qid: 'risk' }, ctx);
  await applyAction(g, 'a', { type: 'ask', qid: 'coverage' }, ctx);
  await applyAction(g, 'a', { type: 'to_plan' }, ctx);
  await applyAction(g, 'a', { type: 'plan', alloc: { cash: 1, protect: 1, growth: 8 }, cards: ['legacy', 'care'] }, ctx);
  const fear = g.session!.objectionOrder.findIndex(i => yuqing.objection.options[i].quality === 'bad');
  await applyAction(g, 'a', { type: 'objection', index: fear }, ctx);
  const r = g.session!.result!;
  assert.equal(r.grade, 'C');
  assert.deepEqual(r.predictionHits, ['B']);
  assert.ok(r.epilogue.headline.includes('<br>') && r.epilogue.noPlan.length === 3);
  const log = g.players[0].sessionLogs![0];
  for (const t of ['early_premium', 'missed_key', 'over_cards', 'low_cash', 'growth_heavy', 'non_compliant', 'stress_broken']) assert.ok(log.tags.includes(t), t);
  // Advance to final round -> trigger end-game announcement
  g.players[0].book.push({ clientId: 'yuqing', name: '林雨晴', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income'], satisfaction: 70, planQuality: 'good', compliance: 100, stressUsed: 0, signedRound: 1, mis: false });
  g.round = 2; g.session = null; g.turnStage = 'event'; g.event = { kind: 'info', playerId: 'b', title: '', body: '', lines: [] }; g.turn = 1;
  await applyAction(g, 'b', { type: 'continue' }, ctx);
  assert.equal(g.round, 3);
  assert.ok(g.announcement && g.announcement.title.includes('終局'));
});

test('學習檔案：弱點排序、客戶圖鑑與徽章', () => {
  const s = (grade: string, tags: string[], clientId = 'yuqing', hintUsed = false) => ({ clientId, clientName: '', job: '', round: 1, grade, score: 90, signed: true, referral: false, hintUsed, clues: { found: 3, decoy: false }, questions: [], freeQuestion: null, plan: { alloc: { cash: 4, protect: 3, growth: 3 }, cards: [], quality: 'good' as const, notes: [] }, objection: { mode: 'choice' as const, text: '', quality: 'good' as const, title: '' }, stress: [], tags });
  const p = buildProfile([
    { ts: 2, score: 85, grade: 'A', data: { service: 90, sessions: [s('S', ['early_premium']), s('B', ['early_premium', 'over_cards'], 'boting')], quizCorrect: 3, quizTotal: 3 } },
    { ts: 1, score: 60, grade: 'B', data: { sessions: [s('C', ['non_compliant'], 'yuqing', true)] } },
  ]);
  assert.equal(p.games, 2);
  assert.equal(p.trend[0].ts, 1);
  assert.equal(p.mistakes[0].tag, 'early_premium');
  assert.equal(p.mistakes[0].count, 2);
  assert.equal(p.clients.find(c => c.id === 'yuqing')!.bestGrade, 'S');
  assert.equal(p.clients.find(c => c.id === 'yuqing')!.served, 2);
  const earned = Object.fromEntries(p.badges.map(b => [b.id, b.earned]));
  assert.ok(earned.first_s && earned.no_hint_s && earned.service_star && earned.growth && !earned.clean_3);
});

test('Google ID Token 驗證：簽章、aud、exp、nonce、email_verified', async () => {
  const { verifyGoogleIdToken } = await import('../src/google-jwt.ts');
  const kp = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
  const pub = { ...(await crypto.subtle.exportKey('jwk', kp.publicKey)), kid: 'k1', alg: 'RS256', use: 'sig' };
  const b64 = (o: unknown) => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
  const sign = async (claims: Record<string, unknown>, kid = 'k1') => {
    const h = b64({ alg: 'RS256', kid, typ: 'JWT' }), p = b64(claims);
    const sig = Buffer.from(await crypto.subtle.sign('RSASSA-PKCS1-v1_5', kp.privateKey, new TextEncoder().encode(`${h}.${p}`))).toString('base64url');
    return `${h}.${p}.${sig}`;
  };
  const keys = async () => [pub as JsonWebKey];
  const now = Date.now();
  const base = { iss: 'https://accounts.google.com', aud: 'cid', sub: '123', email: 'a@b.c', email_verified: true, exp: Math.floor(now / 1000) + 600, nonce: 'n1' };
  assert.equal((await verifyGoogleIdToken(await sign(base), 'cid', 'n1', keys, now))?.sub, '123');
  const good = await sign(base);
  const tampered = good.slice(0, good.lastIndexOf('.') + 1) + Buffer.from('x'.repeat(256)).toString('base64url');
  assert.equal(await verifyGoogleIdToken(tampered, 'cid', 'n1', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign(base), 'other', 'n1', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign({ ...base, exp: Math.floor(now / 1000) - 10 }), 'cid', 'n1', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign(base), 'cid', 'wrong', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign(base), 'cid', '', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign({ ...base, email_verified: false }), 'cid', 'n1', keys, now), null);
  assert.equal(await verifyGoogleIdToken(await sign(base, 'unknown'), 'cid', 'n1', keys, now), null);
  assert.equal((await verifyGoogleIdToken(await sign({ ...base, nonce: undefined }), 'cid', undefined, keys, now))?.sub, '123');
});

test('情境抉擇、保單健檢、季度任務、終局榮譽榜', async () => {
  const { DILEMMAS, reviewOutcome, QUESTS } = await import('../src/game/extras.ts');
  const ctx = ctxFor(21);
  const g = createGame('X2');
  addPlayer(g, { id: 'a', name: 'A' });
  startGame(g, ctx);
  assert.equal(g.quests!.length, 3);
  // Dilemma: picking good choice -> reputation +4, option quality not leaked
  const d = DILEMMAS[0];
  g.turnStage = 'event';
  g.event = { kind: 'dilemma', playerId: 'a', title: d.title, body: d.prompt, lines: [], dilemma: { id: d.id, title: d.title, prompt: d.prompt, choices: d.choices.map((c, i) => ({ id: `${'ABC'[i]}:${c.id}`, text: c.text })), picked: null, outcome: null } };
  const view = JSON.stringify(publicView(g));
  assert.ok(!view.includes('"quality"'));
  assert.match((await applyAction(g, 'a', { type: 'continue' }, ctx))!, /選擇/);
  const rep = g.players[0].reputation;
  assert.equal(await applyAction(g, 'a', { type: 'choose_dilemma', choice: 'A:A' }, ctx), null);
  assert.equal(g.players[0].reputation, rep + 4);
  assert.equal(g.event!.dilemma!.outcome!.tone, 'good');
  assert.match((await applyAction(g, 'a', { type: 'choose_dilemma', choice: 'B:B' }, ctx))!, /沒有待選擇/);
  // Policy review: fill correct gap, confirm already sufficient, add wrong card, skip contact
  const entry = { clientId: 'yuqing', name: '林雨晴', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income' as const], satisfaction: 70, planQuality: 'good' as const, compliance: 100, stressUsed: 0, signedRound: 1, mis: false };
  const cards = CLIENTS.find(c => c.id === 'yuqing')!.plan.cards;
  assert.equal(reviewOutcome(entry, 'accident', 'accident', cards).quality, 'good');
  assert.equal(reviewOutcome(entry, 'income', 'none', cards).quality, 'good');
  assert.equal(reviewOutcome(entry, 'accident', 'none', cards).quality, 'bad');
  assert.equal(reviewOutcome(entry, 'accident', 'legacy', cards).quality, 'bad'); // Yuqing's family responsibility is over-coverage
  assert.equal(reviewOutcome(entry, 'accident', 'skip', cards).sat, -10);
  // Review public state does not leak answer
  g.event = { kind: 'review', playerId: 'a', title: '', body: '', lines: [], review: { clientId: 'yuqing', clientName: '林雨晴', change: { title: 't', body: 'b' }, current: { alloc: entry.alloc, cards: entry.cards }, needCard: 'accident', picked: null, outcome: null } };
  g.players[0].book.push({ ...entry });
  assert.ok(!JSON.stringify(publicView(g)).includes('needCard'));
  assert.equal(await applyAction(g, 'a', { type: 'review', card: 'accident' }, ctx), null);
  assert.ok(g.players[0].book[0].cards.includes('accident') && g.players[0].book[0].reviewed);
  // Quest: completing stat target finishes quest and adds reputation
  g.quests = [{ id: 'quiz', title: '合規小尖兵', desc: '', reward: 4, progress: {} }];
  g.players[0].stats!.quizCorrect = 2;
  const before = g.players[0].reputation;
  assert.equal(await applyAction(g, 'a', { type: 'continue' }, ctx), null);
  assert.ok(g.quests[0].progress.a.done && g.players[0].reputation === before + 4);
  assert.ok(QUESTS.length >= 6);
});

test('完整對局含新玩法：電腦顧問能跑完並產生榮譽榜', async () => {
  for (let i = 0; i < 20; i++) {
    const g = createGame('AW');
    addPlayer(g, { id: 'p1', name: '資深', isBot: true, botLevel: 'pro' });
    addPlayer(g, { id: 'n1', name: '新人', isBot: true, botLevel: 'novice' });
    startGame(g, ctxFor(300 + i));
    await playOut(g, 300 + i);
    assert.ok(Array.isArray(g.awards));
  }
});

test('客戶版圖：簽約佔領格子、再次停格觸發保單健檢與轉介、解約清空格子、公開狀態包含 territory', async () => {
  const ctx = ctxFor(42);
  const g = createGame('TERR');
  addPlayer(g, { id: 'p1', name: '顧問A' });
  addPlayer(g, { id: 'p2', name: '顧問B' });
  startGame(g, ctx);

  assert.deepEqual(g.territory, {});
  const initialView = publicView(g) as { territory: Record<number, unknown> };
  assert.deepEqual(initialView.territory, {});

  // 1. p1 stands on tile 1 (client tile) and signs yuqing
  g.players[0].pos = 1;
  const yuqing = CLIENTS.find(c => c.id === 'yuqing')!;
  g.session = {
    playerId: 'p1', clientId: 'yuqing', referral: false, tileIndex: 1, step: 'plan',
    asked: [], freeLeft: 0, freeHits: [], clues: [], observed: [],
    m: { trust: 60, insight: 50, fit: 50, risk: 50, compliance: 100 },
    objectionOrder: [0, 1, 2, 3], predictions: {},
  };
  g.turnStage = 'session';
  await applyAction(g, 'p1', { type: 'plan', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income', 'medical'] }, ctx);
  const goodOpt = yuqing.objection.options.findIndex(o => o.quality === 'good');
  const optIdx = g.session!.objectionOrder.indexOf(goodOpt);
  await applyAction(g, 'p1', { type: 'objection', index: optIdx }, ctx);

  assert.equal(g.session!.result!.signed, true);
  // Tile 1 should now be recorded as territory
  assert.deepEqual(g.territory[1], { playerId: 'p1', clientId: 'yuqing', clientName: '林雨晴' });
  const view1 = publicView(g) as { territory: Record<number, unknown> };
  assert.deepEqual(view1.territory[1], { playerId: 'p1', clientId: 'yuqing', clientName: '林雨晴' });

  // Book entry tracks stress rehearsal results
  const entry = g.players[0].book[0];
  assert.equal(typeof entry.held, 'number');
  assert.equal(typeof entry.partial, 'number');
  assert.equal(typeof entry.broken, 'number');
  assert.equal((entry.held ?? 0) + (entry.partial ?? 0) + (entry.broken ?? 0), 3);

  await applyAction(g, 'p1', { type: 'continue' }, ctx);

  // 2. p1 lands on own territory tile (tile 1) -> triggers checkup event
  g.turn = 0;
  g.turnStage = 'roll';
  g.players[0].pos = 0; // rolling 1 lands on tile 1
  g.players[0].reputation = 50;
  entry.satisfaction = 70; // +5 will make it 75
  const origRep = g.players[0].reputation;

  // Mock rng so roll lands on 1, then checkup referral roll (rng >= 0.4 -> false)
  const rngSeq = [0.01, 0.9];
  const testCtx: Ctx = { ai: new RuleAI(), rng: () => rngSeq.shift() ?? 0.5, now: () => 0 };
  await applyAction(g, 'p1', { type: 'roll' }, testCtx);

  assert.equal(g.turnStage, 'event');
  assert.equal(g.event?.kind, 'checkup');
  assert.equal(g.event?.title, '保單健檢｜林雨晴');
  assert.equal(g.players[0].reputation, origRep + 2);
  assert.equal(entry.satisfaction, 75);
  assert.equal(g.event?.checkup?.referral, false);

  // Dismiss checkup event without referral
  await applyAction(g, 'p1', { type: 'continue' }, testCtx);
  assert.equal(g.turnStage, 'roll');

  // 3. Landing on own territory with satisfaction >= 75 and referral rng < 0.4 -> triggers referral session on continue
  g.turn = 0;
  g.turnStage = 'roll';
  g.players[0].pos = 0;
  const rngSeq2 = [0.01, 0.2]; // roll 1, referral roll 0.2 < 0.4
  const testCtx2: Ctx = { ai: new RuleAI(), rng: () => rngSeq2.shift() ?? 0.5, now: () => 0 };
  await applyAction(g, 'p1', { type: 'roll' }, testCtx2);

  assert.equal(g.event?.kind, 'checkup');
  assert.equal(g.event?.checkup?.referral, true);
  await applyAction(g, 'p1', { type: 'continue' }, testCtx2);
  assert.equal(g.turnStage, 'session');
  assert.equal(g.session?.referral, true);

  // 4. Opponent p2 lands on p1's territory -> normal client interview, no penalty
  g.session = null as GameState['session'];
  g.turnStage = 'roll';
  g.turn = 1;
  g.players[1].pos = 0;
  const p2Rep = g.players[1].reputation;
  const rngSeq3 = [0.01];
  const testCtx3: Ctx = { ai: new RuleAI(), rng: () => rngSeq3.shift() ?? 0.5, now: () => 0 };
  await applyAction(g, 'p2', { type: 'roll' }, testCtx3);
  assert.equal(g.turnStage, 'session');
  assert.equal(g.session?.playerId, 'p2');
  assert.equal(g.session?.referral, false);
  assert.equal(g.players[1].reputation, p2Rep);

  // 5. If client leaves book, clearing tile on land
  g.players[0].book = [];
  g.session = null as GameState['session'];
  g.turnStage = 'roll';
  g.turn = 0;
  g.players[0].pos = 0;
  const rngSeq4 = [0.01];
  const testCtx4: Ctx = { ai: new RuleAI(), rng: () => rngSeq4.shift() ?? 0.5, now: () => 0 };
  await applyAction(g, 'p1', { type: 'roll' }, testCtx4);
  assert.equal(g.territory[1], undefined);
  assert.equal(g.turnStage, 'session');
  assert.equal(g.session?.referral, false);
});

test('理賠服務時刻：人生事件擊中已簽約客戶，產生理賠數據結構與萬單位格式化說明', async () => {
  const ctx = ctxFor(55);
  const g = createGame('CLAIM');
  addPlayer(g, { id: 'p1', name: '顧問A' });
  startGame(g, ctx);

  const yuqing = CLIENTS.find(c => c.id === 'yuqing')!;
  g.players[0].book.push({
    clientId: 'yuqing', name: '林雨晴', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income', 'medical'],
    satisfaction: 70, planQuality: 'good', compliance: 100, stressUsed: 0, signedRound: 1, mis: false,
    held: 2, partial: 1, broken: 0,
  });

  // Tile 4 rolling 1 lands on tile 5 (life event)
  g.players[0].pos = 4;
  g.turnStage = 'roll';
  // Mock rng to roll 1, and ensure pickLifeChange does not trigger (rng >= 0.5)
  const rngSeq = [0.01, 0.9, 0];
  const testCtx: Ctx = { ai: new RuleAI(), rng: () => rngSeq.shift() ?? 0.5, now: () => 0 };
  await applyAction(g, 'p1', { type: 'roll' }, testCtx);

  assert.equal(g.turnStage, 'event');
  assert.equal(g.event?.kind, 'life');
  assert.equal(g.event?.title, '理賠服務｜林雨晴');
  assert.ok(g.event?.claim, 'claim data exists');
  const claim = g.event!.claim!;
  assert.equal(claim.clientId, 'yuqing');
  assert.equal(claim.clientName, '林雨晴');
  assert.equal(claim.event, yuqing.stress[0].title);
  assert.ok(['held', 'partial', 'broken'].includes(claim.result));
  assert.ok(claim.loss > 0);
  assert.equal(claim.loss, claim.covered + claim.outOfPocket);

  // Check lines
  const firstLine = g.event!.lines[0].text;
  assert.ok(firstLine.includes('萬'), `line should mention 萬: ${firstLine}`);
  if (claim.result === 'held') {
    assert.ok(firstLine.startsWith('理賠') && firstLine.includes('已撥付') && firstLine.includes('還好當初有聽你的'));
  } else if (claim.result === 'partial') {
    assert.ok(firstLine.startsWith('理賠') && firstLine.includes('仍需自付'));
  } else {
    assert.ok(firstLine.startsWith('保障缺口：') && firstLine.includes('自付'));
  }

  // Check BookEntry stress counters incremented
  const book = g.players[0].book[0];
  const totalStress = (book.held ?? 0) + (book.partial ?? 0) + (book.broken ?? 0);
  assert.equal(totalStress, 4); // was 3, +1 from life event hit

  // Check publicView exposes claim
  const view = publicView(g) as { event: { claim: Record<string, unknown> } };
  assert.ok(view.event.claim);
  assert.equal(view.event.claim.clientName, '林雨晴');
});

test('終局客戶守護分：計算公式、紅燈案件零分、加權調整與用心顧問評分優勢', () => {
  // Test formatWan helper
  assert.equal(formatWan(87500), '8.8');
  assert.equal(formatWan(50000), '5.0');
  assert.equal(formatWan(124000), '12');
  assert.equal(formatWan(150000), '15');

  // 1. Direct comparison: careful advisor (fewer clients, high protection) vs sloppy advisor (more clients, low protection, high commission)
  const careful: PlayerState = {
    id: 'c', name: '用心顧問', isBot: false, botLevel: null, connected: true, disconnectedAt: null,
    pos: 0, reputation: 60, commission: 25, sessions: 1,
    skillSum: { trust: 85, insight: 85, fit: 85, risk: 85, compliance: 85 },
    book: [
      { clientId: '1', name: '客戶1', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income'], satisfaction: 85, planQuality: 'good', compliance: 90, stressUsed: 0, signedRound: 1, mis: false, violation: false, held: 3, partial: 0, broken: 0 },
    ],
    decisions: [], quizCorrect: 0, quizTotal: 0,
  };

  const sloppy: PlayerState = {
    id: 's', name: '隨意銷售', isBot: false, botLevel: null, connected: true, disconnectedAt: null,
    pos: 0, reputation: 50, commission: 80, sessions: 4,
    skillSum: { trust: 240, insight: 240, fit: 240, risk: 240, compliance: 240 }, // 60 avg
    book: [
      { clientId: '1', name: '客戶1', alloc: { cash: 1, protect: 1, growth: 8 }, cards: [], satisfaction: 45, planQuality: 'bad', compliance: 60, stressUsed: 0, signedRound: 1, mis: true, violation: false, held: 0, partial: 1, broken: 2 },
      { clientId: '2', name: '客戶2', alloc: { cash: 1, protect: 1, growth: 8 }, cards: [], satisfaction: 40, planQuality: 'bad', compliance: 60, stressUsed: 0, signedRound: 1, mis: true, violation: false, held: 0, partial: 0, broken: 3 },
      { clientId: '3', name: '客戶3', alloc: { cash: 1, protect: 1, growth: 8 }, cards: [], satisfaction: 42, planQuality: 'bad', compliance: 60, stressUsed: 0, signedRound: 1, mis: true, violation: false, held: 0, partial: 1, broken: 2 },
      { clientId: '4', name: '客戶4', alloc: { cash: 1, protect: 1, growth: 8 }, cards: [], satisfaction: 38, planQuality: 'bad', compliance: 60, stressUsed: 0, signedRound: 1, mis: true, violation: false, held: 0, partial: 0, broken: 3 },
    ],
    decisions: [], quizCorrect: 0, quizTotal: 0,
  };

  const scoredCareful = scorePlayer(careful);
  const scoredSloppy = scorePlayer(sloppy);

  assert.equal(scoredCareful.protection, 100);
  assert.equal(scoredCareful.service, 85);
  // careful score: 0.5*85 + 0.15*85 + 0.10*100 + 0.15*60 + 0.10*25 = 42.5 + 12.75 + 10 + 9 + 2.5 = 76.75 -> 77
  assert.equal(scoredCareful.score, 77);

  // sloppy protection: avg of (0.5/3*100, 0, 0.5/3*100, 0) = (16.67 + 0 + 16.67 + 0) / 4 = 8.33 -> 8
  assert.equal(scoredSloppy.protection, 8);
  assert.ok(scoredCareful.score > scoredSloppy.score + 20, `Careful (${scoredCareful.score}) should strongly outrank Sloppy (${scoredSloppy.score})`);

  // 2. Violation cases count as 0 for protection
  const violated: PlayerState = {
    ...careful,
    book: [
      { clientId: '1', name: '客戶1', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income'], satisfaction: 85, planQuality: 'good', compliance: 90, stressUsed: 0, signedRound: 1, mis: false, violation: true, held: 3, partial: 0, broken: 0 },
    ],
  };
  assert.equal(scorePlayer(violated).protection, 0);
});

test('玩家頭像 URL 可透過 addPlayer 傳入並在 publicView 呈現', () => {
  const g = createGame('AVATAR');
  addPlayer(g, { id: 'u1', name: '真人', avatar: 'https://example.com/photo.jpg' });
  addPlayer(g, { id: 'b1', name: '電腦', isBot: true, avatar: 'https://example.com/bot.jpg' });
  const view = publicView(g);
  assert.equal(view.players[0].avatar, 'https://example.com/photo.jpg');
  assert.equal(view.players[1].avatar, null);
});

test('訪談對話中 aiBusy 為 true 時，talk 與 to_plan 及其他提問皆會被伺服器拒絕', async () => {
  const ctx = ctxFor(10);
  const g = createGame('BUSY');
  addPlayer(g, { id: 'p1', name: '顧問' });
  startGame(g, ctx);
  g.session = { playerId: 'p1', clientId: CLIENTS[0].id, referral: false, step: 'discover', asked: [], freeLeft: 1, freeHits: [], clues: [], observed: [], m: { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 }, objectionOrder: [0, 1, 2, 3], predictions: {}, aiBusy: true };
  g.turnStage = 'session';

  assert.match((await applyAction(g, 'p1', { type: 'talk', text: '請問平常有什麼保障？' }, ctx))!, /回應中/);
  assert.match((await applyAction(g, 'p1', { type: 'to_plan' }, ctx))!, /回應中/);
  assert.match((await applyAction(g, 'p1', { type: 'ask', qid: 'income' }, ctx))!, /回應中/);
  assert.match((await applyAction(g, 'p1', { type: 'ask_free', text: '請問收入狀況？' }, ctx))!, /回應中/);

  g.session.aiBusy = false;
  assert.equal(await applyAction(g, 'p1', { type: 'ask', qid: 'income' }, ctx), null);
});

test('partialJsonStringDone：正確判斷客戶回答字串結束與跳脫字元', () => {
  const incomplete = '{"answer": "你好，我想了解';
  assert.deepEqual(partialJsonStringDone(incomplete, 'answer'), { text: '你好，我想了解', done: false });

  const complete = '{"answer": "你好，我想了解", "coachTip": "切中要害"}';
  assert.deepEqual(partialJsonStringDone(complete, 'answer'), { text: '你好，我想了解', done: true });

  const withQuotes = '{"answer": "他說: \\"不用擔心\\" 就好了", "coachTip": "良好"}';
  assert.deepEqual(partialJsonStringDone(withQuotes, 'answer'), { text: '他說: "不用擔心" 就好了', done: true });
});

test('FinalRow AI 等待狀態：AI 啟用時以 pending 起始並填入 AI 評語；AI 失敗時以 fallback 結束且不留 pending；訪客立即取得 fallback', async () => {
  const g = createGame('WAIT');
  addPlayer(g, { id: 'p_ai', name: 'AI 玩家', accountId: 'acc_1' });
  addPlayer(g, { id: 'p_guest', name: '訪客玩家', accountId: null });
  addPlayer(g, { id: 'p_bot', name: '電腦玩家', isBot: true });

  const mockAiService: AIService = {
    enabled: true,
    freeQuestion: async () => ({ answer: '', matched: null, key: null, trust: 0, insight: 0, compliance: 0, note: '' }),
    talk: async () => ({ answer: '', revealedFacts: [], trustDelta: 0, insightDelta: 0, emotion: 'neutral', compliance: { level: 'pass', penalty: 0, issues: [] }, coachTip: '' }),
    letter: async () => '十年信',
    gradeObjection: async () => ({ quality: 'good', trust: 0, fit: 0, risk: 0, compliance: 0, title: '', body: '' }),
    marketNews: async () => '快訊',
    coachTip: async () => '提示',
    hint: async () => '提示',
    debrief: async () => 'AI 教練專屬評語：表現卓越！',
    generateClient: async () => null,
  };

  const failingAiService: AIService = {
    ...mockAiService,
    debrief: async () => null,
  };

  const ctxAi: Ctx = {
    ai: mockAiService,
    rng: seeded(1),
    now: () => 0,
    aiFor: (p) => (p.id === 'p_ai' && p.accountId ? mockAiService : new RuleAI()),
  };

  // 1. 遊戲結算 (endGame)：AI 啟用的登入玩家 coach 為空且 coachPending = true；訪客與電腦立即取得 fallback 且 coachPending = false
  endGame(g, ctxAi);
  assert.ok(g.final && g.final.length === 3);

  const rowAi = g.final.find(r => r.playerId === 'p_ai')!;
  const rowGuest = g.final.find(r => r.playerId === 'p_guest')!;
  const rowBot = g.final.find(r => r.playerId === 'p_bot')!;

  assert.equal(rowAi.coachPending, true);
  assert.equal(rowAi.coach, '');

  assert.equal(rowGuest.coachPending, false);
  assert.ok(rowGuest.coach.length > 0);

  assert.equal(rowBot.coachPending, false);
  assert.ok(rowBot.coach.length > 0);

  // 2. enrichCoach 成功：AI 評語抵達，coachPending 清除為 false，coach 替換為 AI 內容
  await enrichCoach(g, (p) => (p.id === 'p_ai' ? mockAiService : new RuleAI()));
  assert.equal(rowAi.coachPending, false);
  assert.equal(rowAi.coach, 'AI 教練專屬評語：表現卓越！');

  // 3. AI 呼叫失敗情境：重新 endGame，但 enrichCoach 使用 failingAiService
  endGame(g, ctxAi);
  const rowFail = g.final.find(r => r.playerId === 'p_ai')!;
  assert.equal(rowFail.coachPending, true);
  assert.equal(rowFail.coach, '');

  await enrichCoach(g, (p) => (p.id === 'p_ai' ? failingAiService : new RuleAI()));
  assert.equal(rowFail.coachPending, false);
  const pAi = g.players.find(p => p.id === 'p_ai')!;
  assert.equal(rowFail.coach, fallbackTip(pAi));
});

test('partialJsonStringDone 正確從未完整 JSON 擷取 body, content, text', () => {
  const partialBody = '{"title": "test", "body": "這是一段漸進式內容';
  assert.equal(partialJsonStringDone(partialBody, 'body').text, '這是一段漸進式內容');
  assert.equal(partialJsonStringDone(partialBody, 'body').done, false);

  const completedBody = '{"title": "test", "body": "這是一段完整內容"}';
  assert.equal(partialJsonStringDone(completedBody, 'body').text, '這是一段完整內容');
  assert.equal(partialJsonStringDone(completedBody, 'body').done, true);

  const partialContent = '{"content": "親愛的顧問，這十年來';
  assert.equal(partialJsonStringDone(partialContent, 'content').text, '親愛的顧問，這十年來');

  const partialText = '{"text": "全球市場波動加劇';
  assert.equal(partialJsonStringDone(partialText, 'text').text, '全球市場波動加劇');
});

test('非 talk AI 功能（hint / debrief / letter）串流測試：接收漸進式 chunks 且最終狀態儲存驗證後文本', async () => {
  const streamedChunks: Array<{ key: string; text: string }> = [];

  const streamingAiService: AIService = {
    enabled: true,
    freeQuestion: async () => ({ answer: '', matched: null, key: null, trust: 0, insight: 0, compliance: 0, note: '' }),
    talk: async () => ({ answer: '', revealedFacts: [], trustDelta: 0, insightDelta: 0, emotion: 'neutral', compliance: { level: 'pass', penalty: 0, issues: [] }, coachTip: '' }),
    letter: async (_c, _twist, _facts, onStream) => {
      onStream?.('親愛的');
      onStream?.('親愛的顧問，謝謝你');
      return '親愛的顧問，謝謝你的規劃。';
    },
    gradeObjection: async () => ({ quality: 'good', trust: 0, fit: 0, risk: 0, compliance: 0, title: '', body: '' }),
    marketNews: async () => '快訊',
    coachTip: async () => '提示',
    hint: async (_c, _sess, onStream) => {
      onStream?.('建議先');
      onStream?.('建議先釐清家庭');
      return '建議先釐清家庭責任與預算。';
    },
    debrief: async (_p, _row, onStream) => {
      onStream?.('整體表現');
      onStream?.('整體表現穩健');
      return '整體表現穩健，持續精進！';
    },
    generateClient: async () => null,
  };

  const g = createGame('STREAM_TEST');
  addPlayer(g, { id: 'p_stream', name: '串流顧問', accountId: 'acc_stream' });
  const client = CLIENTS[0];

  const ctx: Ctx = {
    ai: streamingAiService,
    rng: seeded(1),
    now: () => 0,
    aiFor: () => streamingAiService,
    onStream: (key, text) => {
      streamedChunks.push({ key, text });
    },
  };

  startGame(g, ctx);

  // 1. 測試 hint 串流
  g.session = {
    playerId: 'p_stream',
    clientId: client.id,
    referral: false,
    step: 'discover',
    asked: [],
    freeLeft: 0,
    freeHits: [],
    clues: [],
    observed: [],
    m: { trust: 50, insight: 50, fit: 50, risk: 50, compliance: 100 },
    objectionOrder: [0, 1, 2, 3],
    predictions: {},
  };
  g.turnStage = 'session';

  const hintErr = await applyAction(g, 'p_stream', { type: 'hint' }, ctx);
  assert.equal(hintErr, null);
  assert.equal(g.session.hint, '建議先釐清家庭責任與預算。');
  assert.equal(g.session.hintUsed, true);

  const hintChunks = streamedChunks.filter(c => c.key === 'hint');
  assert.equal(hintChunks.length, 2);
  assert.equal(hintChunks[0].text, '建議先');
  assert.equal(hintChunks[1].text, '建議先釐清家庭');

  // 2. 測試 endGame + enrichCoach 串流 (coach & letter)
  g.players[0].book.push({ clientId: client.id, name: client.name, alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income'], satisfaction: 70, planQuality: 'good', compliance: 100, stressUsed: 0, signedRound: 1, mis: false });
  endGame(g, ctx);
  assert.ok(g.final && g.final.length === 1);
  assert.equal(g.final[0].coachPending, true);

  // Attach one template letter after settlement (enrichCoach polishes letters from the interview logs)
  g.clients[client.id] = client;
  g.players[0].sessionLogs = [{ clientId: client.id, clientName: client.name, letter: { outcome: 'thanks', content: '模板信' } } as unknown as NonNullable<typeof g.players[0]['sessionLogs']>[number]];
  g.final[0].letters = [{ clientId: client.id, clientName: client.name, outcome: 'thanks', content: '模板信' }];
  g.final[0].lettersPending = true;

  await enrichCoach(g, () => streamingAiService, (key, text) => {
    streamedChunks.push({ key, text });
  });

  assert.equal(g.final[0].coachPending, false);
  assert.equal(g.final[0].coach, '整體表現穩健，持續精進！');
  assert.equal(g.final[0].lettersPending, false);
  assert.ok(g.final[0].letters && g.final[0].letters.length === 1);
  assert.equal(g.final[0].letters[0].content, '親愛的顧問，謝謝你的規劃。');
  assert.equal(g.final[0].letters[0].clientId, client.id);

  const coachChunks = streamedChunks.filter(c => c.key === 'coach:p_stream');
  assert.equal(coachChunks.length, 2);
  assert.equal(coachChunks[0].text, '整體表現');
  assert.equal(coachChunks[1].text, '整體表現穩健');

  const letterChunks = streamedChunks.filter(c => c.key === `letter:p_stream:${client.id}`);
  assert.equal(letterChunks.length, 2);
  assert.equal(letterChunks[0].text, '親愛的');
  assert.equal(letterChunks[1].text, '親愛的顧問，謝謝你');
});



