/* INSURE QUEST | Records Durable Object: accounts, login sessions, daily AI quota, and training records (SQLite).
 * Supports dual-track sharding (User Sharding):
 * 1. Personal DO shard (idFromName('user:' + userId)): 10 GB SQLite storage per user, storing full decision history and daily AI quota.
 * 2. Global DO instance (idFromName('global')): stores accounts, login sessions, and lightweight record summaries (for trainer backend cross-learner aggregation).
 * Retains class name Records, no need to create D1 or modify Durable Object migrations.
 */
import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index.ts';
import { buildProfile, type RecordRow } from './game/profile.ts';

export interface RecordInput { name: string; ts: number; score: number; grade: string; players: number; data: unknown; userId: string; room?: string }
export interface RecordSummary { name: string; ts: number; score: number; grade: string; players: number; userId: string; room?: string }
export interface User { id: string; email: string; name: string; picture: string | null }

const SESSION_DAYS = 30;
/** AI usage rows (quota and per-provider calls) are only shown for the last 7 days, so older rows are deleted. */
export const AI_HISTORY_DAYS = 7;

/** Calculate "today" in Taipei time, quota resets at Taiwan midnight */
export function taipeiDay(now = Date.now()): string {
  return new Date(now + 8 * 3600_000).toISOString().slice(0, 10);
}

/** Get personal standalone DO shard stub (dedicated 10 GB storage per user) */
export function userRecords(env: Env, userId: string) {
  return env.RECORDS.get(env.RECORDS.idFromName(`user:${userId}`));
}

/** Get global DO instance stub (accounts, sessions, and cross-learner aggregation summaries) */
export function globalRecords(env: Env) {
  return env.RECORDS.get(env.RECORDS.idFromName('global'));
}

