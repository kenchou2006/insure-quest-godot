import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  LEGAL_REFS_BY_CODE,
  LAW_CHUNKS,
  LAW_CHUNKS_BY_ID,
  refsForCode,
  mergeRefs,
  type LegalRef,
} from '../src/game/legal-refs.ts';
import {
  ruleCompliance,
  mergeCompliance,
  RULE_BY_CODE,
  type ComplianceCode,
} from '../src/game/compliance.ts';
import {
  cosineSimilarity,
  rankVectors,
  retrieveLaw,
  RAG_SIMILARITY_THRESHOLD,
  float32ArrayToBase64,
  base64ToFloat32Array,
} from '../src/rag.ts';
import { RuleAI, MockAI, MeteredAI } from '../src/ai.ts';

test('法規切塊庫包含 27 段法規原文，每段有完整 metadata', () => {
  assert.equal(LAW_CHUNKS.length, 27);
  assert.equal(LAW_CHUNKS_BY_ID.size, 27);
  for (const chunk of LAW_CHUNKS) {
    assert.ok(chunk.id, 'chunk id 必須存在');
    assert.ok(chunk.doc, 'chunk doc 必須存在');
    assert.ok(chunk.ref, 'chunk ref 必須存在');
    assert.ok(chunk.cite.includes('《') && chunk.cite.includes('》'), `cite 格式需含書名號: ${chunk.cite}`);
    assert.ok(chunk.text.length > 10, `text 必須有實質內容: ${chunk.id}`);
    assert.ok(chunk.url.startsWith('https://'), `url 必須合法: ${chunk.url}`);
    assert.ok(chunk.revised, 'revised 日期必須存在');
  }
});

test('每個非 INJECTION 的 ComplianceCode 都對應到存在的 chunk id（1–3 條）', () => {
  const codes: ComplianceCode[] = [
    'PROMISE_RETURN',
    'FEAR_MONGERING',
    'MISLEADING_COMPARISON',
    'UNDISCLOSED_RISK',
    'EARLY_PRESSURE',
  ];

  for (const code of codes) {
    const ids = LEGAL_REFS_BY_CODE[code];
    assert.ok(Array.isArray(ids), `${code} 必須有對應 chunk id 陣列`);
    assert.ok(ids.length >= 1 && ids.length <= 3, `${code} 對應條數應在 1–3 條之間，實際為 ${ids.length}`);
    for (const id of ids) {
      assert.ok(LAW_CHUNKS_BY_ID.has(id), `${code} 對應的 chunk id "${id}" 不存在於 law-chunks.json`);
    }

    const refs = refsForCode(code);
    assert.equal(refs.length, ids.length);
    for (const r of refs) {
      assert.ok(r.cite, 'LegalRef cite 必須存在');
      assert.ok(r.text, 'LegalRef text 必須存在');
      assert.ok(r.url, 'LegalRef url 必須存在');
      assert.ok(r.revised, 'LegalRef revised 必須存在');
      // Laws cite an article (第N條); 公平待客原則 is a list of principles (原則N)
      assert.ok(/第[\d-]+條|原則[一二三四五六七八九十]/.test(r.cite), `cite 必須含條號或原則編號: ${r.cite}`);
    }
  }

  assert.deepEqual(LEGAL_REFS_BY_CODE.INJECTION_ATTEMPT, [], 'INJECTION_ATTEMPT 對照應為空陣列');
  assert.deepEqual(refsForCode('INJECTION_ATTEMPT'), []);
});

test('ruleCompliance("保證穩賺不賠") 的 issue 附帶 refs 且可被 structuredClone', () => {
  const result = ruleCompliance('這個方案保證穩賺不賠');
  assert.equal(result.level, 'violation');
  assert.ok(result.issues.length >= 1);
  const issue = result.issues.find(i => i.code === 'PROMISE_RETURN');
  assert.ok(issue, '應辨識出 PROMISE_RETURN');
  assert.ok(issue.refs && issue.refs.length >= 1, 'issue 必須帶 refs');
  for (const ref of issue.refs!) {
    assert.ok(ref.cite.includes('第'), `cite 應含「第」: ${ref.cite}`);
    assert.ok(ref.cite.includes('條'), `cite 應含「條」: ${ref.cite}`);
    assert.ok(ref.text.length <= 125, '摘錄字數應適當截短');
  }

  // 驗證純資料特性（structuredClone 不報錯且深拷貝相等）
  assert.doesNotThrow(() => {
    const cloned = structuredClone(result);
    assert.deepEqual(cloned, result);
  });
});

