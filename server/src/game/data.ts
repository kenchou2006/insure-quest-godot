/* INSURE QUEST｜遊戲內容：題目、保障卡、棋盤、市場事件、合規測驗、客戶名冊。 */
import type { CardId, ClientProfile, MarketEvent, QuestionId, QuizItem, Tile, Alloc, Spot } from './types.ts';
import { stressOne, TOTAL_COINS } from './engine.ts';
import original from './clients-original.json' with { type: 'json' };
import { extraClients } from './clients-extra.ts';
import hotspots from './hotspots-extra.json' with { type: 'json' };

export const QUESTIONS: { id: QuestionId; text: string; coach: string }[] = [
  { id: 'income', text: '如果收入中斷一個月，哪些支出仍然必須支付？', coach: '把抽象風險轉成客戶能回答的生活問題。' },
  { id: 'goal', text: '這個人生目標裡，哪一部分是你最不願意犧牲的？', coach: '先確認想保住的目標，方案才不會只剩商品。' },
  { id: 'coverage', text: '目前遇到醫療或無法工作時，有哪些資源可以使用？', coach: '盤點現況，不預設客戶什麼都沒有。' },
  { id: 'risk', text: '這筆目標資金在使用前，你最多能接受多少波動？', coach: '風險承受度必須和使用時間一起看。' },
  { id: 'premium', text: '你一個月願意拿多少錢買保險？', coach: '預算重要，但太早問會讓客戶覺得你只想成交。' },
];

export const CARDS: { id: CardId; tag: string; title: string; detail: string }[] = [
  { id: 'medical', tag: '醫療支出', title: '醫療費用分擔', detail: '降低治療與復健支出對目標資金的衝擊。' },
  { id: 'income', tag: '收入中斷', title: '工作能力防線', detail: '因傷病無法工作期間，提供現金替代來源。' },
  { id: 'accident', tag: '意外風險', title: '意外支出防線', detail: '承接突發事故帶來的額外成本。' },
  { id: 'tools', tag: '營業中斷', title: '器材與營運防線', detail: '工作工具、設備或營業中斷時的財務緩衝概念。' },
  { id: 'legacy', tag: '家庭責任', title: '家庭責任防線', detail: '有人依靠你的收入生活時，保留家人的生活與教育。' },
  { id: 'care', tag: '長期照顧', title: '長期照顧準備', detail: '為自己或家人未來的照顧需求預作安排。' },
];

const T = (type: Tile['type'], name: string): Tile => ({ type, name });
export const BOARD: Tile[] = [
  T('start', '季度結算'), T('client', '社區咖啡廳'), T('training', '合規訓練'), T('client', '公司說明會'),
  T('market', '市場快訊'), T('life', '人生事件'), T('client', '親友聚餐'), T('seminar', '顧問研討會'),
  T('client', '商圈拜訪'), T('life', '人生事件'), T('audit', '合規稽核'), T('client', '線上諮詢'),
  T('market', '市場快訊'), T('client', '共同工作空間'), T('training', '合規訓練'), T('life', '人生事件'),
  T('client', '傳統市場'), T('referral', '客戶轉介紹'), T('client', '親子活動'), T('market', '市場快訊'),
  T('life', '人生事件'), T('client', '醫院附近'), T('audit', '合規稽核'), T('training', '合規訓練'),
];

