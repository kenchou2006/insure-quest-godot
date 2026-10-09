# 第 3 批：重新生成 meiling、yixiang、peishan 三張場景圖

問題：這三張圖裡沒有線索物件，玩家無法靠觀察找到。
- meiling（張美玲，單親行政助理）：缺「教育基金存摺」；班表也不明顯。
- yixiang（高奕翔，健身教練）：缺「膝蓋護具」，學員預約表、工作室估價也不清楚。
- peishan（何佩珊，醫院護理師）：缺「夜班表」，護腰也不明顯。
三張圖都要能清楚看見 3 個線索物件＋1 個干擾物（現有標題見 `client/assets/clients/hotspots.json` 與 `server/src/game/hotspots-extra.json`；線索標題不要改，因為客戶資料與 facts 綁定）。

## 你要做的（只編輯檔案，不要執行指令）
1. **本機限定生圖端點**：在 `server/src/index.ts` 加 `GET /api/dev/gen-img?prompt=...`，只在 `env.DEV_LOGIN === '1'` 且請求網域是 `localhost` 或 `127.0.0.1` 時存在，否則回 404（正式環境絕對不能變成公開的生圖 API）。用 Workers AI `@cf/black-forest-labs/flux-1-schnell`（`env.AI.run`，回傳 base64 圖片，`steps: 8`），回傳 `image/jpeg`。
2. **改寫 `server/tools/generate-all-scenes.mjs`**：
   - 呼叫 `/api/dev/gen-img`；支援 `node tools/generate-all-scenes.mjs meiling yixiang peishan` 只生成指定的客戶；輸出寫到 `client/assets/clients/<id>.jpg`，舊檔先備份成 `<id>.old.jpg`。注意 cwd 是 server/，路徑要正確。
   - 重寫這三位的英文 prompt：沿用原本的動漫背景風格；**每個線索物件要大、居中、彼此分開、不重疊**，分布在畫面不同區域（例如左下、中央、右側）；明確描述外觀（例：bank passbook with blue cover lying open on the desk；black knee brace sleeve；night shift roster printed schedule pinned on a corkboard）；**不要畫出任何可讀文字**（no text, no letters, no words，避免 AI 亂碼字）；畫面不要有人物遮住物件。
3. 在本檔最下方寫「完成紀錄」，包含每張圖預期每個物件會出現在畫面哪個區域。

完成後 Claude 會執行生成，再請你看圖標註熱點座標。

## 完成紀錄

### 1. 本機限定生圖端點實作（`server/src/index.ts`）
- 路由：`GET /api/dev/gen-img?prompt=...`
- 安全防護：僅在 `env.DEV_LOGIN === '1'` 且請求主機名稱為 `localhost` 或 `127.0.0.1` 時允許，否則一律回應 HTTP 404（避免正式環境暴露公開生圖端點）。
- 模型：使用 Workers AI `@cf/black-forest-labs/flux-1-schnell`（`steps: 8`）。
- 格式：將 base64 轉換為二進位 buffer，回傳 `Content-Type: image/jpeg`。

### 2. 批量生圖工具改寫（`server/tools/generate-all-scenes.mjs`）
- API 端點更新為呼叫 `/api/dev/gen-img`。
- 支援命令列指定客戶：`node tools/generate-all-scenes.mjs meiling yixiang peishan`，若無參數則預設處理全部客戶。
- 路徑定位：以腳本目錄定位專案根目錄，精確輸出至 `client/assets/clients/<id>.jpg`（不論從專案根目錄或 `server/` 執行皆能正確指向）。
- 舊檔備份：覆寫前自動將原圖備份為 `client/assets/clients/<id>.old.jpg`。
- 提示詞優化：沿用新海誠動漫風格，嚴格設定「無人物遮擋、物件大且彼此分開不重疊、各自分布於不同象限、無可讀文字（no text, no letters, no words）」。

### 3. 三張場景圖之物件預期畫面分佈區域

| 客戶 | 類別 | 物件標題 | 提示詞描述重點 | 預期畫面區域 |
| :--- | :--- | :--- | :--- | :--- |
| **meiling**<br>（張美玲） | 線索 1 | **教育基金存摺** | 深藍色封面展開的銀行存摺，平放顯示表格格線 | **左下方桌面（Bottom-Left Foreground）** |
| | 線索 2 | **女兒的作業簿** | 封面有彩色卡通插圖與塗鴉的國小作業簿，翻開平放 | **中央前景桌面（Center Foreground）** |
| | 線索 3 | **兩份工作的班表** | 印有每週雙工作輪班時段與彩色班空格子的排班表，釘在牆上 | **上方軟木塞牆／告示板（Top Corkboard Wall）** |
| | 干擾物 | **辦公室文具盒** | 多格辦公桌面文具收納盒，插有彩色筆、螢光筆與剪刀 | **右側桌面（Right Desk Area）** |
| **yixiang**<br>（高奕翔） | 線索 1 | **膝蓋護具** | 黑色專業運動加壓護膝，具矽膠髕骨環與彈性綁帶，平鋪展開 | **中央前景桌面（Center Foreground）** |
| | 線索 2 | **學員預約表** | 金屬寫字夾板夾著印有一對一學員預約時段表的每週課表 | **右側桌面（Right Desk Area）** |
| | 線索 3 | **工作室估價** | 健身工作室改裝裝潢報價藍圖與設備採購估價單，釘在牆上 | **上方軟木塞牆／告示板（Top Corkboard Wall）** |
| | 干擾物 | **乳清蛋白搖搖杯** | 半透明高蛋白運動搖搖杯，配有螢光掀蓋，直立擺放 | **左側桌面（Left Desk Area）** |
| **peishan**<br>（何佩珊） | 線索 1 | **護腰** | 人體工學黑灰色透氣醫療護腰帶，寬版魔鬼氈與支撐條，掛在椅背 | **左側辦公椅背（Left Chair Backrest）** |
| | 線索 2 | **留學簡章** | 翻開的海外護理研究所留學大學簡章手冊，印有校園照片與世界地圖 | **中央前景桌面（Center Foreground）** |
| | 線索 3 | **夜班表** | 大張白色醫院每月夜班輪值排班表，具清晰日曆表格與班別圖示 | **上方軟木塞牆／告示板（Top Corkboard Wall）** |
| | 干擾物 | **護理識別證** | 藍色護理師掛繩與透明壓克力職員識別名牌，旁有捲起的聽診器 | **右側桌面（Right Desk Area）** |
