// Generate all missing client scene images with Cloudflare Workers AI FLUX via the local server
import { existsSync, copyFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const SCENES = [
  {
    id: 'meiling',
    name: '張美玲（單親行政）',
    prompt: 'Makoto Shinkai anime style digital background art, cozy warm Taiwanese apartment study desk at night lit by a warm desk lamp, distant city night lights bokeh outside window. Empty room, no people. Four distinct items clearly separated across different areas of the composition without overlapping: (1) On the bottom-left of the desk: a large open bank savings passbook booklet with a dark blue cover lying flat showing printed table grid columns; (2) In the center foreground of the desk: an open primary school children homework notebook with colorful cover illustrations and pencil doodle marks; (3) On the right side of the desk: a multi-slot office stationery organizer box holding colorful pens, markers, and scissors; (4) Pinned prominently on the corkboard wall above the desk: a printed weekly two-job shift schedule calendar sheet with distinct colored shift grid blocks. Every object is large, well-spaced, isolated in its own quadrant, completely unobstructed. No readable text, no letters, no words, no human figures, clean aesthetic anime digital painting.'
  },
  {
    id: 'jiahao',
    name: '劉家豪（軟體工程師・新手爸爸）',
    prompt: 'Makoto Shinkai anime style cozy apartment room at dusk, modern nursery room combined with home office. A wooden computer desk with dual monitors displaying code and stock charts next to a cute white baby crib with colorful mobile toys, diaper stacks, baby formula cans, mortgage payment receipt papers on desk, warm soft domestic lighting, aesthetic anime background art.'
  },
  {
    id: 'wenjie',
    name: '鄭文傑（國中教師・即將退休）',
    prompt: 'Makoto Shinkai anime style Taiwanese junior high school teacher faculty office desk in late afternoon golden hour. Stacks of student exam papers with red pen corrections, lesson plan notebooks, health examination report, high-yield dividend investment brochures, a folded Taiwan round-island cycling road map on the desk, cozy nostalgic school atmosphere, anime digital art.'
  },
  {
    id: 'yiting',
    name: '蔡依婷（行銷專員・社會新鮮人）',
    prompt: 'Makoto Shinkai anime style cozy small rental studio apartment room of a young 24-year-old Taiwanese female marketing specialist. A neat desk with lightweight pink-gold laptop showing marketing presentation slides, first month salary pay slip, credit card bill, piggy bank, colorful sticky notes, fairy lights on the wall, cozy youthful warm lighting, aesthetic anime illustration.'
  },
  {
    id: 'zhiwei',
    name: '林志偉（小吃店老闆）',
    prompt: 'Makoto Shinkai anime style bustling Taiwanese traditional restaurant kitchen and counter, stainless steel prep counter, wok and commercial gas stove with gentle blue flame, order receipt ticket holder rail, traditional vintage cash box, renovation cost estimate blueprint for second branch store on counter, warm steam and cozy lantern lighting, detailed anime background art.'
  },
  {
    id: 'peishan',
    name: '何佩珊（醫院護理師）',
    prompt: 'Makoto Shinkai anime style digital background art, quiet hospital nurse break room and study desk at night, soft warm desk lamp glow, window overlooking night courtyard. Empty room, no people. Four distinct items clearly separated across different areas of the composition without overlapping: (1) On the left side draped prominently over the desk chair backrest: an ergonomic black and grey medical lumbar support back brace belt with breathable mesh and wide velcro straps; (2) In the center foreground of the desk: an open glossy overseas nursing graduate study abroad prospectus brochure with colorful campus photos and world map motif; (3) On the right side of the desk: a blue hospital nurse lanyard with acrylic staff ID badge card lying beside a coiled medical stethoscope; (4) Pinned prominently on the corkboard wall above the desk: a large printed hospital monthly night-shift rotation duty schedule roster sheet with a distinct calendar grid. Every object is large, well-spaced, isolated in its own quadrant, completely unobstructed. No readable text, no letters, no words, no human figures, clean aesthetic anime digital painting.'
  },
  {
    id: 'chengen',
    name: '李承恩（科技公司資深工程師）',
    prompt: 'Makoto Shinkai anime style sleek modern high-rise luxury apartment tech desk at night overlooking neon city skyline. Curved ultra-wide gaming monitors showing complex code IDE and glowing stock portfolio charts, take-out overtime bento box, ergonomic mechanical keyboard, financial independence 35 years old roadmap notebook, cool blue and warm golden contrast lighting, anime digital background.'
  },
  {
    id: 'guohua',
    name: '楊國華（資深計程車運將）',
    prompt: 'Makoto Shinkai anime style vintage yellow taxi cab driver seat interior view from passenger side. Taxi meter fare dashboard, car loan payment voucher, college student ID card of driver daughter on sun visor, pain relief herbal patches on driver seat backrest, view through windshield of rainy Taipei street with glowing neon lights, warm nostalgic anime art.'
  },
  {
    id: 'yijun',
    name: '陳怡君（外商業務經理）',
    prompt: 'Makoto Shinkai anime style upscale modern executive home office study overlooking Taipei 101 city skyline at twilight. Polished walnut desk, business laptop, 8 million housing mortgage agreement documents, quarterly sales bonus statement, children overseas study brochures, elegant ceramic coffee mug, warm professional golden hour lighting, anime digital painting.'
  },
  {
    id: 'yixiang',
    name: '高奕翔（健身教練）',
    prompt: 'Makoto Shinkai anime style digital background art, modern boutique fitness gym coach lounge and office desk, warm sunlight streaming through large gym windows, softly blurred dumbbells and workout racks in far background. Empty room, no people. Four distinct items clearly separated across different areas of the composition without overlapping: (1) On the left side of the table: a tall translucent sports whey protein shaker bottle with neon flip-cap lid standing upright; (2) In the center foreground of the table: a large black sports knee compression sleeve brace with silicone kneecap ring and elastic straps laid out flat; (3) On the right side of the table: a metal clipboard holding a printed weekly client personal training booking schedule sheet with clear hourly timetable rows; (4) Pinned prominently on the corkboard wall above the desk: a multi-page gym studio renovation cost quotation blueprint document with architectural layout diagrams. Every object is large, well-spaced, isolated in its own zone, completely unobstructed. No readable text, no letters, no words, no human figures, clean aesthetic anime digital painting.'
  }
];

async function main() {
  const targetIds = process.argv.slice(2).map(s => s.trim().toLowerCase()).filter(Boolean);
  let scenesToGenerate = SCENES;
  if (targetIds.length > 0) {
    scenesToGenerate = [];
    for (const tid of targetIds) {
      const match = SCENES.find(s => s.id.toLowerCase() === tid);
      if (match) {
        scenesToGenerate.push(match);
      } else {
        console.warn(`[Warning] 未知客戶 ID: "${tid}"，已略過`);
      }
    }
    if (scenesToGenerate.length === 0) {
      console.error(`未找到任何相符的客戶 ID！可用的 ID: ${SCENES.map(s => s.id).join(', ')}`);
      process.exit(1);
    }
  }

  // Locate client/assets/clients correctly whether run from the project root or from server/
  const projectRoot = resolve(__dirname, '../..');
  const outDir = resolve(projectRoot, 'client/assets/clients');

  console.log(`即將使用 Workers AI FLUX 生成 ${scenesToGenerate.length} 張客戶場景圖...`);
  console.log(`輸出目錄: ${outDir}`);

  const serverUrl = process.env.SERVER_URL || 'http://localhost:8787';

  for (let i = 0; i < scenesToGenerate.length; i++) {
    const s = scenesToGenerate[i];
    console.log(`\n[${i + 1}/${scenesToGenerate.length}] 正在生成 ${s.id}（${s.name}）...`);
    const t0 = Date.now();
    const url = `${serverUrl}/api/dev/gen-img?prompt=${encodeURIComponent(s.prompt)}`;
    const res = await fetch(url);
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      console.error(`生成 ${s.id} 失敗: HTTP ${res.status} ${errText}`);
      continue;
    }
    const buf = Buffer.from(await res.arrayBuffer());
    const targetFile = resolve(outDir, `${s.id}.jpg`);
    // Keep backups outside client/: anything in assets would be imported by Godot and packed into the web build
    const backupDir = resolve(projectRoot, '.scene-backups');
    mkdirSync(backupDir, { recursive: true });
    const backupFile = resolve(backupDir, `${s.id}.${Date.now()}.jpg`);

    if (existsSync(targetFile)) {
      copyFileSync(targetFile, backupFile);
      console.log(`  舊檔已備份至: ${backupFile}`);
    }

    writeFileSync(targetFile, buf);
    console.log(`✓ 已儲存 ${targetFile} (${buf.length} bytes，耗時 ${((Date.now() - t0) / 1000).toFixed(1)}s)`);
  }
  console.log('\n場景圖生成處理完成！');
}

main().catch(console.error);
