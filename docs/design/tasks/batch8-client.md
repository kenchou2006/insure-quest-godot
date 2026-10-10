# Batch 8 (Godot Client): Warm Board-Game Restyle, Territory, Portraits, Claim Moments, Motion

Prerequisites: Batch 7 Completion Record (`territory`, event `kind: 'checkup'`, event `claim {...}`, `FinalRow.protection`) in `docs/design/tasks/batch7-server.md`; Batch 9 portrait contract (`res://assets/portraits/<clientId>.jpg`, may be missing → fallback). Background and decisions: `docs/design/round4-summary.md`.

Modify only `client/`. Hard rules from Batch 5 apply (`@tool`, editor guards, `UI.text_input`, no emoji, 4 layouts, no native-name overrides, no `Button.flat`). Do not use any terminal/command tool; Claude compiles and screenshots. Keep `client/scripts/automation.gd` working: buttons must keep their text, hotspot buttons keep meta `hotspot_index`.

## 1. Palette and component style (`ui.gd`)
- Replace colour constants: BG `#0d231e`, PANEL `#14352d`, PANEL_2 `#1a4239`, ACCENT `#00875a`, ACCENT_2 `#2ed59e`, GOLD `#e5a93c`, TEXT `#f4fbf7`, MUTED `#9ebdb3`, GOOD `#3ddc97`, OK `#e5a93c`, BAD `#e63946`, INFO `#8fd3c7`. Update `TILE_COLORS` to a harmonious warm set on the green base (keep each tile type distinct; audit stays red, start stays gold).
- `UI.box`: default radius 14, border = ACCENT at 25% alpha (1.5 px) when no border is given, softer shadow (alpha 0.35, size 6, offset (0,3)).
- `UI.button`: normal/hover/pressed/disabled styleboxes — 1 px lighter top highlight (use `border_width_top` with a lighter colour), hover lightens 8%, pressed darkens 12% and shifts content 2 px down (`content_margin_top` +2 / bottom −2), disabled desaturated 50%.
- Grep all `Color("#...")` literals in `client/scripts/ui/*.gd` that hard-code the old blue palette (`#0b1f2a`, `#13303f`, `#1b4052`, `#102b3a`, `#0d2432`, …) and switch them to the new constants or green equivalents, so no blue panels remain.
- Background of the game/board screen: subtle radial vignette (darker edges) drawn behind the board.

## 2. Board (`board.gd`, `game.gd`)
- Tiles as cards: rounded rect base (PANEL_2), a 6–8 px category colour band on the outer edge, larger symbol (`_draw_tile_symbol`, ~40% of tile), name label under it; corner tiles slightly larger symbol.
- Territory: tiles in `state.territory` draw the owner's player colour as a thick inner border plus a small circular client portrait (or initial) badge in the tile corner (load portrait textures once and cache).
- Tokens: draw as a coin/pawn with a 2 px gold rim and a drop shadow; keep the existing hop animation; on landing spawn a short expanding ring (0.35 s).
- Board centre (inner rect, when no overlay is open): show a compact "客戶簿" strip with up to 6 signed-client portraits of the local player and their satisfaction dot, instead of an empty dark area. Keep the dice button and banners working.

## 3. Interview and plan (`session_panel.gd`)
- Client portrait: use `res://assets/portraits/<id>.jpg` (fallback to scene thumbnail, then initial). Header portrait 88 px desktop / 64 px phone; client bubbles use a 40 px round portrait. Emotion tag stays next to the name.
- Coverage cards look like playing cards: category colour band at top, title bold, short description, selected = ACCENT_2 border 3 px + soft glow + small ✓ seal.
- Resource coins: show each coin as a round chip (●) in the resource colour inside a tray; ＋/－ keep their text for automation.

## 4. Motion and sound (`session_panel.gd`, `report.gd`, `game.gd`, `timeline_chart.gd`, `sound.gd`)
- Dice: the result number pops with a scale bounce (1.4 → 1.0, 0.25 s) and `Sound.play("dice_settle")`.
- Signing: when the result step shows `signed`, a gold 「已簽約」 stamp scales in from 1.6 with a slight rotation and the commission counts up from 0 (0.6 s). Not signed: grey 「再考慮」 stamp, no confetti.
- 90-day stress events: reveal rows one by one every 0.6 s (fade + slide), each held row plays `Sound.play("shield")`, broken rows `Sound.play("crack")`.
- Timeline chart: `TimelineChart` animates line drawing from year 0 to 10 over 1.5 s (draw only the first `progress` fraction of each polyline; event markers appear when the line reaches them); compact mode (report) draws instantly.
- New sounds synthesized in `sound.gd` like the existing ones: `dice_settle`, `shield`, `crack`, `stamp`, `claim`.
- Animations must run once per new state (not on every refresh); skip them in the editor and when `Engine.is_editor_hint()`.

