/* INSURE QUEST | 10-year financial timeline simulation (pure functions).
 * Translates resource coins into real financial cash flows and net worth over 10 years.
 * Compares "with your plan" vs "no plan" across 3 lifetime stress events.
 */
import type { Alloc, CardId, ClientProfile, StressEvent } from './types.ts';

export interface TimelineEventResult {
  year: number;
  title: string;
  tag: string;
  loss: number;
  covered: number;
  outOfPocket: number;
  noPlanOutOfPocket: number;
}

export interface TimelineResult {
  years: number[];
  withPlan: number[];
  noPlan: number[];
  adopted: boolean;
  events: TimelineEventResult[];
  worstWith: number;
  worstNo: number;
  premiumTotal: number;
}

export interface ClientFinance {
  income: number;
  expense: number;
  savings: number;
}

/** Default finance profile derived from client age when finance field is missing or invalid */
export function defaultFinance(age: number): ClientFinance {
  const income = Math.min(90000, Math.max(30000, 35000 + Math.max(0, age - 22) * 1200));
  const expense = Math.round(income * 0.75);
  const surplus = income - expense;
  const savings = surplus * 6;
  return { income, expense, savings };
}

/** Returns the client's finance profile, falling back to age-based calculation */
export function financeFor(client: ClientProfile): ClientFinance {
  if (client.finance && client.finance.income - client.finance.expense >= 3000 && client.finance.savings >= 0) {
    return client.finance;
  }
  return defaultFinance(client.age);
}

const CARD_BONUS = 2;

/**
 * Calculates claim loss, insurance covered amount, and out-of-pocket expenses in NT$.
 * Formulas:
 *   loss = need * 0.5 * monthly income
 *   covered = insurance defense / need * loss (capped at loss)
 */
export function calculateClaim(
  client: ClientProfile,
  alloc: Alloc,
  cards: CardId[],
  ev: StressEvent,
): { loss: number; covered: number; outOfPocket: number } {
  const fin = financeFor(client);
  const isMarket = ev.tag === '市場' || ev.tag === 'market' ||
    (ev.absorb?.growth !== undefined && (!ev.absorb.protect || ev.absorb.protect === 0));

  if (isMarket) {
    return { loss: 0, covered: 0, outOfPocket: 0 };
  }

  // need is the event's severity; 0.5 month of income per point (need 12 ≈ half a year of income)
  const loss = Math.round(ev.need * fin.income * 0.5);
  const helped = ev.cards.filter(id => cards.includes(id));
  const protectFactor = !ev.cards.length || helped.length ? 1 : 0.35;
  const insuranceDefense = alloc.protect > 0
    ? (alloc.protect * (ev.absorb?.protect || 0) * protectFactor + helped.length * CARD_BONUS)
    : 0;
  const ratioInsurance = ev.need > 0 ? Math.max(0, insuranceDefense / ev.need) : 0;
  const covered = Math.min(loss, Math.round(loss * Math.min(1, ratioInsurance)));
  const outOfPocket = loss - covered;

  return { loss, covered, outOfPocket };
}

/** Formats NT$ amount in 萬 with one decimal when < 10 */
export function formatWan(ntd: number): string {
  const wan = ntd / 10000;
  if (wan < 10) {
    return (Math.round(wan * 10) / 10).toFixed(1);
  }
  return String(Math.round(wan));
}

/**
 * Simulates a 10-year financial trajectory (years 0..10).
 * With plan: surplus split by coins (cash 1%/yr, growth 5%/yr); each protect coin costs 1% of annual income as premium.
 * No plan: all surplus in bank deposit at 1%/yr with no insurance.
 * Stress events hit in years 2, 5, 8; loss = need × 0.5 month of income.
 */
