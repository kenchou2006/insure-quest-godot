/* INSURE QUEST | Rule-based AI and shared AI interfaces.
 * Kept free of the Anthropic SDK and zod so it can also be bundled for the browser (src/local/local-room.ts).
 * Re-exported from ai.ts; server code keeps importing from './ai.ts'.
 */
import type { ClientProfile, Quality, QuestionId, SessionState, FinalRow, MarketEvent, PlayerState } from './game/types.ts';
import { QUESTIONS } from './game/data.ts';
import type { LifeTwist } from './game/twists.ts';
import type { LetterFacts } from './game/letters.ts';
import { generateTemplateLetter } from './game/letters.ts';
import { ruleCompliance } from './game/compliance.ts';


export const CODE_LABEL: Record<string, string> = {
  PROMISE_RETURN: '保證收益', FEAR_MONGERING: '恐嚇推銷', MISLEADING_COMPARISON: '不當比較',
  UNDISCLOSED_RISK: '未揭露風險', EARLY_PRESSURE: '急迫促成', INJECTION_ATTEMPT: '指令注入',
};

export interface FreeAnswer { answer: string; matched: QuestionId | null; key: string | null; trust: number; insight: number; compliance: number; note: string }
export interface Grade { quality: Quality; trust: number; fit: number; risk: number; compliance: number; title: string; body: string }

export interface CombinedDialogue {
  answer: string;
  revealedFacts: string[];
  trustDelta: number;
  insightDelta: number;
  emotion: 'receptive' | 'neutral' | 'defensive' | 'impatient';
  compliance: {
    level: 'pass' | 'warning' | 'violation';
    penalty: number;
    issues: Array<{
      code: 'PROMISE_RETURN' | 'FEAR_MONGERING' | 'MISLEADING_COMPARISON' | 'UNDISCLOSED_RISK' | 'EARLY_PRESSURE' | 'INJECTION_ATTEMPT';
      quote: string;
      rule: string;
      suggestion: string;
    }>;
  };
  coachTip: string;
}

/** AI provider (Workers AI / Claude / mock): returns null unconditionally on failure without falling back to rule-based */
export interface RawAI {
  readonly provider: string;
  readonly unmetered?: boolean;
  freeQuestion(c: ClientProfile, text: string, history: SessionState['asked']): Promise<FreeAnswer | null>;
  /** onAnswer: providers supporting streaming report current text as client answers are generated incrementally (optional) */
  talk(c: ClientProfile, twist: LifeTwist | null | undefined, history: SessionState['asked'], text: string, onAnswer?: (partial: string) => void): Promise<CombinedDialogue | null>;
  letter(c: ClientProfile, twist: LifeTwist | null | undefined, facts: LetterFacts): Promise<string | null>;
  gradeObjection(c: ClientProfile, reply: string): Promise<Grade | null>;
  marketNews(ev: MarketEvent): Promise<string | null>;
  coachTip(p: PlayerState): Promise<string | null>;
  hint(c: ClientProfile, sess: SessionState): Promise<string | null>;
  debrief(p: PlayerState, row: Omit<FinalRow, 'coach'>): Promise<string | null>;
  generateClient(seed: number): Promise<ClientProfile | null>;
}

/** Interface used by game logic: guaranteed to produce results (rule-based when necessary) */
export interface AIService {
  readonly enabled: boolean;
  freeQuestion(c: ClientProfile, text: string, history: SessionState['asked']): Promise<FreeAnswer>;
  talk(c: ClientProfile, twist: LifeTwist | null | undefined, history: SessionState['asked'], text: string, suggested?: QuestionId, onAnswer?: (partial: string) => void): Promise<CombinedDialogue>;
  letter(c: ClientProfile, twist: LifeTwist | null | undefined, facts: LetterFacts): Promise<string>;
  gradeObjection(c: ClientProfile, reply: string): Promise<Grade>;
  marketNews(ev: MarketEvent): Promise<string | null>;
  coachTip(p: PlayerState): Promise<string | null>;
  hint(c: ClientProfile, sess: SessionState): Promise<string>;
  debrief(p: PlayerState, row: Omit<FinalRow, 'coach'> & { coach?: string }): Promise<string | null>;
  generateClient(seed: number): Promise<ClientProfile | null>;
}

/* ───────── Rule-based version ───────── */

const KEYWORDS: Record<QuestionId, RegExp> = {
  income: /收入|支出|開銷|房租|停工|中斷|不能工作|生活費|帳單/,
  goal: /目標|夢想|最在乎|最重要|犧牲|希望|計畫/,
  coverage: /保險|保障|團保|福利|資源|保單|勞保/,
  risk: /投資|波動|風險|虧|股票|基金|ETF|下跌/,
  premium: /預算|多少錢|保費|付多少|價格|費用/,
};
const BAD_WORDS = /保證|一定會|穩賺|絕對|不會虧|後悔|出事|完蛋|詛咒/;
const GOOD_WORDS = /目標|保留|不必|不用|守住|保護|理解|尊重|一起|條款|說明|預備|緩衝/;