## 5. Claim service and checkup events (`event_panel.gd`)
- For events with `claim`: show the client portrait (64 px), title 「理賠服務」, the event, and a three-segment bar (理賠 covered / 自付 outOfPocket) with amounts in 萬; held = green seal 「理賠完成」, broken = red 「保障缺口」. Play `claim` sound on held.
- For `kind == 'checkup'`: portrait + 「保單健檢」 + the lines from the server; gold accent.

## 6. Final report (`report.gd`)
- Score breakdown row under the grade: 能力 / 服務 / 守護 / 聲望 / 業績 with their weights (50/15/10/15/10) and values; 守護 uses `protection`.
- Certificate card uses the new palette (ivory text on deep green, gold seal); title stays 「公平待客面談完訓卡」, no company names or logos.

## 7. Title screen (`menu.gd`)
- Works with the new warm `title.jpg` (Batch 9): reduce the dark overlay so the morning light shows, keep text readable with a left-side gradient; title text colour GOLD for 「INSURE QUEST」 and TEXT for 「人生顧問局」.

## Finish
Append a "Completion Record": files changed, what was done per item, known limitations.

## Status before starting (Claude, 2026-10-10)
- Batch 7 done and verified (71/71 tests); field shapes in the Completion Record of `batch7-server.md`.
- Portraits for all 18 built-in clients exist at `client/assets/portraits/<id>.jpg` (1024×1024, sage-green background, centred bust). New `client/assets/title.jpg` (1344×768 warm morning living room; old one kept as `title.old.jpg`).
- Split: Part A = items 1, 2, 7 (`ui.gd`, `board.gd`, `game.gd`, `menu.gd`, `main.gd`); Part B = items 3, 4, 5, 6 (`session_panel.gd`, `event_panel.gd`, `report.gd`, `timeline_chart.gd`, `sound.gd`). Part B must not edit `ui.gd`; if it needs a shared helper (e.g. portrait texture loader), put it in a new `scripts/ui/portraits.gd` (`class_name Portraits`, static cache) which Part A may also use.

---

## Completion Record (Part A: Items 1, 2, 7)

實作完成日期：2026-10-10

### 1. 變更檔案清單
- `client/scripts/ui/portraits.gd`（新建）：共享靜態快取與載入器 `class_name Portraits`，優先讀取 `res://assets/portraits/<id>.jpg`（.webp, .png），退回至情境插畫或姓名字首；提供 `get_texture`、`has_portrait`、`create_avatar`、`clear_cache`。供 Part A 與 Part B 共同使用。
- `client/scripts/ui/ui.gd`：
  - 更新色票常數為溫暖綠色系（`BG #0d231e`, `PANEL #14352d`, `PANEL_2 #1a4239`, `ACCENT #00875a`, `ACCENT_2 #2ed59e`, `GOLD #e5a93c`, `TEXT #f4fbf7`, `MUTED #9ebdb3`, `GOOD #3ddc97`, `OK #e5a93c`, `BAD #e63946`, `INFO #8fd3c7`）。
  - 更新 `TILE_COLORS` 為基於綠底的和諧色調（audit 保留紅色 `#e63946`，start 保留金色 `#e5a93c`，client `#00875a`，life `#e07a5f`，market `#4ea8de`，training `#9b72cf`，referral `#2ed59e`，seminar `#8fd3c7`）。
  - `UI.box`：預設圓角 14，無傳入邊框時自動施加 1px ACCENT 25% alpha 描邊，柔和下陰影（alpha 0.35, size 6, offset (0, 3)）。
  - `UI.button` 與 `button_stylebox`：支援 normal（上緣 1px 高光）、hover（提亮 8% + 頂緣高光）、pressed（壓暗 12% + 內容下移 2px）、disabled（去飽和 50%）。`UI.make_theme` 與自訂按鈕全面套用。
  - 清理舊藍色票字面值（`#0e2633`, `#2d5a6e`, `#2d6a88`, `#3da8d5`, `#10232e` 等轉為溫暖綠色或新常數）。
