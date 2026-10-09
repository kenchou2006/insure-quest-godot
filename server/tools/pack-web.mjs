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

let page = readFileSync(html, 'utf8');
if (!page.includes('iq-gz-shim')) {
  page = page.replace('<script src="index.js"></script>', `${SHIM}\n\t\t<script src="index.js"></script>`);
  if (!page.includes('iq-gz-shim')) { console.error('index.html 結構不符，無法注入 shim'); process.exit(1); }
  writeFileSync(html, page);
}
console.log('index.html：已注入解壓縮 shim');

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
