/* INSURE QUEST | Letter from ten years later.
 * Rule engine determines outcome, event, and gap; AI or templates generate the emotional client letter.
 */
import type { ClientProfile, StressEvent } from './types.ts';
import type { TimelineResult } from './finance.ts';

export type LetterOutcome = 'thanks' | 'regret' | 'mixed' | 'complaint';

export interface LetterFacts {
  outcome: LetterOutcome;
  event: string;
  gap: number;
  signed: boolean;
  quote?: string;
}

export interface ClientLetter extends LetterFacts {
  content: string;
}

interface StressRunResult {
  quality: string;
  events: Array<{
    ev: StressEvent;
    result: 'held' | 'partial' | 'broken';
    defense: number;
  }>;
}

/** Determines objective letter facts via the rule engine based on stress test and signing results */
export function determineLetter(
  client: ClientProfile,
  signed: boolean,
  st: StressRunResult,
  options?: { violated?: boolean; quote?: string; timeline?: TimelineResult },
): LetterFacts {
  const broken = st.events.find(e => e.result === 'broken');
  const partial = st.events.find(e => e.result === 'partial');
  const primary = st.events[0];

  let outcome: LetterOutcome;
  let event: string;
  let gap: number;

  if (!signed) {
    if (broken) {
      gap = Math.max(10, Math.round(broken.ev.need * 20));
      event = broken.ev.title;
      outcome = 'regret';
    } else {
      outcome = 'mixed';
      event = (partial || primary).ev.title;
      gap = partial ? Math.max(5, Math.round(partial.ev.need * 10)) : 0;
    }
  } else {
    if (st.quality === 'strong') {
      // Fully protected: thank-you letter, gap is 0
      const maxNeedEv = [...st.events].sort((a, b) => b.ev.need - a.ev.need)[0] || primary;
      outcome = 'thanks';
      event = maxNeedEv.ev.title;
      gap = 0;
    } else if (st.quality === 'weak') {
      // Severely breached: regret letter, compute gap amount
      const evTarget = broken || partial || primary;
      const diff = Math.max(1, evTarget.ev.need - evTarget.defense);
      gap = Math.round(diff * 20);
      event = evTarget.ev.title;
      outcome = 'regret';
    } else {
      // medium: partially absorbed
      const evTarget = broken || partial || primary;
      const diff = Math.max(0.5, evTarget.ev.need - evTarget.defense);
      gap = evTarget.result === 'held' ? 0 : Math.round(diff * 15);
      event = evTarget.ev.title;
      outcome = gap === 0 ? 'thanks' : 'mixed';
    }
  }

  // If timeline is supplied, align gap with timeline outOfPocket (signed) or noPlanOutOfPocket (unsigned)
  if (options?.timeline) {
    const evRecord = options.timeline.events.find(e => e.title === event);
    if (evRecord) {
      // An event the plan fully absorbed (stress result 'held') has no shortfall, even if savings paid part of it
      const held = signed && st.events.find(e => e.ev.title === event)?.result === 'held';
      gap = held ? 0 : Math.round((signed ? evRecord.outOfPocket : evRecord.noPlanOutOfPocket) / 10000);
      if (signed && st.quality === 'medium') {
        outcome = gap === 0 ? 'thanks' : 'mixed';
      }
    }
    // A regret/mixed letter must cite a real shortfall: switch to the costliest event (market events have no direct loss)
    if (outcome !== 'thanks' && gap === 0) {
      const pocket = (e: TimelineResult['events'][number]) => signed ? e.outOfPocket : e.noPlanOutOfPocket;
      const notHeld = options.timeline.events.filter(e => !(signed && st.events.find(x => x.ev.title === e.title)?.result === 'held'));
      const worst = [...notHeld].sort((a, b) => pocket(b) - pocket(a))[0];
      if (worst && pocket(worst) > 0) { event = worst.title; gap = Math.max(1, Math.round(pocket(worst) / 10000)); }
      else if (outcome === 'mixed') outcome = 'thanks';
    }
  }

  // Violation overrides thanks/mixed/regret when signed
  if (signed && options?.violated) {
    outcome = 'complaint';
  }

  return {
    outcome,
    event,
    gap,
    signed,
    ...(options?.quote ? { quote: options.quote } : {}),
  };
}

/** Rule-based template letter (120-200 characters, includes event and gap) */
export function generateTemplateLetter(client: ClientProfile, facts: LetterFacts): string {
  if (facts.outcome === 'complaint') {
    const quoteStr = facts.quote ? `「${facts.quote}」` : '當年的承諾';
    return `顧問您好：十年過去了，有些事我必須向您反映。當年面談時您說${quoteStr}，回頭看根本與事實不符。幾年前面對「${facts.event}」時，我們才發現問題重重，深感當初受到誤導與不實招攬。我們已經正式向「金融消費評議中心」提出申訴。希望未來的受訓顧問能引以為戒，不要再給客戶無法兌現的承諾。`;
  }

  if (facts.outcome === 'thanks') {
    return `親愛的顧問：轉眼十年過去了。回想當年我們一起討論規劃的下午，幸好有聽您的建議。幾年前面對「${facts.event}」時，那份規劃替我和家人築起了扎實的防線，我們順利度過了難關，完全沒有留下任何財務缺口。今天特地提筆寫這封信，想再次跟您說聲謝謝，感謝您當年的專業與陪伴！`;
  }

  if (facts.outcome === 'regret') {
    return `顧問您好：十年過去了，有些心裡話一直想跟您說。前幾年發生「${facts.event}」時，因為當初的保障缺口，我們被迫承擔了高達${facts.gap}萬元的損失與費用。那段日子真的非常煎熬，也付出了沉重的代價。如果當年能更完整地補足缺口、做好規劃，或許生活就不會這麼辛苦了。`;
  }

  return `顧問您好：一晃眼十年過去了。當年遇到「${facts.event}」的時候，您替我規劃的預備部位確實幫忙緩衝了一部分衝擊，但仍有約${facts.gap}萬元的資金缺口必須由我們自己咬牙承擔。雖然過程有些辛苦與遺憾，但還是很感謝您當初幫忙守住了一部分底線，讓我們至少能支撐下來。`;
}

const THANKS_FORBIDDEN = /(沒有理賠|後悔|不夠賠|缺口過大|付出了代價|被迫承擔|損失慘重|毫無保障|極度遺憾)/;
const REGRET_FORBIDDEN = /(慶幸|感謝你當初|還好有買|安然度過|毫無遺憾|沒有缺口|完全不用擔心|非常感謝您)/;

/** Validates that AI-generated letter text meets length requirements and avoids conclusions contrary to outcome */
export function validateLetterContent(content: string, outcome: LetterOutcome): boolean {
  if (!content || typeof content !== 'string') return false;
  const trimmed = content.trim();
  if (trimmed.length < 50 || trimmed.length > 400) return false;

  if (outcome === 'thanks' && THANKS_FORBIDDEN.test(trimmed)) {
    return false;
  }

  if (outcome === 'regret' && REGRET_FORBIDDEN.test(trimmed)) {
    return false;
  }

  if (outcome === 'complaint') {
    if (REGRET_FORBIDDEN.test(trimmed)) return false;
    if (!/(申訴|評議)/.test(trimmed)) return false;
  }

  return true;
}
