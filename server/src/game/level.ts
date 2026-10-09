/* INSURE QUEST | Advisor levels: XP = sum of scores across login matches (0-100 per game). */

export const LEVELS = [
  { min: 0, title: '見習顧問' },
  { min: 150, title: '新秀顧問' },
  { min: 400, title: '專業顧問' },
  { min: 800, title: '資深顧問' },
  { min: 1400, title: '金牌顧問' },
  { min: 2200, title: '首席顧問' },
] as const;

export interface LevelInfo { level: number; title: string; xp: number; floor: number; next: number | null; games: number }

export function levelFor(xp: number, games = 0): LevelInfo {
  const x = Math.max(0, Math.round(xp));
  let i = 0;
  while (i + 1 < LEVELS.length && x >= LEVELS[i + 1].min) i++;
  return { level: i + 1, title: LEVELS[i].title, xp: x, floor: LEVELS[i].min, next: LEVELS[i + 1]?.min ?? null, games };
}
