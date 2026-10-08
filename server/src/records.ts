/* INSURE QUEST｜Records Durable Object：帳號、登入工作階段、每日 AI 額度與培訓紀錄（SQLite）。
 * 全域只有一個實例（idFromName('global')），不需另外建立 D1，部署維持一次完成。
 * 類別名稱沿用 Records，避免新增 Durable Object 遷移。
 */
import { DurableObject } from 'cloudflare:workers';
import type { Env } from './index.ts';
import { buildProfile, type RecordRow } from './game/profile.ts';

export interface RecordInput { room: string; name: string; ts: number; score: number; grade: string; players: number; data: unknown; userId: string }
export interface User { id: string; email: string; name: string; picture: string | null }

const SESSION_DAYS = 30;

/** 以台北時間計算「今天」，額度在台灣午夜重置 */
export function taipeiDay(now = Date.now()): string {
  return new Date(now + 8 * 3600_000).toISOString().slice(0, 10);
}

export class Records extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    const sql = ctx.storage.sql;
    sql.exec(`CREATE TABLE IF NOT EXISTS records (
      id INTEGER PRIMARY KEY AUTOINCREMENT, room TEXT, name TEXT, ts INTEGER, score INTEGER, grade TEXT, players INTEGER, data TEXT)`);
    // 舊資料表沒有 user_id 欄位時補上
    const cols = sql.exec('PRAGMA table_info(records)').toArray().map(r => String(r.name));
    if (!cols.includes('user_id')) sql.exec('ALTER TABLE records ADD COLUMN user_id TEXT');
    sql.exec('CREATE INDEX IF NOT EXISTS records_user ON records(user_id, ts)');
    sql.exec(`CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT, name TEXT, picture TEXT, created_at INTEGER, last_login INTEGER)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, expires_at INTEGER NOT NULL)`);
    sql.exec(`CREATE TABLE IF NOT EXISTS ai_usage (user_id TEXT NOT NULL, day TEXT NOT NULL, count INTEGER NOT NULL, PRIMARY KEY (user_id, day))`);
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

  /* ───────── 培訓紀錄 ───────── */

  add(r: RecordInput) {
    this.ctx.storage.sql.exec('INSERT INTO records (room, name, ts, score, grade, players, data, user_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      r.room, r.name.slice(0, 24), r.ts, r.score, r.grade, r.players, JSON.stringify(r.data), r.userId);
  }

  /** 學習檔案：趨勢、弱點、客戶圖鑑、徽章 */
  profile(userId: string) {
    const rows = this.ctx.storage.sql.exec('SELECT ts, score, grade, data FROM records WHERE user_id = ? ORDER BY ts DESC LIMIT 200', userId).toArray();
    return buildProfile(rows.map(r => ({ ts: Number(r.ts), score: Number(r.score), grade: String(r.grade), data: JSON.parse(String(r.data)) }) as RecordRow));
  }

  /** 講師用：有紀錄的學員清單 */
  learners() {
    return this.ctx.storage.sql.exec(
      `SELECT u.id, u.name, u.email, COUNT(r.id) AS games, ROUND(AVG(r.score)) AS avg, MAX(r.ts) AS last
       FROM users u JOIN records r ON r.user_id = u.id GROUP BY u.id ORDER BY last DESC LIMIT 200`).toArray();
  }

  /** userId 有值時只回傳該帳號的紀錄；null 代表講師查詢全部 */
  list(userId: string | null, limit = 50) {
    const lim = Math.max(1, Math.min(200, limit));
    const rows = userId
      ? this.ctx.storage.sql.exec('SELECT * FROM records WHERE user_id = ? ORDER BY ts DESC LIMIT ?', userId, lim).toArray()
      : this.ctx.storage.sql.exec('SELECT * FROM records ORDER BY ts DESC LIMIT ?', lim).toArray();
    return rows.map(r => ({ id: r.id, userId: r.user_id, room: r.room, name: r.name, ts: r.ts, score: r.score, grade: r.grade, players: r.players, data: JSON.parse(String(r.data)) }));
  }
}
