/* INSURE QUEST | Records Durable Object: accounts, login sessions, daily AI quota, and training records (SQLite).
 * Supports dual-track sharding (User Sharding):
 * 1. Personal DO shard (idFromName('user:' + userId)): 10 GB SQLite storage per user, storing full decision history and daily AI quota.
 * 2. Global DO instance (idFromName('global')): stores accounts, login sessions, and lightweight record summaries (for trainer backend cross-learner aggregation).
 * Retains class name Records, no need to create D1 or modify Durable Object migrations.
 */
import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index.ts';
import { buildProfile, type RecordRow } from './game/profile.ts';
import { TAG_INFO } from './game/game.ts';

export interface RecordInput { name: string; ts: number; score: number; grade: string; players: number; data: unknown; userId: string; room?: string }
export interface RecordSummary {
  name: string;
  ts: number;
  score: number;
  grade: string;
  players: number;
  userId: string;
  room?: string;
  tags?: string[];
  sessions?: number;
  violations?: number;
  warnings?: number;
}
export interface User { id: string; email: string; name: string; picture: string | null }

export interface TagInsight {
  tag: string;
  label: string;
  count: number;
  learners: number;
}

export interface LearnerMatrixRow {
  userId: string;
  name: string;
  sessions: number;
  tags: Record<string, number>;
}

export interface InsightsResult {
  learners: number;
  sessions: number;
  tags: TagInsight[];
  matrix: LearnerMatrixRow[];
  compliance: {
    violations: number;
    warnings: number;
    sessions: number;
  };
}

const SESSION_DAYS = 30;
/** AI usage rows (quota and per-provider calls) are only shown for the last 7 days, so older rows are deleted. */
export const AI_HISTORY_DAYS = 7;

/** Non-demo accounts that never finished a game are deleted by the monthly cleanup after this many days without login */
export const INACTIVE_NEVER_PLAYED_DAYS = 90;

