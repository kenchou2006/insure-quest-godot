# 第 2 批（Godot 介面）：對話式面談、合規雷達、十年後的信、介面手術

前置：第 1 批伺服器協定（見 batch1-server.md 最下方「完成紀錄」：`talk` 動作、`session.twist`、`talkLeft`、asked[].compliance／emotion／coachTip／source、FinalRow 的 letters）。只改 client/（必要時可小改 server 的 publicView 欄位，但要告知）。

## 硬性規則（Godot 4.7、網頁版）
- 所有 `client/scripts/**/*.gd` 都是 `@tool`（編輯器預覽靠它）。新檔案第一行也要加 `@tool`；需要網路、計時器、音效等副作用時用 `Engine.is_editor_hint()` 防護。編輯器預覽場景 `client/scenes/preview/*.tscn` 必須仍能顯示（資料來自 states.json，Claude 會重新產生）。
- UI 全部用程式碼建構，沿用 `scripts/ui/ui.gd` 的元件（UI.panel、UI.label、UI.button、UI.box、UI.text_input…）。中文輸入一定要用 `UI.text_input`（網頁版靠 HTML overlay 處理輸入法）。
- 不能定義與原生方法同名的函式（例如 `draw_ellipse`）；`Button.flat = true` 會讓 stylebox 覆寫失效，不要用。
- 不使用 emoji（字型沒有）；可用 ✓×★●◆※▲▼。
- 四種版面都要可用：desktop、phone_landscape、tablet_portrait、phone_portrait（`UI.is_phone()`、`UI.is_portrait()`、`UI.is_phone_portrait()`）。
- 訪客（`not Net.ai_enabled`）的文案不能出現「AI」字樣的承諾；改顯示「規則版」。
- 不要執行指令；Claude 會用 Godot 編譯、跑截圖驗證。

## 1. 面談 discover 步驟改成對話式（session_panel.gd）
- 版面：上方保留生活場景熱點（可收合成縮圖）；下方是**對話串**：客戶訊息在左（小頭像＋淺色泡泡＋情緒小標籤 emotion），顧問訊息在右（藍色泡泡）。
- 每則顧問訊息下方顯示**合規燈號**：綠「✓ 合規」、黃「▲ 話術瑕疵」、紅「× 違規」，展開可看 issues（引用原句 quote、規範 rule、改寫建議 suggestion）；coachTip 以小字顯示。
- 底部輸入區：「剩 N 輪」；5 個**建議問句**按鈕（已問過的停用），點擊送出 `{type:'talk', text, suggested: qid}`；加上自由輸入 `UI.text_input` 送出 `{type:'talk', text}`；「進入方案配置」按鈕（`to_plan`）。
- **本地即時雷達**：送出前在 client 用與伺服器相同的關鍵字規則（把規則版 ruleCompliance 的字詞清單搬一份到 gd）先亮燈並顯示「送出中」，伺服器結果回來後以伺服器為準。
- 等待 AI 時顯示「客戶思考中……」打字動畫（三個點）。
- 若 `session.twist` 存在，在客戶卡顯示一個情境標籤（title），hint 由客戶在第一則訊息中說出（若伺服器已處理則只顯示標籤）。

## 2. 介面手術
1. **本局任務卡**（game.gd `_quests_card`）：平常收合成一行「★ 任務 2/3 ▼」，點擊展開；面談或事件開啟時自動收合。
2. **客戶卡＋五力條**（session_panel `_build_header`）：桌面版壓成一列（頭像 64px、姓名、標籤、核心目標一句）；五力條改為一列 5 個迷你條，數值變化時浮出「信任 +8」之類的提示 1.5 秒。手機直向可兩列。
3. **面談不要整個蓋住棋盤**（desktop 與 tablet）：面談面板寬度約 65%，左側保留縮小的棋盤（或棋盤半透明可見）。手機版維持全螢幕分頁。
4. 步驟條已修正重複編號，不要再加回去。

## 3. 十年後的信
- result 步驟與結算報告（report.gd）顯示信件卡片：信紙風格（米白底、深色字、手寫感留白）、標題「十年後，[客戶名] 寄來的信」，依 outcome 用不同色調（thanks 暖金、regret 灰藍、mixed 中性）；顯示事件與缺口金額小結。
- 結算報告最多顯示 3 封，可左右切換。

## 完成後
在本檔最下方追加「完成紀錄」：改了哪些檔案、哪些版面已處理、已知限制。

## Claude 驗證第 1 批後的補充（請遵守）
- 伺服器規則版雷達在 `server/src/game/compliance.ts`：否定語境（「無法保證收益」「不能說穩賺」）不算違規。Godot 的 RegEx（PCRE2）不支援可變長度 lookbehind，請用 GDScript 先找到關鍵字，再檢查其前 0–4 個字是否為否定詞（不、無法、不能、沒辦法、不敢、不會，後面可接 說／講／承諾）。
- issues[].rule 由伺服器依 code 填入真實法規名稱（不含條號），client 直接顯示即可，不要自行編寫法規條文。
- 面談 result 步驟的信是**模板信**；遊戲結束時伺服器會用 AI 潤稿，結算報告 `final[].letters` 裡的才是最終版本。
- 完成後 Claude 會重新產生 `client/scenes/preview/states.json` 並截圖檢查所有預覽場景。

---

## 完成紀錄

