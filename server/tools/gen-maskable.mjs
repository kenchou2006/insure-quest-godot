// Generate Android maskable 512x512 icon for INSURE QUEST PWA.
// Artwork must sit within central 80% safe zone on full-bleed #0d231e background.
// Usage: node tools/gen-maskable.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '../..');
const svgPath = resolve(root, 'client/icons/icon-foreground.svg');
const outSvgPath = resolve(root, 'client/icons/android/maskable-512.svg');
const outPngPath = resolve(root, 'client/icons/android/maskable-512.png');

if (!existsSync(svgPath)) {
  console.error(`找不到 ${svgPath}`);
  process.exit(1);
}

const rawSvg = readFileSync(svgPath, 'utf8');
// Insert full-bleed background rectangle right after opening <svg> tag
const maskableSvg = rawSvg.replace(
  /<svg([^>]*)>/,
  '<svg$1><rect width="512" height="512" fill="#0d231e"/>'
);

writeFileSync(outSvgPath, maskableSvg, 'utf8');
console.log(`已產生 ${outSvgPath}`);

try {
  const sharp = (await import('sharp')).default;
  await sharp(Buffer.from(maskableSvg))
    .resize(512, 512)
    .png()
    .toFile(outPngPath);
  console.log(`成功透過 sharp 產生 ${outPngPath} (512x512, safe zone 80%, background #0d231e)`);
} catch (err) {
  console.warn(`sharp 模組尚未安裝或無法載入: ${err?.message}`);
  console.warn(`已保留 SVG 格式: ${outSvgPath}。可執行 'npm i -D sharp' 後再次執行本腳本產生 PNG。`);
}
