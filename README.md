# INSURE QUEST 人生顧問局（Godot 網頁版）

法國巴黎人壽 Cardif InsurHack 題目 1-1「保險大富翁」：以大富翁機制訓練保險顧問「依需求銷售、合規溝通」的多人網頁遊戲。
支援 2–4 人連線、單人對電腦顧問、AI 客戶與 AI 教練，可安裝為 PWA。

## 架構：一個 Worker、一次部署

```
瀏覽器（Godot 網頁版／PWA）
   │  同一個網域
   ▼
Cloudflare Worker  insure-quest
   ├─ 靜態檔（Workers Static Assets）：../web 的 Godot 匯出檔
   ├─ /api/rooms…        建房、WebSocket ──▶ Room Durable Object（每個房間一個，伺服器權威遊戲邏輯、電腦顧問）
   ├─ /api/auth/*        Google 登入（OAuth，HttpOnly Cookie）─┐
   ├─ /api/me /api/records /api/profile /api/learners ─────────┴▶ Records Durable Object（SQLite：帳號、工作階段、每日 AI 額度、培訓紀錄）
   └─ Workers AI（預設，env.AI）／Claude（選用）：AI 客戶、AI 評分、教練提示與回饋；每個帳號每日 100 次，超過或訪客改用規則版
```

- **不使用 Cloudflare Pages。** Pages 無法部署 Durable Object，若用 Pages 必須另外部署一個 Worker 放 DO，變成兩次部署、兩個網域（或服務繫結）。Workers Static Assets 讓網頁與 API／DO 在同一個 Worker 一次部署，也是 Cloudflare 目前建議全端專案使用的方式。
- **不需要拆分儲存庫。** 前端（client/）與後端（server/）共用遊戲協定，放在同一個 monorepo 一起改版最安全；部署也只有一個指令。
- **不需要額外的 API 網域。** 網頁與 `/api/*` 同源，沒有 CORS 問題（桌面版開發時才會跨來源，伺服器已允許）。

## 目錄

```
client/        Godot 4.7 專案（UI 全部以程式碼建構，scripts/ui/*.gd）
  fonts-src/   完整字型原檔（.gdignore，不會被匯出）
server/        Cloudflare Worker（TypeScript）
  src/game/    遊戲規則、客戶資料、電腦顧問（純邏輯，有單元測試）
  src/room.ts  Room Durable Object　src/records.ts  Records Durable Object　src/ai.ts  AI 服務
  tools/       build-web.sh、pack-web.mjs、subset-font.py
web/           Godot 網頁匯出結果（建置產物，不納入版本控制）
```

## 需求

- Node.js 22+、npm
- Godot 4.7.2（含 Web 匯出範本：編輯器 → 管理匯出範本）
- （選用）`pip install fonttools`：重新產生字型子集時才需要

## 本機開發

```bash
cd server
npm install
npm run build:web     # 匯出 Godot 網頁版到 ../web（並壓縮 wasm、修正 PWA 快取清單、產生 _headers）
npm run dev           # http://127.0.0.1:8787（--env local：AI 用模擬、不需登入 Cloudflare）
npm run dev:remote-ai # 需先 npx wrangler login，連線真正的 Workers AI
```

- 只改伺服器程式：`npm run dev` 會自動重新載入。改了 client 再跑一次 `npm run build:web` 即可，不必重啟伺服器。
- 桌面版：直接用 Godot 編輯器執行 client/，主選單可設定伺服器位址（預設 `http://127.0.0.1:8787`）。
- 本機設定：把 `server/.dev.vars.example` 複製成 `.dev.vars`（測試登入、AI 供應者、Google 憑證）。
- 測試：`npm run check`（型別檢查＋單元測試，含平衡模擬）。

## 部署（一次完成）

```bash
cd server
npx wrangler login                          # 第一次
npx wrangler secret put GOOGLE_CLIENT_ID     # Google 登入（選用；不設定則只有訪客模式）
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put ANTHROPIC_API_KEY   # 選用；AI_PROVIDER=claude 時才需要 AI
npm run deploy                              # = build:web + wrangler deploy
```

設定集中在 `server/wrangler.jsonc`：靜態檔目錄、`/api/*` 先交給 Worker、Workers AI 繫結、兩個 Durable Object 繫結與 SQLite 遷移（`v1`）、AI／額度／講師變數，以及不含 AI 繫結的 `local` 開發環境。帳號資料放在既有的 Records Durable Object，不需要另外建立 D1，部署仍是一次完成。
新增或改名 Durable Object 類別時，必須在 `migrations` 加一個新的 tag，不要修改既有的 `v1`。

## 帳號、AI 額度與培訓紀錄

