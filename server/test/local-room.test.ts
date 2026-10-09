/* Guest solo games run in the browser via LocalRoom: play one to the end with mocked timers. */
import { test, mock } from 'node:test';
import assert from 'node:assert/strict';
import { LocalRoom } from '../src/local/local-room.ts';
import { botAction } from '../src/game/bots.ts';

const flush = () => new Promise(r => setImmediate(r));

test('LocalRoom plays a full solo game to the report without any server', async () => {
  mock.timers.enable({ apis: ['setTimeout'] });
  try {
    const room = new LocalRoom();
    const out: any[] = [];
    const pump = async () => { for (let i = 0; i < 5; i++) await flush(); out.push(...JSON.parse(room.drain())); };
    const g = () => (room as any).game;

    room.receive(JSON.stringify({ t: 'hello', name: '訪客' }));
    await pump();
    const me = out.find(m => m.t === 'welcome').playerId;
    assert.ok(me);
    room.receive(JSON.stringify({ t: 'add_bot', level: 'pro' }));
    room.receive(JSON.stringify({ t: 'add_bot', level: 'novice' }));
    room.receive(JSON.stringify({ t: 'settings', rounds: 2 }));
    room.receive(JSON.stringify({ t: 'start' }));
    await pump();
    assert.equal(g().phase, 'playing');

    for (let step = 0; step < 2000 && g().phase !== 'ended'; step++) {
      const s = g();
      const p = s.players[s.turn];
      if (p.id === me) {
        // Drive the human seat with the pro bot policy (as Room does for AFK takeover).
        p.botLevel = 'pro';
        const a = botAction(s, Math.random);
        p.botLevel = undefined;
        if (a) room.receive(JSON.stringify({ t: 'action', action: a }));
      } else {
        mock.timers.tick(5000);
      }
      await pump();
    }
    await pump();
    assert.equal(g().phase, 'ended');
    const last = out.filter(m => m.t === 'state').at(-1).state;
    assert.equal(last.phase, 'ended');
    assert.equal(last.aiPending, false);
    assert.ok(Array.isArray(last.final) && last.final.length === 3);
    assert.equal(out.filter(m => m.t === 'error').length, 0, JSON.stringify(out.filter(m => m.t === 'error').slice(0, 3)));
  } finally {
    mock.timers.reset();
  }
});

test('LocalRoom: abandon sends closed; a second hello cannot take a seat', async () => {
  const room = new LocalRoom();
  room.receive(JSON.stringify({ t: 'hello', name: 'A' }));
  room.receive(JSON.stringify({ t: 'hello', name: 'B' }));
  await flush(); await flush();
  room.receive(JSON.stringify({ t: 'abandon' }));
  await flush(); await flush();
  const out = JSON.parse(room.drain());
  assert.ok(out.some((m: any) => m.t === 'error' && m.message === '這是單人練習房間，無法加入'));
  // The rejected hello keeps the original seat, so the player can still abandon.
  assert.ok(out.some((m: any) => m.t === 'closed' && m.message === '已放棄本局'));
  assert.equal((room as any).game, null);
});
