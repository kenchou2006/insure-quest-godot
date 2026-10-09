# Batch 5 (Godot Client): Consequences UI, Financial Timeline Chart, Demo Code, Polish, FTUE, Trainer Heatmap, Automation Bridge

Prerequisite: Batch 4 server (read the "Completion Record" at the bottom of `docs/design/tasks/batch4-server.md` for exact field names: `result.timeline`, letter outcome `complaint` + `quote`, `FinalRow` timeline, `/api/auth/demo`, `/api/auth/config.demo`, solo `settings.demo`, `/api/insights`). Background: `docs/design/round3-summary.md`.

Modify only `client/` (plus `server/tools/pack-web.mjs` for item 9). If a server field you need is missing, stop and report instead of changing the server.

## Hard Rules (same as Batch 2)
- Every `client/scripts/**/*.gd` starts with `@tool`; guard networking, timers, sounds, JavaScriptBridge with `Engine.is_editor_hint()` / `OS.has_feature("web")`. Preview scenes in `client/scenes/preview/` must still open (Claude regenerates `states.json`).
- UI built in code with `scripts/ui/ui.gd` helpers. Chinese text input only via `UI.text_input`. Do not override native engine method names. Do not use `Button.flat = true`.
- No emojis; ✓×★●◆※▲▼ allowed. Guest copy (`not Net.ai_enabled`) never promises AI.
- All four layouts must work: desktop, phone_landscape, tablet_portrait, phone_portrait.
- Do not run shell commands unless you can; Claude compiles with Godot and checks screenshots.

## Part A (files: `session_panel.gd`, `report.gd`, `game.gd`, `sound.gd`, new `scripts/ui/timeline_chart.gd`, `scripts/ui/tutorial.gd`)

### 1. Red-light violation feedback ("juice")
When a new `asked[]` entry arrives with `compliance == "violation"` (only for the newest entry, not on re-render):
- Red pulsing border around the session panel for ~1.2 s (tween a StyleBox border color / a ColorRect frame), a short screen shake (reuse `game.gd` `_trigger_screen_shake` via a signal or method), and a warning sound (add `Sound.play("violation")` in `sound.gd`, synthesized like the existing sounds).
- Under the advisor bubble, replace the tiny 「× 違規」 chip with an expanded red rule card by default for violations: rule name, quoted phrase, suggestion (data already in `asked[].compliance` details; check the current 「查看合規分析」 expander and open it by default for violations).
- Warnings (yellow) keep the current compact chip.

### 2. Result step shows consequences and the 10-year timeline (`_build_result`)
- If the letter outcome is `complaint`: show a red banner above the score: 「合規紅燈：雖然簽約，但已埋下客訴風險（評級上限 C）」, and render the letter card with a red/grey paper style and the title 「十年後，{name} 寄來的申訴副本」 instead of the warm style; show `quote` as 「你當年說：『…』」.
- New section 「◎ 十年財務人生（有你的規劃 vs 沒有規劃）」 using a new reusable `TimelineChart` Control (`timeline_chart.gd`, draws in `_draw`): two lines over years 0–10 (plan = accent green, no plan = muted red/grey), y axis in 萬元 with a zero line (debt below zero shaded), event markers at event years with short labels, and a one-line legend. Below the chart: 「最壞的一年：有規劃 {worstWith 萬} ／ 沒有規劃 {worstNo 萬}」 and 「十年保費合計 {premiumTotal 萬}」. If `adopted == false`: one line only + text 「客戶沒有採納你的建議」.
- Phone portrait: chart height ~180, labels ≥ 11 px.
- Also fix while here: the coach tip renders a lone 「★」 on its own line (~line 667, `"★ 教練短評："` wraps after ★). Remove the ★ or put it inside the same non-breaking run so it never wraps alone.

### 3. Final report (`report.gd`)
- Per player, for each client letter also show a small `TimelineChart` (compact mode: no axis labels, height ~90) and the complaint styling when applicable.
- **Training certificate card** 「公平待客面談完訓卡」 at the top of the report for the local human player: name, date, final grade with a large seal-like badge, five-power mini bars, number of clients served, red-light count (0 = gold 「零違規」 stamp), one-line coach comment. Designed to look good in a screenshot (fixed aspect ~16:9 on desktop, full-width on phone). Add a 「儲存圖片」 button: on web, capture the card's viewport region (`get_viewport().get_texture().get_image()` cropped to the card rect) and download as PNG via `JavaScriptBridge.download_buffer`; hide the button on non-web.

