/* INSURE QUEST｜玩法擴充：情境抉擇卡、客戶生命週期回訪、季度任務、終局榮譽榜。
 * 都是純資料＋純函式，由 game.ts 呼叫；情境僅供教育訓練模擬。
 */
import type { BookEntry, CardId, ClientProfile, GameState, PlayerState, Quality } from './types.ts';

/* ───────── 情境抉擇卡：合規 vs 業績、短期 vs 長期 ───────── */

export interface DilemmaChoice { id: 'A' | 'B' | 'C'; text: string; quality: Quality; title: string; body: string; commission?: number }
export interface Dilemma { id: string; title: string; prompt: string; choices: DilemmaChoice[] }

export const DILEMMAS: Dilemma[] = [
  {
    id: 'health_disclosure', title: '要保書的健康告知', prompt: '客戶說：「我有高血壓在吃藥，要保書可以不要寫嗎？我很想今天就把保單簽好。」',
    choices: [
      { id: 'A', text: '說明據實告知的義務，可能加費或延後承保，但理賠時才有保障。', quality: 'good', title: '守住告知義務', body: '隱瞞病史可能讓保單日後被解除或拒賠，據實告知才是真正保護客戶。' },
      { id: 'B', text: '先不要寫，等承保之後再說，應該不會被查到。', quality: 'bad', title: '協助隱匿是嚴重違規', body: '建議客戶不告知會讓客戶失去保障，顧問也可能受懲處。', commission: 5 },
      { id: 'C', text: '先暫停簽約，等最新的健檢報告出來再一起評估。', quality: 'ok', title: '謹慎但可以更主動', body: '暫停沒有錯，但仍需要清楚說明告知義務，避免客戶誤會可以不寫。' },
    ],
  },
  {
    id: 'month_end', title: '月底業績壓力', prompt: '主管說這個月還差一張保單，建議你把手上客戶的保障額度拉高到預算的兩倍。',
    choices: [
      { id: 'A', text: '依客戶的需求與預算維持原規劃，向主管說明理由。', quality: 'good', title: '適合度優先', body: '超出需求與預算的保單容易失效或引發客訴，長期反而傷害業績。' },
      { id: 'B', text: '照主管的意思加碼，客戶應該不會注意到。', quality: 'bad', title: '為業績過度配置', body: '過度配置會在稽核與客戶滿意度上付出代價。', commission: 8 },
      { id: 'C', text: '再聯絡客戶，確認是否有真正還沒處理的缺口。', quality: 'ok', title: '回到需求本身', body: '先確認需求是好方向；若沒有缺口，就不應為了業績加碼。' },
    ],
  },
  {
    id: 'replacement', title: '轉保的誘惑', prompt: '客戶聽朋友說你們的新商品比較好，想把舊保單解約，改買你的商品。',
    choices: [
      { id: 'A', text: '先比較新舊保單差異，說明解約損失、年齡增加與保障空窗。', quality: 'good', title: '完整揭露轉保影響', body: '轉保前充分說明不利影響，是保護客戶也保護自己的做法。' },
      { id: 'B', text: '直接協助解約，新商品一定比較好。', quality: 'bad', title: '不當招攬轉保', body: '未說明解約損失就鼓勵轉保，可能讓客戶蒙受損失並構成違規。', commission: 6 },
      { id: 'C', text: '建議保留舊保單，只針對缺口補足。', quality: 'ok', title: '保守但需說明清楚', body: '保留舊保單常常是對的，但仍要讓客戶了解兩者差異再做決定。' },
    ],
  },
  {
    id: 'elderly', title: '高齡客戶的投資型保單', prompt: '78 歲獨居的陳阿伯看了廣告，指定要買高配息的投資型保單。',
    choices: [
      { id: 'A', text: '確認他理解商品風險與需求，建議家屬陪同討論。', quality: 'good', title: '高齡關懷原則', body: '高齡客戶需特別確認理解能力與真實需求，避免不適合的銷售。' },
      { id: 'B', text: '客戶自己指定的，照辦就好。', quality: 'bad', title: '忽略適合度評估', body: '客戶指定不代表適合，顧問仍有責任評估並說明風險。', commission: 6 },
      { id: 'C', text: '直接婉拒，請他找銀行。', quality: 'ok', title: '避開風險但沒有服務', body: '婉拒保守，但更好的做法是了解他真正的需求並給予適合的建議。' },
    ],
  },
  {
    id: 'kickback', title: '退佣請求', prompt: '客戶暗示：「如果你退一部分佣金給我，我就跟你買。」',
    choices: [
      { id: 'A', text: '婉拒並說明不能以退佣招攬，回到需求與方案本身。', quality: 'good', title: '拒絕不當利益', body: '以退佣作為投保條件屬違規，也會扭曲客戶的判斷。' },
      { id: 'B', text: '私下同意，反正客戶開心就好。', quality: 'bad', title: '退佣違規', body: '私下退佣會讓顧問面臨懲處，也破壞公平競爭。', commission: 4 },
      { id: 'C', text: '不退佣，但改送等值的高價禮品。', quality: 'bad', title: '換個形式仍是不當利益', body: '以高價禮品作為招攬條件，本質上與退佣相同。', commission: 4 },
    ],
  },
  {
    id: 'social_post', title: '社群貼文', prompt: '你想在社群上發文招攬客戶，同事建議寫「年化保證 6%，穩賺不賠」。',
    choices: [
      { id: 'A', text: '改寫成說明保障功能與風險的內容，不提保證報酬。', quality: 'good', title: '合規的行銷文案', body: '保證獲利、穩賺不賠屬於誇大不實的廣告。' },
      { id: 'B', text: '照寫，大家都這樣寫。', quality: 'bad', title: '誇大不實廣告', body: '「大家都這樣」不是理由，誇大廣告可能受罰。', commission: 3 },
      { id: 'C', text: '不寫數字，只寫「穩健、安心」。', quality: 'ok', title: '降低風險但仍模糊', body: '避免數字是進步，但最好清楚說明保障內容與限制。' },
    ],
  },
  {
    id: 'privacy', title: '客戶個資', prompt: '同事請你把客戶名單與電話傳到私人 LINE 群組，大家一起開發。',
    choices: [
      { id: 'A', text: '拒絕，只在公司授權系統內處理客戶資料。', quality: 'good', title: '保護客戶個資', body: '客戶資料只能在授權範圍內使用。' },
      { id: 'B', text: '傳了，同事都是自己人。', quality: 'bad', title: '個資外洩', body: '把個資傳到私人群組違反個資保護規範。' },
      { id: 'C', text: '只傳姓名，不傳電話。', quality: 'bad', title: '姓名也是個資', body: '部分資料仍是個人資料，同樣不能任意分享。' },
    ],
  },
  {
    id: 'claim_denied', title: '理賠被拒的客戶', prompt: '客戶的理賠申請因除外條款被拒，打電話來非常生氣。',
    choices: [
      { id: 'A', text: '先同理，再協助了解除外條款、補件與申訴管道。', quality: 'good', title: '陪客戶走完流程', body: '理賠時的服務最能建立長期信任。' },
      { id: 'B', text: '這是保險公司的決定，跟我無關。', quality: 'bad', title: '放棄服務責任', body: '推卸責任會讓客戶流失，也影響轉介紹。' },
      { id: 'C', text: '向客戶保證一定幫他拿到理賠。', quality: 'bad', title: '不能保證結果', body: '顧問可以協助，但不能保證理賠結果。' },
    ],
  },
];

