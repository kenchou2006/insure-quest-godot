/* INSURE QUEST | Letter from ten years later.
 * Rule engine determines outcome, event, and gap; AI or templates generate the emotional client letter.
 */
import type { ClientProfile, StressEvent } from './types.ts';

export type LetterOutcome = 'thanks' | 'regret' | 'mixed';

export interface LetterFacts {
  outcome: LetterOutcome;
  event: string;
  gap: number;
  signed: boolean;
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
): LetterFacts {
  const broken = st.events.find(e => e.result === 'broken');
  const partial = st.events.find(e => e.result === 'partial');
  const primary = st.events[0];

  if (!signed) {
    if (broken) {
      const gap = Math.max(10, Math.round(broken.ev.need * 20));
      return { outcome: 'regret', event: broken.ev.title, gap, signed: false };
    }
    return {
      outcome: 'mixed',
      event: (partial || primary).ev.title,
      gap: partial ? Math.max(5, Math.round(partial.ev.need * 10)) : 0,
      signed: false,
    };
  }

  // Signed
  if (st.quality === 'strong') {
    // Fully protected: thank-you letter, gap is 0
    const maxNeedEv = [...st.events].sort((a, b) => b.ev.need - a.ev.need)[0] || primary;
    return { outcome: 'thanks', event: maxNeedEv.ev.title, gap: 0, signed: true };
  }

  if (st.quality === 'weak') {
    // Severely breached: regret letter, compute gap amount
    const evTarget = broken || partial || primary;
    const diff = Math.max(1, evTarget.ev.need - evTarget.defense);
    const gap = Math.round(diff * 20);
    return { outcome: 'regret', event: evTarget.ev.title, gap, signed: true };
  }

  // medium: partially absorbed
  const evTarget = broken || partial || primary;
  const diff = Math.max(0.5, evTarget.ev.need - evTarget.defense);
  const gap = evTarget.result === 'held' ? 0 : Math.round(diff * 15);
  return { outcome: gap === 0 ? 'thanks' : 'mixed', event: evTarget.ev.title, gap, signed: true };
}

/** Rule-based template letter (120-200 characters, includes event and gap) */
export function generateTemplateLetter(client: ClientProfile, facts: LetterFacts): string {
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

  return true;
}
