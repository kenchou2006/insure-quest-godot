/* INSURE QUEST｜Records Durable Object：帳號、登入工作階段、每日 AI 額度與培訓紀錄（SQLite）。
 * 支援雙軌制切片（User Sharding）：
 * 1. 個人 DO 切片（idFromName('user:' + userId)）：每位使用者獨享 10 GB SQLite 空間，儲存詳細決策軌跡與每日 AI 額度。
 * 2. 全域 DO 實例（idFromName('global')）：儲存帳號、登入工作階段，以及輕量紀錄摘要（供講師後台跨學員高效彙總）。
 * 類別名稱沿用 Records，不需建立 D1 或更動 Durable Object migrations。
 */
import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index.ts';
import { buildProfile, type RecordRow } from './game/profile.ts';

export interface RecordInput { name: string; ts: number; score: number; grade: string; players: number; data: unknown; userId: string; room?: string }
export interface RecordSummary { name: string; ts: number; score: number; grade: string; players: number; userId: string; room?: string }
export interface User { id: string; email: string; name: string; picture: string | null }

const SESSION_DAYS = 30;

/** 以台北時間計算「今天」，額度在台灣午夜重置 */
export function taipeiDay(now = Date.now()): string {
  return new Date(now + 8 * 3600_000).toISOString().slice(0, 10);
}

/** 取得個人專屬 DO 切片 Stub（每位使用者獨享 10 GB 儲存空間） */
export function userRecords(env: Env, userId: string) {
  return env.RECORDS.get(env.RECORDS.idFromName(`user:${userId}`));
}

/** 取得全域 DO 實例 Stub（帳號、工作階段與跨學員彙總摘要） */
export function globalRecords(env: Env) {
  return env.RECORDS.get(env.RECORDS.idFromName('global'));
}

export class Records extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS records (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, ts INTEGER, score INTEGER, grade TEXT, players INTEGER, data TEXT, user_id TEXT)`);
    // 舊資料表沒有 user_id 欄位時補上
    const cols = sql.exec('PRAGMA table_info(records)').toArray().map(r => String(r.name));
    if (!cols.includes('user_id')) sql.exec('ALTER TABLE records ADD COLUMN user_id TEXT');
    sql.exec('CREATE INDEX IF NOT EXISTS records_user ON records(user_id, ts)');
    sql.exec(`CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT, name TEXT, picture TEXT, created_at INTEGER, last_login INTEGER)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_usage (user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day))`);
    // 每次成功的 AI 呼叫（含不計額度的 NVIDIA NIM），依供應者分開統計
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_calls (user_id TEXT NOT NULL, day TEXT NOT NULL, provider TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day, provider))`);
  }

  /* ───────── 帳號與工作階段 ───────── */

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
    // 順便清除過期工作階段
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

  /* ───────── 每日 AI 額度 ───────── */

  aiUsage(userId: string): number {
    const row = this.ctx.storage.sql.exec('SELECT count FROM ai_usage WHERE user_id = ? AND day = ?', userId, taipeiDay()).toArray()[0];
    return row ? Number(row.count) : 0;
  }

  /** 原子地扣一次額度；超過上限時不扣並回傳 ok=false。DO 單執行緒，讀寫之間不會被插隊。 */
  consumeAi(userId: string, limit: number): { ok: boolean; used: number } {
    const used = this.aiUsage(userId);
    if (used >= limit) return { ok: false, used };
    this.ctx.storage.sql.exec(
      `INSERT INTO ai_usage (user_id, day, count) VALUES (?, ?, 1) ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1`,
      userId, taipeiDay());
    return { ok: true, used: used + 1 };
  }

  /** AI 呼叫失敗時退還額度 */
  refundAi(userId: string): number {
    this.ctx.storage.sql.exec('UPDATE ai_usage SET count = MAX(0, count - 1) WHERE user_id = ? AND day = ?', userId, taipeiDay());
    return this.aiUsage(userId);
  }

  recordAiCall(userId: string, provider: string) {
    this.ctx.storage.sql.exec(
      `INSERT INTO ai_calls (user_id, day, provider, count) VALUES (?, ?, ?, 1) ON CONFLICT(user_id, day, provider) DO UPDATE SET count = count + 1`,
      userId, taipeiDay(), provider.slice(0, 32));
  }

  /** 近 N 天（台北日期）：每天計入額度的次數與各供應者的實際呼叫次數 */
  aiHistory(userId: string, days = 7) {
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

  /* ───────── 培訓紀錄 ───────── */

  /** 完整紀錄寫入（由個人切片 DO 呼叫，保存完整決策軌跡與情境） */
  add(r: RecordInput) {
    this.ctx.storage.sql.exec('INSERT INTO records (name, ts, score, grade, players, data, user_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
      r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, JSON.stringify(r.data), r.userId);
  }

  /** 輕量摘要寫入（由全域 DO 呼叫，不含大體積 data，專供講師後台極速統計） */
  addSummary(r: RecordSummary) {
    this.ctx.storage.sql.exec('INSERT INTO records (name, ts, score, grade, players, data, user_id) VALUES (?, ?, ?, ?, ?, NULL, ?)',
      r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, r.userId);
  }

  /** 學習檔案：趨勢、弱點、客戶圖鑑、徽章（只計算含完整 data 的紀錄） */
  profile(userId: string) {
    const rows = this.ctx.storage.sql.exec('SELECT ts, score, grade, data FROM records WHERE user_id = ? AND data IS NOT NULL ORDER BY ts DESC LIMIT 200', userId).toArray();
    return buildProfile(rows.map(r => ({ ts: Number(r.ts), score: Number(r.score), grade: String(r.grade), data: JSON.parse(String(r.data)) }) as RecordRow));
  }

  /** 等級用：已完成對局數與分數總和（只算含完整 data 的紀錄，避免全域摘要重複計算） */
  xpSummary(userId: string) {
    const r = this.ctx.storage.sql.exec('SELECT COUNT(*) AS games, COALESCE(SUM(score), 0) AS xp FROM records WHERE user_id = ? AND data IS NOT NULL', userId).one();
    return { games: Number(r.games), xp: Number(r.xp) };
  }

  /** 講師用：有紀錄的學員清單（由全域 DO 提供聚合清單） */
  learners() {
    return this.ctx.storage.sql.exec(
      `SELECT u.id, u.name, u.email, COUNT(r.id) AS games, ROUND(AVG(r.score)) AS avg, MAX(r.ts) AS last
       FROM users u JOIN records r ON r.user_id = u.id GROUP BY u.id ORDER BY last DESC LIMIT 200`).toArray();
  }

  /** userId 有值時只回傳該帳號的紀錄；null 代表講師查詢全部摘要 */
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
