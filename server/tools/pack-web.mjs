// Compress Godot web export .wasm / .pck into .gz, and inject decompression fetch shim into index.html.
// Reason: Workers Static Assets has 25 MiB single-file limit, Godot wasm is ~38 MiB; compression also reduces download size.
// Usage: node tools/pack-web.mjs ../web
import { readFileSync, writeFileSync, unlinkSync, existsSync, statSync, copyFileSync, mkdirSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { join, resolve, dirname } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const dir = process.argv[2] || '../web';
const html = join(dir, 'index.html');
if (!existsSync(html)) { console.error(`找不到 ${html}，請先匯出 Godot 網頁版`); process.exit(1); }

let buildVer = process.env.IQ_BUILD;
if (!buildVer) {
  try {
    buildVer = execSync('git rev-parse --short HEAD', { encoding: 'utf8' }).trim();
  } catch {
    buildVer = Date.now().toString();
  }
}
writeFileSync(join(dir, 'version.json'), JSON.stringify({ version: buildVer }) + '\n');
console.log(`version.json：已產生（版本號 ${buildVer}）`);

const LIMIT = 25 * 1024 * 1024;
const packed = [];
for (const ext of ['wasm', 'pck']) {
  const f = join(dir, `index.${ext}`);
  if (!existsSync(f)) continue;
  const raw = readFileSync(f);
  const gz = gzipSync(raw, { level: 9 });
  // Keep files unchanged if they cannot be compressed much and do not exceed the limit
  if (gz.length > raw.length * 0.9 && raw.length <= LIMIT) { console.log(`${f}: 保留原檔（${(raw.length / 1048576).toFixed(1)} MiB）`); continue; }
  if (gz.length > LIMIT) { console.error(`${f} 壓縮後仍超過 25 MiB（${gz.length} bytes）`); process.exit(1); }
  writeFileSync(`${f}.gz`, gz);
  console.log(`${f}: ${(raw.length / 1048576).toFixed(1)} MiB → ${(gz.length / 1048576).toFixed(1)} MiB`);
  unlinkSync(f);
  packed.push(ext);
}

const SHIM = `<script id="iq-gz-shim">
(function () {
  // Redirect index.wasm / index.pck requests to .gz and decompress in the browser
  var origFetch = window.fetch.bind(window);
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var m = url.match(/\\.(${packed.join('|') || 'none'})(\\?.*)?$/);
    if (!m || typeof DecompressionStream === 'undefined') return origFetch(input, init);
    return origFetch(url.replace(/\\.(wasm|pck)(\\?.*)?$/, '.$1.gz$2'), init).then(function (res) {
      if (!res.ok) return origFetch(input, init);
      var type = m[1] === 'wasm' ? 'application/wasm' : 'application/octet-stream';
      return new Response(res.body.pipeThrough(new DecompressionStream('gzip')), { status: 200, headers: { 'Content-Type': type } });
    });
  };
})();
</script>`;

const TIPS = `<style id="iq-tips-style">
#iq-tips-overlay {
  position: absolute;
  bottom: 3.5%;
  left: 0;
  right: 0;
  margin: 0 auto;
  width: 90%;
  max-width: 620px;
  text-align: center;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans TC", sans-serif;
  pointer-events: none;
  z-index: 10;
  transition: opacity 0.4s ease;
}
#iq-tips-text {
  font-size: 14px;
  line-height: 1.5;
  color: #f1f5f9;
  font-weight: 500;
  text-shadow: 0 1px 4px rgba(0, 0, 0, 0.8);
  min-height: 22px;
  transition: opacity 0.3s ease;
}
/* Brand block replaces Godot's boot logo (boot_splash/show_image=false) */
body, #canvas { background-color: #0d231e; }
#iq-brand {
  position: absolute;
  top: 42%;
  left: 50%;
  transform: translate(-50%, -50%);
  text-align: center;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans TC", sans-serif;
  pointer-events: none;
  z-index: 10;
  animation: iq-fade-in 0.6s ease both;
}
#iq-brand-icon svg {
  width: min(28vmin, 180px);
  height: auto;
  filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.45));
}
#iq-brand-title {
  margin-top: 18px;
  font-size: min(7vmin, 44px);
  font-weight: 800;
  letter-spacing: 0.06em;
  color: #f4fbf7;
  white-space: nowrap;
}
#iq-brand-sub {
  margin-top: 4px;
  font-size: min(4.2vmin, 24px);
  font-weight: 600;
  letter-spacing: 0.3em;
  color: #e5a93c;
}
@keyframes iq-fade-in {
  from { opacity: 0; transform: translate(-50%, -46%); }
  to { opacity: 1; transform: translate(-50%, -50%); }
}
#status-progress { accent-color: #2ed59e; }
#status-progress::-webkit-progress-value { background-color: #2ed59e; }
#status-progress::-moz-progress-bar { background-color: #2ed59e; }
</style>
<div id="iq-brand">
  <div id="iq-brand-icon">__ICON_SVG__</div>
  <div id="iq-brand-title">INSURE QUEST</div>
  <div id="iq-brand-sub">人生顧問局</div>
</div>
<div id="iq-tips-overlay">
  <div id="iq-tips-text">先問需求，再談商品</div>
</div>
<script id="iq-tips-script">
(function () {
  var tips = [
    "先問需求，再談商品",
    "不保證報酬，是對客戶的誠實",
    "發現客戶沒說出口的隱藏需求，能建立更深信任",
    "保障配置需量身定制，防護缺口往往在十年後浮現",
    "誠實說明除外責任與等待期，是頂尖顧問的專業底線",
    "合規不是束縛，而是保護客戶與顧問的護城河",
    "仔細觀察生活場景線索，找出未被滿足的真實缺口",
    "面對客戶異議時先同理傾聽，再引導合適財務配置",
    "重視公平待客原則，為每位客戶的人生風險把關"
  ];
  var idx = 0;
  var textEl = document.getElementById("iq-tips-text");
  var overlay = document.getElementById("iq-tips-overlay");
  if (!textEl || !overlay) return;

  var timer = setInterval(function () {
    idx = (idx + 1) % tips.length;
    textEl.style.opacity = "0";
    setTimeout(function () {
      textEl.textContent = tips[idx];
      textEl.style.opacity = "1";
    }, 300);
  }, 3000);

  function cleanup() {
    clearInterval(timer);
    if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
    var brand = document.getElementById("iq-brand");
    if (brand && brand.parentNode) brand.parentNode.removeChild(brand);
    var style = document.getElementById("iq-tips-style");
    if (style && style.parentNode) style.parentNode.removeChild(style);
  }

  var statusEl = document.getElementById("status");
  if (statusEl) {
    var obs = new MutationObserver(function () {
      if (statusEl.style.visibility === "hidden" || !document.getElementById("status")) {
        cleanup();
        obs.disconnect();
      }
    });
    obs.observe(statusEl, { attributes: true, attributeFilter: ["style", "class"] });
    if (statusEl.parentNode) {
      var parentObs = new MutationObserver(function () {
        if (!document.getElementById("status")) {
          cleanup();
          parentObs.disconnect();
        }
      });
      parentObs.observe(statusEl.parentNode, { childList: true });
    }
  }

  var canvas = document.getElementById("canvas");
  if (canvas) {
    canvas.addEventListener("focus", cleanup, { once: true });
  }
})();
</script>`;

let page = readFileSync(html, 'utf8');
if (!page.includes('iq-gz-shim')) {
  page = page.replace('<script src="index.js"></script>', `${SHIM}\n\t\t<script src="index.js"></script>`);
  if (!page.includes('iq-gz-shim')) { console.error('index.html 結構不符，無法注入 shim'); process.exit(1); }
  writeFileSync(html, page);
}
console.log('index.html：已注入解壓縮 shim');

page = readFileSync(html, 'utf8');
if (!page.includes('iq-tips-script')) {
  // Inline the app icon so the loading screen needs no extra request
  const iconSvg = readFileSync(new URL('../../client/icon.svg', import.meta.url), 'utf8').trim();
  page = page.replace('<script src="index.js"></script>', `${TIPS.replace('__ICON_SVG__', iconSvg)}\n\t\t<script src="index.js"></script>`);
  if (!page.includes('iq-tips-script')) { console.error('index.html 結構不符，無法注入 tips'); process.exit(1); }
  writeFileSync(html, page);
}
console.log('index.html：已注入載入小知識輪播');

// Local (in-browser) solo engine for guests; must load before the Godot runtime starts.
if (existsSync(join(dir, 'local-room.js'))) {
  page = readFileSync(html, 'utf8');
  if (!page.includes('local-room.js')) {
    page = page.replace('<script src="index.js"></script>', `<script src="local-room.js"></script>\n\t\t<script src="index.js"></script>`);
    if (!page.includes('local-room.js')) { console.error('index.html: cannot inject local-room.js'); process.exit(1); }
    writeFileSync(html, page);
  }
  console.log('index.html: injected local-room.js');
}

// Inject IQ_BUILD build version into index.html
page = readFileSync(html, 'utf8');
if (!page.includes('iq-build-stamp')) {
  const STAMP = `<script id="iq-build-stamp">window.IQ_BUILD = ${JSON.stringify(buildVer)};</script>`;
  if (page.includes('<head>')) {
    page = page.replace('<head>', `<head>\n\t\t${STAMP}`);
  } else {
    page = page.replace('<script src="index.js"></script>', `${STAMP}\n\t\t<script src="index.js"></script>`);
  }
  writeFileSync(html, page);
}
console.log(`index.html：已注入 IQ_BUILD 版本號（${buildVer}）`);

// Icons: copy Android and PWA icon files into icons/
const iconsDir = join(dir, 'icons');
if (!existsSync(iconsDir)) mkdirSync(iconsDir, { recursive: true });

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const src192 = join(repoRoot, 'client/icons/android/icon-192.png');
const src512 = join(repoRoot, 'client/icons/icon-512.png');
const srcMaskable = join(repoRoot, 'client/icons/android/maskable-512.png');

if (existsSync(src192)) copyFileSync(src192, join(iconsDir, 'icon-192.png'));
if (existsSync(src512)) copyFileSync(src512, join(iconsDir, 'icon-512.png'));
if (existsSync(srcMaskable)) {
  copyFileSync(srcMaskable, join(iconsDir, 'maskable-512.png'));
} else if (existsSync(src512)) {
  copyFileSync(src512, join(iconsDir, 'maskable-512.png'));
}
console.log('icons/：圖示已複製至輸出目錄');

// Manifest: set short name, colors, and icons list
const manifestFile = join(dir, 'index.manifest.json');
if (existsSync(manifestFile)) {
  try {
    const manifest = JSON.parse(readFileSync(manifestFile, 'utf8'));
    manifest.name = '人生顧問局';
    manifest.short_name = '人生顧問局';
    manifest.background_color = '#0d231e';
    manifest.theme_color = '#0d231e';
    manifest.icons = [
      { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
      { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
      { src: 'icons/maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' }
    ];
    writeFileSync(manifestFile, JSON.stringify(manifest, null, 2) + '\n');
    console.log('index.manifest.json：已更新名稱、主題色與圖示清單');
  } catch (e) {
    console.warn('更新 index.manifest.json 失敗:', e);
  }
}

// PWA: Godot-generated service worker cache manifest lists index.wasm, but browser actually fetches index.wasm.gz
const sw = join(dir, 'index.service.worker.js');
if (existsSync(sw)) {
  let code = readFileSync(sw, 'utf8');
  for (const ext of packed) code = code.split(`"index.${ext}"`).join(`"index.${ext}.gz"`);
  code = code.replace(/const CACHE_VERSION = '[^']+';/, `const CACHE_VERSION = '${Date.now()}';`);
  const newIcons = ['"icons/icon-192.png"', '"icons/icon-512.png"', '"icons/maskable-512.png"'];
  for (const ic of newIcons) {
    if (!code.includes(ic)) {
      code = code.replace('const CACHED_FILES = [', `const CACHED_FILES = [${ic}, `);
    }
  }
  writeFileSync(sw, code);
  console.log(`service worker：快取清單更新，版本號重置為 ${Date.now()}`);
}

// Workers Static Assets custom headers (applies only to static files, /api/* handled by Worker).
// Paths carry IQ_BASE_PATH because build-web.sh serves the build from that subfolder of the assets root.
const hp = (process.env.IQ_BASE_PATH || '').replace(/\/+$/, '');
writeFileSync(join(dir, '_headers'), `${hp}/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

${hp}/
  Cache-Control: no-cache

${hp}/index.html
  Cache-Control: no-cache

${hp}/version.json
  Content-Type: application/json
  Cache-Control: no-cache

${hp}/icons/*
  Cache-Control: public, max-age=86400

${hp}/local-room.js
  Cache-Control: no-cache

${hp}/index.service.worker.js
  Cache-Control: no-cache

${hp}/index.manifest.json
  Content-Type: application/manifest+json
  Cache-Control: no-cache

${hp}/index.pck
  Cache-Control: no-cache, must-revalidate

${hp}/index.wasm.gz
  Cache-Control: no-cache, must-revalidate

${hp}/index.js
  Cache-Control: no-cache, must-revalidate
`);
console.log('_headers：已產生');