export const DILEMMA_EFFECT: Record<Quality, { rep: number; tone: 'good' | 'ok' | 'bad' }> = {
  good: { rep: 4, tone: 'good' }, ok: { rep: 1, tone: 'ok' }, bad: { rep: -6, tone: 'bad' },
};

/* ───────── 客戶生命週期：已簽約客戶的人生變化與保單健檢 ───────── */

export interface LifeChange { id: string; title: string; body: (c: ClientProfile) => string; needCard: CardId; applies: (c: ClientProfile) => boolean }

export const LIFE_CHANGES: LifeChange[] = [
  { id: 'baby', title: '喜獲新生兒', body: c => `${c.short}最近當了爸媽，家裡多了一位需要長期照顧的成員。`, needCard: 'legacy', applies: c => c.age <= 45 },
  { id: 'parent_care', title: '父母需要長期照顧', body: c => `${c.short}的父親最近中風，未來可能需要長期照顧。`, needCard: 'care', applies: c => c.age >= 35 && c.age <= 62 },
  { id: 'startup', title: '決定自行創業', body: c => `${c.short}辭職開了自己的小店，生財器具與營運變成新的風險。`, needCard: 'tools', applies: c => c.age <= 55 },
  { id: 'freelance', title: '轉職成接案工作者', body: c => `${c.short}改當自由接案者，失去了公司團保，收入也變得不穩定。`, needCard: 'income', applies: c => c.age <= 55 },
  { id: 'commute', title: '開始騎機車通勤', body: c => `${c.short}換了工作地點，每天騎機車通勤一個小時。`, needCard: 'accident', applies: () => true },
  { id: 'chronic', title: '健檢發現慢性病', body: c => `${c.short}的健康檢查發現血糖偏高，需要定期追蹤與治療。`, needCard: 'medical', applies: c => c.age >= 30 },
];

