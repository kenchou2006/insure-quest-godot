/* INSURE QUEST | Legal references mapping and data.
 * Verbatim regulation chunks from server/rag/law-chunks.json mapped to ComplianceCodes.
 */
import type { ComplianceCode } from './compliance.ts';
import lawChunksData from '../../rag/law-chunks.json' with { type: 'json' };
import lawMapData from '../../rag/law-map.json' with { type: 'json' };

export interface LawChunk {
  id: string;
  doc: string;
  ref: string;
  cite: string;
  text: string;
  url: string;
  revised: string;
  fetched: string;
  topic: string;
}

export interface LegalRef {
  cite: string;
  text: string;
  url: string;
  revised: string;
}

export const LAW_CHUNKS: LawChunk[] = (lawChunksData as { chunks: LawChunk[] }).chunks;

export const LAW_CHUNKS_BY_ID = new Map<string, LawChunk>(
  LAW_CHUNKS.map(c => [c.id, c]),
);

export const LEGAL_REFS_BY_CODE = lawMapData as Record<ComplianceCode, string[]>;

/**
 * Excerpt rule for regulation chunk:
 * If chunk ref contains '款', take the body following the first newline;
 * otherwise take the original text. Capped at 120 chars (with '…' if truncated).
 * (Keep in sync with chunkToRef in server/tools/rag-build-index.mjs)
 */
export function chunkToRef(chunk: LawChunk): LegalRef {
  let content = chunk.text;
  if (chunk.ref && chunk.ref.includes('款')) {
    const nl = chunk.text.indexOf('\n');
    if (nl !== -1) {
      content = chunk.text.slice(nl + 1).trim();
    }
  }
  const text = content.length > 120 ? `${content.slice(0, 120)}…` : content;
  return {
    cite: chunk.cite,
    text,
    url: chunk.url,
    revised: chunk.revised,
  };
}

export function refsForCode(code: ComplianceCode): LegalRef[] {
  const ids = LEGAL_REFS_BY_CODE[code] ?? [];
  const refs: LegalRef[] = [];
  for (const id of ids) {
    const chunk = LAW_CHUNKS_BY_ID.get(id);
    if (chunk) {
      refs.push(chunkToRef(chunk));
    }
  }
  return refs;
}

/** Merges retrieved RAG refs with static refs: retrieved first, deduplicated by cite, capped at max items (default 3) */
export function mergeRefs(ragRefs?: LegalRef[], staticRefs?: LegalRef[], max = 3): LegalRef[] {
  const result: LegalRef[] = [];
  const seen = new Set<string>();
  for (const r of [...(ragRefs || []), ...(staticRefs || [])]) {
    if (!r || !r.cite) continue;
    if (!seen.has(r.cite)) {
      seen.add(r.cite);
      result.push(r);
      if (result.length >= max) break;
    }
  }
  return result;
}
