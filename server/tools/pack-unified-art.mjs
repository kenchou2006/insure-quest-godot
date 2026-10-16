// Encode imported unified artwork as WebP without changing its composition.
// Run from server/: node tools/pack-unified-art.mjs
import sharp from 'sharp';
import { readdir, unlink } from 'node:fs/promises';
import { resolve, join } from 'node:path';

const root = resolve('../client/assets/unified');
for (const folder of [root, join(root, 'portraits')]) {
  for (const name of await readdir(folder)) {
    if (!name.endsWith('.png')) continue;
    const source = join(folder, name);
    await sharp(source).webp({ quality: 88, effort: 6 }).toFile(source.replace(/\.png$/, '.webp'));
    await unlink(source);
    console.log(`Packed ${name}`);
  }
}
