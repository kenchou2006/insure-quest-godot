/* 產生 Godot 編輯器預覽用的假資料：跑一場電腦對局，擷取各階段的 publicView（以 p1 視角）。
 * 用法：node tools/dump-preview-states.ts → ../client/scenes/preview/states.json */
import { writeFileSync, mkdirSync } from 'node:fs';
import { addPlayer, applyAction, createGame, publicView, startGame, type Ctx } from '../src/game/game.ts';
import { botAction } from '../src/game/bots.ts';
import { RuleAI } from '../src/ai.ts';
import { BOARD, CARDS, QUESTIONS } from '../src/game/data.ts';
import type { GameState } from '../src/game/types.ts';

function seeded(seed: number) {
  let s = seed >>> 0;
  return () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const ctx: Ctx = { ai: new RuleAI(), rng: seeded(7), now: Date.now };
const VIEWER = 'p1';
const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x));

const g: GameState = createGame('DEMO');
const lobbyNames: [string, string, 'pro' | 'novice'][] = [['p1', '你（王顧問）', 'pro'], ['b1', '電腦顧問・安安', 'pro'], ['b2', '電腦顧問・小賴', 'novice'], ['b3', '電腦顧問・阿哲', 'novice']];
for (const [id, name, lv] of lobbyNames) addPlayer(g, { id, name, isBot: id !== 'p1', botLevel: lv });
const out: Record<string, unknown> = { lobby: publicView(g, VIEWER) };
startGame(g, ctx);
out.roll = publicView(g, VIEWER);

const want = new Set(['discover', 'plan', 'objection', 'result', 'event']);
let guard = 0;
while (g.phase === 'playing' && guard++ < 5000) {
  const actor = g.players[g.turn].id;
  // 只擷取「輪到你」的畫面，預覽才會出現可操作的按鈕
  if (actor === VIEWER) {
    const key = g.turnStage === 'session' ? g.session?.step : g.turnStage === 'event' ? 'event' : null;
    // 面談對話擷取「已對話兩輪」的時刻，預覽才看得到對話泡泡與合規燈號
    const ready = key !== 'discover' || (g.session?.asked.length ?? 0) >= 2;
    if (key && ready && want.has(key)) { out[key] = publicView(g, VIEWER); want.delete(key); }
  }
  let a = botAction(g, ctx.rng);
  if (!a) break;
  if (actor === VIEWER && a.type === 'talk' && (g.session?.asked.length ?? 0) === 1) a = { type: 'talk', text: '這張保單保證收益，比定存好，不買會後悔喔！' };
  await applyAction(g, actor, a, ctx);
}
out.ended = publicView(g, VIEWER);
out.static = { board: BOARD, questions: QUESTIONS.map(q => ({ id: q.id, text: q.text, coach: q.coach })), cards: CARDS };
out.playerId = VIEWER;
if (want.size) console.warn('未擷取到：', [...want].join(', '));
mkdirSync('../client/scenes/preview', { recursive: true });
writeFileSync('../client/scenes/preview/states.json', JSON.stringify(clone(out)));
console.log('已輸出', Object.keys(out).join(', '));
