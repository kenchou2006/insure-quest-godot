import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BOARD } from '../src/game/data.ts';
import { addPlayer, applyAction, createGame, publicView, startGame, type Ctx } from '../src/game/game.ts';
import { RuleAI } from '../src/ai.ts';
import type { GameState } from '../src/game/types.ts';

/** First rng call decides the roll (0 -> 1 step); everything after is neutral */
const rollOne = (): Ctx => { let n = 0; return { ai: new RuleAI(), rng: () => (n++ === 0 ? 0 : 0.5), now: () => 0 }; };

function soloWithBot(): GameState {
  const g = createGame('CASE');
  addPlayer(g, { id: 'p1', name: '顧問' });
  addPlayer(g, { id: 'b1', name: '電腦', isBot: true });
  startGame(g, rollOne());
  return g;
}

/** Puts p1 one step before `tile` and rolls a 1 */
async function landOn(g: GameState, tile: number) {
  g.turn = 0; g.turnStage = 'roll'; g.session = null; g.event = null;
  g.players[0].pos = (tile - 1 + BOARD.length) % BOARD.length;
  assert.equal(await applyAction(g, 'p1', { type: 'roll' }, rollOne()), null);
}

test('主要案件：開局選客戶與公事包，三次落在客戶格分別推進需求訪談、方案設計、異議與結果', async () => {
  const g = soloWithBot();
  assert.ok(g.players[1].mainCase, '電腦顧問開局自動選案');
  assert.equal(g.players[0].mainCase, undefined);

  // Validation; setup works even when it is not p1's turn
  g.turn = 1;
  assert.match(String(await applyAction(g, 'p1', { type: 'setup', clientId: 'yuqing', tools: ['needs_form'] }, rollOne())), /3/);
  assert.ok(await applyAction(g, 'p1', { type: 'setup', clientId: 'jiahao', tools: ['needs_form', 'cashflow', 'gap_sheet'] }, rollOne()));
  assert.equal(await applyAction(g, 'p1', { type: 'setup', clientId: 'yuqing', tools: ['needs_form', 'cashflow', 'gap_sheet'] }, rollOne()), null);
  assert.ok(!g.deck.includes('yuqing'), '主要客戶不會再被當成陌生客戶抽出');
  const view = publicView(g, 'p1') as any;
  assert.equal(view.players[0].mainCase.clientName, '林雨晴');
  assert.equal(view.caseOptions.length, 5);

  // Meeting 1: needs interview, with briefcase effects
  await landOn(g, 1);
  assert.equal(BOARD[1].type, 'client');
  const s1 = g.session!;
  assert.equal(s1.clientId, 'yuqing');
  assert.equal(s1.staged, true);
  assert.equal(s1.talkLeft, 4, '需求訪談表：多 1 輪對話');
  assert.equal(s1.observed.length, 1, '收支盤點表：開場掌握 1 條線索');
  assert.ok(s1.clues[s1.observed[0]].real);
  assert.ok(s1.toolHints?.coreCards?.length, '保障缺口分析表：提供優先保障卡');
  for (const qid of ['income', 'goal', 'coverage'] as const) assert.equal(await applyAction(g, 'p1', { type: 'ask', qid }, rollOne()), null);
  assert.equal(await applyAction(g, 'p1', { type: 'to_plan' }, rollOne()), null);
  assert.equal(g.session, null);
  assert.equal(g.turnStage, 'event');
  assert.match(g.event!.title, /第一次會談完成/);
  assert.equal(g.players[0].mainCase!.saved!.step, 'plan');
  await applyAction(g, 'p1', { type: 'continue' }, rollOne());
  assert.equal(g.turn, 1, '會談階段結束後換下一位');

  // Meeting 2: plan design resumes the same interview
  await landOn(g, 3);
  assert.equal(g.session!.clientId, 'yuqing');
  assert.equal(g.session!.step, 'plan');
  assert.equal(g.players[0].mainCase!.visits, 2);
  assert.equal(await applyAction(g, 'p1', { type: 'plan', alloc: { cash: 4, protect: 4, growth: 2 }, cards: ['income', 'medical'] }, rollOne()), null);
  assert.match(g.event!.title, /方案已提交/);
  assert.equal(g.players[0].mainCase!.saved!.step, 'objection');
  await applyAction(g, 'p1', { type: 'continue' }, rollOne());

  // Meeting 3: objection, then the result closes the primary case
  await landOn(g, 6);
  assert.equal(g.session!.step, 'objection');
  assert.equal(await applyAction(g, 'p1', { type: 'objection', index: 0 }, rollOne()), null);
  assert.equal(g.session!.step, 'result');
  assert.equal(g.players[0].mainCase!.done, true);
  assert.equal(g.players[0].sessions, 1);
  await applyAction(g, 'p1', { type: 'continue' }, rollOne());

  // Afterwards client tiles open new cases again
  await landOn(g, 8);
  assert.notEqual(g.session!.clientId, 'yuqing');
  assert.ok(!g.session!.staged);
});

test('主要案件進行中：轉介紹格累積人脈、不開啟新面談', async () => {
  const g = soloWithBot();
  await applyAction(g, 'p1', { type: 'setup', clientId: 'boting', tools: ['needs_form', 'family_map', 'compliance_check'] }, rollOne());
  const tile = BOARD.findIndex(t => t.type === 'referral');
  await landOn(g, tile);
  assert.equal(g.session, null);
  assert.equal(g.event!.title, '人脈事件');
  assert.equal(g.players[0].contacts!.length, 1);
});

test('回合不夠時客戶主動約見；最後一回合一次完成剩餘流程', async () => {
  const g = soloWithBot();
  await applyAction(g, 'p1', { type: 'setup', clientId: 'wanting', tools: ['needs_form', 'cashflow', 'risk_survey'] }, rollOne());
  // Three meetings left and three turns left: a non-client tile still becomes a meeting
  g.settings.rounds = 3;
  const nonClient = BOARD.findIndex((t, i) => i > 0 && t.type !== 'client' && t.type !== 'start');
  await landOn(g, nonClient);
  assert.equal(g.session!.clientId, 'wanting');
  assert.equal(g.session!.staged, true);
  assert.ok(g.session!.toolHints?.ideal, '風險承受度問卷：提供配置區間');

  // Final round: the meeting is not paused, so the case can reach a result
  const g2 = soloWithBot();
  await applyAction(g2, 'p1', { type: 'setup', clientId: 'wanting', tools: ['needs_form', 'cashflow', 'risk_survey'] }, rollOne());
  g2.round = g2.settings.rounds;
  await landOn(g2, nonClient);
  assert.equal(g2.session!.staged, false);
  for (const qid of ['income', 'goal', 'coverage'] as const) await applyAction(g2, 'p1', { type: 'ask', qid }, rollOne());
  await applyAction(g2, 'p1', { type: 'to_plan' }, rollOne());
  assert.equal(g2.session!.step, 'plan', '最後一回合不暫停');
});

test('未開啟設定畫面就擲骰：自動配發主要客戶與預設公事包，遊戲不會卡住', async () => {
  const g = soloWithBot();
  await landOn(g, 2);
  assert.ok(g.players[0].mainCase);
  assert.equal(g.players[0].briefcase!.length, 3);
});
