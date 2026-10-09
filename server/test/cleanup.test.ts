/* Storage cleanup: abandoned / idle / finished rooms must not keep occupying Durable Object storage,
 * and AI usage rows older than 7 days are pruned. Runs the real Room / Records classes on a fake DO state. */
import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { Room } from '../src/room.ts';
import { Records, taipeiDay } from '../src/records.ts';
import { FakeState, type FakeSocket } from './helpers/fake-do.ts';

const realNow = Date.now;
let clock = realNow();
Date.now = () => clock;
afterEach(() => { clock = realNow(); });

function fakeEnv() {
  const saved: unknown[] = [];
  const stub = { add: async (r: unknown) => { saved.push(r); }, addSummary: async () => {}, aiUsage: async () => 0 };
  const RECORDS = { idFromName: (n: string) => n, get: () => stub };
  return { env: { AI_PROVIDER: 'rules', AI_DAILY_LIMIT: '10', RECORDS } as any, saved };
}

async function newRoom(solo = false) {
  const state = new FakeState();
  const { env, saved } = fakeEnv();
  const room = new Room(state as any, env);
  await state.ready;
  const res = await room.fetch(new Request('https://room/init', { method: 'POST', body: JSON.stringify({ code: 'ABCDE', solo }) }));
  assert.equal(res.status, 200);
  return { room, state, saved };
}

const send = (room: Room, ws: FakeSocket, msg: unknown) => room.webSocketMessage(ws as any, JSON.stringify(msg));
const game = (room: Room) => (room as any).game;
const isGone = (room: Room, state: FakeState) => game(room) === null && state.kv.size === 0;

async function soloGame(account: { id: string; name: string } | null = { id: 'u1', name: '測試' }) {
  const r = await newRoom(true);
  const ws = r.state.connect(account);
  await send(r.room, ws, { t: 'hello', name: '測試' });
  await send(r.room, ws, { t: 'add_bot', level: 'pro' });
  await send(r.room, ws, { t: 'start' });
  assert.equal(game(r.room).phase, 'playing');
  return { ...r, ws };
}

test('a room whose host never connects is deleted by the alarm', async () => {
  const { room, state } = await newRoom();
  assert.ok(state.alarm && state.alarm > clock, 'init arms an alarm');
  clock = state.alarm!;
  await room.alarm();
  assert.ok(isGone(room, state));
});

test('a lobby with its host waiting is kept no matter how long nobody joins', async () => {
  const { room, state } = await newRoom();
  const ws = state.connect({ id: 'u1', name: 'H' });
  await send(room, ws, { t: 'hello', name: 'H' });
  clock = state.alarm!;
  await room.alarm();
  clock += 6 * 3600_000;
  await room.alarm();
  assert.equal(game(room).phase, 'lobby');
});

test('the host leaving the lobby closes the room and tells the others', async () => {
  const { room, state } = await newRoom();
  const host = state.connect({ id: 'u1', name: 'H' });
  const guest = state.connect({ id: 'u2', name: 'G' });
  await send(room, host, { t: 'hello', name: 'H' });
  await send(room, guest, { t: 'hello', name: 'G' });
  host.close();
  await room.webSocketClose(host as any);
  assert.ok(isGone(room, state));
  assert.equal(guest.last('closed')?.message, '房主已離開，房間已關閉');
  assert.ok(guest.closed);
});

test('a non-host leaving the lobby only frees the seat', async () => {
  const { room, state } = await newRoom();
  const host = state.connect({ id: 'u1', name: 'H' });
  const guest = state.connect({ id: 'u2', name: 'G' });
  await send(room, host, { t: 'hello', name: 'H' });
  await send(room, guest, { t: 'hello', name: 'G' });
  guest.close();
  await room.webSocketClose(guest as any);
  assert.equal(game(room).players.length, 1);
  assert.equal(host.closed, false);
});

test('multiplayer rooms reject guests; solo rooms accept a guest but nobody else', async () => {
  const multi = await newRoom();
  const guest = multi.state.connect(null);
  await send(multi.room, guest, { t: 'hello', name: 'X' });
  assert.equal(guest.last('error')?.message, '多人連線需先登入');
  assert.equal(game(multi.room).players.length, 0);

  const { room, state } = await soloGame(null);
  assert.equal(game(room).players.filter((p: any) => !p.isBot).length, 1);
  const intruder = state.connect({ id: 'u9', name: 'I' });
  await send(room, intruder, { t: 'hello', name: 'I' });
  assert.equal(intruder.last('error')?.message, '這是單人練習房間，無法加入');
  assert.equal(game(room).players.filter((p: any) => !p.isBot).length, 1);
});

test('abandon: solo player voids the game, no record is saved, sockets are closed', async () => {
  const { room, state, ws, saved } = await soloGame();
  const spectator = state.connect();
  await send(room, ws, { t: 'abandon' });
  assert.ok(isGone(room, state));
  assert.equal(saved.length, 0);
  assert.equal(state.sockets.length, 0);
  assert.ok(spectator.closed);
  assert.equal(ws.last('closed')?.message, '已放棄本局');
});

test('abandon: a spectator cannot void a solo game', async () => {
  const { room, state } = await soloGame();
  const spectator = state.connect();
  await send(room, spectator, { t: 'hello' });
  await send(room, spectator, { t: 'abandon' });
  assert.equal(game(room).phase, 'playing');
  assert.equal(spectator.last('error')?.t, 'error');
});