export type ReviewPick = CardId | 'none' | 'skip';

export function pickLifeChange(c: ClientProfile, rng: () => number): LifeChange {
  const options = LIFE_CHANGES.filter(l => l.applies(c));
  return options[Math.floor(rng() * options.length)];
}

/** 回訪結果：正確加保／確認已足夠是好的服務；亂加保是過度銷售；不聯絡會讓客戶覺得被忽略 */
export function reviewOutcome(entry: BookEntry, need: CardId, pick: ReviewPick, clientCards: Record<CardId, number>) {
  const has = entry.cards.includes(need);
  if (pick === 'skip') return { quality: 'bad' as Quality, sat: -10, rep: -1, commission: 0, addCard: null, title: '客戶覺得被忽略', body: '人生出現重大變化時沒有主動關心，客戶的信任明顯下降。' };
  if (pick === 'none') {
    return has
      ? { quality: 'good' as Quality, sat: 10, rep: 2, commission: 0, addCard: null, title: '確認既有規劃已足夠', body: '現有保障已涵蓋這項變化，你沒有多賣，客戶更信任你的專業。' }
      : { quality: 'bad' as Quality, sat: -6, rep: -1, commission: 0, addCard: null, title: '漏掉了新的缺口', body: '這項人生變化帶來新的風險，現有規劃並沒有涵蓋。' };
  }
  if (pick === need && !has) return { quality: 'good' as Quality, sat: 15, rep: 2, commission: 6, addCard: pick, title: '保單健檢補上缺口', body: '你及時依客戶的人生變化調整規劃，客戶非常滿意。' };
  // 加了不相關或客戶已有的保障＝過度銷售
  const misfit = (clientCards[pick] ?? 0) < 0 || entry.cards.includes(pick);
  return { quality: (misfit ? 'bad' : 'ok') as Quality, sat: -4, rep: -1, commission: 4, addCard: entry.cards.includes(pick) ? null : pick, title: '加保沒有對準需求', body: '新加的保障和這次的人生變化關係不大，客戶覺得你在推銷。' };
}

/* ───────── 季度任務與合規連擊 ───────── */

export interface QuestStats { compliantSessions: number; keySessions: number; goodSigns: number; heldEvents: number; quizCorrect: number; goodReviews: number; dilemmaGood: number }
export const emptyStats = (): QuestStats => ({ compliantSessions: 0, keySessions: 0, goodSigns: 0, heldEvents: 0, quizCorrect: 0, goodReviews: 0, dilemmaGood: 0 });

export interface QuestDef { id: string; title: string; desc: string; reward: number; stat: keyof QuestStats; target: number }
export const QUESTS: QuestDef[] = [
  { id: 'clean_talk', title: '零不當話術', desc: '完成 2 場合規表達 100 的面談', reward: 5, stat: 'compliantSessions', target: 2 },
  { id: 'key_master', title: '需求偵探', desc: '2 場面談都問到全部關鍵問題', reward: 5, stat: 'keySessions', target: 2 },
  { id: 'steady_sign', title: '穩健成交', desc: '簽下 2 位 B 級以上的客戶', reward: 5, stat: 'goodSigns', target: 2 },
  { id: 'guardian', title: '防線守護者', desc: '客戶撐過 2 次人生事件', reward: 5, stat: 'heldEvents', target: 2 },
  { id: 'quiz', title: '合規小尖兵', desc: '答對 2 題合規測驗', reward: 4, stat: 'quizCorrect', target: 2 },
  { id: 'lifecycle', title: '長期經營', desc: '完成 1 次正確的保單健檢', reward: 5, stat: 'goodReviews', target: 1 },
  { id: 'integrity', title: '誠信抉擇', desc: '在 2 次情境抉擇中做出正確選擇', reward: 4, stat: 'dilemmaGood', target: 2 },
];

