// Validate agy-generated client/assets/clients/hotspots.json and write to server/src/game/hotspots-extra.json
// Usage: node tools/merge-hotspots.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const src = '../client/assets/clients/hotspots.json';
if (!existsSync(src)) { console.error(`找不到 ${src}`); process.exit(1); }
const data = JSON.parse(readFileSync(src, 'utf8'));
const okSpot = s => s && ['x', 'y', 'w', 'h'].every(k => typeof s[k] === 'number' && s[k] >= 0 && s[k] <= 100) && s.x + s.w <= 100.5 && s.y + s.h <= 100.5;
const out = {};
// Only include clients with actual illustrations (no illustration means no clickable scene)
for (const [id, v] of Object.entries(data)) {
  const facts = (v.facts || []).filter(f => f && typeof f.title === 'string' && okSpot(f.spot));
  const decoy = v.decoy && typeof v.decoy.title === 'string' && okSpot(v.decoy.spot) ? v.decoy : null;
  if (facts.length !== 3 || !decoy) { console.warn(`略過 ${id}：需要 3 個線索與 1 個干擾物，且座標在 0–100`); continue; }
  out[id] = { facts: facts.map(f => ({ title: f.title, spot: f.spot })), decoy: { title: decoy.title, detail: String(decoy.detail || ''), spot: decoy.spot } };
}
writeFileSync('src/game/hotspots-extra.json', JSON.stringify(out, null, 1) + '\n');
console.log(`已寫入 ${Object.keys(out).length} 位客戶的熱點`);
