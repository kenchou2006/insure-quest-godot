/* INSURE QUEST｜電腦顧問。
 * pro：照教科書做（先問關鍵問題、理想配置、合規回應）——當作示範對手。
 * novice：常見新人錯誤（亂問、太早問預算、偏向高佣金配置、偶爾恐嚇）——讓學員看見反例。
 */
import type { Action, Alloc, CardId, GameState, QuestionId } from './types.ts';
import { QUIZ } from './data.ts';
import { DILEMMAS } from './extras.ts';
import { RES, TOTAL_COINS } from './engine.ts';
import { shuffle } from './game.ts';

export function botAction(s: GameState, rng: () => number): Action | null {
  const p = s.players[s.turn];
  if (!p || s.phase !== 'playing') return null;
  const pro = p.botLevel !== 'novice';

  if (s.turnStage === 'roll') return { type: 'roll' };

  if (s.turnStage === 'event' && s.event) {
    const q = s.event.quiz;
    if (q && q.picked === undefined) {
      const item = QUIZ.find(x => x.id === q.id)!;
      const correct = pro ? rng() < 0.9 : rng() < 0.55;
      const right = q.order.indexOf(item.answer);
      const wrong = q.order.map((_, i) => i).filter(i => i !== right);
      return { type: 'answer_quiz', index: correct ? right : wrong[Math.floor(rng() * wrong.length)] };
    }
    const dl = s.event.dilemma;
    if (dl && !dl.picked) {
      const def = DILEMMAS.find(d => d.id === dl.id)!;
      const good = dl.choices.find(c => def.choices.find(x => x.id === c.id.split(':')[1])?.quality === 'good')!;
      const pick = pro && rng() < 0.9 ? good : dl.choices[Math.floor(rng() * dl.choices.length)];
      return { type: 'choose_dilemma', choice: pick.id };
    }
    const rv = s.event.review;
    if (rv && !rv.picked) {
      const correct = rv.current.cards.includes(rv.needCard) ? 'none' : rv.needCard;
      const all = ['medical', 'income', 'accident', 'tools', 'legacy', 'care', 'none', 'skip'];
      return { type: 'review', card: pro && rng() < 0.85 ? correct : all[Math.floor(rng() * all.length)] };
    }
    return { type: 'continue' };
  }

  const sess = s.session;
  if (s.turnStage !== 'session' || !sess) return null;
  const c = s.clients[sess.clientId];

  if (sess.step === 'discover') {
    if (sess.observed.length < 3) {
      const open = sess.clues.map((cl, i) => ({ cl, i })).filter(x => !sess.observed.includes(x.i));
      const pick = pro ? open.find(x => x.cl.real) ?? open[0] : open[Math.floor(rng() * open.length)];
      return { type: 'observe', index: pick.i };
    }
    const askedStd = sess.asked.filter(a => a.qid !== 'free').map(a => a.qid as QuestionId);
    if (askedStd.length >= 3) return { type: 'to_plan' };
    const all: QuestionId[] = ['income', 'goal', 'coverage', 'risk', 'premium'];
    const remaining = all.filter(q => !askedStd.includes(q));
    if (pro) {
      const order = [...c.keyQuestions, ...shuffle(all.filter(q => q !== 'premium' && !c.keyQuestions.includes(q)), rng)];
      return { type: 'ask', qid: order.find(q => remaining.includes(q))! };
    }
    return { type: 'ask', qid: remaining[Math.floor(rng() * remaining.length)] };
  }

  if (sess.step === 'plan') {
    const weights = Object.entries(c.plan.cards) as [CardId, number][];
    if (pro) {
      const ideal = c.plan.ideal;
      const alloc: Alloc = { cash: ideal.cash[0], protect: ideal.protect[0], growth: ideal.growth[0] };
      let left = TOTAL_COINS - alloc.cash - alloc.protect - alloc.growth;
      for (const r of ['protect', 'cash', 'growth'] as const) {
        const add = Math.min(left, ideal[r][1] - alloc[r]);
        alloc[r] += add; left -= add;
      }
      alloc.growth += left;
      const cards = weights.filter(([, w]) => w > 0).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([id]) => id);
      return { type: 'plan', alloc, cards: cards.length >= 2 ? cards : ['medical', 'income'] };
    }
    // 新人：偏向多配保障（佣金高），卡片隨機
    const alloc: Alloc = { cash: 0, protect: 0, growth: 0 };
    for (let i = 0; i < TOTAL_COINS; i++) {
      const r = rng();
      alloc[r < 0.5 ? 'protect' : r < 0.75 ? 'growth' : 'cash']++;
    }
    if (RES.some(r => alloc[r] === 0)) { alloc.cash = Math.max(1, alloc.cash); alloc.protect = TOTAL_COINS - alloc.cash - alloc.growth; }
    const n = rng() < 0.5 ? 3 : 2;
    return { type: 'plan', alloc, cards: shuffle(weights.map(([id]) => id), rng).slice(0, n) };
  }

  if (sess.step === 'objection') {
    if (pro) {
      const idx = sess.objectionOrder.findIndex(i => c.objection.options[i].quality === 'good');
      return { type: 'objection', index: idx };
    }
    return { type: 'objection', index: Math.floor(rng() * 4) };
  }

  if (sess.step === 'result') return { type: 'continue' };
  return null;
}