- **登入**：Google OAuth 授權碼流程全部在 Worker 完成（`src/auth.ts`），工作階段存在 HttpOnly Cookie；Godot 的 HTTP 與 WebSocket 同源自動帶上，前端不接觸 token。跨來源的 WebSocket 不會帶入身分。
- **AI 額度**：每次實際呼叫模型扣 1 次（`AI_DAILY_LIMIT`，預設 100，台北時間午夜重置）；模型失敗會退還。訪客、電腦顧問、額度用完時一律改用規則版，遊戲照常進行。
- **AI 供應者**（`AI_PROVIDER`）：`workers-ai`（預設，模型 `WORKERS_AI_MODEL`=`@cf/qwen/qwen3.8-27b`）｜`claude`（需 `ANTHROPIC_API_KEY`）｜`mock`（本機模擬）｜`rules`。
- **培訓紀錄只保存登入者**，且只能看自己的；`TRAINER_EMAILS` 內的講師可查看全部學員（`/api/records?scope=all`、`/api/learners`、`/api/profile?user=`）。
- **保存什麼**：除了分數，每場面談都保存完整決策軌跡（線索、提問順序、自由提問、配置與檢討、異議回應、壓力結果、是否用提示），並標記弱點標籤。學習檔案（`/api/profile`）由此彙整出：分數與五力趨勢、最常犯的錯誤與改進建議、客戶圖鑑（18 位客戶的服務次數與最佳評級）、徽章。

### 設定 Google 登入
1. Google Cloud Console → API 和服務 → 憑證 → 建立 OAuth 用戶端 ID（網頁應用程式）。
2. 已授權的重新導向 URI：`https://<你的網域>/api/auth/google/callback`（本機測試加 `http://localhost:8787/api/auth/google/callback`）。
3. `npx wrangler secret put GOOGLE_CLIENT_ID`、`npx wrangler secret put GOOGLE_CLIENT_SECRET`；本機則寫在 `server/.dev.vars`。
4. 未設定時登入按鈕自動隱藏，遊戲以訪客模式運作。本機可設 `DEV_LOGIN=1` 使用測試登入（僅限 localhost）。

## 遊戲性補強（對照原型）

| 項目 | 說明 |
|---|---|
| 場景熱點找線索 | 原型五位有插圖的客戶，恢復在插圖上找 3 個線索＋1 個干擾物 |
| 專屬結局與「沒有規劃」對比 | 面談結果顯示依壓力預演強／中／弱的結局，並對照沒有規劃的後果 |
| 旁觀者預測 | 別人面談時，其他玩家預測評級，猜中聲望 +2，解決多人等待 |
| 終局大事件 | 最後一回合開始時「全球金融海嘯」同時考驗所有顧問的客戶 |
| 教練提示 | 每場面談一次，扣聲望 2，只給方向不給答案 |
| 圖文遊戲說明 | 沿用原型的 5 張說明圖 |

## 網頁版的幾個注意事項

| 問題 | 處理方式 |
|---|---|
| Godot 的 `index.wasm` 約 38 MiB，超過 Workers 單檔 25 MiB 上限 | `pack-web.mjs` 壓成 `index.wasm.gz`（約 10 MiB），並在 `index.html` 注入 fetch shim 於瀏覽器端解壓縮 |
| `wrangler dev` 監看 `web/` 時看到未壓縮的 wasm 會中止 | `build-web.sh` 先匯出到暫存資料夾，壓縮完成才換進 `web/` |
| 瀏覽器已自動解壓 gzip 回應，Godot 再解一次會失敗 | `net.gd` 的 HTTPRequest 設 `accept_gzip = false` |
| Godot 網頁畫布收不到中文輸入法的文字 | `web_text.gd` 在輸入框上覆蓋真正的 HTML `<input>` |
| 字型 12 MB | `subset-font.py` 子集化為 Big5 常用字＋專案用字（約 3 MB），保留字重可變軸 |
| 字型沒有 emoji | 介面只使用 CJK 字與 ✓ × ★ ● ◆ ※ 等符號 |
| 圖片佔用下載量 | 匯入設定改為有損 WebP（品質 0.8），pck 由 14.7 MB 降到 3.2 MB |

## 支援的裝置與版面

同一套 UI 依視窗的 CSS 尺寸切換版型（`main.gd` 設定 `content_scale_size`，`UI.layout_profile` 記錄目前版型）：

| 版型 | 條件 | 基準解析度 | 版面 |
|---|---|---|---|
| desktop | 橫向、CSS 高 ≥ 500 | 1280×720 | 左棋盤＋右資訊欄 |
| phone_landscape | 橫向、CSS 高 < 500 | 960×540 | 同上，資訊欄縮窄 |
| tablet_portrait | 直向、CSS 寬 ≥ 600 | 720×1280 | 上下堆疊 |
| phone_portrait | 直向、CSS 寬 < 600 | 480×854 | 底部分頁（棋盤／面談事件／狀態），輪到自己時自動切頁 |

## PWA

Godot 匯出時已啟用 PWA：產生 manifest、圖示、離線頁與 service worker，可「加入主畫面」以全螢幕開啟，支援直向與橫向。
`pack-web.mjs` 會把 service worker 的快取清單改成實際下載的 `index.wasm.gz`，第二次開啟時遊戲引擎從快取載入。
遊戲需要連線到伺服器才能進行（多人與 AI 都在伺服器端）；離線時會顯示離線頁。
發布新版後，已安裝的使用者會先開到快取的舊版，主選單會出現「有新版本，點此更新」；開發時也一樣（或在 DevTools 勾選 Update on reload）。

## 授權與素材

- 字型：Noto Sans TC（SIL Open Font License）。
- 客戶情境與數值僅供教育訓練模擬；保障卡為功能概念，不對應任何實際保險商品，亦不構成保險或投資建議。
