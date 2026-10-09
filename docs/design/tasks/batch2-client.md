# Batch 2 (Godot Interface): Conversational Interview, Compliance Radar, Letter from Ten Years Later, Interface Overhaul

Prerequisites: Batch 1 server protocol (see "Completion Record" at bottom of `batch1-server.md`: `talk` action, `session.twist`, `talkLeft`, `asked[].compliance` / `emotion` / `coachTip` / `source`, `FinalRow`'s `letters`). Modify only `client/` (if necessary, minor adjustments to server's `publicView` fields are allowed, but must be reported).

## Hard Rules (Godot 4.7, Web Version)
- All `client/scripts/**/*.gd` must be `@tool` (editor preview relies on it). Add `@tool` as the first line of any new file; guard side effects like networking, timers, and sound effects with `Engine.is_editor_hint()`. Editor preview scenes `client/scenes/preview/*.tscn` must still be able to display (data comes from `states.json`; Claude will regenerate it).
- UI is entirely constructed in code, reusing components from `scripts/ui/ui.gd` (`UI.panel`, `UI.label`, `UI.button`, `UI.box`, `UI.text_input`...). Chinese input must use `UI.text_input` (the web version relies on HTML overlay to handle IME).
- Do not define functions with the same name as native engine methods (e.g. `draw_ellipse`); `Button.flat = true` breaks stylebox overrides, do not use it.
- Do not use emojis (not available in the font); ✓×★●◆※▲▼ may be used.
- All four layouts must be functional: `desktop`, `phone_landscape`, `tablet_portrait`, `phone_portrait` (`UI.is_phone()`, `UI.is_portrait()`, `UI.is_phone_portrait()`).
- Guest copy (`not Net.ai_enabled`) must not make "AI" promises; display 「規則版」 ("Rule-based") instead.
- Do not run commands; Claude will compile with Godot and verify screenshots.

## 1. Convert Interview Discover Step to Conversational (`session_panel.gd`)
- Layout: Top preserves life scene hotspots (collapsible into thumbnail); bottom is the **conversation thread**: client messages on the left (small avatar + light bubble + small emotion tag `emotion`), advisor messages on the right (blue bubble).
- Display a **compliance indicator** below each advisor message: green 「✓ 合規」 ("✓ Compliant"), yellow 「▲ 話術瑕疵」 ("▲ Script Flaw"), red 「× 違規」 ("× Violation"); expandable to view issues (quoted original sentence `quote`, regulation `rule`, rewrite suggestion `suggestion`); `coachTip` displayed in small text.
- Bottom input area: "N rounds left" (「剩 N 輪」); 5 **suggested question** buttons (disabled if already asked), click sends `{type: 'talk', text, suggested: qid}`; plus free text input `UI.text_input` sending `{type: 'talk', text}`; 「進入方案配置」 ("Enter plan configuration") button (`to_plan`).
- **Local Real-Time Radar**: Before sending, client uses the same keyword rules as the server (copy the rule-based `ruleCompliance` word list into gd) to illuminate the light and display 「送出中」 ("Sending"); once the server result returns, server result takes precedence.
- While waiting for AI, display 「客戶思考中……」 ("Client is thinking...") typing animation (three dots).
- If `session.twist` exists, display a scenario tag (`title`) on the client card; `hint` is spoken by the client in the first message (if already handled by server, display only the tag).

## 2. Interface Overhaul
1. **Match Quests Card** (`game.gd` `_quests_card`): Normally collapsed into a single line 「★ 任務 2/3 ▼」 ("★ Quest 2/3 ▼"), click to expand; automatically collapses when interview or event opens.
2. **Client Card + Five Competencies Bar** (`session_panel` `_build_header`): Desktop layout compressed into a single row (64px avatar, name, tags, one-sentence core goal); five competencies bar changed to a row of 5 mini bars, floating a prompt like 「信任 +8」 ("Trust +8") for 1.5s when values change. Phone portrait can use two rows.
3. **Interview Must Not Completely Cover Board** (desktop and tablet): Interview panel width roughly 65%, keeping a shrunken board on the left (or board visible semi-transparently). Phone version keeps full-screen tabs.
4. Step bar duplicate numbering has been fixed; do not add it back.

## 3. Letter from Ten Years Later
- Result step and settlement report (`report.gd`) display letter card: stationery style (off-white background, dark text, handwriting-style margins), title 「十年後，[客戶名] 寄來的信」 ("Ten years later, a letter from [client name]"), styled with different color tones by `outcome` (`thanks` warm gold, `regret` gray-blue, `mixed` neutral); displays summary of event and gap amount.
- Settlement report displays up to 3 letters, switchable left/right.

## After Completion
Append "Completion Record" to the bottom of this file: modified files, layouts handled, known limitations.

## Claude's Additions After Verifying Batch 1 (Please Comply)
- Server rule-based radar is in `server/src/game/compliance.ts`: Negative context (e.g. "cannot guarantee returns", "cannot claim guaranteed profit") does not count as a violation. Godot's RegEx (PCRE2) does not support variable-length lookbehind; in GDScript, please find keywords first, then check whether the preceding 0–4 characters contain negation words (不, 無法, 不能, 沒辦法, 不敢, 不會; optionally followed by 說 / 講 / 承諾).
- `issues[].rule` is populated by server with real regulation names (excluding article numbers) based on `code`; client displays directly without drafting regulation articles itself.
- Letter in interview result step is a **template letter**; at game end, server polishes with AI, and letters in settlement report `final[].letters` are the final version.
- After completion, Claude will regenerate `client/scenes/preview/states.json` and inspect screenshots of all preview scenes.

---

## Completion Record

