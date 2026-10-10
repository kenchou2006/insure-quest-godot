import { test } from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { s2t, normalizeStrings } from '../src/s2t.ts';
import { LLMAI, partialJsonStringDone, partialJsonString } from '../src/ai.ts';
import { CLIENTS } from '../src/game/data.ts';

test('s2t converts simplified characters in specific phrases', () => {
  assert.equal(s2t('年輕勞工的逆袭之路'), '年輕勞工的逆襲之路');
  assert.equal(s2t('资产'), '資產');
  assert.equal(s2t('保险顾问与客户'), '保險顧問與客戶');
  assert.equal(s2t('风险规避与财富积累'), '風險規避與財富積累');
});

test('s2t keeps already-Traditional characters and ambiguous characters unchanged', () => {
  // 了, 面, 里程 must NOT be converted
  assert.equal(s2t('了'), '了');
  assert.equal(s2t('面'), '面');
  assert.equal(s2t('里程'), '里程');
  assert.equal(s2t('完成了五個面的里程碑'), '完成了五個面的里程碑');

  // Big5-valid characters (干, 后, 宿舍, surnames 范/杰) stay; simplified-only 发 becomes 發
  assert.equal(s2t('干'), '干');
  assert.equal(s2t('后'), '后');
  assert.equal(s2t('宿舍'), '宿舍');
  assert.equal(s2t('范文杰'), '范文杰');
  assert.equal(s2t('发'), '發');
  // Phrase fixes on top of the character map
  assert.equal(s2t('资产规划与计划'), '資產規劃與計劃');

  // Standard traditional sentences remain identical
  const tradSentence = '這是傳統的保險需求分析，重視家庭責任與風險保障。';
  assert.equal(s2t(tradSentence), tradSentence);
});

test('normalizeStrings recursively converts nested objects and arrays', () => {
  const input = {
    client: {
      name: '陈顾问',
      tags: ['年轻劳工', '资产规划'],
      metrics: {
        score: 100,
        active: true,
        summary: '完成了保险方案设计',
      },
      milestones: [
        { title: '逆袭之路', year: 2026 },
      ],
    },
    status: null,
  };

  const expected = {
    client: {
      name: '陳顧問',
      tags: ['年輕勞工', '資產規劃'],
      metrics: {
        score: 100,
        active: true,
        summary: '完成了保險方案設計',
      },
      milestones: [
        { title: '逆襲之路', year: 2026 },
      ],
    },
    status: null,
  };

  assert.deepEqual(normalizeStrings(input), expected);
});

test('partialJsonStringDone normalizes partial streamed json text with s2t', () => {
  const incompleteJson = '{"answer": "这是年轻劳工的逆袭之路，需要重视资产和险种"}';
  const res = partialJsonStringDone(incompleteJson, 'answer');
  assert.equal(res.done, true);
  assert.equal(res.text, '這是年輕勞工的逆襲之路，需要重視資產和險種');

  const partial = partialJsonString(incompleteJson, 'answer');
  assert.equal(partial, '這是年輕勞工的逆襲之路，需要重視資產和險種');
});

test('AI-result normalization test with an LLMAI provider returning simplified text', async () => {
  // A fake LLMAI provider whose ask implementation returns parsed zod objects containing simplified Chinese
  class FakeSimplifiedLLM extends LLMAI {
    readonly provider = 'fake-simplified';
    protected async ask<T extends z.ZodType>(
      schema: T,
      _system: string,
      _user: string,
      _maxTokens?: number,
      onText?: (raw: string) => void,
    ): Promise<z.infer<T> | null> {
      if (onText) {
        onText('{"answer": "我是年轻劳工，想要逆袭"}');
      }
      // Return raw parsed object with simplified text, wrapped in normalizeStrings (as done by WorkersAI and NvidiaNimAI)
      const mockRaw = {
        answer: '「我是年轻劳工，我的逆袭之路需要资产累积。」',
        revealedFacts: ['年轻劳工的逆袭之路'],
        trustDelta: 5,
        insightDelta: 8,
        emotion: 'receptive',
        compliance: {
          level: 'warning',
          penalty: -5,
          issues: [
            {
              code: 'EARLY_PRESSURE',
              quote: '先买这笔保险',
              rule: '未探询需求',
              suggestion: '先了解客户真实需求与资产状况',
            },
          ],
        },
        coachTip: '关注年轻劳工的逆袭之路与资产防线',
      };
      const parsed = schema.safeParse(mockRaw);
      assert.ok(parsed.success, 'Schema parse should succeed');
      return normalizeStrings(parsed.data) as z.infer<T>;
    }
  }

  const ai = new FakeSimplifiedLLM();
  const c = CLIENTS[0];
  let streamed = '';
  const result = await ai.talk(c, null, [], '先買這筆保險吧', (partial) => {
    streamed = partial;
  });

  assert.ok(result !== null);
  // Streamed callback received Traditional text
  assert.ok(streamed.includes('年輕勞工') && streamed.includes('逆襲'));
  // Returned answer has simplified characters converted to Traditional (襲, 勞, 資, 產)
  assert.equal(result.answer, '「我是年輕勞工，我的逆襲之路需要資產累積。」');
  // revealedFacts is whitelisted against the client's real facts, so the fake title is dropped
  assert.deepEqual(result.revealedFacts, []);
  // Coach tip converted
  assert.equal(result.coachTip, '關注年輕勞工的逆襲之路與資產防線');
  // Compliance issue suggestion converted
  assert.equal(result.compliance.issues[0].suggestion, '先了解客戶真實需求與資產狀況');
});
