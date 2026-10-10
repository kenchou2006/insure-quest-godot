# Batch 15: Instant Question Check-off, Wait-for-AI States, Certificate Export Layout

Touches `server/` and `client/`. Hard rules from earlier batches apply (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working: buttons keep their text). Do not run terminal commands; Claude compiles, runs `npm test`, builds the web export and screenshots.

## 1. Suggested questions grey out as soon as they are sent

`client/scripts/ui/session_panel.gd` 「顧問發言與提問」 (~L1110-1180): a suggested question button only turns into the greyed 「✓ …」 state when the server's `asked` list contains it, i.e. after the coach tip finished (Batch 12 made the answer arrive earlier, but the check-off still waits for the whole exchange). Mark it as asked immediately when the advisor sends it: treat `_pending_talk.suggested` and `_queued_talk.suggested` as asked when computing `was_asked` (disabled + ✓ prefix + greyed style). If the send fails (server error clears `_pending_talk` / `_queued_talk`), the button returns to normal. Keep the button text otherwise identical (automation matches on it; the ✓ prefix is already used for asked items today, so it is fine).

## 2. Wait for AI instead of showing the rule-based text first

Today several AI features first show rule-based placeholder text and then swap in the AI text, so players read one comment and then see it replaced. Example: final report coach comment — `server/src/game/game.ts` ~L944 builds `FinalRow` with `coach: fallbackTip(p)` and `enrichCoach` (~L960) later overwrites it with AI text; the client shows the fallback immediately, also on the certificate.

Wanted, for every AI-generated text shown to players:
- When AI will be used for this player (logged-in, AI enabled, quota available — the same condition the server already uses to choose AI vs rules), the server marks the field pending (e.g. `coachPending: true` on the FinalRow, or `null` text + a `pending` flag) instead of sending the fallback, and only fills it when the AI result arrives. On AI failure / timeout, fill it with the rule-based fallback and clear pending (never leave it pending forever: use the existing timeouts, add one if missing).
- Guests / bots / rules mode / quota exhausted: send the rule-based text immediately as today (no waiting state).
- Client shows a clear waiting state where the text will appear: e.g. 「AI 教練評語產生中……」 with a subtle animated dot/pulse (no emoji), then replaces it in place when it arrives. Disable 「儲存圖片」 on the certificate while its coach comment is pending (button text unchanged; show a small 「等待 AI 評語…」 note next to it).
- Audit and apply the same pattern to all other AI text in the game: settlement coach comment / debrief, ten-years-later letters, AI hint (「求助教練」 already has `_waiting_hint` — check it does not show a fallback first), seminar tile coach tip (`game.ts` ~L350), objection grading feedback, market news, AI-generated clients. For each, list in the Completion Record whether it already waited correctly or what you changed.
- Server tests: a FinalRow with AI enabled starts pending and ends with the AI text; with AI failing it ends with the fallback and not pending; guest gets fallback immediately.

## 3. Certificate PNG export: redesign the layout (too much empty space)

The current export (see `docs/design/tasks/fix-certificate-download.md` and the uncommitted changes in `client/scripts/ui/report.gd` `_download_certificate()` / `_build_certificate_card()`, which already render the card in a 1200x675 SubViewport) now contains everything, but the layout is mostly empty: header + name + 5 bars squeezed into the top-left third, the grade seal and the one-line coach comment floating in the middle right, and the whole bottom half empty.

Redesign the export card (export mode only; the on-screen card may stay as is unless the same improvement is cheap) as a balanced 1200x675 certificate:
- Header band across the full width: 「公平待客面談完訓卡」 large (gold) with 「專業顧問合格證明」 subtitle; small game name 「INSURE QUEST 人生顧問局」 on the right. No company names or logos.
- Body in two columns filling the height: left ~55% = advisor name (large), date, 服務客戶 N 位 + stamps (零違規 / red-light), then the five-power bars with labels and values, bars sized to fill the column width with comfortable row spacing (~44-52 px per row); right ~45% = large grade seal (~180-220 px) centred, total score under it, and the coach comment in a quote box below it, wrapped over several lines (fixed `custom_minimum_size.x`), font ~18-20 px.
- Footer strip: thin gold rule + small text, e.g. 「完訓日期 2026-10-10 · 本證明由 INSURE QUEST 訓練紀錄自動產生」.
- Consistent outer padding (~40 px), no large empty areas; everything inside the gold rounded border; transparent or dark-green outside the border as in the current implementation.
- Export only after the AI coach comment has arrived (item 2).
- Keep: button text 「儲存圖片」, filename, web-only guard, 2-frame layout wait before capture.

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### Item 1: Suggested questions grey out as soon as they are sent
- Modified `client/scripts/ui/session_panel.gd`:
  - Included `_pending_talk.get("suggested", "")` and `_queued_talk.get("suggested", "")` in calculating `was_asked`.
  - When the advisor sends or queues a suggested question, the option button immediately becomes `disabled`, prepends the `✓ ` prefix, and displays the greyed-out disabled stylebox.
  - If a server error occurs, `_on_server_error` clears `_pending_talk` and `_queued_talk` and refreshes the panel, returning the button to its normal interactive state.
  - Button text and identifiers remain compatible with `automation.gd`.