- `client/scripts/ui/board.gd`：
  - 卡牌式棋盤格：圓角底座（`PANEL_2`）、外邊緣 7px 類別色條（依格子所處邊緣繪製外緣色條，角落格雙外緣）、符號放大至約 40%（`_draw_tile_symbol`），角落格符號放大 1.2 倍，地點文字標籤置於符號下方。
  - 客戶版圖（`state.territory`）：佔領格繪製顧問代表色粗描邊（3.5px），並於卡片角落疊加客戶圓形頭像徽章（透過 `Portraits.get_texture` 快取紋理，缺圖時顯示字首與金框）。
  - 顧問棋子：繪製為帶 2px 金色邊緣與地面陰影的硬幣籌碼（保留跳躍 hop 動態與落子擠壓變形）；落子與前進停點生成 0.35 秒擴散光環動態（`_landing_rings`）。
  - 棋盤中心指針與裝飾星芒更新為溫暖墨綠與金綠色調。
- `client/scripts/ui/game.gd`：
  - 棋盤背景新增柔和放射狀暗角暗色遮罩（`GradientTexture2D` FILL_RADIAL）。
  - 棋盤中心（無面談或事件彈窗時）：於中央控制項上方加入緊湊「客戶簿」展示條（`_client_strip`），展示本地玩家簽約的最多 6 位客戶圓形頭像，右下角附帶滿意度燈號點（綠/金/紅）。
  - 擲骰動態：結算彈跳為 1.4 → 1.0（0.25 秒），播放 `Sound.play("dice_settle")`。
  - 棋盤連動版圖：`_board.set_data` 傳入 `s.territory`。
  - 替換舊藍色面版與光暈字面值為新溫暖色調。
- `client/scripts/ui/menu.gd`：
  - 支援晨光溫暖主視覺 `title.jpg`：調降暗色遮罩（modulate 0.88），左側/底部施加線性漸層（`GradientTexture2D`）確保標題與副標高對比可讀。
  - 標題文字色：「INSURE QUEST」設為 `UI.GOLD`，「人生顧問局」設為 `UI.TEXT`。
- `client/scripts/main.gd`：
  - 背景紋理調色調整為溫和淡綠色調（`Color(0.7, 0.85, 0.75, 0.16)`）。

### 2. 已知限制與待後續驗證
- 嚴格遵守規範未碰觸 Part B 檔案（`session_panel.gd`、`event_panel.gd`、`report.gd`、`timeline_chart.gd`、`sound.gd`），由平行代理處理。
- `Portraits` 快取模組可供 Part B（頭像、理賠服務、健檢）直接使用。
- Claude 負責後續編譯與截圖驗證。

---

## Completion Record (Batch 8 - Part B: Items 3, 4, 5, 6)

實作完成日期：2026-10-10

### 1. 變更檔案清單
- `client/scripts/ui/portraits.gd`（共享新建）：提供 `@tool class_name Portraits` 靜態快取與載入器，支援 `get_texture`、`has_portrait`、`create_avatar`、`clear_cache`，優先載入 `res://assets/portraits/<id>.jpg`（.webp, .png），缺圖時依序退回至情境插畫或姓名字首。
- `client/scripts/ui/sound.gd`：
  - 新增程控合成音效生成器：`dice_settle`（雙衝擊清脆敲擊音）、`shield`（清亮三和弦防護音）、`crack`（低頻帶雜訊碎裂音）、`stamp`（重力打擊印章蓋印音）、`claim`（溫暖琶音理賠成功音）。
  - 各音效均使用 `AudioStreamWAV` 於記憶體中動態合成，支援網頁與原生平台無外掛音檔運作。
- `client/scripts/ui/timeline_chart.gd`：
  - 折線進度動態：新增 `anim_progress`，十年財務折線於正常模式下於 1.5 秒內平滑繪製（`_sample_polyline` 線段插值採樣），標註事件於折線到達對應年份時依序浮現。
  - 結算報告小尺寸（`compact`）及編輯器模式（`Engine.is_editor_hint()`）下即時繪製，避免不必要動畫開銷。
  - 圖表網格線與負債背景升級為和諧溫暖墨綠與深紅警示色。
