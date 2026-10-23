import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Records, type TrainingAttempt } from '../src/records.ts';
import { Room } from '../src/room.ts';
import worker from '../src/index.ts';
import { FakeState, type FakeSocket } from './helpers/fake-do.ts';

function fixture() {
  const shards = new Map<string, Records>();
  const env: any = { AI_PROVIDER: 'rules', RECORDS: {
    idFromName: (id: string) => id,
    get(id: string) {
      if (!shards.has(id)) shards.set(id, new Records(new FakeState() as any, env));
      return shards.get(id)!;
    },
  } };
  return { env, rec: (id = 'user:u1'): Records => env.RECORDS.get(id) };
}
const attempt = (overrides: Partial<TrainingAttempt> = {}): TrainingAttempt => ({
  attempt_id: 'training:player', userId: 'u1', status: 'in_progress', started_at: 1, updated_at: 2,
  room: 'ABCDE', name: '新人', round: 1, stage: 'roll', score: null, grade: null,
  data: { decisions: ['decision'] }, ...overrides,
});
const send = (room: Room, ws: FakeSocket, msg: unknown) => room.webSocketMessage(ws as any, JSON.stringify(msg));

test('attempt upsert preserves terminal status, owner isolation, paging, deletion and scored-record idempotence', async () => {
  const { rec } = fixture();
  const r = rec();
  r.saveAttempt(attempt());
  r.saveAttempt(attempt({ status: 'completed', updated_at: 3, score: 70, grade: 'B' }));
  r.saveAttempt(attempt({ updated_at: 4 }));
  assert.equal(r.getAttempt('u1', 'training:player')?.status, 'completed');
  assert.equal(r.getAttempt('u2', 'training:player'), null);
  r.saveAttempt(attempt({ attempt_id: 'other', started_at: 5 }));
  assert.equal(r.listAttempts('u1', 1).next_offset, 1);
  assert.equal(r.listAttempts('u1', 1, 1).attempts[0].attempt_id, 'training:player');
  assert.equal('data' in r.listAttempts('u1').attempts[0], false);
  const final = { attemptId: 'training:player', name: '新人', ts: 1, score: 70, grade: 'B', players: 1, data: {}, userId: 'u1' };
  r.add(final); r.add(final);
  assert.equal(r.list('u1', 100).length, 1);
  const summary = rec('global');
  summary.addSummary(final); summary.addSummary(final);
  assert.equal(summary.list('u1', 100).length, 1);
  await r.deleteUserData('u1');
  assert.equal(r.listAttempts('u1').attempts.length, 0);
});

test('attempt API requires owner session, decodes IDs, and refuses cross-user/all queries', async () => {
  const { env, rec } = fixture();
  const global = rec('global');
  global.upsertUser({ id: 'u1', name: 'Owner', email: 'owner@test', picture: null });
  const token = global.createSession('u1');
  rec().saveAttempt(attempt());
  const get = (path: string, authenticated = true) => worker.fetch(new Request('https://game.test/api/training-attempts' + path,
    { headers: authenticated ? { cookie: `iq_session=${token}` } : {} }), env);
  assert.equal((await get('', false)).status, 401);
  assert.equal((await get('?user=u2')).status, 403);
  assert.equal((await get('?scope=all')).status, 403);
  assert.equal((await get('/unknown')).status, 404);
  assert.equal((await get('/bad%ZZ')).status, 400);
  const detail = await get('/training%3Aplayer');
  assert.equal(detail.status, 200);
  assert.equal((await detail.json() as any).attempt.attempt_id, 'training:player');
});

test('room checkpoints authoritative state; failed abandonment survives and retries without accepting client scores', async () => {
  const { env, rec } = fixture();
  const state = new FakeState();
  const room = new Room(state as any, env);
  await state.ready;
  await room.fetch(new Request('https://room/init', { method: 'POST', body: JSON.stringify({ code: 'ABCDE', solo: true }) }));
  const ws = state.connect({ id: 'u1', name: '新人' });
  await send(room, ws, { t: 'hello', name: '新人' });
  await send(room, ws, { t: 'start' });
  const g = (room as any).game;
  const id = `${g.trainingAttemptId}:${g.players[0].id}`;
  assert.equal(ws.last('state').state.trainingAttemptId, id);
  assert.equal(rec().getAttempt('u1', id)?.status, 'in_progress');
  const intruder = state.connect({ id: 'u2', name: 'Other' });
  await send(room, intruder, { t: 'retry_save', score: 999 });
  assert.equal(intruder.last('error').t, 'error');
  await send(room, ws, { t: 'retry_save', score: 999, data: { decisions: ['forged'] } });
  assert.equal(rec().getAttempt('u1', id)?.score, null);
  assert.deepEqual((rec().getAttempt('u1', id)?.data as any).decisions, g.players[0].decisions);
  const save = rec().saveAttempt.bind(rec());
  rec().saveAttempt = () => { throw new Error('simulated storage outage'); };
  await send(room, ws, { t: 'abandon' });
  assert.ok(state.kv.has('game'), 'terminal snapshot must survive a failed write');
  assert.ok(state.alarm);
  assert.equal(ws.last('training_saved').status, 'failed');
  rec().saveAttempt = save;
  await room.alarm();
  assert.equal(rec().getAttempt('u1', id)?.status, 'abandoned');
  assert.equal(state.kv.size, 0);
  assert.equal(rec().list('u1', 100).length, 0, 'abandonment must not fabricate a final score');
});
