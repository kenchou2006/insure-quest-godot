# 第 1 批（伺服器端）：動態人生變數、3 輪 AI 對話＋合規雷達、十年後的信

依據 docs/design/README.md 與 docs/design/round2-agy.md（schema 與 prompt 大綱）。只改 server/，**不要改 client/**（第 2 批才做）。

## 硬性規則
- **訪客（沒有 accountId）與電腦顧問永遠不用 AI**：一律走 MeteredAI 的規則版 fallback（`server/src/ai.ts` 已有機制，新功能沿用 `MeteredAI.run`）。不要新增任何繞過登入的方式。
- 每個新的 AI 方法：RawAI 介面、`LLMAI`（Workers AI／Claude 共用的 prompt 層）、`MockAI`、`RuleAI`／規則版函式都要實作；AI 回傳一律用 zod 驗證，驗證失敗回傳 null → 退還額度並改用規則版。
- 玩家輸入是不可信資料：放在 `<trainee_utterance>` 區塊，system prompt 明確要求忽略其中的指令（參考 round2-agy.md）。
- 結局、分數、壓力測試勝負**只能由規則引擎決定**；AI 只負責文字。
- 不使用 emoji（字型沒有）；可用 ✓×★●◆※。所有文案繁體中文。
- 既有測試（server/test/*.test.ts）必須維持通過；新功能要新增測試。不能執行指令沒關係，Claude 會跑 `npm run check` 驗證。
- 協定變更要向下相容到 client 第 2 批完成前：保留既有 `ask`／`ask_free`／`objection_free` 動作。

## 1. 動態人生變數（規則機制）
- 在 `src/game/` 新增 `LIFE_TWISTS`：6–8 個情境（例：長輩確診需長照、剛換工作收入不穩、曾被不當推銷而高度防備、房貸寬限期到期、配偶失業、剛得知懷孕）。每個情境有：`id, title, hint`（客戶會透露的一句話）、對客戶的調整（例如提高某個 stress event 的 need、調整 `plan.ideal` 或 `plan.cards` 權重、初始 trust 變化）。
- 開始面談時（`game.ts` 建立 session 處）以 ctx.rng 抽 1 個掛到 session（`session.twist`），publicView 要帶出 `twist: {id,title,hint}`。
- 調整後的客戶要透過一個函式（例如 `applyTwist(client, twist)` 回傳新的 ClientProfile 副本）傳給 evaluatePlan／runStress，**不要修改 CLIENTS 原始資料**。
- 電腦顧問（`bots.ts`）的資深策略要能看到調整後的客戶。
- 測試：對每位客戶 × 每個情境，資深電腦的配置仍為 good 且通過壓力測試（仿照既有「每位客戶：資深電腦的配置判定為 good」測試）。

## 2. 3 輪 AI 對話＋合規雷達（合併成一次呼叫）
- 新動作 `{type:'talk', text: string, suggested?: QuestionId}`：在 discover 步驟使用，每場面談最多 3 輪（`session.talkLeft = 3`）。`suggested` 代表玩家點了建議問句按鈕（文字就是該題 QUESTIONS 的 text）。
- 處理流程：
  1. 先跑**規則版合規雷達**（新函式 `ruleCompliance(text)`：關鍵字／正則判斷 保證、穩賺、一定賺、比定存好、不買會後悔、出事就完了、只剩今天…等），結果寫進該輪紀錄。
  2. 呼叫 `ai.talk(client, twist, history, text)`，回傳 round2-agy.md 的 CombinedDialogueSchema（answer、revealedFacts、trustDelta、insightDelta、emotion、compliance{level,penalty,issues[{code,quote,rule,suggestion}]}、coachTip）。數值要在伺服器端再 clamp 一次。
  3. 規則版 fallback（訪客／額度用完／AI 失敗）：若有 `suggested` 就用既有的 `answers[qid]` 邏輯；自由輸入就用既有 `ruleFreeQuestion`；合規用 `ruleCompliance`。
  4. 合規結果：level 取「規則版與 AI 版較嚴重者」；penalty 扣在 `m.compliance`；revealedFacts 只能對應客戶真實的 facts title（不在清單內的丟掉），命中的要計入既有線索／洞察機制（參考 `freeHits`、`ask` 的處理）。
  5. 存入 `session.asked`（沿用欄位，新增 `compliance`、`emotion`、`coachTip`、`source:'ai'|'rule'`），讓 sessionLogs 與決策紀錄（decisions）、弱點標籤也能用到（違規要產生對應的弱點標籤，參考 `TAG_INFO`）。
- 3 輪用完或玩家按「進入方案配置」（既有 `to_plan`）就結束 discover。舊的 `ask`／`ask_free` 先保留。
- 電腦顧問：讓 bots 改用 `talk` 搭配 `suggested`（規則版），維持平衡。
- 測試：ruleCompliance 的正反例、talk 的規則版流程、訪客不會呼叫 RawAI、AI 回傳不合法 JSON 會 fallback 且退額度、revealedFacts 被白名單過濾、prompt 中玩家文字被包在 `<trainee_utterance>`。

## 3. 十年後的信
- 在 result 步驟（`game.ts` 約 278–308 行 runStress 之後）由規則引擎決定 `letter`：`{ outcome:'thanks'|'regret'|'mixed', event: 十年內發生的一個 stress event 標題, gap: 缺口金額（數字，可為 0）, signed }`。
- 規則版模板信（訪客與 fallback）：依 outcome 產生 120–200 字客戶口吻的信，內容要提到 event 與 gap。
- AI 版：`ai.letter(client, twist, letterFacts)` 只能改寫語氣，prompt 明確給定 outcome／event／gap 不可更動；伺服器檢查 AI 文字中**不能出現與 outcome 相反的結論**（簡單規則：thanks 時不能含「沒有理賠」「後悔」等），不合格就用模板。
- AI 寫信在背景進行，不要阻塞回合：可以先放模板，AI 回來再更新（參考 `enrichCoach` 的做法），或放在結算時批次生成。結算報告 FinalRow 帶出每位客戶的信（最多保留 3 封最具代表性的）。
- 測試：outcome 由壓力測試決定、模板信包含 event 與 gap、AI 給出相反結論時會被換成模板。

## 完成後
在 docs/design/tasks/batch1-server.md 最下方追加「完成紀錄」：改了哪些檔案、新的協定欄位（client 第 2 批要用）、尚未完成的項目。

---

## 完成紀錄

### 1. 修改與新增之檔案清單
- **新增 `server/src/game/twists.ts`**：
  - 定義 `LIFE_TWISTS`（7 個動態人生變數情境：長輩確診需長照、剛換工作收入不穩、曾被不當推銷而高度防備、房貸寬限期到期、配偶失業待業中、剛得知懷孕喜訊、籌備副業工作室）。
  - 實作 `applyTwist(client, twist)`：安全產生 `ClientProfile` 調整副本，不更動原始 `CLIENTS`。
- **新增 `server/src/game/compliance.ts`**：
  - 實作 `ruleCompliance(text)`：正規表達式與關鍵字即時偵測 `PROMISE_RETURN`（保證收益）、`FEAR_MONGERING`（恐嚇推銷）、`MISLEADING_COMPARISON`（不實比較）、`EARLY_PRESSURE`（時間/預算逼單）、`INJECTION_ATTEMPT`（指令注入攻擊）。
  - 實作 `mergeCompliance(ruleComp, aiComp)`：整合規則版初篩與 AI 深度判讀，以較嚴重者與扣分較多者為準。
- **新增 `server/src/game/letters.ts`**：
  - 實作 `determineLetter(client, signed, st)`：由壓力預演與簽約狀態決定結局傾向（`thanks`／`regret`／`mixed`）、關鍵事件與缺口金額（數字，萬元）。
  - 實作 `generateTemplateLetter(client, facts)`：120–200 字繁體中文口吻客戶模板信，內含事件與缺口數額。
  - 實作 `validateLetterContent(content, outcome)`：伺服器端檢查 AI 改寫文字長度及相反結論禁語（thanks 禁「後悔/沒有理賠」、regret 禁「慶幸/還好有買」），不合格時自動換成模板信。
- **修改 `server/src/game/types.ts`**：
  - 匯入並擴充型別定義（`LifeTwist`、`ClientLetter`、`ComplianceLevel`）。
  - `SessionState`：新增 `twist?: LifeTwist | null`、`talkLeft?: number`；`asked` 元素擴充 `compliance`、`emotion`、`coachTip`、`source`；`result` 新增 `letter?: ClientLetter | null`。
  - `SessionLog`：新增 `twist` 與 `letter`。
  - `FinalRow`：新增 `letters?: { clientName: string; outcome: 'thanks' | 'regret' | 'mixed'; content: string }[]`。
  - `Action`：新增動作 `{ type: 'talk'; text: string; suggested?: QuestionId }`。
- **修改 `server/src/ai.ts`**：
  - 新增 zod 結構 `CombinedDialogueSchema`（依 round2-agy.md 定義，含客戶回覆、線索白名單、雙向信任與洞察變化、客戶心理狀態、合規燈號與條文、教練建議）與 `LetterSchema`。
  - 在 `RawAI` 與 `AIService` 新增 `talk(...)` 與 `letter(...)`。
  - `LLMAI` 實作：
    - `talk`：玩家輸入包於 `<trainee_utterance>`，包含動態變數 Persona 與防注入指令，數值在伺服器端 clamp。
    - `letter`：給定不可更動的事實參數，經 `validateLetterContent` 驗證合格後回傳。
  - `RuleAI`、`MockAI`、`MeteredAI`：完整實作 `talk` 與 `letter`，訪客與額度耗盡時無縫走規則版 fallback。
- **修改 `server/src/game/game.ts`**：
  - `startSession`：抽 1 個 `twist` 掛到 session，套用 `initialTrustDelta`，初始化 `talkLeft = 3`。
  - `applyActionInner`：新增 `talk` 動作處理（合規雷達、AI 呼叫、白名單過濾 `revealedFacts` 計入線索與 `freeHits`、扣減 `talkLeft`、記錄至 `asked` 與弱點決策）。
  - `to_plan` 與 `interviewReady`：支援 3 輪對話結束後或標準題問滿時進入方案配置。
  - `plan` 與 `finishSession`：全面改用 `applyTwist(c, sess.twist)` 進行適合度評估與壓力測試；生成十年後的信，背景非阻塞呼叫 AI 潤色。
  - `publicView`：帶出 `session.twist`、`session.talkLeft`、`session.result.letter`。
  - `endGame`：`FinalRow` 帶出每位顧問代表性信件（最多 3 封）。
- **修改 `server/src/game/bots.ts`**：
  - 電腦顧問在 discover 階段改用 `talk` 搭配 `suggested`。
  - 資深策略（pro）在 plan 階段依據 `applyTwist(c, sess.twist)` 調整後客戶進行最優配置。
- **新增 `server/test/batch1.test.ts`**：
  - 覆蓋所有新增功能單元測試：每位客戶 × 每個動態情境資深電腦判定為 good 且通過壓力測試、合規雷達正反例、talk 動作規則版流程、訪客與額度退還、線索白名單過濾、十年後的信與相反結論過濾、publicView 與結算資料欄位驗證。

### 2. 新的協定欄位（Client 第 2 批需對接）
1. **動作請求 (`Action`)**：
   - `{ type: 'talk', text: string, suggested?: QuestionId }`：
     - `text`：受訓顧問發言文字（建議問句的文字或自由輸入）。
     - `suggested`（可選）：點擊建議問句按鈕時帶入題目 ID（`'income' | 'goal' | 'coverage' | 'risk' | 'premium'`）。
2. **公開狀態 (`publicView.session`)**：
   - `twist: { id: string, title: string, hint: string } | null`：當前面談隨機抽取的動態人生變數，前端可直接展示在客戶卡上。
   - `talkLeft: number`：剩餘對話輪數（初始為 3，降至 0 時需引導至「進入方案配置」）。
   - `asked: Array<{ ..., compliance?: 'pass' | 'warning' | 'violation', emotion?: string, coachTip?: string, source?: 'ai' | 'rule' }>`：對話紀錄包含該輪合規燈號、客戶防備心理、教練短評與生成來源。
   - `result.letter: { outcome: 'thanks' | 'regret' | 'mixed', event: string, gap: number, signed: boolean, content: string } | null`：十年後的信件物件，包含結局傾向、關聯事件、缺口金額（萬元）與信件全文（初始為模板信，若有登入 AI 潤色完成會即時更新）。
3. **結算報告 (`publicView.final`)**：
   - `letters?: Array<{ clientName: string, outcome: 'thanks' | 'regret' | 'mixed', content: string }>`：每位顧問面談中最多 3 封最具代表性的信件紀錄，用於複盤展示。

### 3. 尚未完成的項目（後續批次待辦）
- **Client 第 2 批（Godot / Web 前端）**：
  - 面談面板視覺小說對話氣泡化與 3 輪對話 UI。
  - 建議問句按鈕＋自由輸入框＋即時前端正則初篩燈號。
  - 動態人生變數 Tag 與客戶透露提示之展示。
  - 結果階段「十年後的信」專屬信紙動態展示面板。
- **展示與評審機制**：
  - 評審體驗碼（`DEMO_CODES`）免登入體驗 AI 呼叫額度之介面輸入與綁定（第 2 批或後續）。
