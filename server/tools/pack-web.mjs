// 將 Godot 網頁匯出的 .wasm / .pck 壓成 .gz，並在 index.html 注入解壓縮 fetch shim。
// 原因：Workers Static Assets 單檔上限 25 MiB，而 Godot 的 wasm 約 38 MiB；壓縮後也大幅減少下載量。
// 用法：node tools/pack-web.mjs ../web
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
  // 壓不太下來且未超過上限的檔案維持原樣
  if (gz.length > raw.length * 0.9 && raw.length <= LIMIT) { console.log(`${f}: 保留原檔（${(raw.length / 1048576).toFixed(1)} MiB）`); continue; }
  if (gz.length > LIMIT) { console.error(`${f} 壓縮後仍超過 25 MiB（${gz.length} bytes）`); process.exit(1); }
  writeFileSync(`${f}.gz`, gz);
  console.log(`${f}: ${(raw.length / 1048576).toFixed(1)} MiB → ${(gz.length / 1048576).toFixed(1)} MiB`);
  unlinkSync(f);
  packed.push(ext);
}

const SHIM = `<script id="iq-gz-shim">
(function () {
  // 把 index.wasm / index.pck 的請求改抓 .gz 並在瀏覽器端解壓縮
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

let page = readFileSync(html, 'utf8');
if (!page.includes('iq-gz-shim')) {
  page = page.replace('<script src="index.js"></script>', `${SHIM}\n\t\t<script src="index.js"></script>`);
  if (!page.includes('iq-gz-shim')) { console.error('index.html 結構不符，無法注入 shim'); process.exit(1); }
  writeFileSync(html, page);
}
console.log('index.html：已注入解壓縮 shim');

// PWA：Godot 產生的 service worker 快取清單寫的是 index.wasm，但瀏覽器實際抓的是 index.wasm.gz
const sw = join(dir, 'index.service.worker.js');
if (existsSync(sw)) {
  let code = readFileSync(sw, 'utf8');
  for (const ext of packed) code = code.split(`"index.${ext}"`).join(`"index.${ext}.gz"`);
  code = code.replace(/const CACHE_VERSION = '[^']+';/, `const CACHE_VERSION = '${Date.now()}';`);
  writeFileSync(sw, code);
  console.log(`service worker：快取清單更新，版本號重置為 ${Date.now()}`);
}

// Workers Static Assets 自訂標頭（只作用在靜態檔，/api/* 由 Worker 處理）
writeFileSync(join(dir, '_headers'), `/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

/
  Cache-Control: no-cache

/index.html
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