export const MARKET_EVENTS: MarketEvent[] = [
  { id: 'crash', tag: '股市', title: '全球股市單月下跌 20%', body: '景氣衰退疑慮升高，風險資產全面修正。', absorb: { cash: 1.6, growth: -0.5 }, need: 3, lesson: '有足夠預備金的客戶不必在低點賣出；短期要用的錢不該放在高波動資產。' },
  { id: 'tech', tag: '產業', title: '科技股泡沫修正 35%', body: '熱門科技股估值回落，集中持股的投資人受創最深。', absorb: { cash: 1.6, growth: -0.8 }, need: 2.5, lesson: '集中投資放大波動；分散與預備金是基本防線。' },
  { id: 'rate', tag: '利率', title: '央行連續升息，房貸利率上升', body: '浮動利率房貸月付金增加，現金流變緊。', absorb: { cash: 2.0, protect: 0.2 }, need: 6, lesson: '利率變化先衝擊現金流，緊急預備是第一道緩衝。' },
  { id: 'inflation', tag: '物價', title: '通膨升溫，生活成本上漲 6%', body: '食物、房租與交通費全面上漲。', absorb: { cash: 1.3, growth: 0.3 }, need: 4.5, lesson: '通膨侵蝕現金購買力，長期目標需要適度成長部位。' },
  { id: 'fx', tag: '匯率', title: '新台幣劇烈升值，外幣資產縮水', body: '外幣計價的投資換回台幣後明顯縮水。', absorb: { cash: 1.5, growth: -0.4 }, need: 3, lesson: '匯率是外幣資產的隱藏風險，使用期限近的錢應避免。' },
  { id: 'bond', tag: '債市', title: '高收益債違約潮', body: '高配息商品淨值重挫，「配息」不等於「報酬」。', absorb: { cash: 1.4, growth: -0.6 }, need: 2.5, lesson: '高配息不代表本金安全，配息可能來自本金。' },
  { id: 'bull', tag: '多頭', title: '多頭行情，股市全年上漲 18%', body: '長期投資人資產穩定增值。', absorb: {}, need: 1, boom: true, lesson: '長期目標保留成長部位，才能參與市場成長；但上漲時也不要追高借錢投資。' },
  { id: 'steady', tag: '穩定', title: '經濟溫和成長，市場穩定', body: '企業獲利穩定，資產溫和增值。', absorb: {}, need: 1, boom: true, lesson: '穩定時期是檢視與再平衡配置的好時機。' },
];

export const QUIZ: QuizItem[] = [
  { id: 'q1', q: '客戶說：「我只想要保證高報酬的商品。」最合適的回應是？', options: ['推薦預期報酬最高的商品', '說明沒有商品能保證高報酬，並了解他的目標與可承受風險', '告訴他保險都保證報酬', '請他去找別人'], answer: 1, explain: '任何投資都不能保證報酬；先釐清目標與風險承受度才是適合度評估。' },
  { id: 'q2', q: '了解客戶（KYC）時，下列哪一項最優先？', options: ['客戶的預算上限', '客戶的財務狀況、需求、目標與風險承受度', '客戶認識哪些朋友可以轉介', '客戶喜歡哪家公司'], answer: 1, explain: '適合度評估的基礎是完整了解客戶的財務與需求。' },
  { id: 'q3', q: '下列哪一句說法違反合規要求？', options: ['「這張保單的保障範圍與除外條款我一起跟你看」', '「這個方案保證不會虧損，穩賺不賠」', '「你可以回家考慮，不用今天決定」', '「投資型商品的投資風險由要保人承擔」'], answer: 1, explain: '保證獲利、穩賺不賠屬於不當保證，可能構成誤導招攬。' },
  { id: 'q4', q: '客戶想把舊保單解約、改買新保單，顧問應該？', options: ['直接協助解約，新保單比較好', '說明解約可能的損失、保障空窗與新舊差異，由客戶自行判斷', '告訴他舊保單是詐騙', '不做任何說明'], answer: 1, explain: '轉保前應充分說明解約費用、年齡增加導致保費上升與保障空窗等影響。' },
  { id: 'q5', q: '客戶有高血壓，問你投保時可不可以不告知？', options: ['可以，沒人會查', '告知對方應據實告知健康狀況，隱瞞可能影響日後理賠', '幫他把健康問卷填好', '叫他先投保再說'], answer: 1, explain: '要保人有據實告知義務，顧問不得建議或協助隱瞞。' },
  { id: 'q6', q: '客戶的身分證影本和病歷，下列處理哪一個正確？', options: ['傳到私人 LINE 群組請同事幫忙看', '僅在公司授權系統中存取，用完依規定處理', '印出來放在車上方便拿', '分享給其他業務參考'], answer: 1, explain: '客戶個人資料須依個資保護規範，只在授權範圍內使用。' },
  { id: 'q7', q: '面對 75 歲的高齡客戶，銷售時應特別注意？', options: ['講快一點以免他累', '確認他理解商品內容與風險，必要時請家屬陪同，並確認投保意願', '直接推薦最貴的商品', '請他簽名就好'], answer: 1, explain: '高齡客戶需特別確認理解能力與真實意願，避免不適合的銷售。' },
  { id: 'q8', q: '客戶簽約時不方便，請你幫他簽名，你應該？', options: ['幫他簽，反正他同意了', '婉拒並說明必須由本人親簽', '請同事幫忙簽', '用印章代替'], answer: 1, explain: '代簽名屬違規行為，契約文件必須由本人親自簽名。' },
  { id: 'q9', q: '為了促成交易，下列哪一個做法不適當？', options: ['清楚說明商品費用', '以退佣或贈送高價禮品作為投保條件', '提供書面資料讓客戶比較', '說明契約撤銷權'], answer: 1, explain: '以不當利益招攬可能違反規範，也會扭曲客戶的判斷。' },
  { id: 'q10', q: '比較兩家公司的商品時，正確的做法是？', options: ['只講對方缺點', '以公開、正確的資訊客觀比較，不誇大或貶低', '說對方公司快倒了', '不比較，直接推自家商品最好'], answer: 1, explain: '不實比較或貶低同業屬於不當招攬。' },
  { id: 'q11', q: '人身保險的「契約撤銷權」（猶豫期）是什麼？', options: ['顧問可以隨時取消保單', '要保人收到保單後一定期間內，可以撤銷契約', '保險公司可以拒絕理賠的期間', '保費可以延後繳的期間'], answer: 1, explain: '要保人在收到保單後的法定期間內可撤銷契約（台灣人身保險通常為 10 日），應主動告知。' },
  { id: 'q12', q: '客戶預算有限，但需求很多，最好的做法是？', options: ['全部都買，預算以後再說', '依風險影響程度排序，先處理最關鍵的缺口與緊急預備金', '只買最便宜的', '建議他借錢投保'], answer: 1, explain: '依需求排序並守住預算，是適合度的核心；過度配置會造成後續失效。' },
];