export class Records extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS records (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ts INTEGER, score INTEGER, grade TEXT, players INTEGER, data TEXT, user_id TEXT)`);
    // Backfill user_id column if legacy table lacks it
    const cols = sql.exec('PRAGMA table_info(records)').toArray().map(r => String(r.name));
    if (!cols.includes('user_id')) sql.exec('ALTER TABLE records ADD COLUMN user_id TEXT');
    sql.exec('CREATE INDEX IF NOT EXISTS records_user ON records(user_id, ts)');
    sql.exec(`CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT, name TEXT, picture TEXT, created_at INTEGER, last_login INTEGER)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_usage (user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day))`);
    // Track each successful AI call (including unmetered NVIDIA NIM) separated by provider
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_calls (user_id TEXT NOT NULL, day TEXT NOT NULL, provider TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day, provider))`);
    // Runs on every wake-up of this DO, so stale rows never accumulate (also covers rows left in the global DO before sharding).
    this.pruneAiHistory();
    sql.exec('DELETE FROM sessions WHERE expires_at < ?', Date.now());
  }

  /** Delete AI usage rows older than AI_HISTORY_DAYS (Taipei dates; 'YYYY-MM-DD' strings compare correctly). */
  pruneAiHistory(now = Date.now()) {
    const oldest = taipeiDay(now - (AI_HISTORY_DAYS - 1) * 86_400_000);
    this.ctx.storage.sql.exec('DELETE FROM ai_usage WHERE day < ?', oldest);
    this.ctx.storage.sql.exec('DELETE FROM ai_calls WHERE day < ?', oldest);
  }

  /* ───────── Accounts & Sessions ───────── */

  upsertUser(u: User): User {
    const now = Date.now();
    this.ctx.storage.sql.exec(
      `INSERT INTO users (id, email, name, picture, created_at, last_login) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET email = excluded.email, name = excluded.name, picture = excluded.picture, last_login = excluded.last_login`,
      u.id, u.email, u.name.slice(0, 40), u.picture, now, now);
    return u;
  }

  createSession(userId: string): string {
    const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
    this.ctx.storage.sql.exec('INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)', token, userId, Date.now() + SESSION_DAYS * 86400_000);
    // Clean up expired sessions opportunistically
    this.ctx.storage.sql.exec('DELETE FROM sessions WHERE expires_at < ?', Date.now());
    return token;
  }

  getSessionUser(token: string): User | null {
    if (!/^[0-9a-f]{64}$/.test(token)) return null;
    const row = this.ctx.storage.sql.exec(
      `SELECT u.id, u.email, u.name, u.picture FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ? AND s.expires_at > ?`,
      token, Date.now()).toArray()[0];
    return row ? { id: String(row.id), email: String(row.email), name: String(row.name), picture: row.picture ? String(row.picture) : null } : null;
  }

  deleteSession(token: string) {
    this.ctx.storage.sql.exec('DELETE FROM sessions WHERE token = ?', token);
  }

  /* ───────── Daily AI Quota ───────── */

  aiUsage(userId: string): number {
    const row = this.ctx.storage.sql.exec('SELECT count FROM ai_usage WHERE user_id = ? AND day = ?', userId, taipeiDay()).toArray()[0];
    return row ? Number(row.count) : 0;
  }

  /** Atomically consume quota once; if limit exceeded, do not consume and return ok=false. DO is single-threaded, no interleaved reads/writes. */
  consumeAi(userId: string, limit: number): { ok: boolean; used: number } {
    const used = this.aiUsage(userId);
    if (used >= limit) return { ok: false, used };
    this.ctx.storage.sql.exec(
      `INSERT INTO ai_usage (user_id, day, count) VALUES (?, ?, 1) ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1`,
      userId, taipeiDay());
    this.pruneAiHistory();
    return { ok: true, used: used + 1 };
  }

  /** Refund quota when AI call fails */
  refundAi(userId: string): number {
    this.ctx.storage.sql.exec('UPDATE ai_usage SET count = MAX(0, count - 1) WHERE user_id = ? AND day = ?', userId, taipeiDay());
    return this.aiUsage(userId);
  }

  recordAiCall(userId: string, provider: string) {
    this.ctx.storage.sql.exec(
      `INSERT INTO ai_calls (user_id, day, provider, count) VALUES (?, ?, ?, 1) ON CONFLICT(user_id, day, provider) DO UPDATE SET count = count + 1`,
      userId, taipeiDay(), provider.slice(0, 32));
  }

  /** Last N days (Taipei dates): quota calls and actual calls per provider each day */
  aiHistory(userId: string, days = AI_HISTORY_DAYS) {
    const out: { day: string; quota: number; calls: Record<string, number> }[] = [];
    for (let i = days - 1; i >= 0; i--) {
      const day = taipeiDay(Date.now() - i * 86_400_000);
      const q = this.ctx.storage.sql.exec('SELECT count FROM ai_usage WHERE user_id = ? AND day = ?', userId, day).toArray()[0];
      const calls: Record<string, number> = {};
      for (const r of this.ctx.storage.sql.exec('SELECT provider, count FROM ai_calls WHERE user_id = ? AND day = ?', userId, day).toArray()) calls[String(r.provider)] = Number(r.count);
      out.push({ day, quota: q ? Number(q.count) : 0, calls });
    }
    return out;
  }

  /* ───────── Training Records ───────── */

  /** Full record write (called by personal shard DO, preserves full decision history and context) */
  add(r: RecordInput) {
    this.ctx.storage.sql.exec('INSERT INTO records (name, ts, score, grade, players, data, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
      r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, JSON.stringify(r.data), r.userId);
  }

  /** Lightweight summary write (called by global DO, omits bulky data, for trainer backend rapid stats) */
  addSummary(r: RecordSummary) {
    this.ctx.storage.sql.exec('INSERT INTO records (name, ts, score, grade, players, data, user_id) VALUES (?, ?, ?, ?, ?, NULL, ?)',
      r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, r.userId);
  }

  /** Learning profile: trends, weaknesses, client catalog, badges (computes only records with full data) */
  profile(userId: string) {
    const rows = this.ctx.storage.sql.exec('SELECT ts, score, grade, data FROM records WHERE user_id = ? AND data IS NOT NULL ORDER BY ts DESC LIMIT 200', userId).toArray();
    return buildProfile(rows.map(r => ({ ts: Number(r.ts), score: Number(r.score), grade: String(r.grade), data: JSON.parse(String(r.data)) }) as RecordRow));
  }

  /** For level: completed game count and total score (computes only records with full data to prevent duplicate counting) */
  xpSummary(userId: string) {
    const r = this.ctx.storage.sql.exec('SELECT COUNT(*) AS games, COALESCE(SUM(score), 0) AS xp FROM records WHERE user_id = ? AND data IS NOT NULL', userId).one();
    return { games: Number(r.games), xp: Number(r.xp) };
  }

  /** For trainer: learner list with records (aggregated list provided by global DO) */
  learners() {
    return this.ctx.storage.sql.exec(
      `SELECT u.id, u.name, u.email, COUNT(r.id) AS games, ROUND(AVG(r.score)) AS avg, MAX(r.ts) AS last
       FROM users u JOIN records r ON r.user_id = u.id GROUP BY u.id ORDER BY last DESC LIMIT 200`).toArray();
  }

  /** Returns records for specified userId when present; null means trainer query for all summaries */
  list(userId: string | null, limit = 50) {
    const lim = Math.max(1, Math.min(200, limit));
    const rows = userId
      ? this.ctx.storage.sql.exec('SELECT * FROM records WHERE user_id = ? ORDER BY ts DESC LIMIT ?', userId, lim).toArray()
      : this.ctx.storage.sql.exec('SELECT * FROM records ORDER BY ts DESC LIMIT ?', lim).toArray();
    return rows.map(r => ({
      id: r.id, userId: r.user_id, name: r.name, ts: r.ts, score: r.score, grade: r.grade, players: r.players,
      data: r.data ? JSON.parse(String(r.data)) : null
    }));
  }
}