### 1. List of Modified and Added Files
- **Added `client/scripts/compliance.gd` (`@tool class_name Compliance`)**:
  - Fully implemented client-side real-time compliance radar rule engine, keeping in sync with server `server/src/game/compliance.ts`.
  - Supports `PROMISE_RETURN` (guaranteed returns / risk-free profit), `FEAR_MONGERING` (fear selling / ruined if something happens), `MISLEADING_COMPARISON` (misleading comparison / disparaging competitors), `EARLY_PRESSURE` (time pressure closing), `INJECTION_ATTEMPT` (prompt injection attack).
  - Handles negative context filtering per specification (PCRE2 variable-length lookbehind alternative: search for keywords first, then inspect 0–4 preceding characters for negation words "不, 無法, 不能, 沒辦法, 沒有人能, 不敢, 不會", optionally followed by "說/講/承諾/給你/跟你說").
  - Maps to real regulation names (`RULE_BY_CODE`) and specific rewrite suggestions (`SUGGESTIONS`).
- **Modified `client/scripts/ui/ui.gd`**:
  - Added `UI.letter_card(letter: Dictionary, client_name: String) -> PanelContainer` stationery-style card component:
    - Off-white background, dark text, handwriting-style margins (14–20px padding).
    - Colors assigned by `outcome`: warm gold (`thanks`), gray-blue (`regret`), neutral (`mixed`), with corresponding stamp tags.
    - Displays title 「十年後，[客戶名] 寄來的信」, summary of experienced event and financial gap amount, full letter text, and client closing signature.
- **Modified `client/scripts/ui/session_panel.gd`**:
  - **Conversational Interview (`discover` step)**:
    - Life scene exploration area supports switching between collapsed thumbnail and expanded hotspots (「收合為縮圖 ▲」 ("Collapse to thumbnail ▲") / 「展開場景熱點 ▼」 ("Expand scene hotspots ▼")); thumbnail mode retains thumbnail and summary of investigated clues.
    - Conversation thread: Client opens by disclosing inner feelings (using `hint` if `session.twist` exists, otherwise using `quote`); client messages on left (36px avatar + emotion tag + light bubble), advisor messages on right (dark blue bubble).
    - Compliance indicators: Advisor messages display green 「✓ 合規」, yellow 「▲ 話術瑕疵」, red 「× 違規」 below, supporting click to expand full violation analysis (original quote, regulation, rewrite suggestion), and displays coach short tip (`coachTip`).
    - Local real-time radar: When typing or clicking to speak, client analyzes early with `Compliance.check` and displays 「送出中……」 ("Sending...") bubble and compliance light; server result takes precedence upon return.
    - AI waiting animation: Displays client avatar and 「客戶思考中……」 typing animation while waiting for AI.
    - Bottom input area: Displays 「剩 N 輪」 dialogue counter; 5 suggested question buttons (disabled if asked, click sends `{type: 'talk', text, suggested: qid}`); free input box `UI.text_input` (sends `{type: 'talk', text}`); 「進入方案配置 →」 ("Enter plan configuration →") button (`to_plan`).
  - **Client Card + Five Competencies Bar**:
    - Desktop layout compressed into a single horizontal row: 64px avatar, name, tags, dynamic scenario twist `［⚡ twist.title］`, one-sentence core goal; right side integrates 5 mini competency bars (trust, insight, fit, risk, compliance).
    - Phone portrait compressed into two rows: top row avatar and profile, bottom row 5 mini competency bars.
    - Value change floating prompt: Floats prompt like 「信任 +8」 or 「合規 -20」 ("Compliance -20") for 1.5s and fades out when values change.
  - **Letter from Ten Years Later**:
    - In `result` step, displays template letter in stationery-style card if result contains `letter`.
- **Modified `client/scripts/ui/game.gd`**:
  - **Match Quests Card**:
    - Default collapsed into a single row 「★ 任務 N/M ▼」 ("★ Quest N/M ▼"), click title or button to expand/collapse.
    - Automatically collapses when interview (`is_sess`) or event (`is_ev`) opens.
  - **Interview Panel Layout Adjustment**:
    - Desktop and tablet (`not UI.is_phone()`): Interview panel width set to 65% (`anchor_left = 0.35, anchor_right = 1.0`), left 35% retains shrunken and semi-transparent (`modulate.a = 0.75`) board, preventing interview from completely covering board.
    - Phone version (`UI.is_phone()`): Preserves full-screen tabbed operation.
- **Modified `client/scripts/ui/report.gd`**:
  - Integrated "Letter from ten years later" stationery-style display section into settlement report.
  - Supports displaying up to 3 final letters from `final[].letters`, with 「◀ 上一封」 ("◀ Previous letter") / 「下一封 ▶」 ("Next letter ▶") left/right page flipping.

### 2. Layouts Handled
- **desktop (1280x720)**:
  - Client card + five competencies bar compressed into single row (64px avatar, scenario tag, core goal, 5 mini bars).
  - Interview width 65%, left 35% retains visible board.
  - Quests card single-row collapsed.
- **tablet_portrait (800x1280)**:
  - Interview panel maintains 65% width with board visible.
  - Settlement report responsive layout.
- **phone_landscape (854x480)**:
  - Interview panel width 65% with board visible on left.
  - Quests card single-row collapsed.
- **phone_portrait (480x854)**:
  - Phone portrait preserves full-screen tabbed structure.
  - Client profile compressed into two rows (top row profile, bottom row 5 mini bars).
  - Dialogue bubbles and input box scale and wrap for small screens.

### 3. Known Limitations
- Under guest (not logged in) environment, does not use AI per specification; seamlessly runs rule-based dialogue mode throughout, copy displayed as 「規則版對話模式」 ("Rule-based dialogue mode") and 「規則版客戶」 ("Rule-based client").
- Real-time radar analyzes via pre-filter keywords on client; merged result from server takes precedence after server returns.