/** 依理想配置下限校準新客戶壓力事件的 need（原型五位已有手動數值） */
function referencePlan(c: ClientProfile): { alloc: Alloc; cards: CardId[] } {
  const cash = c.plan.ideal.cash[0];
  const protect = c.plan.ideal.protect[0];
  let growth = TOTAL_COINS - cash - protect;
  let extraCash = 0;
  if (growth > c.plan.ideal.growth[1]) { extraCash = growth - c.plan.ideal.growth[1]; growth = c.plan.ideal.growth[1]; }
  const cards = (Object.entries(c.plan.cards) as [CardId, number][])
    .filter(([, w]) => w > 0).sort((x, y) => y[1] - x[1]).slice(0, 3).map(([id]) => id);
  return { alloc: { cash: cash + extraCash, protect, growth }, cards };
}

function calibrate(c: ClientProfile): ClientProfile {
  const ref = referencePlan(c);
  for (const ev of c.stress) {
    if (ev.need > 0) continue;
    const d = stressOne({ ...ev, need: 1 }, ref.alloc, ref.cards).defense;
    ev.need = Math.max(1.5, Math.round(d * 0.92 * 2) / 2);
  }
  return c;
}

/** 套用場景插圖的熱點座標（由 tools/merge-hotspots.mjs 產生）；有熱點的客戶才啟用場景找線索 */
type HotspotData = Record<string, { facts: { title: string; spot: Spot }[]; decoy: { title: string; detail: string; spot: Spot } }>;
function withHotspots(c: ClientProfile): ClientProfile {
  const h = (hotspots as HotspotData)[c.id];
  if (!h) return c;
  const facts = c.facts.map(f => ({ ...f, spot: h.facts.find(x => x.title === f.title)?.spot }));
  if (facts.some(f => !f.spot)) return c;
  return { ...c, facts, decoy: h.decoy, scene: c.id };
}

export const CLIENTS: ClientProfile[] = [
  ...(original as unknown as ClientProfile[]),
  ...extraClients.map(calibrate).map(withHotspots),
];

export const CLIENT_MAP: Record<string, ClientProfile> = Object.fromEntries(CLIENTS.map(c => [c.id, c]));

/** 場景干擾物：看起來有故事，但和財務需求無關 */
export const DECOYS: { title: string; detail: string }[] = [
  { title: '窗外風景', detail: '很美的景色，但和財務需求沒有直接關係。' },
  { title: '桌上的咖啡', detail: '客戶喜歡手沖咖啡——是好話題，但不是需求線索。' },
  { title: '牆上的海報', detail: '一張電影海報，和財務規劃無關。' },
  { title: '新買的球鞋', detail: '客戶的興趣，但看不出風險或目標。' },
  { title: '寵物照片', detail: '可以拉近距離的話題，但不是這次的關鍵線索。' },
];
