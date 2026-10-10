import type { Award, QuestState, QuestStats } from './extras.ts';
import type { LifeTwist } from './twists.ts';
import type { ClientLetter } from './letters.ts';
import type { ComplianceLevel } from './compliance.ts';
import type { TimelineResult } from './finance.ts';
/* INSURE QUEST | Shared types. Authoritative server state, client profiles, and message protocols are defined here. */

export type Metric = 'trust' | 'insight' | 'fit' | 'risk' | 'compliance';
export type Metrics = Record<Metric, number>;
export type Changes = Partial<Metrics>;
export type Quality = 'good' | 'ok' | 'bad';
export type ResKey = 'cash' | 'protect' | 'growth';
export type Alloc = Record<ResKey, number>;
export type QuestionId = 'income' | 'goal' | 'coverage' | 'risk' | 'premium';
export type CardId = 'medical' | 'income' | 'accident' | 'tools' | 'legacy' | 'care';

/** Hotspots on scene illustrations (percentage 0-100) */
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
  /** Clients with scene illustrations (prototype 5 clients): illustration id and dedicated decoy, used for finding clue hotspots */
  scene?: string | null;
  decoy?: { title: string; detail: string; spot?: Spot };
  /** Dedicated ending copy (by stress rehearsal strong / medium / weak) and consequences of "no plan" */
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
  finance?: { income: number; expense: number; savings: number };
  generated?: boolean;
}

export type TileType = 'start' | 'client' | 'life' | 'market' | 'training' | 'referral' | 'audit' | 'seminar';
export interface Tile { type: TileType; name: string }

export interface MarketEvent {
  id: string; title: string; body: string; tag: string;
  /** Absorption power per resource coin (negative value = exposure). */
  absorb: Partial<Record<ResKey, number>>;
  need: number;
  /** Bull market: growth position generates satisfaction rather than testing defenses */
  boom?: boolean;
  lesson: string;
}

export interface QuizItem { id: string; q: string; options: string[]; answer: number; explain: string }

export type BotLevel = 'novice' | 'pro';

export interface BookEntry {
  clientId: string; name: string; alloc: Alloc; cards: CardId[];
  satisfaction: number; planQuality: Quality; compliance: number;
  stressUsed: number; signedRound: number; mis: boolean;
  /** Whether lifecycle review has been conducted */
  reviewed?: boolean;
  /** Whether the interview involved a red-light violation */
  violation?: boolean;
  /** Cumulative stress absorption results (interview rehearsal + life tiles) */
  held?: number;
  partial?: number;
  broken?: number;
}

export interface Decision { round: number; clientName: string; stage: string; quality: Quality; title: string; body: string }

export interface PlayerState {
  id: string; name: string; isBot: boolean; botLevel: BotLevel | null;
  /** Login account (Google); null for guests and bot advisors */
  accountId?: string | null;
  /** Google photo URL; null for guests and bots */
  avatar?: string | null;
  connected: boolean; disconnectedAt: number | null;
  pos: number; reputation: number; commission: number;
  skillSum: Metrics; sessions: number;
  book: BookEntry[];
  decisions: Decision[];
  quizCorrect: number; quizTotal: number;
  /** Complete log of each interview (saved to training records, used to calculate weakness tags) */
  sessionLogs?: SessionLog[];
  /** Quarterly quest stats and compliance streak */
  stats?: QuestStats;
  complianceStreak?: number;
  finalTurn?: boolean;
}

export interface SessionState {
  playerId: string; clientId: string; referral: boolean;
  tileIndex?: number;
  step: 'discover' | 'plan' | 'objection' | 'result';
  asked: {
    qid: QuestionId | 'free';
    question: string;
    answer: string;
    key: string | null;
    note?: string;
    compliance?: ComplianceLevel;
    emotion?: string;
    coachTip?: string;
    source?: 'ai' | 'rule';
  }[];
  freeLeft: number;
  talkLeft?: number;
  twist?: LifeTwist | null;
  /** Standard questions matched by free-form asking (counted toward key question coverage) */
  freeHits: QuestionId[];
  /** Scene clues (3 real, 1 decoy); observed contains indices already investigated */
  clues: { title: string; detail: string; fact: string; real: boolean; spot?: Spot }[];
  /** Spectator predictions: playerId -> grade */
  predictions: Record<string, string>;
  observed: number[];
  m: Metrics;
  objectionOrder: number[];
  objectionReply?: { text: string; title: string; body: string; quality: Quality };
  objectionMode?: 'choice' | 'free';
  objViolation?: boolean;
  violationQuote?: string;
  /** AI coach hint: limited to once per interview */
  hintUsed?: boolean;
  hint?: string;
  plan?: { alloc: Alloc; cards: CardId[]; quality: Quality; notes: string[] };
  stress?: { title: string; tag: string; result: 'held' | 'partial' | 'broken'; defense: number; need: number; text: string }[];
  result?: {
    signed: boolean; score: number; grade: string; caps: string[]; commission: number; summary: string;
    predictionHits: string[];
    epilogue: { headline: string; title: string; list: string[]; noPlan: string[] };
    letter?: ClientLetter | null;
    timeline?: TimelineResult | null;
  };
  aiBusy?: boolean;
}