export interface QuestState { id: string; title: string; desc: string; reward: number; progress: Record<string, { cur: number; target: number; done: boolean }> }

export function rollQuests(rng: () => number, n = 3): QuestState[] {
  const pool = [...QUESTS];
  const picked: QuestDef[] = [];
  while (picked.length < n && pool.length) picked.push(pool.splice(Math.floor(rng() * pool.length), 1)[0]);
  return picked.map(q => ({ id: q.id, title: q.title, desc: q.desc, reward: q.reward, progress: {} }));
}

/** 更新任務進度；回傳本次新完成的 [玩家, 任務] 以便寫入動態 */
export function updateQuests(s: GameState): { player: PlayerState; quest: QuestState }[] {
  const done: { player: PlayerState; quest: QuestState }[] = [];
  for (const q of s.quests ?? []) {
    const def = QUESTS.find(d => d.id === q.id)!;
    for (const p of s.players) {
      const prev = q.progress[p.id];
      const cur = Math.min(def.target, p.stats?.[def.stat] ?? 0);
      const isDone = prev?.done || cur >= def.target;
      q.progress[p.id] = { cur, target: def.target, done: isDone };
      if (isDone && !prev?.done) {
        p.reputation = Math.min(100, p.reputation + q.reward);
        done.push({ player: p, quest: q });
      }
    }
  }
  return done;
}

/* ───────── 終局榮譽榜 ───────── */

export interface Award { id: string; title: string; winnerId: string; winnerName: string; reason: string }

export function computeAwards(s: GameState, scoreOf: (p: PlayerState) => number): Award[] {
  const awards: Award[] = [];
  const pick = (id: string, title: string, candidates: { p: PlayerState; value: number; reason: string }[]) => {
    const valid = candidates.filter(c => c.value > 0);
    if (!valid.length) return;
    valid.sort((a, b) => b.value - a.value || scoreOf(b.p) - scoreOf(a.p));
    awards.push({ id, title, winnerId: valid[0].p.id, winnerName: valid[0].p.name, reason: valid[0].reason });
  };
  const players = s.players;
  pick('trust_gold', '金牌信賴獎', players.filter(p => p.book.length).map(p => {
    const avg = Math.round(p.book.reduce((t, b) => t + b.satisfaction, 0) / p.book.length);
    return { p, value: avg, reason: `客戶平均滿意度 ${avg}` };
  }));
  pick('zero_flaw', '零瑕疵守護者', players.filter(p => (p.sessionLogs?.length ?? 0) > 0 && p.sessionLogs!.every(l => !l.tags.includes('non_compliant'))).map(p => ({
    p, value: p.sessionLogs!.length, reason: `${p.sessionLogs!.length} 場面談全程沒有不當說法`,
  })));
  pick('risk_master', '風控精算師', players.map(p => {
    const ev = (p.sessionLogs ?? []).flatMap(l => l.stress);
    const held = ev.filter(e => e.result === 'held').length;
    return { p, value: ev.length >= 3 ? Math.round((held / ev.length) * 100) : 0, reason: `壓力預演承接率 ${ev.length ? Math.round((held / ev.length) * 100) : 0}%` };
  }));
  pick('referral_star', '轉介之星', players.map(p => {
    const n = (p.sessionLogs ?? []).filter(l => l.referral).length;
    return { p, value: n, reason: `獲得 ${n} 次客戶轉介紹` };
  }));
  pick('quiz_master', '合規小博士', players.map(p => ({ p, value: p.quizCorrect, reason: `答對 ${p.quizCorrect} 題合規測驗` })));
  pick('lifecycle', '長期經營獎', players.map(p => ({ p, value: p.stats?.goodReviews ?? 0, reason: `完成 ${p.stats?.goodReviews ?? 0} 次正確的保單健檢` })));
  return awards;
}