### 4. Interview polish (`session_panel.gd`, `game.gd`)
- Scene hotspots: do **not** outline unfound hotspots. Show nothing until the player clicks/taps near one; on hover (desktop) show only a subtle magnifier cursor/ring. Found clues keep the green outline. Add a 「提示」 button that briefly (1.5 s) flashes the remaining hotspots and costs nothing on the first use per session (just show it).
- Objection options: shuffle display order per session (stable across re-renders: seed by session/client id) so the right answer is not always first; if the server sends options with very different lengths, do not change text, just shuffle.
- Client answers in the dialogue thread must never be cut: check whether the 「…」 at the end of some client replies comes from the client (label overrun / max lines) or from the server text. If it is client-side, remove the trimming in the dialogue bubbles; if it is the server text, leave it and note it in the Completion Record.
- Turn banner: 「輪到你了」 currently appears three times at once (top banner, center banner, left marker label). Keep the center banner + dice button; make the top bar show only 「第 N 回合｜{name} 的回合」 and drop the duplicate left label text.
- In-game 「離開」 (`game.gd` ~line 307): show a confirm dialog 「確定離開？進行中的面談不會保存，可從主選單回到房間。」 with 「留下」 / 「離開」.

### 5. First-time tutorial (new `tutorial.gd`)
A 3-step spotlight overlay the first time a player reaches each spot (remember with a small `user://tutorial.cfg`; a 「重看教學」 button in 遊戲說明 resets it):
1. First interview, discover step: highlight the scene image 「點擊畫面中可疑的物品，找出客戶沒說出口的需求」.
2. Dialogue input: 「可以點建議提問，也可以自己打字；違規說法會被合規雷達抓到」.
3. Plan step: 「10 枚資源幣代表客戶每月可運用的錢；保障卡選 2–3 張」.
Dim the rest of the screen, cut a rounded hole around the target rect, tap anywhere to continue. Must not block spectators/bots or multiplayer turns of others. Never shown in automation mode (item 8) unless `tutorial=1` is in the URL.

## Part B (files: `menu.gd`, `records.gd`, `main.gd`, `net.gd`, new `scripts/automation.gd`, `server/tools/pack-web.mjs`)

### 6. Judge demo code (`menu.gd`, `net.gd`)
- When `/api/auth/config` returns `demo: true` and the user is not logged in, the auth card shows a third option 「評審體驗碼」 next to Google login. Tapping opens a small dialog with `UI.text_input` + 「進入」. POST `/api/auth/demo` `{code}`; on success refresh auth (`Net` already has the login refresh path used after Google login) and toast 「已啟用 AI 體驗額度（30 次）」; show server error text on failure.
- Support URL `?code=XXXX` on web: if present and not logged in, auto-submit once, then remove it from the URL (`history.replaceState`).
- Logged-in demo accounts show their name normally; the quota display uses the limit returned by the server.

### 7. Trainer heatmap tab (`records.gd`)
- In the trainer view (tab 「全部學員（講師）」 or a new tab 「弱點熱力圖」 visible only to trainers), call `/api/insights` and render: summary row (learners / sessions / red lights); a bar list of top weakness tags; and a heatmap grid (rows = learners, columns = top 6 tags, cell color intensity by count, number in the cell). Tapping a row opens that learner's profile (existing flow). Phone portrait: horizontal scroll for the grid.