export interface PendingEvent {
  kind: 'life' | 'market' | 'quiz' | 'audit' | 'settlement' | 'seminar' | 'info' | 'dilemma' | 'review' | 'checkup';
  playerId: string; title: string; body: string;
  lines: { text: string; tone: 'good' | 'ok' | 'bad' | 'info' }[];
  /** order[display position] = question bank original option index; server-only, not sent to client */
  quiz?: { id: string; q: string; options: string[]; order: number[]; picked?: number; answer?: number; explain?: string };
  /** Dilemma cards (option quality is server-only, matched by id to DILEMMAS) */
  dilemma?: { id: string; title: string; prompt: string; choices: { id: string; text: string }[]; picked: string | null; outcome: { title: string; body: string; tone: 'good' | 'ok' | 'bad'; effects: string } | null };
  /** Client lifecycle review; needCard is server-only, removed before sending */
  review?: { clientId: string; clientName: string; change: { title: string; body: string }; current: { alloc: Alloc; cards: CardId[] }; needCard: CardId; picked: string | null; outcome: { title: string; body: string; tone: 'good' | 'ok' | 'bad' } | null };
  /** Territory policy checkup */
  checkup?: { clientId: string; clientName: string; referral?: boolean };
  /** Claim service moment */
  claim?: {
    clientId: string;
    clientName: string;
    event: string;
    tag: string;
    result: 'held' | 'partial' | 'broken';
    loss: number;
    covered: number;
    outOfPocket: number;
  };
}

/** Reviewable record of an interview */
export interface SessionLog {
  clientId: string; clientName: string; job: string; round: number;
  grade: string; score: number; signed: boolean; referral: boolean; hintUsed: boolean;
  twist?: { id: string; title: string; hint: string } | null;
  letter?: ClientLetter | null;
  timeline?: TimelineResult | null;
  clues: { found: number; decoy: boolean };
  questions: { qid: string; text: string; key: string | null }[];
  freeQuestion: { text: string; note: string } | null;
  plan: { alloc: Alloc; cards: CardId[]; quality: Quality; notes: string[] };
  objection: { mode: 'choice' | 'free'; text: string; quality: Quality; title: string };
  stress: { title: string; result: string }[];
  tags: string[];
  violations?: number;
  warnings?: number;
}

/** Server-wide announcement (e.g. endgame major event), displayed once per id on client */
export interface Announcement { id: string; title: string; body: string; lines: { text: string; tone: 'good' | 'ok' | 'bad' | 'info' }[] }

export interface LogLine { ts: number; text: string; tone?: 'good' | 'ok' | 'bad' | 'info' }

export interface FinalRow {
  playerId: string; name: string; isBot: boolean;
  score: number; grade: string; caps: string[];
  skill: Metrics; service: number; protection: number; reputation: number; commission: number; clients: number;
  coach: string;
  coachPending?: boolean;
  lettersPending?: boolean;
  letters?: { clientId?: string; clientName: string; outcome: 'thanks' | 'regret' | 'mixed' | 'complaint'; content: string }[];
  timeline?: TimelineResult;
  timelines?: ({ clientName: string } & TimelineResult)[];
}

export interface GameState {
  code: string; phase: 'lobby' | 'playing' | 'ended';
  hostId: string | null;
  settings: { rounds: number; aiClients: boolean };
  /** Solo practice room: guests may create it, but no other human can join or spectate. */
  solo?: boolean;
  /** Seeded demo client for reproducible video recordings */
  demo?: string;
  demoFirstRoll?: boolean;
  demoFirstSession?: boolean;
  players: PlayerState[];
  turn: number; round: number;
  turnStage: 'roll' | 'session' | 'event' | 'done';
  lastRoll: number | null;
  deck: string[];
  marketDeck: string[]; quizDeck: string[];
  clients: Record<string, ClientProfile>;
  session: SessionState | null;
  event: PendingEvent | null;
  /** Client territory on board: tile index -> owner */
  territory: Record<number, { playerId: string; clientId: string; clientName: string }>;
  log: LogLine[];
  final: FinalRow[] | null;
  announcement?: Announcement | null;
  quests?: QuestState[];
  awards?: Award[] | null;
  /** AI still writing coach feedback and letter from ten years later after settlement (report shows rule-based first, updated upon completion) */
  aiPending?: boolean;
  version: number;
}

export type Action =
  | { type: 'roll' }
  | { type: 'observe'; index: number }
  | { type: 'ask'; qid: QuestionId }
  | { type: 'ask_free'; text: string }
  | { type: 'talk'; text: string; suggested?: QuestionId }
  | { type: 'to_plan' }
  | { type: 'plan'; alloc: Alloc; cards: CardId[] }
  | { type: 'objection'; index: number }
  | { type: 'objection_free'; text: string }
  | { type: 'answer_quiz'; index: number }
  | { type: 'hint' }
  | { type: 'choose_dilemma'; choice: string }
  | { type: 'review'; card: string }
  | { type: 'continue' };
