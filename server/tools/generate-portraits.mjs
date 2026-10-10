#!/usr/bin/env node
/**
 * INSURE QUEST | Batch 9: Client Portraits and Title Visual Generator
 *
 * Generates bust portraits for all 18 built-in clients and warm title visual
 * using local Workers AI FLUX Schnell endpoint (GET /api/dev/gen-img).
 *
 * Usage:
 *   node tools/generate-portraits.mjs [ids...] [--base http://localhost:8787] [--force]
 *   node tools/generate-portraits.mjs title [--base http://localhost:8787] [--force]
 *   node tools/generate-portraits.mjs all [--base http://localhost:8787]
 */

import { writeFileSync, copyFileSync, existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const PORTRAITS_DIR = path.resolve(ROOT, 'client/assets/portraits');
const TITLE_PATH = path.resolve(ROOT, 'client/assets/title.jpg');
// Kept outside client/ so the backup is never exported into the game package
const TITLE_BACKUP = path.resolve(ROOT, 'docs/design/archive/title-backup.jpg');

export const SHARED_STYLE_SUFFIX =
  'anime illustration in the style of a modern Japanese animated film, bust portrait, head and shoulders, facing the viewer, gentle natural expression, soft warm studio lighting, soft muted sage green backdrop, clean line art, consistent character design, no text, no letters, no watermark, single person';

export const TITLE_PROMPT =
  'warm morning living room in a Taiwanese city apartment, sunlight through sheer curtains, coffee table with a cup of tea, a tablet showing a simple rising line chart with a small shield icon, plants, a framed family photo turned slightly away (no readable faces), Taipei skyline softly visible, hopeful calm mood, anime illustration in the style of a modern Japanese animated film, clean line art, wide 16:9 composition with empty space on the left third for the logo text, no people, no text';

export const CLIENT_PORTRAITS = [
  {
    id: 'yuqing',
    name: '林雨晴',
    age: 29,
    gender: '女性',
    job: '自由接案插畫家',
    tag: '收入波動型',
    family: '單身、與室友合租，沒有扶養對象',
    look: '29-year-old Taiwanese woman illustrator, shoulder-length wavy dark brown hair tied in a loose half-up bun, warm thoughtful brown eyes, wearing a comfortable oversized cream knit sweater, a supportive elastic wrist brace visible on her right wrist',
    nim: 'friendly Taiwanese illustrator in her late twenties, shoulder-length wavy dark brown hair in a loose half-up bun, cream knit sweater',
  },
  {
    id: 'boting',
    name: '陳柏廷',
    age: 36,
    gender: '男性',
    job: '半導體工程師／新手爸爸',
    tag: '高收入高責任',
    family: '已婚，孩子 8 個月大，配偶育嬰留停中，另需孝親費',
    look: '36-year-old Taiwanese male semiconductor engineer and new father, neat short black hair, modern dark-rimmed rectangular glasses, warm slightly weary eyes with a tender smile, wearing a navy blue casual collared button-up shirt over a heather grey t-shirt',
    nim: 'friendly Taiwanese semiconductor engineer in his mid thirties, short black hair, dark rectangular glasses, navy blue button-up shirt',
  },
  {
    id: 'wanting',
    name: '蘇婉婷',
    age: 43,
    gender: '女性',
    job: '獨立咖啡店老闆／單親家長',
    tag: '創業家庭型',
    family: '單親，獨自扶養高一的孩子',
    look: '43-year-old Taiwanese woman café owner and single mother, soft dark hair gathered in a relaxed low ponytail, serene confident smile, wearing a dark olive-green canvas barista apron over a rust-orange linen blouse with rolled sleeves',
    nim: 'friendly Taiwanese cafe owner in her early forties, dark hair in a low ponytail, olive green barista apron over a rust orange blouse',
  },
  {
    id: 'ziyuan',
    name: '周子安',
    age: 25,
    gender: '非二元',
    job: '研究生／接案攝影師',
    tag: '低收入成長型',
    family: '獨居租屋，沒有扶養對象，家裡無法提供經濟支援',
    look: '25-year-old Taiwanese non-binary graduate student photographer, androgynous layered dark shaggy wolf-cut hair, focused inquisitive hazel eyes, wearing a vintage khaki multi-pocket utility vest over a charcoal long-sleeve tee, woven camera strap around the neck',
    nim: 'friendly Taiwanese graduate student photographer in their mid twenties, layered dark shaggy hair, khaki utility vest over a charcoal long-sleeve shirt',
  },
  {
    id: 'zhiming',
    name: '黃志明',
    age: 58,
    gender: '男性',
    job: '計程車司機／家庭照顧者',
    tag: '準退休保障型',
    family: '與配偶同住，照顧 84 歲母親；子女已成年',
    look: '58-year-old Taiwanese male veteran taxi driver and caregiver, short salt-and-pepper hair, warm crinkles around kindly eyes, humble honest smile, wearing a clean sky-blue collared driving polo shirt over a white crewneck undershirt',
    nim: 'friendly Taiwanese taxi driver in his late fifties, short salt-and-pepper hair, sky blue polo shirt',
  },
  {
    id: 'junhao',
    name: '王俊豪',
    age: 32,
    gender: '男性',
    job: '外送平台騎手',
    tag: '零工經濟型',
    family: '單身，每月給父母 8,000 元',
    look: '32-year-old Taiwanese male food delivery courier, sun-tanned skin, sporty cropped black hair, cheerful spirited smile, wearing a lightweight windbreaker jacket with dark teal and black paneling, athletic build',
    nim: 'friendly Taiwanese delivery courier in his early thirties, tanned skin, short black hair, teal and black windbreaker jacket',
  },
  {
    id: 'meiling',
    name: '張美玲',
    age: 36,
    gender: '女性',
    job: '公司行政助理',
    tag: '單親家長型',
    family: '單親，扶養 8 歲女兒',
    look: '36-year-old Taiwanese woman office administrative assistant and single mother, neat low ponytail with soft side bangs, gentle patient expression, wearing a modest pastel lilac knit cardigan over a white round-neck blouse',
    nim: 'friendly Taiwanese office assistant in her mid thirties, low ponytail with soft side bangs, lilac knit cardigan over a white blouse',
  },
  {
    id: 'jiahao',
    name: '劉家豪',
    age: 31,
    gender: '男性',
    job: '軟體工程師',
    tag: '新手爸媽型',
    family: '已婚，新生兒 3 個月',
    look: '31-year-old Taiwanese man, software engineer, upright posture, head straight and centered, looking directly at the viewer, short neat black hair, thin round metal glasses, calm friendly smile, wearing a plain heather-gray crewneck sweatshirt, nobody else in the picture, no baby, no props',
    nim: 'friendly Taiwanese software engineer in his early thirties, short neat black hair, thin round metal glasses, grey sweatshirt',
  },
  {
    id: 'shufen',
    name: '吳淑芬',
    age: 45,
    gender: '女性',
    job: '會計主管',
    tag: '三明治世代',
    family: '已婚，兩個國中孩子，父親 78 歲',
    look: '45-year-old Taiwanese woman accounting manager, elegant chin-length bob haircut, delicate tortoiseshell glasses, composed and intelligent expression, wearing a tailored dusty-rose blazer over an ivory silk inner blouse',
    nim: 'friendly Taiwanese accounting manager in her mid forties, chin-length bob, tortoiseshell glasses, dusty rose blazer',
  },
  {
    id: 'wenjie',
    name: '鄭文傑',
    age: 58,
    gender: '男性',
    job: '國中教師',
    tag: '退休準備型',
    family: '已婚，子女皆已工作',
    look: '58-year-old Taiwanese male middle school teacher, neatly parted silver-streaked hair, warm approachable smile, round tortoiseshell glasses, wearing a forest-green knitted vest over an ironed plaid collared button-up shirt',
    nim: 'friendly Taiwanese middle school teacher in his late fifties, silver-streaked hair, round tortoiseshell glasses, forest green knitted vest over a plaid shirt',
  },
  {
    id: 'yiting',
    name: '蔡依婷',
    age: 24,
    gender: '女性',
    job: '行銷專員（社會新鮮人）',
    tag: '小資起步型',
    family: '單身，與家人同住',
    look: '24-year-old Taiwanese woman fresh marketing graduate, cheerful bob with wispy bangs, bright sparkling eyes, bright optimistic smile, wearing a smart-casual light sage blazer over a plain white tee with a dainty silver pendant necklace',
    nim: 'friendly Taiwanese marketing specialist in her mid twenties, bob haircut with wispy bangs, light sage blazer over a white shirt',
  },
  {
    id: 'zhiwei',
    name: '林志偉',
    age: 40,
    gender: '男性',
    job: '小吃店老闆',
    tag: '自營商家型',
    family: '已婚，一個國小孩子，太太在店裡幫忙',
    look: '40-year-old Taiwanese male traditional eatery owner, robust build, short spiky black hair, friendly hearty smile, wearing a durable dark navy bib work apron over a breathable dark charcoal cotton t-shirt',
    nim: 'friendly Taiwanese eatery owner around forty, short spiky black hair, dark navy work apron over a charcoal shirt',
  },
  {
    id: 'peishan',
    name: '何佩珊',
    age: 34,
    gender: '女性',
    job: '醫院護理師',
    tag: '輪班高壓型',
    family: '單身，與男友同居',
    look: '34-year-old Taiwanese woman hospital shift nurse, hair neatly bound in a high practical bun, resolute yet compassionate eyes, wearing light seafoam-green hospital scrubs with a dark navy fleece zip jacket slightly open',
    nim: 'friendly Taiwanese hospital nurse in her mid thirties, hair in a high bun, seafoam green scrubs with a navy fleece jacket',
  },
  {
    id: 'chengen',
    name: '李承恩',
    age: 29,
    gender: '男性',
    job: '科技公司資深工程師',
    tag: '高收入集中型',
    family: '單身',
    look: '29-year-old Taiwanese male senior tech lead, sharp modern side-parted hairstyle, sleek rectangular wireframe glasses, confident analytical gaze, wearing a minimalist fine-knit black mock-neck pullover',
    nim: 'friendly Taiwanese tech lead in his late twenties, side-parted hair, rectangular wireframe glasses, black knit pullover',
  },
  {
    id: 'jiaming',
    name: '許家銘',
    age: 38,
    gender: '男性',
    job: '設計公司合夥人',
    tag: '頂客族型',
    family: '已婚，無子女，養兩隻貓',
    look: '38-year-old Taiwanese male design studio partner, cultured well-groomed look with a hint of neat designer stubble, stylish round horn-rim glasses, wearing an artistically tailored charcoal turtleneck sweater',
    nim: 'friendly Taiwanese design studio partner in his late thirties, light stubble, round horn-rim glasses, charcoal turtleneck sweater',
  },
  {
    id: 'guohua',
    name: '楊國華',
    age: 50,
    gender: '男性',
    job: '計程車司機',
    tag: '高風險職業型',
    family: '已婚，女兒念大學',
    look: '50-year-old Taiwanese male taxi driver, weathered sun-kissed face, short thinning hair, kind crinkled eyes, hardworking earnest smile, wearing a beige short-sleeve collared utility shirt over a white undershirt',
    nim: 'friendly Taiwanese taxi driver around fifty, weathered tanned face, short thinning hair, beige short-sleeve work shirt',
  },
  {
    id: 'yijun',
    name: '陳怡君',
    age: 42,
    gender: '女性',
    job: '外商業務經理',
    tag: '高房貸家庭型',
    family: '已婚，兩個孩子，先生是自由工作者',
    look: '42-year-old Taiwanese woman multinational sales director, polished shoulder-length layered dark hair, elegant confident gaze, wearing a sharply tailored navy blue blazer over an ivory crepe blouse with subtle pearl stud earrings',
    nim: 'friendly Taiwanese sales director in her early forties, shoulder-length layered dark hair, navy blue blazer over an ivory blouse, pearl earrings',
  },
  {
    id: 'yixiang',
    name: '高奕翔',
    age: 27,
    gender: '男性',
    job: '健身教練（自由接課）',
    tag: '身體即資本型',
    family: '單身',
    look: '27-year-old Taiwanese male freelance fitness coach, athletic muscular build, clean high-and-tight fade haircut, healthy tan, radiant friendly smile, wearing a dark heather-grey athletic compression crewneck tee',
    nim: 'friendly Taiwanese fitness coach in his late twenties, short fade haircut, tanned skin, dark grey sports t-shirt',
  },
];

/**
 * Request image from local Workers AI FLUX Schnell endpoint with retry
 */
/**
 * NVIDIA NIM's FLUX content filter rejects portrait prompts that contain numeric ages ("31-year-old")
 * or the words "plain ... background" (tested 2026-10-10), so ages are rewritten as words before sending.
 */
/**
 * Generic portraits for AI-generated clients (no per-client art). The server picks one by gender and
 * age band (see poolPortraitFor in server/src/ai.ts). Run: node tools/generate-portraits.mjs pool
 */
export const POOL_PORTRAITS = [
  { id: 'pool_m_20s', name: '年輕男性', age: 25, gender: '男性', job: '通用', look: 'friendly Taiwanese young office worker in his mid twenties, short black hair, light blue casual shirt', nim: 'friendly Taiwanese young office worker in his mid twenties, short black hair, light blue casual shirt' },
  { id: 'pool_m_30s', name: '三十代男性', age: 35, gender: '男性', job: '通用', look: 'friendly Taiwanese professional in his mid thirties, neat short hair, rectangular glasses, navy cardigan over a white shirt', nim: 'friendly Taiwanese professional in his mid thirties, neat short hair, rectangular glasses, navy cardigan over a white shirt' },
  { id: 'pool_m_40s', name: '四十代男性', age: 45, gender: '男性', job: '通用', look: 'friendly Taiwanese small business owner in his mid forties, short hair with a little grey, olive green jacket', nim: 'friendly Taiwanese small business owner in his mid forties, short hair with a little grey, olive green jacket' },
  { id: 'pool_m_50s', name: '五十代男性', age: 55, gender: '男性', job: '通用', look: 'friendly Taiwanese manager in his mid fifties, greying side-parted hair, glasses, brown knit vest over a checked shirt', nim: 'friendly Taiwanese manager in his mid fifties, greying side-parted hair, glasses, brown knit vest over a checked shirt' },
  { id: 'pool_m_60s', name: '長者男性', age: 65, gender: '男性', job: '通用', look: 'kind Taiwanese retiree in his mid sixties, short white hair, beige cardigan', nim: 'kind Taiwanese retiree in his mid sixties, short white hair, beige cardigan' },
  { id: 'pool_f_20s', name: '年輕女性', age: 25, gender: '女性', job: '通用', look: 'friendly Taiwanese young designer in her mid twenties, shoulder-length hair with bangs, mustard yellow sweater', nim: 'friendly Taiwanese young designer in her mid twenties, shoulder-length hair with bangs, mustard yellow sweater' },
  { id: 'pool_f_30s', name: '三十代女性', age: 35, gender: '女性', job: '通用', look: 'friendly Taiwanese professional in her mid thirties, dark hair in a low ponytail, light grey blazer over a white blouse', nim: 'friendly Taiwanese professional in her mid thirties, dark hair in a low ponytail, light grey blazer over a white blouse' },
  { id: 'pool_f_40s', name: '四十代女性', age: 45, gender: '女性', job: '通用', look: 'friendly Taiwanese shop owner in her mid forties, chin-length bob, coral cardigan', nim: 'friendly Taiwanese shop owner in her mid forties, chin-length bob, coral cardigan' },
  { id: 'pool_f_50s', name: '五十代女性', age: 55, gender: '女性', job: '通用', look: 'friendly Taiwanese civil servant in her mid fifties, short permed hair, pearl earrings, teal blouse', nim: 'friendly Taiwanese civil servant in her mid fifties, short permed hair, pearl earrings, teal blouse' },
  { id: 'pool_f_60s', name: '長者女性', age: 65, gender: '女性', job: '通用', look: 'kind Taiwanese grandmother in her mid sixties, short grey hair, lavender knit cardigan', nim: 'kind Taiwanese grandmother in her mid sixties, short grey hair, lavender knit cardigan' },
  { id: 'pool_x', name: '中性', age: 30, gender: '非二元', job: '通用', look: 'friendly Taiwanese freelance creator around thirty, layered dark hair, round glasses, charcoal hoodie', nim: 'friendly Taiwanese freelance creator around thirty, layered dark hair, round glasses, charcoal hoodie' },
];

/** Style tail verified to pass NIM's content filter (2026-10-10) */
export const NIM_TAIL = 'facing the viewer, gentle smile, soft warm studio lighting, soft muted green backdrop, clean line art';

export function nimSafe(prompt) {
  return prompt.replace(/\b(\d{2})-year-old\b/g, (_m, n) => {
    const age = Number(n);
    const decade = ['', 'teens', 'twenties', 'thirties', 'forties', 'fifties', 'sixties', 'seventies'][Math.floor(age / 10)] || 'senior years';
    const part = age % 10 <= 3 ? 'early' : age % 10 <= 6 ? 'mid' : 'late';
    return `${part}-${decade}`;
  }).replace(/plain ([a-z ]*?)background/gi, 'soft $1backdrop');
}

export async function generateImage({ base, prompt, alt, width, height, maxAttempts = 3 }) {
  const url = new URL('/api/dev/gen-img', base);
  url.searchParams.set('prompt', prompt);
  // Short wording the endpoint retries on NIM when the full prompt is content-filtered
  if (alt) url.searchParams.set('alt', alt);
  if (width) url.searchParams.set('w', String(width));
  if (height) url.searchParams.set('h', String(height));

  let lastError = null;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const res = await fetch(url.toString());
      if (res.ok) console.log(`  provider: ${res.headers.get('x-image-provider') || '?'}`);
      if (!res.ok) {
        const errText = await res.text();
        throw new Error(`HTTP ${res.status}: ${errText}`);
      }
      const arrayBuffer = await res.arrayBuffer();
      return Buffer.from(arrayBuffer);
    } catch (err) {
      lastError = err;
      console.warn(`  [嘗試 ${attempt}/${maxAttempts}] 生圖請求失敗: ${err.message}`);
      if (attempt < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, attempt * 1500));
      }
    }
  }
  throw lastError;
}

