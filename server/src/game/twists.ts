import type { CardId, ClientProfile } from './types.ts';

export interface LifeTwist {
  id: string;
  title: string;
  hint: string;
  initialTrustDelta?: number;
  bonusCard?: CardId;
  stressTag?: string;
  needDelta?: number;
}

export const LIFE_TWISTS: LifeTwist[] = [
  {
    id: 'elderly_care',
    title: '長輩確診需長照',
    hint: '「最近家裡長輩突然倒下，看護和機構費用讓我開始擔心未來……」',
    initialTrustDelta: 0,
    bonusCard: 'care',
    stressTag: '長照',
    needDelta: 0.5,
  },
  {
    id: 'job_transition',
    title: '剛換工作收入不穩',
    hint: '「我剛換到新公司還在試用期，薪水還沒完全穩定，很怕突然有意外。」',
    initialTrustDelta: 0,
    bonusCard: 'income',
    stressTag: '收入',
    needDelta: 0.5,
  },
  {
    id: 'bad_sales_history',
    title: '曾被不當推銷而高度防備',
    hint: '「以前遇過別家業務跟我說『買這個保證穩賺』，結果差點被坑，我現在對保險很謹慎。」',
    initialTrustDelta: -10,
  },
  {
    id: 'grace_period_end',
    title: '房貸寬限期到期',
    hint: '「房貸寬限期快到了，下個月開始本利攤還，每個月手頭會變得很緊。」',
    initialTrustDelta: 0,
    bonusCard: 'income',
    stressTag: '房貸',
    needDelta: 0.5,
  },
  {
    id: 'spouse_unemployed',
    title: '配偶失業待業中',
    hint: '「我先生/太太上個月非自願離職，現在家裡只靠我一份薪水撐著。」',
    initialTrustDelta: 0,
    bonusCard: 'legacy',
    stressTag: '家庭',
    needDelta: 0.5,
  },
  {
    id: 'newborn_on_way',
    title: '剛得知懷孕喜訊',
    hint: '「我們剛確認有了小寶寶，很開心但一想到接下來的開銷和責任就覺得壓力好大。」',
    initialTrustDelta: 5,
    bonusCard: 'medical',
    stressTag: '醫療',
    needDelta: 0.5,
  },
  {
    id: 'side_hustle_prep',
    title: '籌備副業工作室',
    hint: '「我打算下半年跟朋友合夥開個小工作室，手邊的資金不能出任何差錯。」',
    initialTrustDelta: 0,
    bonusCard: 'tools',
    stressTag: '營業',
    needDelta: 0.5,
  },
];

/**
 * Adjusts client profile copy based on dynamic twist (does not mutate original CLIENTS objects).
 * Used by pro bot and stress test evaluations.
 */
export function applyTwist(client: ClientProfile, twist: LifeTwist | null | undefined): ClientProfile {
  if (!twist) return client;
  const clone: ClientProfile = structuredClone(client);

  // 1. If twist boosts need for a specific coverage card, slightly increase weight (only for non-negative cards to avoid turning redundant cards positive)
  if (twist.bonusCard && clone.plan.cards[twist.bonusCard] !== undefined) {
    const cur = clone.plan.cards[twist.bonusCard];
    if (cur >= 0 && cur < 3) {
      clone.plan.cards[twist.bonusCard] = cur + 1;
    }
  }

  // 2. If twist affects specific stress events, moderately increase need without exceeding pro allocation defense limits
  if (twist.stressTag && twist.needDelta) {
    for (const ev of clone.stress) {
      if (ev.tag.includes(twist.stressTag) || ev.title.includes(twist.stressTag)) {
        // Slightly raise need threshold to increase realism of stress
        ev.need = Math.round((ev.need + twist.needDelta) * 10) / 10;
      }
    }
  }

  return clone;
}
