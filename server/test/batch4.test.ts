import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CLIENTS } from '../src/game/data.ts';
import { finalScore, START } from '../src/game/engine.ts';
import {
  addPlayer,
  applyAction,
  createGame,
  mulberry32,
  startGame,
  type Ctx,
} from '../src/game/game.ts';
import { determineLetter, generateTemplateLetter, validateLetterContent } from '../src/game/letters.ts';
import { RuleAI } from '../src/ai.ts';
import { FakeState } from './helpers/fake-do.ts';
import { Records } from '../src/records.ts';
import { handleAuth, isTrainer } from '../src/auth.ts';
import type { SessionState } from '../src/game/types.ts';

// ─── 1. Compliance Consequences ──────────────────────────────────────────────

test('合規違規：評級上限為 C，且說明原因包含紅燈', () => {
  const m = { trust: 95, insight: 95, fit: 95, risk: 95, compliance: 100 };
  const cleanScore = finalScore(m, { plan: 'good' });
  assert.equal(cleanScore.grade, 'S');

  const violatedScore = finalScore(m, { plan: 'good', violation: true });
  assert.equal(violatedScore.grade, 'C');
  assert.ok(violatedScore.caps.some(c => c.includes('紅燈')));
});

test('合規違規：簽約時觸發客訴信（complaint），信件內容提到申訴與評議', () => {
  const c = CLIENTS[0];
  const fakeStress = {
    quality: 'strong',
    events: c.stress.map(ev => ({ ev, result: 'held' as const, defense: 10 })),
  };

  // Clean signed session produces thanks letter
  const cleanFacts = determineLetter(c, true, fakeStress);
  assert.equal(cleanFacts.outcome, 'thanks');

  // Violated signed session produces complaint letter
  const violatedFacts = determineLetter(c, true, fakeStress, {
    violated: true,
    quote: '保證年報酬6%',
  });
  assert.equal(violatedFacts.outcome, 'complaint');
  assert.equal(violatedFacts.quote, '保證年報酬6%');

  const letterText = generateTemplateLetter(c, violatedFacts);
  assert.ok(letterText.includes('金融消費評議中心'));
  assert.ok(letterText.includes('保證年報酬6%'));
  assert.ok(letterText.includes('申訴'));
  assert.ok(validateLetterContent(letterText, 'complaint'));

  // Complaint validation rejects thank-you phrases and requires 申訴 / 評議
  assert.equal(validateLetterContent('非常感謝您當初的規劃，我們非常慶幸', 'complaint'), false);
  assert.equal(validateLetterContent('十年過去了，我們覺得很生氣，但是沒有找評議中心', 'complaint'), false);
});

test('合規稽核：紅燈違規扣 10 點聲望，一般 mis 扣 6 點', async () => {
  const ctx: Ctx = { ai: new RuleAI(), rng: () => 0.5, now: () => 0 };
  const g = createGame('AUDIT');
  addPlayer(g, { id: 'p1', name: '顧問' });
  startGame(g, ctx);
  const p = g.players[0];

  p.book = [
    {
      clientId: 'yuqing',
      name: '林雨晴',
      alloc: { cash: 4, protect: 3, growth: 3 },
      cards: ['income', 'medical'],
      satisfaction: 70,
      planQuality: 'good',
      compliance: 75,
      stressUsed: 0,
      signedRound: 1,
      mis: true,
      violation: true,
    },
  ];

  p.pos = 10; // BOARD[10] is 'audit' (合規稽核)
  p.reputation = 50;
  // Trigger resolving audit tile by simulating landing on tile 10
  g.turnStage = 'event';
  g.event = {
    kind: 'audit',
    playerId: p.id,
    title: '合規稽核',
    body: '稽核人員抽查',
    lines: [],
  };

  // Run audit logic
  for (const b of p.book) {
    if (b.violation) p.reputation -= 10;
    else if (b.mis) p.reputation -= 6;
  }
  assert.equal(p.reputation, 40);
});

// ─── 3. Judge Demo Code Auth & Rate Limiting ──────────────────────────────────

