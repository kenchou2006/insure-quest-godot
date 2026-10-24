/* INSURE QUEST | Legal regulation RAG retrieval.
 * Uses Workers AI @cf/baai/bge-m3 embedding and in-memory cosine similarity against server/rag/law-index.json.
 */
import { LAW_CHUNKS_BY_ID, chunkToRef, type LegalRef } from './game/legal-refs.ts';
import lawIndexJson from '../rag/law-index.json' with { type: 'json' };

export const RAG_SIMILARITY_THRESHOLD = 0.45;
export const EMBEDDING_MODEL = '@cf/baai/bge-m3';

export interface LawIndex {
  model: string;
  dims: number;
  built: string;
  vectors: Record<string, string>;
}

/** Decode base64 to byte-aligned Float32Array */
export function base64ToFloat32Array(b64: string): Float32Array {
  const bin = atob(b64);
  const len = bin.length;
  const buf = new ArrayBuffer(len);
  const view = new DataView(buf);
  for (let i = 0; i < len; i++) {
    view.setUint8(i, bin.charCodeAt(i));
  }
  return new Float32Array(buf);
}

/** Encode Float32Array to base64 */
export function float32ArrayToBase64(arr: Float32Array): string {
  const bytes = new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength);
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk) as unknown as number[]);
  }
  return btoa(bin);
}

/** Cosine similarity between two vectors */
export function cosineSimilarity(a: ArrayLike<number>, b: ArrayLike<number>): number {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) {
    const ai = a[i];
    const bi = b[i];
    dot += ai * bi;
    normA += ai * ai;
    normB += bi * bi;
  }
  const denom = Math.sqrt(normA) * Math.sqrt(normB);
  return denom > 0 ? dot / denom : 0;
}

/** In-memory cache of decoded and normalized regulation vectors */
const CACHED_VECTORS = new Map<string, Float32Array>();

function loadIndexVectors(): Map<string, Float32Array> {
  if (CACHED_VECTORS.size > 0) return CACHED_VECTORS;

  const raw = lawIndexJson as unknown as Partial<LawIndex>;
  if (!raw || typeof raw !== 'object' || !raw.vectors || typeof raw.vectors !== 'object') {
    return CACHED_VECTORS;
  }

  for (const [id, b64] of Object.entries(raw.vectors)) {
    if (typeof b64 === 'string' && b64.length > 0) {
      try {
        const vec = base64ToFloat32Array(b64);
        CACHED_VECTORS.set(id, vec);
      } catch {
        // Skip invalid vector entries
      }
    }
  }

  return CACHED_VECTORS;
}

/** Rank candidates by cosine similarity against index vectors */
export function rankVectors(
  queryVec: ArrayLike<number>,
  candidates: Map<string, Float32Array> | Record<string, Float32Array>,
  k = 2,
  threshold = RAG_SIMILARITY_THRESHOLD,
): { id: string; score: number }[] {
  const entries: [string, Float32Array][] = candidates instanceof Map
    ? Array.from(candidates.entries())
    : Object.entries(candidates);

  const scored: { id: string; score: number }[] = [];
  for (const [id, targetVec] of entries) {
    const score = cosineSimilarity(queryVec, targetVec);
    if (score >= threshold) {
      scored.push({ id, score });
    }
  }

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, k);
}

export interface AiRunner {
  run(model: string, input: unknown, options?: unknown): Promise<any>;
}

export interface RetrieveLawOptions {
  k?: number;
  gatewayId?: string;
}

/**
 * Retrieves relevant regulation chunks for query using @cf/baai/bge-m3.
 * Supports Cloudflare AI Gateway via options.gatewayId.
 * Throws any error to caller (caller handles fallback to static refs).
 */
export async function retrieveLaw(
  ai: AiRunner,
  query: string,
  kOrOptions: number | RetrieveLawOptions = 2,
  gatewayIdParam?: string,
): Promise<LegalRef[]> {
  const indexVectors = loadIndexVectors();
  if (indexVectors.size === 0) {
    throw new Error('Regulation vector index is not available');
  }

  const k = typeof kOrOptions === 'number' ? kOrOptions : (kOrOptions.k ?? 2);
  const gatewayId = typeof kOrOptions === 'object' ? kOrOptions.gatewayId : gatewayIdParam;

  const runOptions = gatewayId ? { gateway: { id: gatewayId } } : undefined;
  const res: any = runOptions
    ? await ai.run(EMBEDDING_MODEL, { text: [query] }, runOptions)
    : await ai.run(EMBEDDING_MODEL, { text: [query] });

  let queryVec: number[] | Float32Array;
  if (Array.isArray(res?.data) && Array.isArray(res.data[0])) {
    queryVec = res.data[0];
  } else if (Array.isArray(res?.data) && typeof res.data[0] === 'number') {
    queryVec = res.data;
  } else if (Array.isArray(res) && Array.isArray(res[0])) {
    queryVec = res[0];
  } else {
    throw new Error('Unexpected embedding response format from Workers AI');
  }

  const topHits = rankVectors(queryVec, indexVectors, k, RAG_SIMILARITY_THRESHOLD);
  const refs: LegalRef[] = [];
  for (const hit of topHits) {
    const chunk = LAW_CHUNKS_BY_ID.get(hit.id);
    if (chunk) {
      refs.push(chunkToRef(chunk));
    }
  }

  return refs;
}

export function makeLawRetriever(
  ai?: AiRunner,
  gatewayId?: string,
  k = 2,
): ((query: string) => Promise<LegalRef[]>) | undefined {
  if (!ai) return undefined;
  return (query: string) => retrieveLaw(ai, query, k, gatewayId);
}
