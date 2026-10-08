import type { Award, QuestState, QuestStats } from './extras.ts';
/* INSURE QUEST｜共用型別。伺服器權威狀態、客戶資料與訊息協定都在這裡定義。 */

export type Metric = 'trust' | 'insight' | 'fit' | 'risk' | 'compliance';
export type Metrics = Record<Metric, number>;
export type Changes = Partial<Metrics>;
export type Quality = 'good' | 'ok' | 'bad';
export type ResKey = 'cash' | 'protect' | 'growth';
export type Alloc = Record<ResKey, number>;
export type QuestionId = 'income' | 'goal' | 'coverage' | 'risk' | 'premium';
export type CardId = 'medical' | 'income' | 'accident' | 'tools' | 'legacy' | 'care';

/** 場景插圖上的熱點（百分比 0–100） */
export interface Spot { x: number; y: number; w: number; h: number }

export interface Answer { text: string; trust: number; insight: number; key: string | null }

export interface ChoiceOption { quality: Quality; text: string; title: string; body: string; changes: Changes }

export interface StressEvent {
  day: number; tag: string; title: string; body: string;
  absorb: Partial<Record<ResKey, number>>;
  cards: CardId[]; need: number; held: string; hit: string;
}

export interface ClientProfile {
  id: string; name: string; short: string; age: number; gender: string; job: string;
  tag: string; difficulty: string; portrait: string | null;
  goal: string; amount: string; incomeInfo: string; family: string;
  intro: string; quote: string;
  facts: { title: string; detail: string; fact: string; spot?: Spot }[];
  /** 有場景插圖的客戶（原型五位）：插圖 id 與專屬干擾物，用於熱點找線索 */
  scene?: string | null;
  decoy?: { title: string; detail: string; spot?: Spot };
  /** 專屬結局文案（依壓力預演強／中／弱）與「沒有規劃」的後果 */
  outcomes?: Record<'strong' | 'medium' | 'weak', { headline: string; title: string; list: string[] }>;
  noPlan?: string[];
  answers: Record<QuestionId, Answer>;
  keyQuestions: QuestionId[];
  plan: {
    ideal: Record<ResKey, [number, number]>;
    cards: Record<CardId, number>;
    overProtect?: number;
    overNote?: Partial<Record<CardId, string>>;
  };
  objection: { text: string; options: ChoiceOption[] };
  stress: StressEvent[];
  generated?: boolean;
}

export type TileType = 'start' | 'client' | 'life' | 'market' | 'training' | 'referral' | 'audit' | 'seminar';
export interface Tile { type: TileType; name: string }

export interface MarketEvent {
  id: string; title: string; body: string; tag: string;
  /** 每枚資源幣的承接力（負值＝暴露）。 */
  absorb: Partial<Record<ResKey, number>>;
  need: number;
  /** 正面行情：成長部位帶來滿意度，不是測試防線 */
  boom?: boolean;
  lesson: string;
}

export interface QuizItem { id: string; q: string; options: string[]; answer: number; explain: string }

export type BotLevel = 'novice' | 'pro';

export interface BookEntry {
  clientId: string; name: string; alloc: Alloc; cards: CardId[];
  satisfaction: number; planQuality: Quality; compliance: number;
  stressUsed: number; signedRound: number; mis: boolean;
  /** 是否已做過生命週期回訪 */
  reviewed?: boolean;
}

export interface Decision { round: number; clientName: string; stage: string; quality: Quality; title: string; body: string }

export interface PlayerState {
  id: string; name: string; isBot: boolean; botLevel: BotLevel | null;
  /** 登入帳號（Google）；訪客與電腦顧問為 null */
  accountId?: string | null;
  connected: boolean; disconnectedAt: number | null;
  pos: number; reputation: number; commission: number;
  skillSum: Metrics; sessions: number;
  book: BookEntry[];
  decisions: Decision[];
  quizCorrect: number; quizTotal: number;
  /** 每場面談的完整紀錄（保存到培訓紀錄、計算弱點標籤） */
  sessionLogs?: SessionLog[];
  /** 季度任務統計與合規連擊 */
  stats?: QuestStats;
  complianceStreak?: number;
  finalTurn?: boolean;
}