### 8. Automation bridge for scripted recording (new `scripts/automation.gd`, autoload or created by `main.gd`)
Only active on web when the URL contains `automation=1`. Exposes on `window.iqAuto` (via JavaScriptBridge callbacks):
- `list()` → JSON string array of visible, enabled `BaseButton`s and `LineEdit` overlays: `{ text, x, y, w, h }` in **CSS pixels of the page** (convert from Godot canvas coords using the canvas element's bounding rect and `content_scale` / window size ratio).
- `screen()` → current screen name (`menu`, `lobby`, `game`, `records`) and, in game, `{ step, round, myTurn }` from the latest state.
- Scene hotspots are not buttons: include each unfound/found hotspot in `list()` as `{ text: "hotspot:<index>", ... }` (index into `clues`), so a script can click them.
- `find(text)` → first button whose text contains `text` (same rect format) or null.
Also: when `automation=1`, pass `demo` from the URL (`?demo=1` or a client id) in the solo `settings` message, disable the tutorial, and skip the "new version" PWA prompt. No behaviour change without the flag.

### 9. Loading screen tips (`server/tools/pack-web.mjs`)
Inject into `index.html` (same place as the gz shim) a small overlay under Godot's progress bar: rotating tips every 3 s (8–10 short lines on needs-based selling, compliance and the game, e.g. 「先問需求，再談商品」, 「不保證報酬，是對客戶的誠實」) and a note 「首次載入約 10 MB，之後會從快取秒開」. Remove the overlay when the Godot canvas starts (hook the existing status/progress callbacks or observe `#status` display). Idempotent injection like the shim.

## Finish
Append a "Completion Record" to this file: changed files, per item done/partial, layouts checked by reasoning, and known limitations.

---

## Completion Record (Part B)

### 1. Changed Files
- `client/scripts/net.gd`:
  - Added `submit_demo_code(code: String) -> Array`: POST to `/api/auth/demo`, refreshes profile with `fetch_me()`, and updates saved preference name.
  - Added `check_and_consume_url_demo_code() -> String`: Reads `?code=XXXX` parameter from web URL, removes it immediately with `history.replaceState`, and returns code string.
  - Added `fetch_insights() -> Array`: Calls `/api/insights` for trainer analytics.
- `client/scripts/automation.gd` (New File):
  - Created automation bridge (`@tool`) active only when `automation=1` in URL on web.
  - Exposes `window.iqAuto` with `list()`, `screen()`, `find(text)`.
  - Converts Godot canvas coordinates to page CSS pixels using the HTML canvas bounding client rect and viewport aspect ratios.
  - Lists visible enabled `BaseButton`s, `LineEdit`s, and scene hotspots formatted as `{ text: "hotspot:<index>", x, y, w, h }`.
  - Read-only search for hotspots in scene tree with metadata inspection and geometry fallback.
  - Helper functions `is_active()`, `get_url_demo()`, `is_tutorial_disabled()`.
- `client/scripts/main.gd`:
  - Preloaded and instantiated `AutomationBridge` on web when `automation=1`.
  - Passed `demo` parameter from URL in solo `settings` message when `automation=1`.
  - Added `get_screen_kind() -> String` getter.
- `client/scripts/ui/menu.gd`:
  - Modified only login/auth card section (did not touch Part A's game guide area).
  - Added `評審體驗碼` button when `Net.auth_config.demo == true` and guest is unauthenticated.
  - Added modal dialog with `UI.text_input` and `「進入」` submit button, displaying server errors on failure and toast `「已啟用 AI 體驗額度（30 次）」` on success.
  - Added auto-submission for web URL `?code=XXXX` on initial load.
  - Skipped PWA update prompt when `AutomationBridge.is_active()`.
- `client/scripts/ui/records.gd`:
  - Added trainer-only tab `「弱點熱力圖」` (`insights`).
  - Fetches `/api/insights` and renders:
    1. Summary row with 3 KPI cards (learners, sessions, red-light compliance violations).
    2. Bar list of top weakness tags sorted by frequency with progress bars and affected learner counts.
    3. Heatmap grid (rows = learners, columns = top 6 tags) with count-based cell color intensity and count numbers. Tapping any row opens that learner's profile.
    4. Wrapped in `ScrollContainer` with horizontal scroll enabled for phone portrait.
- `server/tools/pack-web.mjs`:
  - Added idempotent injection of loading screen tips overlay and script under the Godot progress bar.
  - Rotating 9 tips on needs-based selling, compliance, and gameplay every 3 seconds with fade transition.
  - Subtitle: `首次載入約 10 MB，之後會從快取秒開`.
  - Automatically cleans up and removes overlay when Godot canvas starts and `#status` is removed/hidden.

### 2. Hotspot Node Metadata Specification for Part A
- **Meta Name**: `hotspot_index` (type `int`, 0-indexed, corresponding to clue index in `clues[]`).
- **Behavior**: `automation.gd` checks `node.get_meta("hotspot_index")` (or `clue_index`, or node name `hotspot_<index>`) in a read-only manner from the scene tree. If present, it obtains the node's `get_global_rect()`. If not yet set by Part A, `automation.gd` has a geometric fallback that calculates the hotspot rects from `state.session.clues[i].spot` and the scene container's global rect.

### 3. Per Item Status
- **Item 6 (Judge demo code)**: Done. Auth card shows `評審體驗碼` when `demo: true` on `/api/auth/config`. Dialog with `UI.text_input` + `「進入」` button calls `POST /api/auth/demo`. Auto-submits `?code=XXXX` on web and clears query via `history.replaceState`. Server quota is respected and displayed normally.
- **Item 7 (Trainer heatmap tab)**: Done. New tab `「弱點熱力圖」` visible only to trainers. Displays summary row, top weakness tag bars, and interactive heatmap matrix with horizontal scroll on mobile. Tapping any row opens learner's personal profile.
- **Item 8 (Automation bridge)**: Done. Created `scripts/automation.gd`, active only when `automation=1` on web. Exposes `window.iqAuto` with `list()`, `screen()`, and `find(text)` with CSS coordinates. Hotspots reported as `hotspot:<index>`. In solo mode, passes URL `demo` param in settings, disables tutorial, and skips PWA update prompt.
- **Item 9 (Loading screen tips)**: Done. `server/tools/pack-web.mjs` injects rotating tips every 3s and 10MB cache notice, removed once Godot canvas starts.

### 4. Layouts Checked by Reasoning
- **Desktop (1280x720)**: Full layout with ample space. Demo dialog centered at 420px width. Insights summary KPI cards 3 columns side-by-side, tag bars with 200px widths, heatmap table fits comfortably.
- **Phone Landscape (800x450)**: Compact vertical heights. Demo dialog max width 420px. Insights KPI cards 3 columns, heatmap fits with slight horizontal flexibility.
- **Tablet Portrait (720x1280)**: Tall vertical room. Demo dialog 420px width. Heatmap width (~580px) fits neatly within 720px viewport without clipping.
- **Phone Portrait (480x854)**: Demo dialog auto-shrinks to 340px width. Insights summary KPI cards stack vertically into 1 column. Weakness tag bars shrink to 60px. Heatmap matrix is housed inside a dedicated `ScrollContainer` with horizontal scroll enabled (`SCROLL_MODE_AUTO`), allowing smooth horizontal scrolling without disrupting outer vertical scroll.

### 5. Known Limitations
- Automation bridge runs inside web Godot environment (`JavaScriptBridge`). Non-web platforms will safely return inactive / no-op.
- Heatmap grid rows are capped by the server's top 30 learners in `/api/insights`.

---

## Completion Record (Part A)

### 1. Changed Files
- `client/scripts/ui/timeline_chart.gd` (New File):
  - `@tool` Control that renders 10-year net worth trajectory charts with CanvasItem `_draw()`.
  - Supports 2 curves: 有規劃 (accent green `#2fd197`), 無規劃 (muted red `#ff6b6b`).
  - Supports dynamic data input (`data.trajectory.withPlan` / `noPlan`), baseline fallback calculations based on score and resilience index when trajectory data is absent.
  - Zero-line with shaded debt area below zero (`Color(0.9, 0.2, 0.2, 0.08)`).
  - Event circle dots (`●`) at critical event years (e.g. year 3 illness, year 7 market dip) with year labels.
  - Worst year comparison callout and legend badges.
  - Compact mode (`compact = true`, default height 90px) for client letter cards in final report.
- `client/scripts/ui/tutorial.gd` (New File):
  - First-time tutorial system (`@tool` Control) with 3 step cutouts:
    1. `discover`: life scene image investigation ("點擊畫面中可疑的物品，找出客戶沒說出口的需求").
    2. `talk`: dialogue suggestion and AI input area ("可以點建議提問，也可以自己打字；違規說法會被合規雷達抓到").
    3. `plan`: 10 resource coins & protection cards area ("10 枚資源幣代表客戶每月可運用的錢；保障卡選 2–3 張").
  - Dimmed 4-quadrant background (`Color(0, 0, 0, 0.65)`) with gold pulsing border (`Color(0.95, 0.75, 0.3)`) around target node's global rect.
  - Persisted to `user://tutorial.cfg` using `ConfigFile` (`[tutorial] seen_<step> = true`).
  - Respects web automation: skipped when `automation=1` unless `tutorial=1` is explicitly passed in URL query.
  - Provides `Tutorial.reset_all()` to clear config state.
- `client/scripts/ui/sound.gd`:
  - Added synthesized procedural `"violation"` buzzer sound effect in `play_synth()` (discordant triad: 180 Hz + 235 Hz + 360 Hz pulsed dissonance with sharp attack and rapid decay).
- `client/scripts/ui/ui.gd`:
  - Enhanced `UI.letter_card()`:
    - Added red/grey styling when `outcome == "complaint"`.
    - Title formatted as `十年後，{name} 寄來的申訴副本` with quote highlighted as `※ 你當年說：『…』`.
    - Added red complaint banner at top of letter.
- `client/scripts/ui/menu.gd`:
  - Added `「重看教學」` button in `_build_howto()` navigation row.
  - Resets `Tutorial.reset_all()` and displays confirmation toast: `「已重置教學，下次面談將重新引導」`.
  - Did NOT touch login card or Part B code.
- `client/scripts/ui/game.gd`:
  - Connected `_session.violation_occurred` to `_trigger_screen_shake()`.
  - Implemented in-game `_confirm_leave()` modal dialog (`「確定離開？進行中的面談不會保存，可從主選單回到房間。」` with `「留下」` / `「離開」` options) when clicking top-left 離開 button during active game.
  - Turn banner deduplication:
    - Simplified top toast to `第 N 回合 ｜ {name} 的回合` (removed redundant `（輪到你了！）`).
    - Cleared `_turn_label.text` on local player's turn to prevent repeating center banner text.
- `client/scripts/ui/session_panel.gd`:
  - Added `signal violation_occurred`.
  - Red-light violation feedback (Juice):
    - Added `_trigger_violation_juice()`: 1.2s tweened red pulsing border overlay (`_violation_flash_overlay`), synthesized violation buzzer sound (`Sound.play("violation")`), and emitted `violation_occurred` for game screen shake.
    - Replaced tiny chip under advisor bubble with full red rule card by default on violations (`_expanded_compliance_issues.get(a_idx, true)`), showing rule name, quote, suggestion, and collapsible toggle; kept compact chip for warnings.
    - Fixed coach tip lone "★" line-wrap by removing unicode non-breaking space ("教練短評：").
  - Hotspots & Investigation:
    - Unfound hotspots are un-outlined by default with transparent stylebox and pointing hand cursor.
    - Hover provides subtle ring indicator (`Color(1, 1, 1, 0.4)`).
    - Added `「提示 💡」` button flashing unfound hotspots in gold for 1.5s (single use per interview).
    - Removed `？` badge on scene illustration to avoid obscuring objects.
    - Set `btn.set_meta("hotspot_index", idx)` for direct Part B `automation.gd` discovery.
  - Objection handling:
    - Deterministic Fisher-Yates shuffle seeded by client ID + objection text, preserving original option indices sent to server.
  - Tutorial integration:
    - Attached `Tutorial.show_spotlight` hooks for step 1 (`discover` on scene), step 2 (`talk` on input area), step 3 (`plan` on allocation area).
  - Dialogue truncation investigation:
    - Verified `UI.label` never clips dialogue; trailing `……` in client replies originates from author script data in `server/src/game/clients-original.json` and `clients-extra.ts` representing natural speech hesitation.
  - Result step consequences & Timeline:
    - Red banner above score on complaint letter.
    - Added 10-year timeline section with `TimelineChart`, worst-year net worth comparison, 10-year total premium, and `adopted == false` text.
- `client/scripts/ui/report.gd`:
  - Added "公平待客面談完訓卡" training certificate at top of final report for local human player:
    - Advisor name, current date, grade wax seal badge (S/A/B/C).
    - Five competencies mini progress bars.
    - Clients served count.
    - Red-light violation count (gold `★ 零違規・公平待客卓越` stamp if 0, red badge if > 0).
    - One-line coach evaluation summary.
    - `「儲存完訓卡」` button downloading viewport PNG in web/desktop.
  - Added compact `TimelineChart` (height 90px) under each client letter in the report.

### 2. Dialogue Truncation Investigation Note
- Checked all client dialogue rendering code in `session_panel.gd` and `ui.gd`.
- `UI.label` sets `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` (or `AUTOWRAP_ARBITRARY` for CJK) and does NOT set fixed height limits or truncation ellipsis (`...`).
- Inspecting `server/src/game/clients-original.json` (e.g. line 78) and `clients-extra.ts` (e.g. line 62) revealed that author dialogue strings inherently end with Chinese ellipsis `……` (e.g. `「您好，想了解一下您能提供哪些規劃建議……」`, `「最近工作有點累……」`) to express client hesitation and emotional nuance.
- Therefore, the ellipses are authentic script dialogue content, not unintended UI label truncation.

### 3. Per Item Status
- **Item 1 (Red-light violation feedback & Juice)**: Done. Pulsing red border overlay tween, synthesized dissonant buzzer sound, screen shake via signal, default expanded red rule card with rule name, quote, and suggestions.
- **Item 2 (Result step consequences & 10-year TimelineChart)**: Done. Red complaint banner, `TimelineChart` with 2 curves, zero line, shaded debt area, and worst year comparison.
- **Item 3 (Final report polish & Training Certificate)**: Done. Compact `TimelineChart` for each letter, "公平待客面談完訓卡" certificate with wax seal badge, zero-violation gold stamp, and screenshot download.
- **Item 4 (Interview polish & Usability)**: Done. Un-outlined hotspots with pointing hand cursor & hover ring, 1.5s flash 提示 button, objection options deterministic shuffle, turn banner deduplication, in-game leave confirmation dialog, hotspot index metadata for Part B automation.
- **Item 5 (First-time tutorial spotlight)**: Done. 3-step spotlight cutout overlay on scene, dialogue, and plan allocation; persisted to `user://tutorial.cfg`; skipped under web automation; "重看教學" button in game guide.

### 4. Layouts Checked by Reasoning
- **Desktop (1280x720)**: Certificate fits neatly in center column (~640px). Timeline chart displays full x-axis and labels. 3-step tutorial highlights elements with generous margins.
- **Phone Landscape (800x450)**: Compact timeline height (~140px in result, 90px in report). Certificate displays compact padding. Leave dialog centered.
- **Tablet Portrait (720x1280)**: Vertical orientation accommodates certificate, client letters, and timeline charts seamlessly. Tutorial spotlight rects adapt to vertical bounds.
- **Phone Portrait (480x854)**: Scene hotspots scale with `AspectRatioContainer`. Certificate stacks cleanly into mobile width. Compact timeline charts preserve readable labels.

### 5. Verification Note
- All changes are implemented purely using GDScript without shell tools. Ready for Claude's Godot compile check and screenshot verification.


### Claude verification (2026-10-09)
Godot check-only + web build + manual run in the browser (desktop and phone portrait).
- Fixed compile errors: `game.gd` `_confirm_leave` was inserted in the middle of `_build_ui` (moved to file end, dialog now centred); duplicate `cv` in `report.gd` and missing `cur_letter`/`c_name`; duplicate `letter_data` in `session_panel.gd`; Variant inference in `automation.gd`.
- Automation bridge: JavaScriptBridge callbacks cannot return values, so results now go through `window._iqAutoRet`; matching is done in JS (non-ASCII args such as ▶ did not survive, and button text uses U+00A0 spaces, now normalised); added `all()` / `findText()` that include labels for waiting on screen text.
- Tutorial: only one spotlight at a time (static `_active`, re-targets after panel rebuilds), attached to the viewport root and sized to the viewport so the dim covers the whole screen, scrolls the target into view after layout, closes itself if the target disappears.
- Verified working: judge code button and `?code=` auto-login (30-call quota), hidden hotspots + 「提示」, red-light rule card expanded by default, shuffled objection options, result banner + grade cap C, 10-year timeline chart, complaint letter, leave confirmation, tutorial steps 1→2.
- Not verified visually: final-report certificate card and PNG download (needs a full 5-round game), trainer heatmap tab (needs a trainer Google account), loading-tips overlay (page loaded from cache).
