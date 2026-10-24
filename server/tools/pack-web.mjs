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
const cacheVer = buildVer.replace(/[^a-zA-Z0-9._-]/g, '_');
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
/* The exported cover already contains the game title and artwork. */
body, #canvas { background-color: #0d231e; }
#status-progress { accent-color: #2ed59e; }
#status-progress::-webkit-progress-value { background-color: #2ed59e; }
#status-progress::-moz-progress-bar { background-color: #2ed59e; }
</style>
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
  page = page.replace('<script src="index.js"></script>', `${TIPS}\n\t\t<script src="index.js"></script>`);
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
const STAMP = `<script id="iq-build-stamp">window.IQ_BUILD = ${JSON.stringify(buildVer)};</script>`;
if (page.includes('id="iq-build-stamp"')) {
  page = page.replace(/<script id="iq-build-stamp">[\s\S]*?<\/script>/, STAMP);
  writeFileSync(html, page);
} else if (!page.includes('iq-build-stamp')) {
  if (page.includes('<head>')) {
    page = page.replace('<head>', `<head>\n\t\t${STAMP}`);
  } else {
    page = page.replace('<script src="index.js"></script>', `${STAMP}\n\t\t<script src="index.js"></script>`);
  }
  writeFileSync(html, page);
}
console.log(`index.html：已注入 IQ_BUILD 版本號（${buildVer}）`);

// Auto-update on load: if version.json is newer than the running (cached) build, or if an old
// service worker still controls the page / lacks the new build cache, activate the new
// service worker and reload before the game starts, so players never see an "update" prompt.
// sessionStorage guards against reload loops when the new build cannot be fetched.
const sw = join(dir, 'index.service.worker.js');
let cachePrefix = 'INSURE QUEST 人生顧-sw-cache-';
if (existsSync(sw)) {
  const prefixMatch = readFileSync(sw, 'utf8').match(/const CACHE_PREFIX = '([^']+)';/);
  if (prefixMatch) cachePrefix = prefixMatch[1];
}

page = readFileSync(html, 'utf8');
const AUTO_UPDATE = `<script id="iq-auto-update">(function () {
  try {
    var cur = window.IQ_BUILD || '';
    if (!window.fetch) return;
    fetch('version.json', { cache: 'no-store' }).then(function (r) {
      return r.ok ? r.json() : null;
    }).then(function (d) {
      if (!d || !d.version) return;
      var targetVer = d.version.replace(/[^a-zA-Z0-9._-]/g, '_');
      var targetCache = ${JSON.stringify(cachePrefix)} + targetVer;
      var hasSW = 'serviceWorker' in navigator;
      var reload = function () {
        var u = new URL(location.href);
        u.searchParams.set('v', d.version);
        location.replace(u.toString());
      };

      var triggerUpdate = function (reg, targetSW) {
        if (sessionStorage.getItem('iq-updating') === d.version) return;
        sessionStorage.setItem('iq-updating', d.version);
        if (!hasSW || !reg) return reload();
        var activate = function (sw) {
          sw.postMessage('update');
          setTimeout(reload, 4000);
        };
        var swToActivate = targetSW || reg.waiting;
        if (swToActivate) return activate(swToActivate);
        reg.update().then(function () {
          if (reg.waiting) return activate(reg.waiting);
          var sw = reg.installing;
          if (!sw) return reload();
          if (sw.state === 'installed') return activate(sw);
          sw.addEventListener('statechange', function () {
            if (sw.state === 'installed') activate(sw);
          });
          setTimeout(reload, 8000);
        }).catch(reload);
      };

      if (!hasSW) {
        if (cur !== d.version) triggerUpdate(null);
        return;
      }

      var getKeys = (typeof caches !== 'undefined' && caches.keys) ? caches.keys() : Promise.resolve([]);
      Promise.all([navigator.serviceWorker.getRegistration(), getKeys]).then(function (res) {
        var reg = res[0];
        var keys = res[1] || [];
        var hasController = !!navigator.serviceWorker.controller;
        var hasTargetCache = keys.indexOf(targetCache) !== -1;
        var hasWaiting = !!(reg && reg.waiting);

        if (cur !== d.version || (hasController && (!hasTargetCache || hasWaiting))) {
          return triggerUpdate(reg);
        }

        if (hasController && reg) {
          reg.update().then(function () {
            if (reg.waiting) {
              triggerUpdate(reg, reg.waiting);
            } else if (reg.installing) {
              var sw = reg.installing;
              if (sw.state === 'installed') {
                triggerUpdate(reg, sw);
              } else {
                sw.addEventListener('statechange', function () {
                  if (sw.state === 'installed') triggerUpdate(reg, sw);
                });
              }
            }
          }).catch(function () {});
        }
      }).catch(function () {});
    }).catch(function () {});
  } catch (e) {}
})();</script>`;

if (page.includes('id="iq-auto-update"')) {
  page = page.replace(/<script id="iq-auto-update">[\s\S]*?<\/script>/, AUTO_UPDATE);
} else {
  page = page.replace('<script src="index.js"></script>', `${AUTO_UPDATE}\n\t\t<script src="index.js"></script>`);
}
if (!page.includes('iq-auto-update')) { console.error('index.html: cannot inject auto-update'); process.exit(1); }
writeFileSync(html, page);
console.log('index.html: injected auto-update');

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
if (existsSync(sw)) {
  let code = readFileSync(sw, 'utf8');

  for (const ext of packed) {
    const target = `"index.${ext}"`;
    const gz = `"index.${ext}.gz"`;
    if (!code.includes(gz)) {
      code = code.split(target).join(gz);
      if (!code.includes(gz)) {
        console.error(`index.service.worker.js: 無法替換 ${target} 為 ${gz}`);
        process.exit(1);
      }
    }
  }

  const cacheVerDef = `const CACHE_VERSION = '${cacheVer}';`;
  if (!code.includes(cacheVerDef)) {
    code = code.replace(/const CACHE_VERSION = '[^']+';/, cacheVerDef);
    if (!code.includes(cacheVerDef)) {
      console.error('index.service.worker.js: 無法更新 CACHE_VERSION');
      process.exit(1);
    }
  }

  const newIcons = ['"icons/icon-192.png"', '"icons/icon-512.png"', '"icons/maskable-512.png"'];
  for (const ic of newIcons) {
    if (!code.includes(ic)) {
      code = code.replace('const CACHED_FILES = [', `const CACHED_FILES = [${ic}, `);
      if (!code.includes(ic)) {
        console.error(`index.service.worker.js: 無法加入快取圖示 ${ic}`);
        process.exit(1);
      }
    }
  }

  const SKIP_WAITING_HOOK = 'cache.addAll(CACHED_FILES).then(() => self.skipWaiting())';
  if (!code.includes(SKIP_WAITING_HOOK)) {
    code = code.replace('cache.addAll(CACHED_FILES)', SKIP_WAITING_HOOK);
    if (!code.includes(SKIP_WAITING_HOOK)) {
      console.error('index.service.worker.js: 無法注入 self.skipWaiting()');
      process.exit(1);
    }
  }

  const CLAIM_HOOK = '.map((key) => caches.delete(key))).then(() => self.clients.claim());';
  if (!code.includes(CLAIM_HOOK)) {
    code = code.replace('.map((key) => caches.delete(key)));', CLAIM_HOOK);
    if (!code.includes(CLAIM_HOOK)) {
      console.error('index.service.worker.js: 無法注入 self.clients.claim()');
      process.exit(1);
    }
  }

  writeFileSync(sw, code);
  console.log(`service worker：快取清單更新，版本號重置為 ${cacheVer}`);
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