export interface SessionState {
  playerId: string; clientId: string; referral: boolean;
  step: 'discover' | 'plan' | 'objection' | 'result';
  asked: { qid: QuestionId | 'free'; question: string; answer: string; key: string | null; note?: string }[];
  freeLeft: number;
  /** 自由提問命中的標準題目（計入關鍵問題覆蓋） */
  freeHits: QuestionId[];
  /** 場景線索（3 真 1 干擾），observed 為已調查的索引 */
  clues: { title: string; detail: string; fact: string; real: boolean; spot?: Spot }[];
  /** 旁觀者預測：playerId → 評級 */
  predictions: Record<string, string>;
  observed: number[];
  m: Metrics;
  objectionOrder: number[];
  objectionReply?: { text: string; title: string; body: string; quality: Quality };
  objectionMode?: 'choice' | 'free';
  /** AI 教練提示：每場面談限用一次 */
  hintUsed?: boolean;
  hint?: string;
  plan?: { alloc: Alloc; cards: CardId[]; quality: Quality; notes: string[] };
  stress?: { title: string; tag: string; result: 'held' | 'partial' | 'broken'; defense: number; need: number; text: string }[];
  result?: {
    signed: boolean; score: number; grade: string; caps: string[]; commission: number; summary: string;
    predictionHits: string[];
    epilogue: { headline: string; title: string; list: string[]; noPlan: string[] };
  };
  aiBusy?: boolean;
}

export interface PendingEvent {
  kind: 'life' | 'market' | 'quiz' | 'audit' | 'settlement' | 'seminar' | 'info' | 'dilemma' | 'review';
  playerId: string; title: string; body: string;
  lines: { text: string; tone: 'good' | 'ok' | 'bad' | 'info' }[];
  /** order[顯示位置] = 題庫原始選項索引；只存在伺服器，不送給客戶端 */
  quiz?: { id: string; q: string; options: string[]; order: number[]; picked?: number; answer?: number; explain?: string };
  /** 情境抉擇卡（選項品質只在伺服器端，用 id 對照 DILEMMAS） */
  dilemma?: { id: string; title: string; prompt: string; choices: { id: string; text: string }[]; picked: string | null; outcome: { title: string; body: string; tone: 'good' | 'ok' | 'bad'; effects: string } | null };
  /** 客戶生命週期回訪；needCard 只在伺服器端，送出前移除 */
  review?: { clientId: string; clientName: string; change: { title: string; body: string }; current: { alloc: Alloc; cards: CardId[] }; needCard: CardId; picked: string | null; outcome: { title: string; body: string; tone: 'good' | 'ok' | 'bad' } | null };
}

/** 一場面談的可回顧紀錄 */
export interface SessionLog {
  clientId: string; clientName: string; job: string; round: number;
  grade: string; score: number; signed: boolean; referral: boolean; hintUsed: boolean;
  clues: { found: number; decoy: boolean };
  questions: { qid: string; text: string; key: string | null }[];
  freeQuestion: { text: string; note: string } | null;
  plan: { alloc: Alloc; cards: CardId[]; quality: Quality; notes: string[] };
  objection: { mode: 'choice' | 'free'; text: string; quality: Quality; title: string };
  stress: { title: string; result: string }[];
  tags: string[];
}

/** 全體公告（例如終局大事件），客戶端每個 id 顯示一次 */
export interface Announcement { id: string; title: string; body: string; lines: { text: string; tone: 'good' | 'ok' | 'bad' | 'info' }[] }

export interface LogLine { ts: number; text: string; tone?: 'good' | 'ok' | 'bad' | 'info' }

export interface FinalRow {
  playerId: string; name: string; isBot: boolean;
  score: number; grade: string; caps: string[];
  skill: Metrics; service: number; reputation: number; commission: number; clients: number;
  coach: string;
}

export interface GameState {
  code: string; phase: 'lobby' | 'playing' | 'ended';
  hostId: string | null;
  settings: { rounds: number; aiClients: boolean };
  players: PlayerState[];
  turn: number; round: number;
  turnStage: 'roll' | 'session' | 'event' | 'done';
  lastRoll: number | null;
  deck: string[];
  marketDeck: string[]; quizDeck: string[];
  clients: Record<string, ClientProfile>;
  session: SessionState | null;
  event: PendingEvent | null;
  log: LogLine[];
  final: FinalRow[] | null;
  announcement?: Announcement | null;
  quests?: QuestState[];
  awards?: Award[] | null;
  version: number;
}

export type Action =
  | { type: 'roll' }
  | { type: 'observe'; index: number }
  | { type: 'ask'; qid: QuestionId }
  | { type: 'ask_free'; text: string }
  | { type: 'to_plan' }
  | { type: 'plan'; alloc: Alloc; cards: CardId[] }
  | { type: 'objection'; index: number }
  | { type: 'objection_free'; text: string }
  | { type: 'answer_quiz'; index: number }
  | { type: 'hint' }
  | { type: 'choose_dilemma'; choice: string }
  | { type: 'review'; card: string }
  | { type: 'continue' };
