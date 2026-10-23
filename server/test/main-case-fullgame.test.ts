import { test } from 'node:test';
import assert from 'node:assert/strict';
import { addPlayer, applyAction, createGame, endGame, mulberry32, startGame, CASE_OPTIONS, type Ctx } from '../src/game/game.ts';
import { botAction } from '../src/game/bots.ts';
import { RuleAI } from '../src/ai.ts';

/** Plays a whole solo game (human + 2 bots, 5 rounds like the client) from setup to settlement */
async function playFullGame(seed: number, rounds: number) {
  const rng = mulberry32(seed);
  const ctx: Ctx = { ai: new RuleAI(), rng, now: () => 0 };
  const g = createGame('FULL');
  addPlayer(g, { id: 'me', name: '顧問' });
  addPlayer(g, { id: 'b1', name: '電腦A', isBot: true, botLevel: 'pro' });
  addPlayer(g, { id: 'b2', name: '電腦B', isBot: true, botLevel: 'novice' });
  g.settings.rounds = rounds;
  startGame(g, ctx);
  const clientId = CASE_OPTIONS[seed % CASE_OPTIONS.length];
  assert.equal(await applyAction(g, 'me', { type: 'setup', clientId, tools: ['needs_form', 'cashflow', 'gap_sheet'] }, ctx), null);
  let steps = 0;
  while (g.phase === 'playing') {
    assert.ok(++steps < 5000, `seed ${seed}: game did not finish`);
    const p = g.players[g.turn];
    const a = botAction(g, rng);
    assert.ok(a, `seed ${seed}: no action for ${p.id} at ${g.turnStage}`);
    const err = await applyAction(g, p.id, a, ctx);
    if (err && g.session?.step === 'discover') await applyAction(g, p.id, { type: 'to_plan' }, ctx);
    else assert.equal(err, null, `seed ${seed}: ${p.id} ${a.type} rejected: ${err}`);
  }
  if (g.phase !== 'ended') endGame(g, ctx);
  return { g, clientId };
}

test('完整一局（5 回合、3 位顧問）：每位顧問都完成主要案件並進入結算', async () => {
  for (let seed = 1; seed <= 60; seed++) {
    const { g, clientId } = await playFullGame(seed, 5);
    assert.equal(g.phase, 'ended');
    assert.ok(g.final && g.final.length === 3, `seed ${seed}: settlement rows`);
    for (const p of g.players) {
      assert.ok(p.mainCase?.done, `seed ${seed}: ${p.name} 主要案件未完成（${p.mainCase?.visits} 次會談）`);
      assert.ok(p.sessions >= 1);
      assert.ok((p.sessionLogs ?? []).some(l => l.clientId === p.mainCase!.clientId));
    }
    assert.equal(g.players[0].mainCase!.clientId, clientId);
  }
});

test('短局（3 回合）也能在最後一回合完成主要案件', async () => {
  for (let seed = 1; seed <= 30; seed++) {
    const { g } = await playFullGame(seed, 3);
    for (const p of g.players) assert.ok(p.mainCase?.done, `seed ${seed}: ${p.name}`);
  }
});
