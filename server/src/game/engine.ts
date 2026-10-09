/* INSURE QUEST | Scoring engine (pure functions). Ported from prototype engine.js, added single-event evaluation for board events. */
import type { Alloc, CardId, Changes, ClientProfile, Metric, Metrics, Quality, ResKey, StressEvent, MarketEvent } from './types.ts';

export const RES: ResKey[] = ['cash', 'protect', 'growth'];
export const METRICS: Metric[] = ['trust', 'insight', 'fit', 'risk', 'compliance'];
export const TOTAL_COINS = 10;
const CARD_BONUS = 2;
const CASH_CAP = 5;
export const START: Metrics = { trust: 50, insight: 20, fit: 50, risk: 30, compliance: 100 };
export const WEIGHTS: Metrics = { trust: 0.2, insight: 0.2, fit: 0.22, risk: 0.22, compliance: 0.16 };
export const RES_NAMES: Record<ResKey, string> = { cash: '緊急預備', protect: '風險保障', growth: '目標成長' };

export const clamp = (v: number) => Math.max(0, Math.min(100, Math.round(v)));

export function apply(m: Metrics, changes: Changes | undefined): Metrics {
  for (const [k, v] of Object.entries(changes || {})) {
    if (k in m) m[k as Metric] = clamp(m[k as Metric] + (v as number));
  }
  return m;
}

export function validPlan(alloc: Alloc, cards: CardId[], client: ClientProfile): string | null {
  const sum = RES.reduce((s, r) => s + alloc[r], 0);
  if (RES.some(r => !Number.isInteger(alloc[r]) || alloc[r] < 0)) return '資源幣必須是非負整數';
  if (sum !== TOTAL_COINS) return `資源幣總和必須是 ${TOTAL_COINS}`;
  if (cards.length < 2 || cards.length > 3) return '請選擇 2–3 張保障卡';
  if (new Set(cards).size !== cards.length) return '保障卡不可重複';
  if (cards.some(c => !(c in client.plan.cards))) return '未知的保障卡';
  return null;
}

export function evaluatePlan(client: ClientProfile, alloc: Alloc, cardIds: CardId[]) {
  const plan = client.plan;
  const notes: string[] = [];
  let allocDist = 0;
  const off = {} as Record<ResKey, 'low' | 'high' | 'ok'>;
  for (const r of RES) {
    const [min, max] = plan.ideal[r];
    allocDist += Math.max(0, min - alloc[r]) + Math.max(0, alloc[r] - max);
    off[r] = alloc[r] < min ? 'low' : alloc[r] > max ? 'high' : 'ok';
  }
  const cardScore = cardIds.reduce((s, id) => s + (plan.cards[id] || 0), 0);
  const over = cardIds.filter(id => (plan.cards[id] || 0) < 0);
  const core = cardIds.filter(id => (plan.cards[id] || 0) >= 3);
  const changes: Metrics = { trust: 0, insight: 0, fit: 0, risk: 0, compliance: 0 };

  changes.fit += allocDist === 0 ? 14 : Math.max(-14, 14 - allocDist * 5);
  changes.fit += cardScore * 2;
  changes.risk += alloc.cash >= plan.ideal.cash[0] ? 7 : -6;
  changes.risk += alloc.protect >= plan.ideal.protect[0] ? 7 : -6;
  if (alloc.growth > plan.ideal.growth[1]) changes.risk -= 5;
  changes.risk += core.length ? 4 : -4;
  changes.trust += over.length ? -5 * over.length : 4;
  if (plan.overProtect && alloc.protect > plan.overProtect) {
    changes.trust -= 4; changes.fit -= 4;
    notes.push(`保障配置超過 ${plan.overProtect} 枚，對${client.short}的預算會形成壓力。`);
  }
  for (const id of over) notes.push(plan.overNote?.[id] || '這張保障卡和目前確認的需求不相符。');
  for (const r of RES) {
    if (off[r] === 'low') notes.push(`${RES_NAMES[r]}偏低（建議 ${plan.ideal[r][0]}–${plan.ideal[r][1]} 枚）。`);
    if (off[r] === 'high') notes.push(`${RES_NAMES[r]}偏高（建議 ${plan.ideal[r][0]}–${plan.ideal[r][1]} 枚）。`);
  }
  if (!core.length) notes.push('沒有選到對應核心需求的保障卡。');
  const quality: Quality = allocDist === 0 && !over.length && core.length ? 'good' : allocDist <= 2 && !over.length ? 'ok' : 'bad';
  return { changes, allocDist, cardScore, over, core, off, notes, quality };
}

