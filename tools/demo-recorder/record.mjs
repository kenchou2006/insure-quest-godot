#!/usr/bin/env node
/**
 * Insure Quest - Automated Playwright Demo Recorder
 * Produces clean, reproducible raw footage of key gameplay moments for demo video editing.
 *
 * Requirements: Node 22, Playwright
 * Run via: node record.mjs [--url http://127.0.0.1:8787] [--size 1920x1080] [--headless] [--scenes menu,interview,result,trainer] [--code CARDIF-DEMO-2026]
 */

import { chromium } from 'playwright';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

// ───────── CLI Options Parsing ─────────

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    url: 'http://127.0.0.1:8787',
    size: '1920x1080',
    headless: false,
    scenes: ['menu', 'interview', 'result', 'trainer'],
    code: process.env.DEMO_CODE || 'CARDIF-DEMO-2026',
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      console.log(`
Usage: node record.mjs [options]

Options:
  --url <url>        Base URL of the Insure Quest web server (default: http://127.0.0.1:8787)
  --size <WxH>       Video recording resolution (default: 1920x1080)
  --headless         Run Chromium in headless mode (default: false, headed is more reliable for WebGL)
  --scenes <list>    Comma-separated list of scenes to record (default: menu,interview,result,trainer)
  --code <code>      Judge demo code to use for login (default: CARDIF-DEMO-2026 or env DEMO_CODE)
      `);
      process.exit(0);
    } else if (arg.startsWith('--url=')) {
      options.url = arg.slice(6);
    } else if (arg === '--url' && i + 1 < args.length) {
      options.url = args[++i];
    } else if (arg.startsWith('--size=')) {
      options.size = arg.slice(7);
    } else if (arg === '--size' && i + 1 < args.length) {
      options.size = args[++i];
    } else if (arg === '--headless') {
      options.headless = true;
    } else if (arg.startsWith('--scenes=')) {
      options.scenes = arg.slice(9).split(',').map((s) => s.trim().toLowerCase());
    } else if (arg === '--scenes' && i + 1 < args.length) {
      options.scenes = args[++i].split(',').map((s) => s.trim().toLowerCase());
    } else if (arg.startsWith('--code=')) {
      options.code = arg.slice(7);
    } else if (arg === '--code' && i + 1 < args.length) {
      options.code = args[++i];
    }
  }

  const [wStr, hStr] = options.size.split('x');
  options.width = parseInt(wStr, 10) || 1920;
  options.height = parseInt(hStr, 10) || 1080;

  return options;
}

const opts = parseArgs();

// Format timestamp: YYYYMMDD-HHmm in local time
function getTimestamp() {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const y = now.getFullYear();
  const m = pad(now.getMonth() + 1);
  const d = pad(now.getDate());
  const h = pad(now.getHours());
  const min = pad(now.getMinutes());
  return `${y}${m}${d}-${h}${min}`;
}

const repoRoot = path.resolve(import.meta.dirname, '../..');
const recordingsRoot = path.resolve(repoRoot, 'recordings');
const timestamp = getTimestamp();
const targetOutputDir = path.join(recordingsRoot, timestamp);
const tempVideoDir = path.join(recordingsRoot, `.temp-${Date.now()}`);

fs.mkdirSync(tempVideoDir, { recursive: true });

console.log(`[IQ Recorder] Starting demo recorder with settings:`);
console.log(`  URL:        ${opts.url}`);
console.log(`  Size:       ${opts.width}x${opts.height}`);
console.log(`  Headless:   ${opts.headless}`);
console.log(`  Scenes:     ${opts.scenes.join(', ')}`);
console.log(`  Code:       ${opts.code}`);
console.log(`  Target Dir: ${targetOutputDir}`);

let currentScene = 'init';
let lastWaitingFor = '';
let page = null;

// Error handler taking screenshot
async function handleError(err) {
  console.error(`\n[IQ Recorder ERROR] Scene "${currentScene}" failed:`, err.message || err);
  if (lastWaitingFor) {
    console.error(`[IQ Recorder ERROR] Was waiting for text: "${lastWaitingFor}"`);
  }
  if (page) {
    try {
      const errorScreenshot = path.resolve(process.cwd(), `error-${currentScene}.png`);
      await page.screenshot({ path: errorScreenshot, fullPage: true });
      console.error(`[IQ Recorder] Saved failure screenshot to: ${errorScreenshot}`);
    } catch (e) {
      console.error(`[IQ Recorder] Failed to capture error screenshot:`, e.message);
    }
  }
  process.exit(1);
}