### 1. 修改與新增之檔案清單
- **新增 `client/scripts/compliance.gd` (`@tool class_name Compliance`)**：
  - 完整實作客戶端即時合規雷達規則引擎，與伺服器 `server/src/game/compliance.ts` 保持同步。
  - 支援 `PROMISE_RETURN`（保證獲利/穩賺）、`FEAR_MONGERING`（恐嚇推銷/出事就完了）、`MISLEADING_COMPARISON`（不實比較/貶低同業）、`EARLY_PRESSURE`（時間逼單）、`INJECTION_ATTEMPT`（指令注入攻擊）。
  - 依照規定處理否定語境過濾（PCRE2 變長 lookbehind 替代方案：先搜尋關鍵詞，再向前檢查 0–4 字之否定詞「不、無法、不能、沒辦法、沒有人能、不敢、不會」，可接「說/講/承諾/給你/跟你說」）。
  - 對照真實法規名稱（`RULE_BY_CODE`）與具體改寫建議（`SUGGESTIONS`）。
- **修改 `client/scripts/ui/ui.gd`**：
  - 新增 `UI.letter_card(letter: Dictionary, client_name: String) -> PanelContainer` 信紙風格卡片元件：
    - 米白底、深色字、手寫感留白（邊距 14–20px）。
    - 依 `outcome` 分配暖金（thanks）、灰藍（regret）、中性（mixed）色調與對應印章標籤。
    - 顯示「十年後，[客戶名] 寄來的信」標題、經歷事件與財務缺口金額小結、信件全文與客戶敬上落款。
- **修改 `client/scripts/ui/session_panel.gd`**：
  - **對話式面談（discover 步驟）**：
    - 生活場景探索區支援收合縮圖與展開熱點切換（「收合為縮圖 ▲」／「展開場景熱點 ▼」），縮圖模式保留縮圖與已調查線索小結。
    - 對話串：開場由客戶吐露心聲（若有 `session.twist` 帶入 hint，否則使用 quote）；客戶訊息在左（36px 頭像＋情緒標籤＋淺色泡泡），顧問訊息在右（深藍色氣泡）。
    - 合規燈號：顧問訊息下方顯示綠「✓ 合規」、黃「▲ 話術瑕疵」、紅「× 違規」，支援點擊展開完整違規分析（原句、法規規範、改寫建議），並顯示教練短評（coachTip）。
    - 本地即時雷達：輸入或點擊發言時，在 client 先行以 `Compliance.check` 分析並顯示「送出中……」氣泡與合規燈號，待伺服器結果返回後以伺服器為準。
    - AI 等待動畫：等待 AI 時顯示客戶頭像與「客戶思考中……」打字動畫。
    - 底部輸入區：顯示「剩 N 輪」對話計數；5 個建議問句按鈕（已問過則停用，點擊送出 `{type:'talk', text, suggested: qid}`）；自由輸入框 `UI.text_input`（送出 `{type:'talk', text}`）；「進入方案配置 →」按鈕（`to_plan`）。
  - **客戶卡＋五力條**：
    - 桌面版壓成單一橫列：頭像 64px、姓名、標籤、動態情境變數 `［⚡ twist.title］`、核心目標一句話；右側整合 5 個迷你五力條（信任、洞察、適配、風險、合規）。
    - 手機直向壓為兩列：上列頭像與檔案，下列 5 個迷你五力條。
    - 數值變動浮動提示：五力指標數值變化時浮出「信任 +8」或「合規 -20」等提示 1.5 秒並淡出。
  - **十年後的信**：
    - result 步驟中，若結果含有 `letter` 則以信紙風格卡片展示模板信。
- **修改 `client/scripts/ui/game.gd`**：
  - **本局任務卡**：
    - 平常預設收合成單一行「★ 任務 N/M ▼」，點擊標題或按鈕展開／收合。
    - 面談（`is_sess`）或事件（`is_ev`）開啟時自動收合。
  - **面談面板版面調整**：
    - 桌面與平板（`not UI.is_phone()`）：面談面板寬度設定為 65%（`anchor_left = 0.35, anchor_right = 1.0`），左側 35% 保留縮小且半透明（`modulate.a = 0.75`）的棋盤，避免面談完全蓋住棋盤。
    - 手機版（`UI.is_phone()`）：維持全螢幕分頁操作。
- **修改 `client/scripts/ui/report.gd`**：
  - 結算報告中整合「十年後的信」信紙風格展示專區。
  - 支援展示最多 3 封來自 `final[].letters` 的最終版信件，並提供「◀ 上一封」／「下一封 ▶」左右切換翻閱。

### 2. 四種版面之處理情形
- **desktop (1280x720)**：
  - 客戶卡＋五力條壓成單列（64px 頭像、情境標籤、核心目標、5 個迷你條）。
  - 面談寬度 65%，左側 35% 保留可見棋盤。
  - 任務卡單行收合。
- **tablet_portrait (800x1280)**：
  - 面談面板維持 65% 寬度且棋盤可見。
  - 結算報告自適應排版。
- **phone_landscape (854x480)**：
  - 面談面板寬度 65% 且左側棋盤可見。
  - 任務卡單行收合。
- **phone_portrait (480x854)**：
  - 手機直向維持全螢幕分頁結構。
  - 客戶檔案壓為兩列（上列檔案、下列 5 個迷你條）。
  - 對話氣泡與輸入框依小螢幕縮放與自動換行。

### 3. 已知限制
- 訪客（未登入）環境下依規格不使用 AI，全面無縫走規則版對話模式，文案顯示為「規則版對話模式」與「規則版客戶」。
- 即時雷達在 client 端以預篩關鍵詞分析，伺服器返回後以 server 合併結果為準。

