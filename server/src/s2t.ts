/* INSURE QUEST | Simplified-to-Traditional Chinese converter.
 * Converts simplified-only Chinese characters in AI outputs to Traditional Chinese (Taiwan variants),
 * preventing missing-glyph boxes in Big5 / NotoSansTC font subsets.
 */
import s2tMapRaw from './s2t-map.json' with { type: 'json' };

const s2tMap = s2tMapRaw as Record<string, string>;

/**
 * Converts simplified-only Chinese characters in a string to Traditional Chinese.
 * Unambiguous or valid Traditional Chinese characters (e.g. 了, 面, 里, 程) remain untouched.
 */
export function s2t(text: string): string {
  if (!text || typeof text !== 'string') return text;
  const out = text.replace(/[\u3400-\u9fff]/g, ch => s2tMap[ch] ?? ch);
  // 划 is valid Traditional (划船) so the map keeps it; fix the common simplified 规划/计划/策划 phrases
  return out.replace(/([規計策企])划/g, '$1劃');
}

/**
 * Recursively walks an object or array and normalizes all string values to Traditional Chinese.
 * Non-string primitives (numbers, booleans, null) and structure are preserved.
 */
export function normalizeStrings<T>(obj: T): T {
  if (obj === null || obj === undefined) return obj;
  if (typeof obj === 'string') return s2t(obj) as T;
  if (Array.isArray(obj)) {
    return obj.map(item => normalizeStrings(item)) as unknown as T;
  }
  if (typeof obj === 'object') {
    const res: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      res[k] = normalizeStrings(v);
    }
    return res as T;
  }
  return obj;
}
