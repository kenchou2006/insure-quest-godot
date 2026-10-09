import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CLIENTS } from '../src/game/data.ts';
import { defaultFinance, financeFor, simulateTimeline } from '../src/game/finance.ts';
import { TOTAL_COINS } from '../src/game/engine.ts';
import type { Alloc, CardId } from '../src/game/types.ts';

test('10年財務時間軸：輸出為確定性純函數且所有數值均為有限整數', () => {
  const c = CLIENTS[0];
  const alloc: Alloc = { cash: 4, protect: 3, growth: 3 };
  const cards: CardId[] = ['income', 'medical'];
  const res1 = simulateTimeline(c, alloc, cards, c.stress, true);
  const res2 = simulateTimeline(c, alloc, cards, c.stress, true);

  assert.deepEqual(res1, res2);
  assert.equal(res1.years.length, 11);
  assert.equal(res1.withPlan.length, 11);
  assert.equal(res1.noPlan.length, 11);
  assert.equal(res1.events.length, 3);

  for (const v of res1.withPlan) {
    assert.ok(Number.isInteger(v), `withPlan not integer: ${v}`);
    assert.ok(Number.isFinite(v), `withPlan not finite: ${v}`);
  }
  for (const v of res1.noPlan) {
    assert.ok(Number.isInteger(v), `noPlan not integer: ${v}`);
    assert.ok(Number.isFinite(v), `noPlan not finite: ${v}`);
  }
  for (const ev of res1.events) {
    assert.ok(Number.isInteger(ev.loss), `loss not integer: ${ev.loss}`);
    assert.ok(Number.isInteger(ev.covered), `covered not integer: ${ev.covered}`);
    assert.ok(Number.isInteger(ev.outOfPocket), `outOfPocket not integer: ${ev.outOfPocket}`);
    assert.ok(Number.isInteger(ev.noPlanOutOfPocket), `noPlanOutOfPocket not integer: ${ev.noPlanOutOfPocket}`);
  }
});

test('資深電腦配置：多數客戶最壞的一年明顯較好，且沒有客戶明顯變差', () => {
  let better = 0;
  for (const c of CLIENTS) {
    const ideal = c.plan.ideal;
    const alloc: Alloc = { cash: ideal.cash[0], protect: ideal.protect[0], growth: ideal.growth[0] };
    let left = TOTAL_COINS - alloc.cash - alloc.protect - alloc.growth;
    for (const r of ['protect', 'cash', 'growth'] as const) {
      const add = Math.min(left, ideal[r][1] - alloc[r]);
      alloc[r] += add;
      left -= add;
    }
    alloc.growth += left;

    const weights = Object.entries(c.plan.cards) as [CardId, number][];
    const cards = weights.filter(([, w]) => w > 0).sort((a, b) => b[1] - a[1]).slice(0, 3).map(([id]) => id);

    const res = simulateTimeline(c, alloc, cards, c.stress, true);
    assert.ok(res.adopted, `${c.id} adopted should be true`);
    if (res.worstWith > res.worstNo) better++;
    // High earners with large buffers may gain little from insurance, but it must never clearly hurt
    assert.ok(res.worstWith >= res.worstNo - Math.abs(res.worstNo) * 0.05, `${c.id}: worstWith ${res.worstWith} vs worstNo ${res.worstNo}`);
  }
  assert.ok(better >= CLIENTS.length - 3, `only ${better}/${CLIENTS.length} clients improved`);
});

test('0 保障幣配置不會有免費午餐：沒有保費就沒有任何理賠', () => {
  for (const c of CLIENTS) {
    const alloc: Alloc = { cash: 5, protect: 0, growth: 5 };
    const res = simulateTimeline(c, alloc, [], c.stress, true);
    assert.equal(res.premiumTotal, 0);
    for (const e of res.events) {
      assert.equal(e.covered, 0, `${c.id}: ${e.title} covered without premium`);
      assert.equal(e.outOfPocket, e.noPlanOutOfPocket);
    }
  }
});

test('未簽約：adopted 為 false，withPlan 與 noPlan 完全一致', () => {
  for (const c of CLIENTS) {
    const alloc: Alloc = { cash: 4, protect: 3, growth: 3 };
    const res = simulateTimeline(c, alloc, ['income', 'medical'], c.stress, false);
    assert.equal(res.adopted, false);
    assert.deepEqual(res.withPlan, res.noPlan);
    assert.equal(res.worstWith, res.worstNo);
    assert.equal(res.premiumTotal, 0);
  }
});

test('defaultFinance 與 financeFor 回退邏輯正確且每位客戶盈餘 >= 3000', () => {
  for (const c of CLIENTS) {
    const fin = financeFor(c);
    assert.ok(fin.income > fin.expense, `${c.id} income > expense`);
    assert.ok(fin.income - fin.expense >= 3000, `${c.id} surplus >= 3000`);
    assert.ok(fin.savings >= 0, `${c.id} savings >= 0`);
  }

  const def = defaultFinance(28);
  assert.equal(def.income, 35000 + 6 * 1200);
  assert.equal(def.expense, Math.round(def.income * 0.75));
  assert.ok(def.savings > 0);

  const capped = defaultFinance(75);
  assert.equal(capped.income, 90000);
});
