// Compress Godot web export .wasm / .pck into .gz, and inject decompression fetch shim into index.html.
// Reason: Workers Static Assets has 25 MiB single-file limit, Godot wasm is ~38 MiB; compression also reduces download size.
// Usage: node tools/pack-web.mjs ../web
import { readFileSync, writeFileSync, unlinkSync, existsSync, statSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { join } from 'node:path';

const dir = process.argv[2] || '../web';
const html = join(dir, 'index.html');
if (!existsSync(html)) { console.error(`找不到 ${html}，請先匯出 Godot 網頁版`); process.exit(1); }

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
#iq-tips-sub {
  font-size: 11px;
  color: #94a3b8;
  margin-top: 5px;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.8);
}
</style>
<div id="iq-tips-overlay">
  <div id="iq-tips-text">先問需求，再談商品</div>
  <div id="iq-tips-sub">首次載入約 10 MB，之後會從快取秒開</div>
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

// PWA: Godot-generated service worker cache manifest lists index.wasm, but browser actually fetches index.wasm.gz
const sw = join(dir, 'index.service.worker.js');
if (existsSync(sw)) {
  let code = readFileSync(sw, 'utf8');
  for (const ext of packed) code = code.split(`"index.${ext}"`).join(`"index.${ext}.gz"`);
  code = code.replace(/const CACHE_VERSION = '[^']+';/, `const CACHE_VERSION = '${Date.now()}';`);
  writeFileSync(sw, code);
  console.log(`service worker：快取清單更新，版本號重置為 ${Date.now()}`);
}

// Workers Static Assets custom headers (applies only to static files, /api/* handled by Worker)
writeFileSync(join(dir, '_headers'), `/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

/
  Cache-Control: no-cache

/index.html
  Cache-Control: no-cache

/local-room.js
  Cache-Control: no-cache

/index.service.worker.js
  Cache-Control: no-cache

/index.manifest.json
  Content-Type: application/manifest+json
  Cache-Control: no-cache

/index.pck
  Cache-Control: no-cache, must-revalidate

/index.wasm.gz
  Cache-Control: no-cache, must-revalidate

/index.js
  Cache-Control: no-cache, must-revalidate
`);
console.log('_headers：已產生');
