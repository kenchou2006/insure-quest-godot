# 客戶胸像資源庫 (Client Portraits)

本目錄存放《INSURE QUEST 人生顧問局》18 位內建客戶的半身胸像插畫 (`.jpg`)。

## 檔案命名與載入約定 (Client Usage Contract)
- **路徑格式**：`res://assets/portraits/<clientId>.jpg`
- **使用場景**：
  - 面談面板 (`session_panel.gd`) 客戶頭像（72–96px）
  - 棋盤格上簽約版圖徽章與客戶小頭像
  - 人生事件／理賠服務時刻彈窗 (`claim_dialog.gd`)
  - 季度結算與終局計分頁面
- **Fallback 規則**：若圖片不存在（例如自訂動態生成客戶），客戶端自動回退至原有的名字首字字首頭像。

## 視覺風格規範 (Visual Consistency)
- **視角**：胸像 (bust portrait, head and shoulders)，正面朝向鏡頭，溫暖自然神情。
- **背景**：純色柔焦漸層鼠尾草綠 (muted sage green)，無文字、無水印、無雜亂背景。
- **畫風**：現代日本動畫電影風格、乾淨線條、柔和溫暖光影。

## 18 位內建客戶清單
1. `yuqing.jpg` - 林雨晴（29 歲，自由接案插畫家，單身租屋）
2. `boting.jpg` - 陳柏廷（36 歲，半導體工程師／新手爸爸）
3. `wanting.jpg` - 蘇婉婷（43 歲，獨立咖啡店老闆／單親家長）
4. `ziyuan.jpg` - 周子安（25 歲，研究生／接案攝影師，非二元）
5. `zhiming.jpg` - 黃志明（58 歲，計程車司機／家庭照顧者）
6. `junhao.jpg` - 王俊豪（32 歲，外送平台騎手）
7. `meiling.jpg` - 張美玲（36 歲，公司行政助理／單親家長）
8. `jiahao.jpg` - 劉家豪（31 歲，軟體工程師／新手爸爸）
9. `shufen.jpg` - 吳淑芬（45 歲，會計主管／三明治世代）
10. `wenjie.jpg` - 鄭文傑（58 歲，國中教師／即將退休）
11. `yiting.jpg` - 蔡依婷（24 歲，行銷專員／社會新鮮人）
12. `zhiwei.jpg` - 林志偉（40 歲，小吃店老闆／自營餐飲）
13. `peishan.jpg` - 何佩珊（34 歲，醫院護理師／輪班高壓）
14. `chengen.jpg` - 李承恩（29 歲，科技公司資深工程師）
15. `jiaming.jpg` - 許家銘（38 歲，設計公司合夥人／頂客族）
16. `guohua.jpg` - 楊國華（50 歲，計程車司機／高風險長工時）
17. `yijun.jpg` - 陳怡君（42 歲，外商業務經理／高房貸）
18. `yixiang.jpg` - 高奕翔（27 歲，健身教練／自由接課）

## 生成工具
由 `server/tools/generate-portraits.mjs` 透過本機 Workers AI FLUX Schnell (`GET /api/dev/gen-img`) 批次產出。
