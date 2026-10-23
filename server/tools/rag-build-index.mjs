#!/usr/bin/env node
/**
 * Build regulation vector index for compliance RAG and export client law refs.
 *
 * Usage:
 * 1. Start the dev server with DEV_LOGIN=1 connecting to remote Workers AI:
 *    cd server && DEV_LOGIN=1 npm run dev:remote-ai
 * 2. In another terminal, run this build script:
 *    cd server && npm run rag:index
 *
 * This script:
 * 1. Reads server/rag/law-chunks.json (27 verbatim regulation chunks).
 * 2. Batches (cite + '\n' + text) to http://127.0.0.1:${PORT||8787}/api/dev/embed.
 * 3. Encodes embedding vectors as base64 Float32Array into server/rag/law-index.json.
 * 4. Exports static mapping client/data/law_refs.json for standalone/client lookups.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const CHUNKS_FILE = resolve(ROOT, 'rag/law-chunks.json');
const MAP_FILE = resolve(ROOT, 'rag/law-map.json');
const INDEX_FILE = resolve(ROOT, 'rag/law-index.json');
const CLIENT_DATA_DIR = resolve(ROOT, '../client/data');
const CLIENT_REFS_FILE = resolve(CLIENT_DATA_DIR, 'law_refs.json');

const PORT = process.env.PORT || 8787;
const EMBED_URL = `http://127.0.0.1:${PORT}/api/dev/embed`;

// Static legal refs mapping is stored in server/rag/law-map.json (single source of truth)
const LEGAL_REFS_BY_CODE = JSON.parse(readFileSync(MAP_FILE, 'utf-8'));

function float32ArrayToBase64(arr) {
  const bytes = new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

/**
 * Excerpt rule for regulation chunk:
 * If chunk ref contains '款', take the body following the first newline;
 * otherwise take the original text. Capped at 120 chars (with '…' if truncated).
 * (Keep in sync with chunkToRef in server/src/game/legal-refs.ts)
 */
function chunkToRef(c) {
  let content = c.text;
  if (c.ref && c.ref.includes('款')) {
    const nl = c.text.indexOf('\n');
    if (nl !== -1) {
      content = c.text.slice(nl + 1).trim();
    }
  }
  const text = content.length > 120 ? `${content.slice(0, 120)}…` : content;
  return {
    cite: c.cite,
    text,
    url: c.url,
    revised: c.revised,
  };
}

async function exportClientLawRefs(chunks) {
  if (!existsSync(CLIENT_DATA_DIR)) {
    mkdirSync(CLIENT_DATA_DIR, { recursive: true });
  }

  const chunksById = new Map(chunks.map(c => [c.id, c]));
  const byCode = {};

  for (const [code, ids] of Object.entries(LEGAL_REFS_BY_CODE)) {
    byCode[code] = ids.map(id => {
      const c = chunksById.get(id);
      if (!c) throw new Error(`Chunk ID "${id}" for code "${code}" not found in law-chunks.json`);
      return chunkToRef(c);
    });
  }

  writeFileSync(CLIENT_REFS_FILE, JSON.stringify({ byCode }, null, 2), 'utf-8');
  console.log(`[RAG Index] Wrote client static references to ${CLIENT_REFS_FILE}`);
}

async function main() {
  console.log('[RAG Index] Reading law chunks from:', CHUNKS_FILE);
  const data = JSON.parse(readFileSync(CHUNKS_FILE, 'utf-8'));
  const chunks = data.chunks;
  console.log(`[RAG Index] Found ${chunks.length} chunks.`);

  // 1. Export client/data/law_refs.json
  await exportClientLawRefs(chunks);

  // 2. Batch embed chunks to remote AI via local dev server endpoint
  console.log(`[RAG Index] Sending chunks to ${EMBED_URL} ...`);
  const batchSize = 10;
  const vectors = {};
  let modelName = '@cf/baai/bge-m3';
  let dims = 1024;

  for (let i = 0; i < chunks.length; i += batchSize) {
    const batch = chunks.slice(i, i + batchSize);
    const texts = batch.map(c => `${c.cite}\n${c.text}`);

    console.log(`[RAG Index] Embedding chunks ${i + 1}–${Math.min(i + batchSize, chunks.length)}...`);
    const res = await fetch(EMBED_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ texts }),
    });

    if (!res.ok) {
      const errText = await res.text();
      throw new Error(`Embedding request failed (${res.status}): ${errText}`);
    }

    const json = await res.json();
    modelName = json.model || modelName;
    dims = json.dims || dims;

    for (let j = 0; j < batch.length; j++) {
      const chunk = batch[j];
      const vec = json.vectors[j];
      const f32 = new Float32Array(vec);
      vectors[chunk.id] = float32ArrayToBase64(f32);
    }
  }

  const indexOutput = {
    model: modelName,
    dims,
    built: new Date().toISOString(),
    vectors,
  };

  writeFileSync(INDEX_FILE, JSON.stringify(indexOutput, null, 2), 'utf-8');
  console.log(`[RAG Index] Successfully wrote index (${Object.keys(vectors).length} vectors) to ${INDEX_FILE}`);
}

main().catch(err => {
  console.error('[RAG Index] Error:', err.message);
  process.exit(1);
});
