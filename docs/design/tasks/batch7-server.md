# Batch 7 (Server): Client Territory, Claim Service Moments, Protection Score

Background: `docs/design/round4-summary.md`. Modify only `server/` and `server/test/`. Same hard rules as Batch 4 (rules engine decides all numbers, additive protocol, local-room parity, Traditional Chinese copy, no emoji). Do not use any terminal/command tool; Claude runs `npm run check`.

## 1. Client territory on the board
- Add `GameState.territory: Record<number, { playerId: string; clientId: string; clientName: string }>` (tile index → owner). When a session ends **signed**, record the tile index where that session started (the tile the player stood on; for referral/life-started sessions use the player's current tile only if it is a `client` tile, otherwise skip). One owner per tile; a later signing on the same tile replaces it.
- When a player ends a move on a tile they own: instead of drawing a new client, trigger a short event `kind: 'checkup'` 「保單健檢｜{clientName}」: +2 reputation, client satisfaction +5, and if satisfaction ≥ 75 a 40% chance (seeded rng) to start a referral session (`startSession(..., referral=true)`). If the client already left the book, clear the tile and behave as a normal client tile.
- Opponents landing on someone else's territory: normal client tile behaviour (no penalty). Expose `territory` in `publicView`.
- Bots: the senior bot logic must still work (they will trigger checkups too). Keep the existing balance test green.

## 2. Claim service moments (life tile hitting a signed client)
In `case 'life'` (`game.ts`), where a stress event hits a book client, add structured data to the event (keep the existing `lines`):
`claim: { clientId, clientName, event: se.title, tag: se.tag, result: 'held'|'partial'|'broken', loss, covered, outOfPocket }` in NT$, computed with the same formulas as `finance.ts` (loss = need × 0.5 × monthly income; covered = insurance part of the defense from protect coins + matching cards; reuse/extract a helper from `finance.ts` instead of duplicating). Title becomes 「理賠服務｜{clientName}」 and add one line: held → 「理賠 {covered 萬} 萬已撥付，{clientName}：『還好當初有聽你的。』」, partial → 「理賠 {covered} 萬，仍需自付 {outOfPocket} 萬」, broken → 「保障缺口：{clientName} 自付 {outOfPocket} 萬」. Amounts in 萬 with one decimal when < 10.

## 3. Protection score in the final ranking
- Track per book entry the stress results the client actually experienced: in-interview 90-day rehearsal (`st.events`) and later life-tile hits. Store counts on `BookEntry`: `held`, `partial`, `broken` (optional numbers).
- `scorePlayer`: `protection` = average over book entries of `(held + 0.5 × partial) / max(1, held + partial + broken) × 100`; entries with `violation` count as 0. Score weights become `0.5 skill + 0.15 service + 0.10 protection + 0.15 reputation + 0.10 commission`. Add `protection` to `FinalRow`.
- Update tests: existing expectations that depend on the old weights; add a test that a player who signs more clients with poor plans does not outrank a careful player (construct two players directly).

## Finish
Append a "Completion Record" with new fields (exact shapes) for Batch 8.

---

## Completion Record (Batch 7 - Server)

實作完成日期：2026-10-10

### 1. 變更檔案清單
- `server/src/game/types.ts`：擴充 `BookEntry`（`held`, `partial`, `broken`）、`SessionState`（`tileIndex`）、`PendingEvent`（`kind: 'checkup'`, `checkup`, `claim`）、`FinalRow`（`protection`）、`GameState`（`territory`）。
- `server/src/game/finance.ts`：抽取純函式 `calculateClaim(client, alloc, cards, ev)`（計算 NT$ 之 loss, covered, outOfPocket）與 `formatWan(ntd)`（萬單位格式化，< 10 帶一位小數），並於 `simulateTimeline` 中重用。
- `server/src/game/profile.ts`：`RecordRow.data` 支援 `protection?: number`。
- `server/src/game/game.ts`：
  - `createGame` 初始化 `territory: {}`。
  - `startSession` 記錄面談起點格子 `tileIndex: p.pos`。
  - `finishSession` 成交時記錄客戶版圖 `territory[tileIndex]`（僅 client 格，referral/life 格不佔領；後簽約者覆蓋舊版圖）；並將壓力測試結果計入 `BookEntry`（`held`, `partial`, `broken`）。
  - `resolveTile`：
    - `case 'client'`：停在自己版圖格觸發 `kind: 'checkup'` 「保單健檢｜{clientName}」（聲望 +2，滿意度 +5）；若滿意度 ≥ 75 且 40% 機率判定轉介，於繼續時無縫開啟轉介紹面談；若客戶已解約則清除版圖並作一般客戶格；對手停在版圖格維持一般客戶格無懲罰。
    - `case 'life'`：人生事件擊中已簽約客戶改以「理賠服務｜{clientName}」呈現，加入結構化 `claim` 資料、首行理賠感謝/自付說明文字，並累計該客戶之壓力承接次數。
  - `applyActionInner`：`continue` 事件支援健檢轉介順利進入 `turnStage: 'session'`。
  - `scorePlayer`：實作 `protection` 守護分公式（每位客戶 `(held + 0.5 * partial) / max(1, held + partial + broken) * 100` 之平均，違規紅燈案件為 0），新加權比例為 `0.5 skill + 0.15 service + 0.10 protection + 0.15 reputation + 0.10 commission`，回傳加入 `protection`。
  - `publicView`：公開暴露 `territory`、`players[].book[].{held, partial, broken}`，以及 `event.claim`。
- `server/test/game.test.ts`：新增 3 組嚴密單元測試，涵蓋版圖佔領/健檢/轉介/解約清理、理賠服務結構化資料與格式化、守護分計算/紅燈零分/加權評分比較（證明隨意銷售多位客戶者總分無法超越用心規劃顧問）。

### 2. Batch 8（Client / Godot）新資料欄位與規格對照

#### A. 客戶版圖 (`publicView.territory`)
- 型別：`Record<number, { playerId: string; clientId: string; clientName: string }>`
- 說明：Key 為格子索引（`0..23`）。當格子被簽約顧問佔領時存在。
- Client 端介面表現建議：在棋盤對應客戶格上方疊加顧問代表色小徽章與客戶頭像。

#### B. 保單健檢事件 (`publicView.event` with `kind: 'checkup'`)
- `kind`: `'checkup'`
- `title`: `「保單健檢｜{clientName}」`
- `checkup`:
  ```ts
  {
    clientId: string;
    clientName: string;
    referral?: boolean; // 若為 true，玩家按下「繼續」將直接觸發轉介紹面談
  }
  ```
- `lines`: 包含滿意度 +5、顧問聲望 +2 以及轉介紹相關回饋。

#### C. 理賠服務時刻 (`publicView.event` with `kind: 'life'`)
- `kind`: `'life'`
- `title`: `「理賠服務｜{clientName}」`
- `claim`:
  ```ts
  {
    clientId: string;
    clientName: string;
    event: string;              // 壓力事件標題
    tag: string;                // 標籤（如：醫療、收入中斷等）
    result: 'held' | 'partial' | 'broken';
    loss: number;               // 總損失金額（NT$）
    covered: number;            // 保險理賠金額（NT$）
    outOfPocket: number;        // 自付額（NT$）
  }
  ```
- `lines`: 第一行為理賠服務摘要文字（以「萬」為單位，< 10 萬帶一位小數）：
  - 承接 (`held`): `「理賠 {covered} 萬已撥付，{clientName}：『還好當初有聽你的。』」`
  - 部分承接 (`partial`): `「理賠 {covered} 萬，仍需自付 {outOfPocket} 萬」`
  - 擊穿 (`broken`): `「保障缺口：{clientName} 自付 {outOfPocket} 萬」`

#### D. 客戶簿承接次數追蹤 (`publicView.players[].book[]`)
- 每位客戶物件新增：
  - `held`: `number`（承接次數）
  - `partial`: `number`（部分承接次數）
  - `broken`: `number`（擊穿次數）

#### E. 終局客戶守護分 (`publicView.final[]`)
- `FinalRow` 新增：
  - `protection`: `number`（0–100）
- 總分權重公式：
  `Math.round(0.50 * skillScore + 0.15 * service + 0.10 * protection + 0.15 * reputation + 0.10 * Math.min(100, commission))`