- `client/scripts/ui/event_panel.gd`：
  - 理賠服務（`claim`）：展示客戶 64px 圓形頭像、事件標題、財務衝擊估算；實作三段式撥付對比長條圖（理賠撥付 covered / 自付負擔 outOfPocket / 剩餘），金額以「萬」顯示；印鑑標章（穩健承接為綠色「理賠完成」、擊穿為紅色「保障缺口」、部分為金色「部分理賠」）；理賠完成時觸發 `Sound.play("claim")`。
  - 保單健檢（`checkup`）：展示 64px 客戶頭像、金色飾條「保單健檢」、提示說明；若觸發轉介紹顯示綠色印章徽章「♥ 觸發轉介紹」。
  - 清除事件面板內部殘留之舊藍色色票，統一為 `UI.PANEL_2`、`UI.PANEL` 與新色常數。
- `client/scripts/ui/report.gd`：
  - 評級下方新增五大面向權重配比列：能力(50%) / 服務(15%) / 守護(10%) / 聲望(15%) / 業績(10%)，守護分對齊 `r.protection`。
  - 完訓卡（`_build_certificate_card`）全面套用溫暖紙質與墨綠色調：象牙白文字（`#fdfcf7`）、深墨綠底色（`#0d2821`）、金色邊框與評級火漆徽章，保持「公平待客面談完訓卡」無商業機構名稱規範。
  - 替換舊藍色票字面值為新溫暖色。
- `client/scripts/ui/session_panel.gd`：
  - 客戶頭像整合：頂部卡片支援 88px（桌面）/ 64px（手機直向）/ 48px（手機橫向），訪談對話串開場與客戶對話氣泡統一使用 40px 圓形頭像（`Portraits.get_texture` 快取）；保留情緒標籤。
  - 對話氣泡：顧問對話框改為柔和深底（`UI.PANEL_2.lightened(0.06)`，搭配精緻高光描邊，揮別刺眼藍底）；合規問題分析卡與說明面板全數更換為墨綠色系。
  - 方案配置卡牌化：各保障卡頂部繪製 6px 類別色條（`CARD_CATEGORY_COLORS`），選取時套用 3px `ACCENT_2` 亮綠邊框、柔和發光陰影與「✓」標記；按鈕文字保持原有標題與細節，相容 `automation.gd` 查詢。
  - 資源幣托盤：各類別（預備/保障/成長）以資源代表色（金/綠/藍）繪製籌碼盤（●），直向與橫向自適應顯示圓點；保持「＋」「－」按鈕文字以維持自動化測試穩定性。
  - 結果結算動態：簽約成功時金色印章「已簽約」以 1.6 倍縮放與微角度旋轉蓋下（0.28 秒），伴隨 `stamp` 音效與輕微震動回饋；業績數字於 0.6 秒內滾動累加；未簽約顯示灰色「再考慮」印章且不噴彩帶。
  - 90 天壓力預演：各項事件卡片以 0.6 秒間隔依序滑入淡出揭曉，穩健承接播放 `shield` 音效，風險擊穿播放 `crack` 音效。
  - 清理所有舊版青藍色碼（`#0b1f2a`, `#133647`, `#144d70`, `#206894`, `#102b3a`, `#0d202c`, `#0d202b`, `#173748`, `#2b3a42` 等）。

### 2. 已知限制與相容性
- 未碰觸任何 Part A 檔案（`ui.gd`、`board.gd`、`game.gd`、`menu.gd`、`main.gd`）。
- 嚴格遵守全自動化合約，按鈕文字與 `hotspot_index` 中繼資料完全保留。
- 所有動畫均設有 `Engine.is_editor_hint()` 與重繪保護，避免非運行時或重覆觸發造成效能損耗。
- 交由 Claude 負責編譯與截圖驗證。


### Claude verification (2026-10-10)
Godot check-only (no parse errors this time), web build, full demo-recorder run (menu → interview → result) and frame review.
- Fixed: floating turn-actor badge on your own turn (hidden when the gold banner shows); centre client-book strip hidden until the first signing and moved below the dice button; title overlay lightened (bottom gradient only, no image dimming); grade badge kept circular; complaint-letter quote now cut at the first clause (≤ 24 chars) instead of 15 characters mid-word.
- Package size: new images had lossless import → pck 19.2 MB. All illustration imports switched to lossy WebP 0.8 and portraits capped at 512 px → pck 5.6 MB. Old title moved out of `client/` to `docs/design/archive/title-rainy-night.jpg` (it was being exported).
- Verified on screen: green palette, card-style tiles with colour bands, territory badge (portrait + owner border) after signing, coin chips, coloured coverage cards, portraits in the dialogue, red banner + grade cap, timeline chart, complaint letter.
- Not verified on screen: claim-service and checkup event panels (need a later life/own-territory tile), final report score breakdown and certificate (needs a full game), sounds.