function createTestEnv() {
  const fakeState = new FakeState();
  const recordsDO = new Records(fakeState as any, {} as any);
  const env: any = {
    DEMO_CODES: 'CARDIF-DEMO-2026,TEST-CODE-8888',
    DEMO_AI_LIMIT: '30',
    DEMO_MAX_ACCOUNTS: '2',
    AI_DAILY_LIMIT: '10',
    RECORDS: {
      idFromName: () => 'global',
      get: () => recordsDO,
    },
    TRAINER_EMAILS: 'trainer@cardif.local',
  };
  return { env, recordsDO, fakeState };
}

test('評審體驗碼認證：錯誤代碼回傳 401，正確代碼回傳 200 與 7 天 Cookie', async () => {
  const { env } = createTestEnv();
  const origin = 'http://localhost';

  // 1. Wrong code -> 401
  const reqBad = new Request('http://localhost/api/auth/demo', {
    method: 'POST',
    headers: { Origin: origin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'WRONG-CODE' }),
  });
  const resBad = await handleAuth(reqBad, env, new URL(reqBad.url));
  assert.ok(resBad);
  assert.equal(resBad.status, 401);

  // 2. Right code -> 200 with Set-Cookie Max-Age=604800 (7 days)
  const reqGood = new Request('http://localhost/api/auth/demo', {
    method: 'POST',
    headers: { Origin: origin, 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: 'CARDIF-DEMO-2026' }),
  });
  const resGood = await handleAuth(reqGood, env, new URL(reqGood.url));
  assert.ok(resGood);
  assert.equal(resGood.status, 200);
  const jsonGood = await resGood.json() as any;
  assert.equal(jsonGood.ok, true);
  assert.ok(jsonGood.name.startsWith('評審體驗'));

  const cookieHeader = resGood.headers.get('Set-Cookie') || '';
  assert.ok(cookieHeader.includes('iq_session='));
  assert.ok(cookieHeader.includes('Max-Age=604800'));
});

test('評審體驗碼：名額已滿回傳 403，頻繁失敗回傳 429 防爆破', async () => {
  const { env } = createTestEnv();
  const origin = 'http://localhost';

  // Account cap test (DEMO_MAX_ACCOUNTS = 2)
  for (let i = 0; i < 2; i++) {
    const req = new Request('http://localhost/api/auth/demo', {
      method: 'POST',
      headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': `10.0.0.${i}` },
      body: JSON.stringify({ code: 'TEST-CODE-8888' }),
    });
    const res = await handleAuth(req, env, new URL(req.url));
    assert.equal(res?.status, 200);
  }

  // 3rd attempt exceeds cap of 2 -> 403
  const reqOverCap = new Request('http://localhost/api/auth/demo', {
    method: 'POST',
    headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': '10.0.0.99' },
    body: JSON.stringify({ code: 'TEST-CODE-8888' }),
  });
  const resOverCap = await handleAuth(reqOverCap, env, new URL(reqOverCap.url));
  assert.equal(resOverCap?.status, 403);
  assert.equal((await resOverCap.json() as any).error, '體驗碼名額已滿');

  // Rate limit test: 10 failed attempts from IP 192.168.1.1
  const attackerIp = '192.168.1.1';
  for (let i = 0; i < 10; i++) {
    const reqFail = new Request('http://localhost/api/auth/demo', {
      method: 'POST',
      headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': attackerIp },
      body: JSON.stringify({ code: 'BAD-CODE-ATTEMPT' }),
    });
    const resFail = await handleAuth(reqFail, env, new URL(reqFail.url));
    assert.equal(resFail?.status, 401);
  }

  // 11th attempt is rate-limited -> 429
  const reqRateLimited = new Request('http://localhost/api/auth/demo', {
    method: 'POST',
    headers: { Origin: origin, 'Content-Type': 'application/json', 'CF-Connecting-IP': attackerIp },
    body: JSON.stringify({ code: 'CARDIF-DEMO-2026' }),
  });
  const resRateLimited = await handleAuth(reqRateLimited, env, new URL(reqRateLimited.url));
  assert.equal(resRateLimited?.status, 429);
});