test('abandon: a multiplayer host cannot void the game for others', async () => {
  const { room, state } = await newRoom();
  const host = state.connect({ id: 'u1', name: 'H' });
  const guest = state.connect({ id: 'u2', name: 'G' });
  await send(room, host, { t: 'hello', name: 'H' });
  await send(room, guest, { t: 'hello', name: 'G' });
  await send(room, host, { t: 'start' });
  await send(room, host, { t: 'abandon' });
  assert.equal(game(room).phase, 'playing');
});

test('solo player disconnects: room survives 44 s, is voided after 45 s without saving', async () => {
  const { room, state, ws, saved } = await soloGame();
  ws.close();
  await room.webSocketClose(ws as any);
  const due = state.alarm!;
  assert.equal(due, clock + 45_000);
  clock += 44_000;
  await room.alarm();
  assert.ok(game(room), 'not voided before 45 s');
  clock = due;
  await room.alarm();
  assert.ok(isGone(room, state));
  assert.equal(saved.length, 0);
});

test('solo player reconnects within 45 s: game continues', async () => {
  const { room, state, ws } = await soloGame();
  const pid = game(room).players.find((p: any) => !p.isBot).id;
  ws.close();
  await room.webSocketClose(ws as any);
  clock += 20_000;
  const ws2 = state.connect({ id: 'u1', name: '測試' });
  await send(room, ws2, { t: 'hello', playerId: pid });
  clock += 30_000;
  await room.alarm();
  assert.equal(game(room).phase, 'playing');
});

test('multiplayer: one human offline is taken over, the room is kept', async () => {
  const { room, state } = await newRoom();
  const a = state.connect({ id: 'u1', name: 'A' });
  const b = state.connect({ id: 'u2', name: 'B' });
  await send(room, a, { t: 'hello', name: 'A' });
  await send(room, b, { t: 'hello', name: 'B' });
  await send(room, a, { t: 'start' });
  a.close();
  await room.webSocketClose(a as any);
  clock += 46_000;
  await room.alarm();
  assert.equal(game(room).phase, 'playing');
});

test('multiplayer: all humans offline for 45 s voids the room', async () => {
  const { room, state } = await newRoom();
  const a = state.connect({ id: 'u1', name: 'A' });
  const b = state.connect({ id: 'u2', name: 'B' });
  await send(room, a, { t: 'hello', name: 'A' });
  await send(room, b, { t: 'hello', name: 'B' });
  await send(room, a, { t: 'start' });
  a.close(); await room.webSocketClose(a as any);
  clock += 10_000;
  b.close(); await room.webSocketClose(b as any);
  assert.equal(state.alarm, clock + 45_000, 'timer counts from the last disconnect');
  clock += 45_000;
  await room.alarm();
  assert.ok(isGone(room, state));
});

test('ended game: deleted when the last socket leaves; sweep alarm keeps it while someone is viewing', async () => {
  const { room, state, ws } = await soloGame();
  game(room).phase = 'ended';
  clock += 60_000;
  await room.alarm();
  assert.ok(game(room), 'still viewing the report');
  assert.ok(state.alarm! > clock);
  ws.close();
  await room.webSocketClose(ws as any);
  assert.ok(isGone(room, state));
});

test('ended game: sweep alarm deletes it if the close event was missed', async () => {
  const { room, state, ws } = await soloGame();
  game(room).phase = 'ended';
  state.sockets = state.sockets.filter(s => s !== ws);
  await room.alarm();
  assert.ok(isGone(room, state));
});

test('Records: AI usage older than 7 days is pruned, the last 7 days are kept', async () => {
  const state = new FakeState();
  const sql = state.storage.sql;
  // Seed rows before the DO wakes up (as if left from earlier days).
  sql.exec('CREATE TABLE ai_usage (user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day))');
  sql.exec('CREATE TABLE ai_calls (user_id TEXT NOT NULL, day TEXT NOT NULL, provider TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day, provider))');
  for (let i = 0; i < 10; i++) {
    const day = taipeiDay(clock - i * 86_400_000);
    sql.exec('INSERT INTO ai_usage VALUES (?, ?, ?)', 'u1', day, 1);
    sql.exec('INSERT INTO ai_calls VALUES (?, ?, ?, ?)', 'u1', day, 'nvidia-nim', 2);
  }
  const rec = new Records(state as any, {} as any);
  const days = (t: string) => sql.exec(`SELECT day FROM ${t} ORDER BY day`).toArray().map((r: any) => r.day);
  assert.equal(days('ai_usage').length, 7);
  assert.equal(days('ai_calls').length, 7);
  assert.equal(days('ai_usage')[0], taipeiDay(clock - 6 * 86_400_000));
  // History still returns 7 full days, and today's count is intact.
  const h = rec.aiHistory('u1');
  assert.equal(h.length, 7);
  assert.equal(h.at(-1)!.quota, 1);
  assert.equal(h[0].calls['nvidia-nim'], 2);
  // A DO that stays awake across midnight prunes on the next consume.
  clock += 86_400_000;
  rec.consumeAi('u1', 10);
  assert.equal(days('ai_usage').length, 7);
  assert.equal(days('ai_usage').at(-1), taipeiDay(clock));
});

test('Records: expired login sessions are removed on wake-up', async () => {
  const state = new FakeState();
  const sql = state.storage.sql;
  sql.exec('CREATE TABLE sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL)');
  sql.exec('INSERT INTO sessions VALUES (?, ?, ?)', 'old', 'u1', clock - 1);
  sql.exec('INSERT INTO sessions VALUES (?, ?, ?)', 'live', 'u1', clock + 1000);
  new Records(state as any, {} as any);
  assert.deepEqual(sql.exec('SELECT token FROM sessions').toArray().map((r: any) => r.token), ['live']);
});
