/* INSURE QUEST | Learning profile: aggregates training records across matches into actionable feedback (pure functions, unit testable).
 * The valuable preservation focus is not the "score", but decision traces of each interview: deriving weakness tags, growth trends, client pokedex, and badges.
 */
import type { Metrics, SessionLog } from './types.ts';
import { CLIENTS } from './data.ts';
import { TAG_INFO } from './game.ts';

export interface RecordRow {
  ts: number; score: number; grade: string;
  data: { skill?: Metrics; service?: number; sessions?: SessionLog[]; quizCorrect?: number; quizTotal?: number };
}

const GRADE_ORDER = ['C', 'B', 'A', 'S'];
const better = (a: string, b: string) => (GRADE_ORDER.indexOf(a) >= GRADE_ORDER.indexOf(b) ? a : b);

export const BADGES = [
  { id: 'first_s', title: '首張 S 級面談', desc: '任一場客戶面談拿到 S 評級' },
  { id: 'no_hint_s', title: '獨立判斷', desc: '不使用教練提示拿到 S 評級' },
  { id: 'clean_3', title: '合規零違規 ×3', desc: '累計 3 場遊戲沒有任何不當說法' },
  { id: 'service_star', title: '客戶滿意之星', desc: '單場遊戲客戶平均滿意度達 85' },
  { id: 'collector_10', title: '客戶圖鑑 10 位', desc: '服務過 10 位不同的客戶' },
  { id: 'collector_all', title: '全客戶制霸', desc: '服務過所有內建客戶' },
  { id: 'quiz_master', title: '合規小博士', desc: '合規測驗累計答對 10 題且正確率 80% 以上' },
  { id: 'growth', title: '持續進步', desc: '最近一場分數比第一場高 15 分以上' },
] as const;

export function buildProfile(rowsNewestFirst: RecordRow[]) {
  const rows = [...rowsNewestFirst].sort((a, b) => a.ts - b.ts);
  const sessions = rows.flatMap(r => r.data.sessions ?? []);

  const mistakeCount = new Map<string, number>();
  for (const s of sessions) for (const t of s.tags) mistakeCount.set(t, (mistakeCount.get(t) ?? 0) + 1);
  const mistakes = [...mistakeCount.entries()]
    .filter(([t]) => TAG_INFO[t])
    .sort((a, b) => b[1] - a[1])
    .map(([tag, count]) => ({ tag, label: TAG_INFO[tag].label, count, advice: TAG_INFO[tag].advice }));

  const served = new Map<string, { served: number; best: string }>();
  for (const s of sessions) {
    const cur = served.get(s.clientId) ?? { served: 0, best: '' };
    served.set(s.clientId, { served: cur.served + 1, best: cur.best ? better(cur.best, s.grade) : s.grade });
  }
  const clients = CLIENTS.map(c => ({ id: c.id, name: c.name, job: c.job, served: served.get(c.id)?.served ?? 0, bestGrade: served.get(c.id)?.best ?? '' }));
  const distinctServed = clients.filter(c => c.served > 0).length;

  const quiz = rows.reduce((q, r) => ({ correct: q.correct + (r.data.quizCorrect ?? 0), total: q.total + (r.data.quizTotal ?? 0) }), { correct: 0, total: 0 });
  const cleanGames = rows.filter(r => (r.data.sessions?.length ?? 0) > 0 && r.data.sessions!.every(s => !s.tags.includes('non_compliant'))).length;
  const earned: Record<string, boolean> = {
    first_s: sessions.some(s => s.grade === 'S'),
    no_hint_s: sessions.some(s => s.grade === 'S' && !s.hintUsed),
    clean_3: cleanGames >= 3,
    service_star: rows.some(r => (r.data.service ?? 0) >= 85),
    collector_10: distinctServed >= 10,
    collector_all: distinctServed >= CLIENTS.length,
    quiz_master: quiz.correct >= 10 && quiz.correct / Math.max(1, quiz.total) >= 0.8,
    growth: rows.length >= 2 && rows[rows.length - 1].score - rows[0].score >= 15,
  };

  return {
    games: rows.length,
    avgScore: rows.length ? Math.round(rows.reduce((t, r) => t + r.score, 0) / rows.length) : 0,
    bestGrade: rows.reduce((g, r) => (g ? better(g, r.grade) : r.grade), ''),
    trend: rows.slice(-20).map(r => ({ ts: r.ts, score: r.score, grade: r.grade, skill: r.data.skill ?? null })),
    mistakes,
    clients,
    badges: BADGES.map(b => ({ ...b, earned: !!earned[b.id] })),
    quiz,
  };
}