### Item 2: Wait for AI instead of showing the rule-based text first
- Server changes:
  - `server/src/game/types.ts`: Added `coachPending?: boolean;` to `FinalRow`.
  - `server/src/game/game.ts`: Added `aiFor?: (p: PlayerState) => AIService` to `Ctx`. In `endGame`, players with AI enabled (`!p.isBot && !!p.accountId && ai.enabled`) initialize with `coach: ''` and `coachPending: true`. Guests, bots, and rules mode players initialize immediately with `coach: fallbackTip(p)` and `coachPending: false`.
  - `server/src/game/game.ts` & `server/src/room.ts`: `enrichCoach` resolves `ai.debrief(p, row)` (with a 30s timeout safety race), sets `row.coach` to the AI feedback on success or `fallbackTip(p)` on failure/timeout, and clears `coachPending: false`. `room.ts` supplies `aiFor` in `makeCtx`.
  - `server/test/game.test.ts`: Added automated unit test verifying that `FinalRow` for an AI-enabled player starts with `coachPending: true` and empty text, then finishes with AI debrief text and `coachPending: false`; on AI failure ends with `fallbackTip(p)` and `coachPending: false`; and guests/bots receive rule-based fallback immediately with `coachPending: false`.
- Client changes:
  - `client/scripts/ui/report.gd`: Report body coach feedback and certificate card coach feedback display a clear waiting state 「AI 教練評語產生中……」 with a subtle opacity pulse animation (no emoji) while `coachPending` is true, replacing with the arrived text in-place upon receipt.
  - Certificate 「儲存圖片」 button is disabled while `coachPending` is true, displaying an adjacent 「等待 AI 評語…」 note, and `_download_certificate` guards against download while pending.
- Audit of AI text features in the game:
  1. **Final report coach comment / debrief (`debrief`)**: Changed. Previously initialized with rule fallback and overwritten later; now starts pending (`coachPending: true`, empty text) and only populates on AI arrival or failure fallback.
  2. **Ten-years-later letters (`letter`)**: Already had explicit wait-and-notify UX. In `report.gd`, the header indicates 「AI 潤稿中……（先顯示草稿）」 while `aiPending` is true, updating to the polished text once `enrichCoach` finishes.
  3. **AI hint (`hint` / 「求助教練」)**: Already waited correctly. Client sets `_waiting_hint = true` (displaying 「教練思考中……」) and server awaits `ctx.ai.hint(c, sess)` synchronously within `applyAction` before returning state; no fallback is shown before completion.
  4. **Seminar tile coach tip (`coachTip`)**: Already waited correctly. `resolveTile` in `game.ts` line 350 awaits `ctx.ai.coachTip(p)` before emitting the seminar event dialog; client receives the final tip directly.
  5. **Objection grading feedback (`gradeObjection`)**: Already waited correctly. Submitting freeform objection sets `_waiting_ai = true` (displaying 「AI 講師評分中……」) and server awaits `ctx.ai.gradeObjection` within `applyAction` before advancing to result screen.
  6. **Market news (`marketNews`)**: Already waited correctly. `resolveTile` in `game.ts` line 299 awaits `ctx.ai.marketNews(me)` before creating the event dialog; client displays the event with the generated headline directly.
  7. **AI-generated clients (`generateClient`)**: Already waited correctly. Generated in background and only injected into game state via `injectClient` after full schema validation and calibration.

### Item 3: Certificate PNG export redesign
- Modified `client/scripts/ui/report.gd`:
  - Added dedicated `_build_export_certificate_card(mine, s)` producing an export card formatted to 1200x675:
    - Root `Control` at 1200x675 with theme applied.
    - Outer card `PanelContainer` positioned at `(40, 30)` with size `(1120, 615)` (~40 px consistent outer padding), rounded gold border (3px), transparent surround.
    - Full-width header band: 「公平待客面談完訓卡」 (28px gold), 「｜ 專業顧問合格證明」 (16px ivory/muted), right-aligned 「INSURE QUEST 人生顧問局」 (14px).
    - Body in two balanced columns filling height:
      - Left column ~55% (~580 px): Large advisor name (22px), completion date, 服務客戶 N 位 with 「★ 零違規」 gold stamp or red-light badge, and 5 competency progress bars with label, custom height ~46 px, bar filling width, and score aligned right.
      - Right column ~45% (~440 px): Centered large gold grade seal (190x190 px, grade letter 76px, GRADE subtitle), total score underneath (19px gold), and coach comment quote box with gold-tinted border, full comment text wrapped at 400px min width with 18px font.
    - Footer strip: Thin gold rule (1px) and centered small text 「完訓日期 YYYY-MM-DD · 本證明由 INSURE QUEST 訓練紀錄自動產生」 (13px).
    - Export only permits download after AI coach feedback has arrived.
    - Maintained button text 「儲存圖片」, filename `fair-treatment-certificate.png`, web-only guard, and 2-frame layout settlement wait before rendering.

### Files Changed
- `client/scripts/ui/session_panel.gd`
- `client/scripts/ui/report.gd`
- `server/src/game/types.ts`
- `server/src/game/game.ts`
- `server/src/room.ts`
- `server/test/game.test.ts`
- `docs/design/tasks/batch15-ai-wait-cert-layout.md`

### Anything Not Done
- None. All requirements implemented and audited.