export function simulateTimeline(
  client: ClientProfile,
  alloc: Alloc,
  cards: CardId[],
  stressEvents: StressEvent[],
  signed: boolean,
): TimelineResult {
  const fin = financeFor(client);
  const surplus = (fin.income - fin.expense) * 12;

  const years: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const noPlan: number[] = new Array(11);
  const withPlan: number[] = new Array(11);

  // Year 0 starting net worth
  let noPlanDep = fin.savings;
  noPlan[0] = Math.round(noPlanDep);

  const cashShare = alloc.cash / 10;
  const protectShare = alloc.protect / 10;
  const growthShare = alloc.growth / 10;

  // Starting savings: protect share stays in cash
  let cashBucket = Math.round(fin.savings * (cashShare + protectShare));
  let growthBucket = Math.round(fin.savings * growthShare);
  let planDebt = 0;
  withPlan[0] = cashBucket + growthBucket - planDebt;

  // Premium: each protect coin costs 1% of annual income; the rest of the protect share stays in cash
  const annualPremium = Math.round(alloc.protect * fin.income * 12 * 0.01);
  const annualCashSurplus = Math.round(surplus * (cashShare + protectShare)) - annualPremium;
  const annualGrowthSurplus = Math.round(surplus * growthShare);
  

  const eventYears = [2, 5, 8];
  const eventResults: TimelineEventResult[] = [];

  for (let yr = 1; yr <= 10; yr++) {
    // 1. Annual accumulation
    // No plan: deposit accumulates at 1%/yr (if positive), plus surplus
    if (noPlanDep > 0) {
      noPlanDep = Math.round(noPlanDep * 1.01) + surplus;
    } else {
      noPlanDep = noPlanDep + surplus;
    }

    // With plan: cash 1%/yr, growth 5%/yr
    if (cashBucket > 0) {
      cashBucket = Math.round(cashBucket * 1.01) + annualCashSurplus;
    } else {
      cashBucket += annualCashSurplus;
    }

    if (growthBucket > 0) {
      growthBucket = Math.round(growthBucket * 1.05) + annualGrowthSurplus;
    } else {
      growthBucket += annualGrowthSurplus;
    }

    // 2. Stress events at years 2, 5, 8
    const evIdx = eventYears.indexOf(yr);
    if (evIdx !== -1 && stressEvents[evIdx]) {
      const ev = stressEvents[evIdx];
      const isMarket = ev.tag === '市場' || ev.tag === 'market' ||
        (ev.absorb?.growth !== undefined && (!ev.absorb.protect || ev.absorb.protect === 0));

      let loss = 0;
      let covered = 0;
      let outOfPocket = 0;
      let noPlanOutOfPocket = 0;

      if (isMarket) {
        // Market-tag events with no direct loss affect only growth bucket (drop by 20%)
        growthBucket = Math.round(growthBucket * 0.8);
        loss = 0;
        covered = 0;
        outOfPocket = 0;
        noPlanOutOfPocket = 0;
      } else {
        const claim = calculateClaim(client, alloc, cards, ev);
        loss = claim.loss;
        covered = claim.covered;
        outOfPocket = claim.outOfPocket;
        noPlanOutOfPocket = loss;
        noPlanDep -= loss;

        // Pay outOfPocket from cash first, then growth
        let remaining = outOfPocket;
        if (cashBucket > 0) {
          const fromCash = Math.min(cashBucket, remaining);
          cashBucket -= fromCash;
          remaining -= fromCash;
        }

        if (remaining > 0 && growthBucket > 0) {
          const effectiveGrowth = isMarket ? Math.floor(growthBucket * 0.85) : growthBucket;
          if (effectiveGrowth >= remaining) {
            const growthDeducted = isMarket ? Math.ceil(remaining / 0.85) : remaining;
            growthBucket -= growthDeducted;
            remaining = 0;
          } else {
            remaining -= effectiveGrowth;
            growthBucket = 0;
          }
        }

        if (remaining > 0) {
          planDebt += remaining;
        }
      }

      eventResults.push({
        year: yr,
        title: ev.title,
        tag: ev.tag,
        loss,
        covered,
        outOfPocket,
        noPlanOutOfPocket,
      });
    }

    noPlan[yr] = Math.round(noPlanDep);
    withPlan[yr] = Math.round(cashBucket + growthBucket - planDebt);
  }

  // Worst year = lowest net worth among the event years (year 0 is just the starting point)
  const worstOf = (line: number[]) => Math.min(...eventResults.map(e => line[e.year]), line[10]);
  const worstNo = worstOf(noPlan);

  if (!signed) {
    return {
      years,
      withPlan: [...noPlan],
      noPlan,
      adopted: false,
      events: eventResults,
      worstWith: worstNo,
      worstNo,
      premiumTotal: 0,
    };
  }

  const worstWith = worstOf(withPlan);
  const premiumTotal = annualPremium * 10;

  return {
    years,
    withPlan,
    noPlan,
    adopted: true,
    events: eventResults,
    worstWith,
    worstNo,
    premiumTotal,
  };
}
