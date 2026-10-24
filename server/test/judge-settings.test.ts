/* Judge mode settings & 1-round fast evaluation test */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Room } from '../src/room.ts';
import { FakeState } from './helpers/fake-do.ts';
import { addPlayer, applyAction, createGame, endGame, mulberry32, startGame, type Ctx } from '../src/game/game.ts';
import { botAction } from '../src/game/bots.ts';
import { RuleAI } from '../src/ai.ts';

async function createLobby(solo = true) {
  const state = new FakeState();
  const stub = { saveAttempt: async () => {}, listAttempts: async () => ({ attempts: [] }), add: async () => {}, addSummary: async () => {}, aiUsage: async () => 0 };
  const env = { AI_PROVIDER: 'rules', RECORDS: { idFromName: (n: string) => n, get: () => stub } } as any;
  const room = new Room(state as any, env);
  await state.ready;
  await room.fetch(new Request('https://room/init', { method: 'POST', body: JSON.stringify({ code: 'JUDGE', solo }) }));
  const ws = state.connect({ id: 'u_judge', name: '評審顧問' });
  await room.webSocketMessage(ws as any, JSON.stringify({ t: 'hello', name: '評審顧問' }));
  return { room, ws };
}

test('solo 局送 { t: "settings", rounds: 1, demo: "1" } 後 rounds === 1 且首個案件是 jiahao；不帶 demo 時 rounds:1 仍被夾成 2', async () => {
  // 1. Without demo: rounds: 1 is clamped to 2
  const { room: roomNoDemo, ws: wsNoDemo } = await createLobby(true);
  await roomNoDemo.webSocketMessage(wsNoDemo as any, JSON.stringify({ t: 'settings', rounds: 1 }));
  assert.equal((roomNoDemo as any).game.settings.rounds, 2);

  // 2. With demo: '1' in solo mode: rounds: 1 is accepted, demo is set to 'jiahao'
  const { room, ws } = await createLobby(true);
  await room.webSocketMessage(ws as any, JSON.stringify({ t: 'settings', rounds: 1, demo: '1' }));
  const game = (room as any).game;
  assert.equal(game.settings.rounds, 1);
  assert.equal(game.demo, 'jiahao');

  // Start game with 1 bot
  await room.webSocketMessage(ws as any, JSON.stringify({ t: 'add_bot', level: 'pro' }));
  await room.webSocketMessage(ws as any, JSON.stringify({ t: 'start' }));
  assert.equal(game.phase, 'playing');

  // First action by judge (roll): triggers autoSetup with demo client
  const human = game.players.find((p: any) => !p.isBot);
  assert.ok(human);
  await room.webSocketMessage(ws as any, JSON.stringify({ t: 'action', action: { type: 'roll' } }));
  assert.equal(human.mainCase?.clientId, 'jiahao');
});

test('不合法的 demo id 或多人連線局無法設定 rounds: 1', async () => {
  // 1. Invalid demo id in solo mode
  const { room: roomInvalidDemo, ws: wsInvalidDemo } = await createLobby(true);
  await roomInvalidDemo.webSocketMessage(wsInvalidDemo as any, JSON.stringify({ t: 'settings', rounds: 1, demo: 'invalid_hero' }));
  assert.equal((roomInvalidDemo as any).game.settings.rounds, 2);

  // 2. Multiplayer room with demo: '1'
  const { room: roomMulti, ws: wsMulti } = await createLobby(false);
  await roomMulti.webSocketMessage(wsMulti as any, JSON.stringify({ t: 'settings', rounds: 1, demo: '1' }));
  assert.equal((roomMulti as any).game.settings.rounds, 2);
});

test('rounds: 1 完整一局能正常結束並產生培訓報告（包含十年時間軸與十年後的信）', async () => {
  const rng = mulberry32(20261106);
  const ctx: Ctx = { ai: new RuleAI(), rng, now: () => 0 };
  const g = createGame('JUDGE1');
  addPlayer(g, { id: 'judge', name: '評審顧問' });
  addPlayer(g, { id: 'bot1', name: '沈知妍（資深）', isBot: true, botLevel: 'pro' });
  addPlayer(g, { id: 'bot2', name: '顧承宇（新人）', isBot: true, botLevel: 'novice' });
  g.solo = true;
  g.settings.rounds = 1;
  g.demo = 'jiahao';
  g.demoFirstRoll = true;
  g.demoFirstSession = true;

  startGame(g, ctx);
  assert.equal(g.phase, 'playing');
  assert.equal(g.settings.rounds, 1);

  // Auto setup or run actions until game ends
  let steps = 0;
  while (g.phase === 'playing') {
    assert.ok(++steps < 1000, '1-round judge game did not finish in 1000 steps');
    const p = g.players[g.turn];
    const a = botAction(g, rng);
    assert.ok(a, `no action for ${p.id} at ${g.turnStage}`);
    const err = await applyAction(g, p.id, a, ctx);
    if (err && g.session?.step === 'discover') await applyAction(g, p.id, { type: 'to_plan' }, ctx);
    else assert.equal(err, null, `${p.id} ${a.type} rejected: ${err}`);
  }

  assert.equal(g.phase, 'ended');
  assert.ok(g.final && g.final.length === 3);

  const judgeFinal = g.final.find(f => f.playerId === 'judge');
  assert.ok(judgeFinal);
  assert.ok(judgeFinal.timelines && judgeFinal.timelines.length > 0, 'judge has timeline in final report');
  assert.ok(judgeFinal.letters && judgeFinal.letters.length > 0, 'judge has letter in final report');
});