/**
 * Generate title visual after backing up the original
 */
export async function generateTitle({ base, force = false }) {
  if (!force && existsSync(TITLE_PATH) && existsSync(TITLE_BACKUP)) {
    console.log(`[title] 主視覺已存在且已有備份，略過 (使用 --force 強制重新生成)`);
    return;
  }

  if (existsSync(TITLE_PATH) && !existsSync(TITLE_BACKUP)) {
    copyFileSync(TITLE_PATH, TITLE_BACKUP);
    console.log(`[title] 已備份現有主視覺至 ${TITLE_BACKUP}`);
  }

  console.log(`[title] 正在生成溫暖客廳主視覺 (1280x720)...`);
  const bytes = await generateImage({
    base,
    prompt: TITLE_PROMPT,
    width: 1344,
    height: 768,
  });
  writeFileSync(TITLE_PATH, bytes);
  console.log(`[title] 已成功寫入: ${TITLE_PATH} (${bytes.length} bytes)`);
}

/**
 * Generate portraits for specified clients
 */
export async function generatePortraits(clients, { base, force = false }) {
  mkdirSync(PORTRAITS_DIR, { recursive: true });

  for (const c of clients) {
    const outPath = path.resolve(PORTRAITS_DIR, `${c.id}.jpg`);
    if (!force && existsSync(outPath)) {
      console.log(`[portrait: ${c.id}] 檔案已存在，略過 (使用 --force 強制重新生成)`);
      continue;
    }

    const prompt = nimSafe(`${c.look}, ${SHARED_STYLE_SUFFIX}`);
    console.log(`[portrait: ${c.id}] 正在生成 (${c.name}, ${c.age}歲, ${c.job})...`);
    try {
      const bytes = await generateImage({
        base,
        prompt,
        alt: c.nim ? `anime illustration, bust portrait of a ${c.nim}, ${NIM_TAIL}` : undefined,
        width: 1024,
        height: 1024,
      });
      writeFileSync(outPath, bytes);
      console.log(`[portrait: ${c.id}] 已儲存至 ${outPath} (${bytes.length} bytes)`);
    } catch (err) {
      console.error(`[portrait: ${c.id}] 生成失敗: ${err.message}`);
    }
  }
}