export function ruleFreeQuestion(c: ClientProfile, text: string, history: SessionState['asked']): FreeAnswer {
  const flagged = BAD_WORDS.test(text);
  const asked = new Set(history.map(h => h.qid));
  const match = (Object.keys(KEYWORDS) as QuestionId[]).find(q => KEYWORDS[q].test(text) && !asked.has(q))
    ?? (Object.keys(KEYWORDS) as QuestionId[]).find(q => KEYWORDS[q].test(text)) ?? null;
  if (!match) {
    return { answer: `「嗯……你的意思是？可以再具體一點嗎？」（${c.short}看起來有點困惑）`, matched: null, key: null, trust: 0, insight: 0, compliance: flagged ? -10 : 0, note: flagged ? '提問中出現保證或恐嚇字眼。' : '問題不夠具體，客戶難以回答。' };
  }
  const a = c.answers[match];
  return {
    answer: a.text, matched: match === 'premium' ? null : match, key: a.key,
    trust: Math.round(a.trust * 0.8), insight: Math.round(a.insight * 0.8), compliance: flagged ? -10 : 0,
    note: flagged ? '提問中出現保證或恐嚇字眼。' : '（規則版：以關鍵字比對到相近的訪談題）',
  };
}

export function ruleGrade(c: ClientProfile, reply: string): Grade {
  if (BAD_WORDS.test(reply)) {
    return { quality: 'bad', trust: -12, fit: -3, risk: 0, compliance: -20, title: '出現保證或恐嚇式說法', body: '「保證」「一定」「後悔」這類說法會被視為不當招攬，也會傷害信任。' };
  }
  const goalHit = c.goal.split(/[，、\s]/).some(w => w.length >= 2 && reply.includes(w.slice(0, 2)));
  if (GOOD_WORDS.test(reply) && (goalHit || reply.length >= 25)) {
    return { quality: 'good', trust: 10, fit: 6, risk: 3, compliance: 0, title: '把保障連回客戶的目標', body: '你回應了客戶的顧慮，並說明方案如何保護他在乎的事。' };
  }
  if (/[？?]/.test(reply)) {
    return { quality: 'ok', trust: 6, fit: 3, risk: 1, compliance: 0, title: '用提問引導客戶思考', body: '提問能讓客戶自己看見風險；下一步要把方案和他的答案連起來。' };
  }
  return { quality: 'ok', trust: 3, fit: 1, risk: 0, compliance: 0, title: '回應合規，但還不夠具體', body: '試著提到客戶的目標或具體情境，說服力會更強。' };
}

/** Rule-based coach tips: provides thinking directions rather than direct answers */
export function ruleHint(c: ClientProfile, sess: SessionState): string {
  if (sess.step === 'discover') {
    const asked = new Set<string>([...sess.asked.map(a => a.qid), ...sess.freeHits]);
    const missing = c.keyQuestions.find(k => !asked.has(k));
    if (sess.observed.length < 3) return '先看場景：哪些物品透露了收入來源、責任或目標資金？裝飾品通常不是線索。';
    if (missing) return `${QUESTIONS.find(q => q.id === missing)!.coach}${c.short}最在意的事還沒被問出來。`;
    return '關鍵需求已經掌握了。太早談預算會讓客戶防備，可以準備進入方案配置。';
  }
  if (sess.step === 'plan') {
    return `回想你找到的線索：${c.facts.map(f => f.fact).join('、')}。先確保緊急預備能撐過收入中斷，再挑和這些風險直接相關的保障卡，不相關的卡會被視為過度配置。`;
  }
  return `把回應連回${c.short}自己的目標「${c.goal}」，說明方案如何保護它；避免「保證」「一定」「後悔」這類說法。`;
}

export function ruleTalk(
  c: ClientProfile,
  _twist: LifeTwist | null | undefined,
  history: SessionState['asked'],
  text: string,
  suggested?: QuestionId,
): CombinedDialogue {
  const comp = ruleCompliance(text);

  if (suggested && c.answers[suggested]) {
    const a = c.answers[suggested];
    const q = QUESTIONS.find(x => x.id === suggested);
    return {
      answer: a.text,
      revealedFacts: a.key ? [a.key] : [],
      trustDelta: a.trust,
      insightDelta: a.insight,
      emotion: comp.level === 'violation' ? 'defensive' : 'receptive',
      compliance: comp,
      coachTip: q?.coach ?? '切入點很合適。',
    };
  }

  // Free-form text question
  const free = ruleFreeQuestion(c, text, history);
  return {
    answer: free.answer,
    revealedFacts: free.key ? [free.key] : [],
    trustDelta: free.trust,
    insightDelta: free.insight,
    emotion: comp.level === 'violation' ? 'defensive' : 'neutral',
    compliance: comp,
    coachTip: free.note || '試著多探詢客戶的生活目標與擔憂。',
  };
}

export class RuleAI implements AIService {
  readonly enabled: boolean = false;
  async freeQuestion(c: ClientProfile, text: string, h: SessionState['asked']) { return ruleFreeQuestion(c, text, h); }
  async talk(c: ClientProfile, twist: LifeTwist | null | undefined, history: SessionState['asked'], text: string, suggested?: QuestionId) {
    return ruleTalk(c, twist, history, text, suggested);
  }
  async letter(c: ClientProfile, _twist: LifeTwist | null | undefined, facts: LetterFacts) {
    return generateTemplateLetter(c, facts);
  }
  async gradeObjection(c: ClientProfile, reply: string) { return ruleGrade(c, reply); }
  async marketNews() { return null; }
  async coachTip() { return null; }
  async hint(c: ClientProfile, sess: SessionState) { return ruleHint(c, sess); }
  async debrief() { return null; }
  async generateClient() { return null; }
}