test('mergeCompliance 正確保留與合併 refs（AI 無 refs 時補上靜態 refs）', () => {
  const ruleComp = ruleCompliance('出事就完了，一定要買');
  assert.ok(ruleComp.issues.some(i => i.code === 'FEAR_MONGERING'));

  // 1. AI issue 無 refs：自動補上靜態 refs
  const aiCompNoRefs = {
    level: 'violation' as const,
    penalty: -20,
    issues: [
      {
        code: 'PROMISE_RETURN' as const,
        quote: '一定賺',
        rule: RULE_BY_CODE.PROMISE_RETURN,
        suggestion: '避免保證用語',
      },
    ],
  };

  const merged1 = mergeCompliance(ruleComp, aiCompNoRefs);
  assert.equal(merged1.level, 'violation');
  const promiseIssue = merged1.issues.find(i => i.code === 'PROMISE_RETURN');
  assert.ok(promiseIssue, '應包含 PROMISE_RETURN');
  assert.ok(promiseIssue.refs && promiseIssue.refs.length >= 1, '應自動補上靜態 refs');

  // 2. AI issue 自帶檢索到的新 refs：檢索結果排前面，最多 3 條，去重
  const customRAGRef: LegalRef = {
    cite: '《自訂檢索條文》第99條',
    text: '此為檢索結果...',
    url: 'https://example.com',
    revised: '民國 112 年 01 月 01 日',
  };
  const aiCompWithRefs = {
    level: 'violation' as const,
    penalty: -20,
    issues: [
      {
        code: 'PROMISE_RETURN' as const,
        quote: '一定賺',
        rule: RULE_BY_CODE.PROMISE_RETURN,
        suggestion: '避免保證用語',
        refs: [customRAGRef],
      },
    ],
  };

  const merged2 = mergeCompliance(ruleComp, aiCompWithRefs);
  const pIssue2 = merged2.issues.find(i => i.code === 'PROMISE_RETURN');
  assert.ok(pIssue2 && pIssue2.refs);
  assert.equal(pIssue2.refs[0].cite, '《自訂檢索條文》第99條', '檢索到的條文應排在最前面');
  assert.ok(pIssue2.refs.length <= 3, '最多保留 3 條');

  assert.doesNotThrow(() => structuredClone(merged2));
});

test('Float32Array 與 base64 編碼/解碼互轉一致性', () => {
  const original = new Float32Array([0.1, -0.5, 1.25, -3.14159, 0.0, 42.0]);
  const b64 = float32ArrayToBase64(original);
  assert.equal(typeof b64, 'string');
  const decoded = base64ToFloat32Array(b64);
  assert.equal(decoded.length, original.length);
  for (let i = 0; i < original.length; i++) {
    assert.ok(Math.abs(decoded[i] - original[i]) < 1e-6);
  }
});

test('小維度假向量測 cosine 相似度排序與門檻 (rankVectors)', () => {
  // 建立 4 維向量
  // Target A: 與 query 完全相同（cosine = 1.0）
  // Target B: 與 query 成 45 度角（cosine ≈ 0.707）
  // Target C: 與 query 正交（cosine = 0.0，低於 0.45 門檻）
  const query = [1, 0, 0, 0];
  const candidates = new Map<string, Float32Array>([
    ['chunk_A', new Float32Array([2, 0, 0, 0])],
    ['chunk_B', new Float32Array([1, 1, 0, 0])],
    ['chunk_C', new Float32Array([0, 1, 1, 0])],
  ]);

  const hits = rankVectors(query, candidates, 2, RAG_SIMILARITY_THRESHOLD);
  // C 相似度為 0 < 0.45，應被過濾；A (1.0) 與 B (~0.707) 應留存並依分數由高到低排序
  assert.equal(hits.length, 2);
  assert.equal(hits[0].id, 'chunk_A');
  assert.ok(Math.abs(hits[0].score - 1.0) < 1e-5);
  assert.equal(hits[1].id, 'chunk_B');
  assert.ok(hits[1].score >= RAG_SIMILARITY_THRESHOLD);
});

test('cosineSimilarity 邊界條件處理', () => {
  assert.equal(cosineSimilarity([0, 0], [1, 1]), 0);
  assert.equal(cosineSimilarity([1, 0], [0, 1]), 0);
  assert.ok(Math.abs(cosineSimilarity([3, 4], [3, 4]) - 1.0) < 1e-6);
  assert.ok(Math.abs(cosineSimilarity([1, 0], [-1, 0]) - (-1.0)) < 1e-6);
});

test('AIService / MeteredAI: ai.run 拋錯或無索引時安靜退回靜態 refs', async () => {
  // 1. RuleAI 直接回靜態 refs
  const ruleAI = new RuleAI();
  const ruleRefs = await ruleAI.lawRefs?.('保證獲利', 'PROMISE_RETURN');
  assert.ok(ruleRefs && ruleRefs.length >= 1);
  assert.equal(ruleRefs[0].cite, '《保險業務員管理規則》第19條第1項第5款');

  // 2. MockAI 直接回靜態 refs
  const mockAI = new MockAI();
  const mockRefs = await mockAI.lawRefs('保證獲利', 'PROMISE_RETURN');
  assert.deepEqual(mockRefs, ruleRefs);

  // 3. MeteredAI 當 ai.run 拋錯時，安靜捕捉並回傳靜態 refs（不讓遊戲出錯）
  const failingAi = {
    run: async () => {
      throw new Error('Cloudflare Workers AI temporary 500 error');
    },
  };
  const dummyMeter = {
    consume: async () => true,
    refund: async () => {},
  };
  const metered = new MeteredAI(new MockAI(), dummyMeter, async () => failingAi.run());
  const fallbackRefs = await metered.lawRefs('保證獲利', 'PROMISE_RETURN');
  assert.ok(fallbackRefs && fallbackRefs.length >= 1);
  assert.equal(fallbackRefs[0].cite, '《保險業務員管理規則》第19條第1項第5款');

  // 4. 訪客/機器人（meter 為 null 或未啟用）不呼叫 AI，直接回靜態 refs
  let calledAi = false;
  const spyRetriever = async () => {
    calledAi = true;
    return [];
  };
  const guestAI = new MeteredAI(new MockAI(), null, spyRetriever);
  const guestRefs = await guestAI.lawRefs('保證獲利', 'PROMISE_RETURN');
  assert.equal(calledAi, false, '訪客模式絕不呼叫 AI');
  assert.ok(guestRefs && guestRefs.length >= 1);
});