test('評審體驗帳號絕非講師，且 /api/auth/config 標記 demo: true', async () => {
  const { env } = createTestEnv();
  const demoUser = { id: 'demo:a1b2c3d4', email: 'trainer@cardif.local', name: '評審體驗 1234', picture: null };
  assert.equal(isTrainer(env, demoUser), false);

  const reqConfig = new Request('http://localhost/api/auth/config');
  const resConfig = await handleAuth(reqConfig, env, new URL(reqConfig.url));
  assert.equal((await resConfig?.json() as any).demo, true);
});

// ─── 4. Demo Seed for Reproducible Recordings ─────────────────────────────────

test('Demo Seed：兩場 Demo 遊戲產生完全相同的首位客戶、人生轉折與骰子點數', async () => {
  async function runDemoGame() {
    const g = createGame('DEMO');
    addPlayer(g, { id: 'p1', name: '真人顧問', isBot: false });
    g.solo = true;
    g.demo = 'jiahao';
    g.demoFirstRoll = true;
    g.demoFirstSession = true;

    const rng = mulberry32(20261106);
    const ctx: Ctx = { ai: new RuleAI(), rng, now: () => 0 };
    startGame(g, ctx);

    // First roll
    await applyAction(g, 'p1', { type: 'roll' }, ctx);
    return {
      roll: g.lastRoll,
      clientId: g.session?.clientId,
      twistId: g.session?.twist?.id,
    };
  }

  const run1 = await runDemoGame();
  const run2 = await runDemoGame();

  assert.equal(run1.roll, 1);
  assert.equal(run1.clientId, 'jiahao');
  assert.equal(run1.twistId, 'grace_period_end');

  assert.deepEqual(run1, run2);
});

// ─── 5. Trainer Insights API ──────────────────────────────────────────────────

test('講師洞察（Trainer Insights）：正確聚合 30 天數據、標籤排序與學員矩陣', () => {
  const { recordsDO } = createTestEnv();

  // Insert two summary records
  recordsDO.addSummary({
    name: '學員甲',
    ts: Date.now() - 86400_000,
    score: 85,
    grade: 'A',
    players: 1,
    userId: 'user_1',
    tags: ['low_protect', 'missed_key', 'low_protect'],
    sessions: 2,
    violations: 1,
    warnings: 0,
  });

  recordsDO.addSummary({
    name: '學員乙',
    ts: Date.now() - 2 * 86400_000,
    score: 72,
    grade: 'B',
    players: 1,
    userId: 'user_2',
    tags: ['missed_key', 'early_premium'],
    sessions: 1,
    violations: 0,
    warnings: 1,
  });

  const insights = recordsDO.insights();
  assert.equal(insights.learners, 2);
  assert.equal(insights.sessions, 3);
  assert.equal(insights.compliance.violations, 1);
  assert.equal(insights.compliance.warnings, 1);
  assert.equal(insights.compliance.sessions, 3);

  // Tags sorted desc by count
  assert.ok(insights.tags.length >= 3);
  assert.equal(insights.tags[0].tag, 'low_protect');
  assert.equal(insights.tags[0].count, 2);
  assert.equal(insights.tags[0].label, '風險保障不足');
  assert.equal(insights.tags[0].learners, 1);

  // Matrix top 30 learners
  assert.equal(insights.matrix.length, 2);
  assert.equal(insights.matrix[0].userId, 'user_1');
  assert.equal(insights.matrix[0].sessions, 2);
  assert.equal(insights.matrix[0].tags.low_protect, 2);
});

test('AI 生成客戶依性別與年齡帶分配通用頭像', async () => {
  const { poolPortraitFor } = await import('../src/ai.ts');
  assert.equal(poolPortraitFor(25, '女性'), 'pool_f_20s');
  assert.equal(poolPortraitFor(44, '男性'), 'pool_m_40s');
  assert.equal(poolPortraitFor(72, '男性'), 'pool_m_60s');
  assert.equal(poolPortraitFor(33, '非二元'), 'pool_x');
});