/** NVIDIA NIM is outside the daily quota; each account may start at most one NIM call per second (extra calls queue) */
export const NIM_MIN_INTERVAL_MS = 1000;

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
  /** Earliest time this account's next NIM call may start (in memory; the personal shard is single-threaded) */
  private nimNextSlot = 0;
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS records (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ts INTEGER, score INTEGER, grade TEXT, players INTEGER, data TEXT, user_id TEXT)`);
    // Backfill columns if legacy table lacks them
    const cols = sql.exec('PRAGMA table_info(records)').toArray().map(r => String(r.name));
    if (!cols.includes('user_id')) sql.exec('ALTER TABLE records ADD COLUMN user_id TEXT');
    if (!cols.includes('tags')) sql.exec('ALTER TABLE records ADD COLUMN tags TEXT');
    if (!cols.includes('sessions')) sql.exec('ALTER TABLE records ADD COLUMN sessions INTEGER DEFAULT 0');
    if (!cols.includes('violations')) sql.exec('ALTER TABLE records ADD COLUMN violations INTEGER DEFAULT 0');
    if (!cols.includes('warnings')) sql.exec('ALTER TABLE records ADD COLUMN warnings INTEGER DEFAULT 0');
    sql.exec('CREATE INDEX IF NOT EXISTS records_user ON records(user_id, ts)');
    sql.exec(`CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT, name TEXT, picture TEXT, created_at INTEGER, last_login INTEGER)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_usage (user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day))`);
    // Track each successful AI call (including unmetered NVIDIA NIM) separated by provider
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_calls (user_id TEXT NOT NULL, day TEXT NOT NULL, provider TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day, provider))`);
    sql.exec(`CREATE TABLE IF NOT EXISTS demo_attempts (ip TEXT, ts INTEGER)`);
    sql.exec('CREATE INDEX IF NOT EXISTS demo_attempts_ip ON demo_attempts(ip, ts)');
    sql.exec(`CREATE TABLE IF NOT EXISTS demo_accounts (code TEXT, user_id TEXT, ts INTEGER)`);
    sql.exec('CREATE INDEX IF NOT EXISTS demo_accounts_code ON demo_accounts(code)');
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

  createSession(userId: string, days = SESSION_DAYS): string {
    const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
    this.ctx.storage.sql.exec('INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)', token, userId, Date.now() + days * 86400_000);
    // Clean up expired sessions opportunistically
    this.ctx.storage.sql.exec('DELETE FROM sessions WHERE expires_at < ?', Date.now());
    return token;
  }

  /* ───────── Demo Auth & Rate Limiting ───────── */

  checkDemoRateLimit(ip: string): boolean {
    const hourAgo = Date.now() - 3600_000;
    this.ctx.storage.sql.exec('DELETE FROM demo_attempts WHERE ts < ?', hourAgo);
    const row = this.ctx.storage.sql.exec('SELECT COUNT(*) AS c FROM demo_attempts WHERE ip = ? AND ts >= ?', ip, hourAgo).toArray()[0];
    return (Number(row?.c) || 0) < 10;
  }

  recordDemoAttempt(ip: string) {
    this.ctx.storage.sql.exec('INSERT INTO demo_attempts (ip, ts) VALUES (?, ?)', ip, Date.now());
  }

  demoAccountCount(code: string): number {
    const row = this.ctx.storage.sql.exec('SELECT COUNT(*) AS c FROM demo_accounts WHERE code = ?', code).toArray()[0];
    return Number(row?.c) || 0;
  }

  recordDemoAccount(code: string, userId: string) {
    this.ctx.storage.sql.exec('INSERT INTO demo_accounts (code, user_id, ts) VALUES (?, ?, ?)', code, userId, Date.now());
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

  /** Personal shard DO wipe: clears all stored data */
  async wipe(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }

  /** Completely deletes all data belonging to a single user in both global DO and their personal shard */
  async deleteUserData(userId: string): Promise<void> {
    this.ctx.storage.sql.exec('DELETE FROM users WHERE id = ?', userId);
    this.ctx.storage.sql.exec('DELETE FROM sessions WHERE user_id = ?', userId);
    this.ctx.storage.sql.exec('DELETE FROM demo_accounts WHERE user_id = ?', userId);
    this.ctx.storage.sql.exec('DELETE FROM records WHERE user_id = ?', userId);
    this.ctx.storage.sql.exec('DELETE FROM ai_usage WHERE user_id = ?', userId);
    this.ctx.storage.sql.exec('DELETE FROM ai_calls WHERE user_id = ?', userId);
    if (this.env?.RECORDS) {
      await userRecords(this.env, userId).wipe().catch(() => {});
    }
  }

  /**
   * Daily purge for demo users older than 7 days.
   * Cleans global records, sessions, demo_accounts, ai_usage, ai_calls, and wipes each personal shard.
   * Also prunes demo_attempts older than 1 hour.
   */
  async purgeStaleDemoUsers(limit = 200, now = Date.now()): Promise<string[]> {
    const cutoff = now - 7 * 86_400_000;
    const hourAgo = now - 3600_000;
    this.ctx.storage.sql.exec('DELETE FROM demo_attempts WHERE ts < ?', hourAgo);

    const rows = this.ctx.storage.sql.exec(
      "SELECT id FROM users WHERE id LIKE 'demo:%' AND created_at < ? ORDER BY created_at ASC LIMIT ?",
      cutoff, limit
    ).toArray();
    const purged: string[] = [];
    for (const r of rows) {
      const uid = String(r.id);
      await this.deleteUserData(uid);
      purged.push(uid);
    }

    if (purged.length < limit) {
      const remainingLimit = limit - purged.length;
      const demoAccRows = this.ctx.storage.sql.exec(
        "SELECT DISTINCT user_id FROM demo_accounts WHERE ts < ? AND user_id LIKE 'demo:%' LIMIT ?",
        cutoff, remainingLimit
      ).toArray();
      for (const r of demoAccRows) {
        const uid = String(r.user_id);
        if (!purged.includes(uid)) {
          await this.deleteUserData(uid);
          purged.push(uid);
        }
      }
    }
    return purged;
  }

  /**
   * Monthly cleanup: deletes non-demo accounts that never finished a game, have no valid session and have not logged in
   * for INACTIVE_NEVER_PLAYED_DAYS. Logging in with Google again simply recreates the account.
   * The personal shard is checked too, so an account whose global summary write failed is never mistaken for "never played".
   */
  async purgeInactiveNeverPlayed(limit = 200, now = Date.now()): Promise<string[]> {
    const cutoff = now - INACTIVE_NEVER_PLAYED_DAYS * 86_400_000;
    const rows = this.ctx.storage.sql.exec(
      `SELECT u.id FROM users u
       WHERE u.id NOT LIKE 'demo:%' AND COALESCE(u.last_login, u.created_at, 0) < ?
         AND NOT EXISTS (SELECT 1 FROM records r WHERE r.user_id = u.id)
         AND NOT EXISTS (SELECT 1 FROM sessions s WHERE s.user_id = u.id AND s.expires_at > ?)
       ORDER BY u.last_login ASC LIMIT ?`,
      cutoff, now, limit,
    ).toArray();
    const purged: string[] = [];
    for (const r of rows) {
      const uid = String(r.id);
      const played = await userRecords(this.env, uid).xpSummary(uid).then(x => x.games > 0).catch(() => true);
      if (played) continue;
      await this.deleteUserData(uid);
      purged.push(uid);
    }
    return purged;
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

  /** Reserves this account's next NIM slot (one per second) and returns how many ms the caller must wait first */
  reserveUnmetered(_provider = 'nvidia-nim', now = Date.now()): number {
    const start = Math.max(now, this.nimNextSlot);
    this.nimNextSlot = start + NIM_MIN_INTERVAL_MS;
    return start - now;
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
    this.ctx.storage.sql.exec(
      'INSERT INTO records (name, ts, score, grade, players, data, user_id, tags, sessions, violations, warnings) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?)',
      r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, r.userId,
      r.tags ? JSON.stringify(r.tags) : null,
      r.sessions ?? 0,
      r.violations ?? 0,
      r.warnings ?? 0,
    );
  }

  /** Trainer insights: aggregated metrics, top weakness tags, matrix, and compliance for the last 30 days */
  insights(): InsightsResult {
    const since = Date.now() - 30 * 86_400_000;
    const rows = this.ctx.storage.sql.exec(
      `SELECT r.id, r.user_id, r.name, r.ts, r.tags, r.sessions, r.violations, r.warnings, r.data, u.name AS u_name
       FROM records r
       LEFT JOIN users u ON u.id = r.user_id
       WHERE r.ts >= ?`,
      since
    ).toArray();

    const userIds = new Set<string>();
    let totalSessions = 0;
    let totalViolations = 0;
    let totalWarnings = 0;

    const tagTotalCounts = new Map<string, number>();
    const tagLearners = new Map<string, Set<string>>();

    const userMap = new Map<string, {
      name: string;
      sessions: number;
      tags: Record<string, number>;
    }>();

    for (const row of rows) {
      const uid = String(row.user_id || '');
      if (uid) userIds.add(uid);

      let sCount = Number(row.sessions) || 0;
      let rViolations = Number(row.violations) || 0;
      let rWarnings = Number(row.warnings) || 0;
      let tagList: string[] = [];

      if (row.tags) {
        try {
          const parsed = JSON.parse(String(row.tags));
          if (Array.isArray(parsed)) tagList = parsed;
        } catch {}
      } else if (row.data) {
        try {
          const d = JSON.parse(String(row.data));
          if (Array.isArray(d.sessions)) {
            tagList = d.sessions.flatMap((s: any) => s.tags || []);
            if (!sCount) sCount = d.sessions.length;
            if (!rViolations) rViolations = d.sessions.reduce((acc: number, s: any) => acc + (Number(s.violations) || 0), 0);
            if (!rWarnings) rWarnings = d.sessions.reduce((acc: number, s: any) => acc + (Number(s.warnings) || 0), 0);
          }
        } catch {}
      }

      if (sCount === 0) sCount = 1;
      totalSessions += sCount;
      totalViolations += rViolations;
      totalWarnings += rWarnings;

      if (uid) {
        let uEntry = userMap.get(uid);
        if (!uEntry) {
          uEntry = {
            name: String(row.u_name || row.name || '學員'),
            sessions: 0,
            tags: {},
          };
          userMap.set(uid, uEntry);
        }
        uEntry.sessions += sCount;
        for (const t of tagList) {
          uEntry.tags[t] = (uEntry.tags[t] || 0) + 1;
        }
      }

      for (const t of tagList) {
        tagTotalCounts.set(t, (tagTotalCounts.get(t) || 0) + 1);
        if (uid) {
          let set = tagLearners.get(t);
          if (!set) {
            set = new Set();
            tagLearners.set(t, set);
          }
          set.add(uid);
        }
      }
    }

    const tags: TagInsight[] = Array.from(tagTotalCounts.entries())
      .map(([tag, count]) => ({
        tag,
        label: TAG_INFO[tag]?.label ?? tag,
        count,
        learners: tagLearners.get(tag)?.size ?? 0,
      }))
      .sort((a, b) => b.count - a.count);

    const matrix: LearnerMatrixRow[] = Array.from(userMap.entries())
      .map(([userId, entry]) => ({
        userId,
        name: entry.name,
        sessions: entry.sessions,
        tags: entry.tags,
      }))
      .sort((a, b) => b.sessions - a.sessions)
      .slice(0, 30);

    return {
      learners: userIds.size,
      sessions: totalSessions,
      tags,
      matrix,
      compliance: {
        violations: totalViolations,
        warnings: totalWarnings,
        sessions: totalSessions,
      },
    };
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