export type StressResult = 'held' | 'partial' | 'broken';

/** Single-event absorption evaluation (same formula as prototype runStress) */
export function stressOne(ev: Pick<StressEvent, 'absorb' | 'cards' | 'need'>, alloc: Alloc, cardIds: CardId[]) {
  const helped = ev.cards.filter(id => cardIds.includes(id));
  const protectFactor = !ev.cards.length || helped.length ? 1 : 0.35;
  let defense = Math.min(alloc.cash, CASH_CAP) * (ev.absorb.cash || 0)
    + alloc.protect * (ev.absorb.protect || 0) * protectFactor
    + alloc.growth * (ev.absorb.growth || 0);
  defense += helped.length * CARD_BONUS;
  const ratio = defense / ev.need;
  const result: StressResult = ratio >= 1 ? 'held' : ratio >= 0.55 ? 'partial' : 'broken';
  return { defense: Math.round(defense * 10) / 10, ratio: Math.max(0, Math.min(1.2, ratio)), result, helped };
}

/** All client stress events (for balance testing) */
export function runStress(client: ClientProfile, alloc: Alloc, cardIds: CardId[]) {
  const events = client.stress.map(ev => ({ ev, ...stressOne(ev, alloc, cardIds) }));
  const pts = events.reduce((s, e) => s + (e.result === 'held' ? 2 : e.result === 'partial' ? 1 : 0), 0);
  const quality = pts >= 5 ? 'strong' : pts >= 3 ? 'medium' : 'weak';
  return { events, pts, quality };
}

/** Market events: bull market checks growth position; bear market checks if emergency cash prevents selling at lows */
export function marketOne(ev: MarketEvent, alloc: Alloc): StressResult {
  if (ev.boom) return alloc.growth >= 2 ? 'held' : alloc.growth >= 1 ? 'partial' : 'broken';
  return stressOne({ absorb: ev.absorb, cards: [], need: ev.need }, alloc, []).result;
}

export function finalScore(m: Metrics, flags: { overCards?: boolean; plan?: Quality } = {}) {
  const score = Math.round(METRICS.reduce((s, k) => s + clamp(m[k]) * WEIGHTS[k], 0));
  let grade = score >= 90 ? 'S' : score >= 80 ? 'A' : score >= 68 ? 'B' : 'C';
  const caps: string[] = [];
  const order = ['C', 'B', 'A', 'S'];
  const cap = (g: string, reason: string) => { if (order.indexOf(grade) > order.indexOf(g)) grade = g; caps.push(reason); };
  if (m.compliance < 70) cap('B', '合規表達低於 70：出現恐嚇或保證式說法');
  if (flags.overCards) cap('A', '方案含有過度配置的保障卡');
  else if (flags.plan === 'bad') cap('A', '資源配置與客戶需求落差過大');
  return { score, grade, caps };
}

export const STEP = {
  clueFound: { insight: 7 } as Changes,
  clueFinish: { trust: 4, insight: 4, fit: 2 } as Changes,
  stressEvent: (r: StressResult): Changes => r === 'held' ? { risk: 6, fit: 3 } : r === 'partial' ? { risk: 2 } : { risk: -5, fit: -3, trust: -2 },
  stressFinal: (q: string): Changes => q === 'strong' ? { trust: 6, fit: 5, risk: 8 } : q === 'medium' ? { trust: 2, risk: 2 } : { trust: -4, fit: -6, risk: -6 },
  interviewFinish: (keyHit: number): Changes => keyHit >= 2 ? { trust: 3, insight: 6, fit: 4 } : keyHit === 1 ? { trust: 2, insight: 3, fit: 2 } : { insight: -3, fit: -4 },
};

/** Commission proxy: more protection and growth positions yield higher commission — intentionally creates tension between "selling more" and "selling right", balanced by audits and client complaints. */
export function commissionFor(alloc: Alloc, cards: CardId[]): number {
  return alloc.protect * 3 + alloc.growth * 2 + cards.length * 2;
}