// CLI Execution
async function main() {
  const args = process.argv.slice(2);
  let base = 'http://localhost:8787';
  let force = false;
  let doTitle = false;
  const requestedIds = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--help' || arg === '-h') {
      console.log(`用法: node tools/generate-portraits.mjs [ids...] [--base http://localhost:8787] [--force]`);
      console.log(`參數:`);
      console.log(`  [ids...]     客戶 ID 清單 (例如: yuqing boting)；若傳 'title' 則生成主視覺；若傳 'all' 或留空則處理全部 18 位客戶`);
      console.log(`  --base <url> 指定伺服器網址 (預設 http://localhost:8787)`);
      console.log(`  --force      覆寫已存在的圖片`);
      console.log(`  --title      生成主視覺圖片`);
      process.exit(0);
    } else if (arg === '--force') {
      force = true;
    } else if (arg === '--title') {
      doTitle = true;
    } else if (arg.startsWith('--base=')) {
      base = arg.slice(7);
    } else if (arg === '--base' && i + 1 < args.length) {
      base = args[++i];
    } else if (arg === 'title') {
      doTitle = true;
    } else if (arg === 'pool') {
      requestedIds.push(...POOL_PORTRAITS.map((c) => c.id));
    } else {
      requestedIds.push(arg);
    }
  }

  if (doTitle) {
    await generateTitle({ base, force });
  }

  let targets = [];
  if (requestedIds.length === 0 && !doTitle) {
    targets = CLIENT_PORTRAITS;
  } else if (requestedIds.includes('all')) {
    targets = CLIENT_PORTRAITS;
  } else if (requestedIds.length > 0) {
    const known = [...CLIENT_PORTRAITS, ...POOL_PORTRAITS];
    targets = known.filter((c) => requestedIds.includes(c.id));
    const missing = requestedIds.filter((id) => id !== 'title' && id !== 'all' && !known.some((c) => c.id === id));
    if (missing.length > 0) {
      console.warn(`警告: 未知客戶 ID: ${missing.join(', ')}`);
    }
  }

  if (targets.length > 0) {
    console.log(`即將處理 ${targets.length} 位客戶頭像 (目標目錄: ${PORTRAITS_DIR})...`);
    await generatePortraits(targets, { base, force });
  }

  console.log('完成。');
}

if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(import.meta.url))) {
  main().catch((err) => {
    console.error('執行失敗:', err);
    process.exit(1);
  });
}