process.on('unhandledRejection', handleError);

// ───────── Playwright Automation & Helpers ─────────

async function main() {
  const browser = await chromium.launch({
    headless: opts.headless,
    args: ['--autoplay-policy=no-user-gesture-required'],
  });

  const context = await browser.newContext({
    viewport: { width: opts.width, height: opts.height },
    deviceScaleFactor: 1,
    recordVideo: {
      dir: tempVideoDir,
      size: { width: opts.width, height: opts.height },
    },
  });

  page = await context.newPage();

  // Inject visible cursor that follows Playwright mousemove (Playwright does not render OS cursor in video)
  const injectCursorScript = () => {
    if (document.getElementById('__iq_rec_cursor__')) return;
    const dot = document.createElement('div');
    dot.id = '__iq_rec_cursor__';
    dot.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      width: 22px;
      height: 22px;
      margin-left: -11px;
      margin-top: -11px;
      border-radius: 50%;
      background: rgba(255, 60, 60, 0.75);
      border: 2px solid #ffffff;
      box-shadow: 0 0 6px rgba(0, 0, 0, 0.6);
      pointer-events: none;
      z-index: 2147483647;
      transition: transform 0.08s ease, background 0.08s ease;
      transform: scale(1);
    `;
    document.body.appendChild(dot);
    window.addEventListener('mousemove', (e) => {
      dot.style.left = e.clientX + 'px';
      dot.style.top = e.clientY + 'px';
    }, { passive: true });
    window.addEventListener('mousedown', () => {
      dot.style.transform = 'scale(0.7)';
      dot.style.background = 'rgba(255, 215, 0, 0.9)';
    }, { passive: true });
    window.addEventListener('mouseup', () => {
      dot.style.transform = 'scale(1)';
      dot.style.background = 'rgba(255, 60, 60, 0.75)';
    }, { passive: true });
  };

  await page.addInitScript(injectCursorScript);

  // Helper primitives
  const hold = async (ms = 1500) => {
    await page.waitForTimeout(ms);
  };

  const find = async (query) => {
    return await page.evaluate((q) => {
      return window.iqAuto ? window.iqAuto.find(q) : null;
    }, query);
  };

  const list = async () => {
    return await page.evaluate(() => {
      return window.iqAuto ? window.iqAuto.list() : [];
    });
  };

  const screen = async () => {
    return await page.evaluate(() => {
      return window.iqAuto ? window.iqAuto.screen() : null;
    });
  };

  // Buttons first; otherwise any on-screen text (labels) so we can wait for screen state
  const findAny = async (query) => {
    return await page.evaluate((q) => {
      if (!window.iqAuto) return null;
      return window.iqAuto.find(q) || (window.iqAuto.findText ? window.iqAuto.findText(q) : null);
    }, query);
  };

  const waitFor = async (query, timeoutMs = 60000) => {
    lastWaitingFor = query;
    const startTime = Date.now();
    while (Date.now() - startTime < timeoutMs) {
      const el = await findAny(query);
      if (el) {
        lastWaitingFor = '';
        return el;
      }
      await page.waitForTimeout(200);
    }
    throw new Error(`Timed out waiting for element matching "${query}" after ${timeoutMs} ms`);
  };

  // Scroll into view if element is positioned outside the viewport (Claude note #38)
  const scrollIntoViewIfNeeded = async (target) => {
    if (!target) return target;
    let cy = target.y + target.h / 2;
    const margin = 90;
    let attempts = 0;

    while ((cy < margin || cy > opts.height - margin) && attempts < 12) {
      attempts++;
      // Move mouse over the session panel area and scroll
      const panelX = Math.round(opts.width * 0.65);
      const panelY = Math.round(opts.height * 0.5);
      await page.mouse.move(panelX, panelY, { steps: 5 });

      const delta = cy > opts.height - margin ? 260 : -260;
      await page.mouse.wheel(0, delta);
      await page.waitForTimeout(160);

      const refreshed = await find(target.text);
      if (refreshed) {
        target = refreshed;
        cy = target.y + target.h / 2;
      } else {
        break;
      }
    }
    return target;
  };

  // Smooth mouse movement in ~15 steps to button center, short pause, then click (spec §16)
  const click = async (queryOrItem, { holdAfter = 500, steps = 15 } = {}) => {
    let item;
    if (typeof queryOrItem === 'string') {
      item = await waitFor(queryOrItem);
    } else {
      item = queryOrItem;
    }

    item = (await scrollIntoViewIfNeeded(item)) || item;

    const cx = item.x + item.w / 2;
    const cy = item.y + item.h / 2;

    await page.mouse.move(cx, cy, { steps });
    await page.waitForTimeout(120);
    await page.mouse.down();
    await page.waitForTimeout(70);
    await page.mouse.up();
    if (holdAfter > 0) {
      await page.waitForTimeout(holdAfter);
    }
  };

  // Type into DOM #iq-input overlay with ~90ms delay per char (spec §16 & Claude note #40)
  const typeHuman = async (text, { delay = 90 } = {}) => {
    await page.waitForSelector('#iq-input', { state: 'visible', timeout: 10000 });
    await page.focus('#iq-input');
    await page.keyboard.type(text, { delay });
    await page.waitForTimeout(300);
  };

  // Wait for AI response (Claude note #41: takes 5-15s, poll until client bubble / suggestions ready)
  const waitForAiReply = async (timeoutMs = 45000) => {
    const startTime = Date.now();
    lastWaitingFor = 'AI Client Reply';
    while (Date.now() - startTime < timeoutMs) {
      const thinking = await find('客戶思考中……');
      const isDiscover = await page.evaluate(() => {
        const s = window.iqAuto ? window.iqAuto.screen() : null;
        if (!s) return false;
        return typeof s === 'object' ? s.step === 'discover' : false;
      });

      if (!thinking && isDiscover) {
        // Check if input or suggested questions are re-enabled
        const inputField = await find('輸入你想向客戶');
        const toPlanBtn = await find('進入方案配置');
        if (inputField || toPlanBtn) {
          lastWaitingFor = '';
          return;
        }
      }
      await page.waitForTimeout(300);
    }
    throw new Error(`Timed out waiting for AI client reply after ${timeoutMs} ms`);
  };

  // ───────── Open Page & Initialize ─────────

  // Note #39: ?code=<CODE> in the URL logs in automatically without reloading the page
  const targetUrl = new URL(opts.url);
  targetUrl.searchParams.set('automation', '1');
  targetUrl.searchParams.set('demo', '1');
  if (opts.code) {
    targetUrl.searchParams.set('code', opts.code);
  }

  console.log(`[IQ Recorder] Navigating to ${targetUrl.toString()} ...`);
  await page.goto(targetUrl.toString(), { waitUntil: 'domcontentloaded' });

  // Re-inject cursor if needed after DOM is ready
  await page.evaluate(injectCursorScript);

  // Wait until window.iqAuto is ready (timeout 60s, Godot load)
  console.log('[IQ Recorder] Waiting for window.iqAuto bridge to initialize (up to 60s) ...');
  lastWaitingFor = 'window.iqAuto';
  await page.waitForFunction(() => typeof window.iqAuto !== 'undefined', null, { timeout: 60000 });
  lastWaitingFor = '';
  console.log('[IQ Recorder] window.iqAuto is ready!');

  const chapters = [];
  const recordingStartTime = Date.now();

  const recordChapter = (scene, label, fn) => async () => {
    currentScene = scene;
    const startSec = Number(((Date.now() - recordingStartTime) / 1000).toFixed(2));
    console.log(`\n▶ [Scene: ${scene}] Starting: "${label}" at ${startSec}s`);
    await fn();
    const endSec = Number(((Date.now() - recordingStartTime) / 1000).toFixed(2));
    console.log(`■ [Scene: ${scene}] Completed: "${label}" at ${endSec}s (duration: ${(endSec - startSec).toFixed(2)}s)`);
    chapters.push({ scene, label, start: startSec, end: endSec });
  };

  // ───────── Scene 1: menu ─────────
  // Title/menu visible 3s -> enter judge code -> toast
  const runMenuScene = recordChapter('menu', '主選單與評審體驗登入', async () => {
    // Wait for menu screen
    await page.waitForFunction(() => {
      const s = window.iqAuto?.screen();
      return s === 'menu' || (typeof s === 'object' && s.screen === 'menu');
    }, null, { timeout: 15000 });

    console.log('  Holding 3s on menu screen for video introduction ...');
    await hold(3000);

    // Wait for auth card to settle (asynchronous ~3-8s after load)
    console.log('  Waiting for auth card to resolve ...');
    await page.waitForFunction(() => {
      return !!(window.iqAuto?.find('登出') || window.iqAuto?.find('評審體驗碼') || window.iqAuto?.find('測試登入'));
    }, null, { timeout: 20000 });

    const logoutBtn = await find('登出');
    if (logoutBtn) {
      console.log('  Already logged in (via URL ?code or existing session).');
      // If code was consumed, a toast appeared or avatar is visible
      await hold(1500);
    } else {
      const demoBtn = await find('評審體驗碼');
      if (demoBtn && opts.code) {
        console.log(`  Clicking 「評審體驗碼」 to enter judge code ${opts.code} ...`);
        await click('評審體驗碼');
        await waitFor('輸入體驗碼');
        await click('輸入體驗碼');
        await typeHuman(opts.code);
        await click('進入');
        console.log('  Waiting for login toast ...');
        await waitFor('已啟用 AI 體驗額度', 15000);
        await hold(1500);
      } else {
        const devLoginBtn = await find('測試登入');
        if (devLoginBtn) {
          console.log('  Clicking 「測試登入」 ...');
          await click('測試登入');
          await hold(2000);
        }
      }
    }
  });

  // ───────── Scene 2: interview ─────────
  // Start solo (2 bots, 資深) -> roll dice -> mortgage client -> 2 hotspots -> violation line -> red light -> hold 3s -> compliant question -> suggested question
  const runInterviewScene = recordChapter('interview', '單人對戰與深度需求訪談', async () => {
    // If not in game, start solo from menu
    const curScreen = await screen();
    const isGame = typeof curScreen === 'object' && curScreen.screen === 'game';
    if (!isGame) {
      console.log('  Starting solo practice with 2 bots (資深顧問) ...');
      await click('▶ 開始單人練習');
    }

    console.log('  Waiting for game board and dice roll button ...');
    await waitFor('▶ 擲骰子', 30000);
    await hold(1500);

    console.log('  Rolling dice ...');
    await click('▶ 擲骰子');

    // Demo seed lands on mortgage client (劉家豪). Wait for interview panel.
    console.log('  Waiting for client interview screen (劉家豪 - 房貸科技工程師) ...');
    await waitFor('生活場景探索', 35000);
    await hold(1500);

    // Click 2 scene hotspots
    console.log('  Finding scene hotspots ...');
    let elements = await list();
    let hotspots = elements.filter((el) => el.text && el.text.startsWith('hotspot:'));

    if (hotspots.length > 0) {
      console.log(`  Clicking hotspot #1 (${hotspots[0].text}) ...`);
      await click(hotspots[0]);
      await hold(1500);

      // Re-query unobserved hotspots
      elements = await list();
      hotspots = elements.filter((el) => el.text && el.text.startsWith('hotspot:'));
      if (hotspots.length > 0) {
        console.log(`  Clicking hotspot #2 (${hotspots[0].text}) ...`);
        await click(hotspots[0]);
        await hold(1500);
      }
    } else {
      console.log('  Hotspots already investigated or using clue list.');
    }

    // Violation line
    const violationText = '這張保單保證年報酬 6%，比定存穩賺不賠';
    console.log(`  Typing violation line: "${violationText}" ...`);
    const inputField = await waitFor('輸入你想向客戶');
    await click(inputField);
    await typeHuman(violationText);
    await click('送出');

    console.log('  Waiting for compliance red light warning ...');
    await waitFor('踩到合規紅燈', 45000);
    console.log('  Holding 3s on red light warning for impact ...');
    await hold(3000);

    // Compliant question
    const compliantText = '如果收入中斷三個月，家裡哪些支出一定要先顧住？';
    console.log(`  Typing compliant question: "${compliantText}" ...`);
    const nextInputField = await waitFor('輸入你想向客戶', 45000);
    await click(nextInputField);
    await typeHuman(compliantText);
    await click('送出');

    console.log('  Waiting for AI client response to compliant question ...');
    await waitForAiReply(45000);
    await hold(2000);

    // Click one suggested question
    console.log('  Selecting one suggested question ...');
    const standardQuestions = [
      '目前遇到醫療或無法工作時',
      '這個人生目標裡，哪一部分是你最不願意犧牲的',
      '這筆目標資金在使用前，你最多能接受多少波動',
      '在預備金、保障和投資之間，你過去是如何分配的',
    ];

    let foundQuestion = null;
    const currentList = await list();
    for (const qPhrase of standardQuestions) {
      const match = currentList.find((el) => el.text && el.text.includes(qPhrase) && !el.text.includes('✓'));
      if (match) {
        foundQuestion = match;
        break;
      }
    }

    if (foundQuestion) {
      console.log(`  Clicking suggested question: "${foundQuestion.text.slice(0, 20)}..." ...`);
      await click(foundQuestion);
      console.log('  Waiting for client reply to suggested question ...');
      await waitForAiReply(45000);
      await hold(2000);
    } else {
      console.log('  No unasked suggested question found; proceeding.');
      await hold(1500);
    }
  });

  // ───────── Scene 3: result ─────────
  // Go to plan -> set coins (cash/protect/growth via ＋/－) and pick 2 cards matching mortgage client -> objection: pick best -> result: scroll stress test, 10y timeline, letter -> hold 4s -> continue
  const runResultScene = recordChapter('result', '方案配置、異議處理與十年信件', async () => {
    console.log('  Proceeding to plan allocation ...');
    await waitFor('進入方案配置', 15000);
    await click('進入方案配置');
    await hold(1500);

    // Note #42: ＋ buttons are disabled while 0 coins remain; press － first
    console.log('  Adjusting resource coins (10 coins) ...');
    const allButtons = await list();
    const minusButtons = allButtons.filter((el) => el.text === '－').sort((a, b) => a.y - b.y);

    if (minusButtons.length >= 3) {
      // Reduce growth (row 3, index 2)
      console.log('  Pressing － on growth to free up 1 coin ...');
      await click(minusButtons[2]);
      await hold(800);

      // Now ＋ buttons are enabled; increase protect (row 2, index 1)
      const plusList = await list();
      const plusButtons = plusList.filter((el) => el.text === '＋').sort((a, b) => a.y - b.y);
      if (plusButtons.length >= 2) {
        console.log('  Pressing ＋ on protect ...');
        await click(plusButtons[1]);
        await hold(800);
      }
    }

    // Pick 2 coverage cards matching mortgage client (劉家豪: 工作能力防線, 家庭責任防線)
    console.log('  Selecting coverage cards matching mortgage client (工作能力防線, 家庭責任防線) ...');
    await click('工作能力防線');
    await hold(800);
    await click('家庭責任防線');
    await hold(1000);

    console.log('  Submitting plan ...');
    await click('提交方案');
    await hold(1500);

    // Objection: Note #43: pick the one starting with 「投資照樣留著長期成長」
    console.log('  Waiting for client objection ...');
    await waitFor('投資照樣留著長期成長', 20000);
    console.log('  Selecting best objection response: 「投資照樣留著長期成長」 ...');
    await click('投資照樣留著長期成長');
    await hold(2000);

    // Result screen
    console.log('  Waiting for result and evaluation screen ...');
    await waitFor('90 天壓力預演', 30000);
    console.log('  Holding 2.5s on top score evaluation ...');
    await hold(2500);

    // Scroll slowly through stress test
    console.log('  Scrolling slowly through 90-day stress test ...');
    const panelX = Math.round(opts.width * 0.65);
    const panelY = Math.round(opts.height * 0.5);
    await page.mouse.move(panelX, panelY, { steps: 5 });

    for (let i = 0; i < 6; i++) {
      await page.mouse.wheel(0, 90);
      await page.waitForTimeout(220);
    }

    // Scroll to 10-year timeline chart
    console.log('  Centering 10-year financial timeline chart ...');
    const chartEl = await waitFor('十年財務人生', 12000);
    await scrollIntoViewIfNeeded(chartEl);
    console.log('  Holding 4s on 10-year timeline chart ...');
    await hold(4000);

    // Scroll to letter from ten years later (complaint version due to compliance violation)
    console.log('  Scrolling down to letter from ten years later ...');
    for (let i = 0; i < 7; i++) {
      await page.mouse.wheel(0, 100);
      await page.waitForTimeout(200);
    }

    let letterEl = await find('寄來的申訴副本');
    if (!letterEl) letterEl = await find('申訴副本');
    if (letterEl) {
      await scrollIntoViewIfNeeded(letterEl);
    }
    console.log('  Holding 4s on complaint letter ...');
    await hold(4000);

    // Scroll to 「繼續 →」 button
    console.log('  Scrolling to 「繼續 →」 button ...');
    const continueBtn = await waitFor('繼續 →', 12000);
    await scrollIntoViewIfNeeded(continueBtn);
    await hold(1200);
    await click('繼續 →');
    await hold(1800);
  });

  // ───────── Scene 4: trainer ─────────
  // Optional: open 培訓紀錄 -> heatmap tab -> hold 4s
  const runTrainerScene = recordChapter('trainer', '講師管理與弱點熱力圖', async () => {
    console.log('  Opening 培訓紀錄 from menu ...');
    const recordsBtn = await waitFor('培訓紀錄', 15000);
    await click(recordsBtn);
    await hold(1500);

    await waitFor('回主選單', 15000);

    // Check if user is a trainer (弱點熱力圖 tab exists)
    const heatmapTab = await find('弱點熱力圖');
    if (heatmapTab) {
      console.log('  Trainer detected! Opening 「弱點熱力圖」 tab ...');
      await click(heatmapTab);
      console.log('  Holding 4s on weakness heatmap ...');
      await hold(4000);
    } else {
      console.log('  [trainer] Logged-in user is not a trainer locally (弱點熱力圖 tab not available). Skipping heatmap.');
      await hold(1500);
    }
  });

  // ───────── Execute Requested Scenes ─────────

  const sceneMap = {
    menu: runMenuScene,
    interview: runInterviewScene,
    result: runResultScene,
    trainer: runTrainerScene,
  };

  for (const sceneName of opts.scenes) {
    const fn = sceneMap[sceneName];
    if (fn) {
      await fn();
    } else {
      console.warn(`[IQ Recorder] Unknown scene "${sceneName}", skipping.`);
    }
  }

  // ───────── Finalize Recording & Video Files ─────────

  console.log('\n[IQ Recorder] Closing browser context to flush video to disk ...');
  await context.close();
  await browser.close();

  // Find generated video in temp directory
  const files = fs.readdirSync(tempVideoDir);
  const videoFile = files.find((f) => f.endsWith('.webm'));

  if (!videoFile) {
    throw new Error(`No .webm video was generated in ${tempVideoDir}`);
  }

  fs.mkdirSync(targetOutputDir, { recursive: true });
  const rawVideoDest = path.join(targetOutputDir, 'raw.webm');
  const tempVideoPath = path.join(tempVideoDir, videoFile);

  fs.renameSync(tempVideoPath, rawVideoDest);
  try {
    fs.rmdirSync(tempVideoDir);
  } catch (_) {}

  console.log(`[IQ Recorder] Saved raw footage: ${rawVideoDest}`);

  // Write chapters.json
  const chaptersDest = path.join(targetOutputDir, 'chapters.json');
  fs.writeFileSync(chaptersDest, JSON.stringify(chapters, null, 2), 'utf-8');
  console.log(`[IQ Recorder] Saved chapter markers: ${chaptersDest}`);

  // Cut NN-<scene>.mp4 per chapter if ffmpeg is on PATH (spec §25)
  let hasFfmpeg = false;
  try {
    const check = spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' });
    hasFfmpeg = check.status === 0;
  } catch (_) {
    hasFfmpeg = false;
  }

  if (hasFfmpeg) {
    console.log('[IQ Recorder] ffmpeg detected. Cutting per-chapter clips (H.264, CRF 18, 30fps) ...');
    for (let i = 0; i < chapters.length; i++) {
      const ch = chapters[i];
      const numStr = String(i + 1).padStart(2, '0');
      const outClip = path.join(targetOutputDir, `${numStr}-${ch.scene}.mp4`);
      const duration = Math.max(0.1, ch.end - ch.start);

      console.log(`  Cutting [${numStr}-${ch.scene}.mp4] (${ch.start}s - ${ch.end}s, duration: ${duration.toFixed(2)}s) ...`);
      const args = [
        '-y',
        '-ss',
        String(ch.start),
        '-t',
        String(duration),
        '-i',
        rawVideoDest,
        '-c:v',
        'libx264',
        '-crf',
        '18',
        '-r',
        '30',
        '-c:a',
        'aac',
        outClip,
      ];
      const res = spawnSync('ffmpeg', args, { stdio: 'inherit' });
      if (res.status === 0) {
        console.log(`  ✓ Saved ${outClip}`);
      } else {
        console.warn(`  × Failed to cut ${outClip} (exit code ${res.status})`);
      }
    }
  } else {
    console.log('[IQ Recorder] Note: ffmpeg is not found on PATH. Skipped cutting per-chapter MP4 clips.');
  }

  console.log('\n========================================');
  console.log('🎉 Demo recording completed successfully!');
  console.log(`Directory: ${targetOutputDir}`);
  console.log(`Chapters:  ${chapters.length} markers written to chapters.json`);
  console.log('========================================\n');
}

main().catch(handleError);
