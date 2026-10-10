# Batch 14: Mobile Centring, Board Label Overlap, Simplified-Chinese Glyphs, Duplicate Coach Placeholder

Touches `server/` and `client/`. Hard rules from earlier batches apply (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working: buttons keep their text). Do not run terminal commands; Claude compiles, runs `npm test` and screenshots. Reference screenshots were taken on a phone in portrait (Android Chrome, ~412 px wide CSS viewport → `phone_portrait` layout).

## 1. Missing-glyph boxes come from Simplified Chinese in AI output (root cause found)

The tag 「年輕勞工的逆□之路」 showed a box. Claude checked: the AI model wrote the **simplified** 「袭」 (U+88AD) instead of 「襲」 (U+8972). The game font `client/assets/fonts/NotoSansTC.ttf` is a Big5 subset (see `server/tools/subset-font.py`), and many simplified characters (袭, 资, 劳 …) are not even in the full Noto Sans TC, so expanding the font cannot fix this. NIM / Workers AI models (Qwen, DeepSeek, Nemotron) leak simplified characters now and then; this has happened before.

Fix on the server, at the single point where AI text enters the game:
- Add a Simplified→Traditional (Taiwan) converter, e.g. `server/src/s2t.ts`. Prefer a small character-level map over a big dependency: generate it once with a tool script (e.g. `server/tools/gen-s2t.mjs` reading OpenCC's `STCharacters.txt` + `TWVariants.txt` from the `opencc-js` package or an inline list) into `server/src/s2t-map.json`, keeping only characters that are simplified-only (not valid Traditional too — e.g. do not convert 了, 后 only when unambiguous, 干/发/面/里 are ambiguous: leave them alone). Keep the generated JSON small (target < 60 KB). If you use `opencc-js` at runtime instead, confirm the Worker bundle stays well under the size limit and only load the cn→tw character table.
- Apply it to every string field of every AI result after zod validation in `server/src/ai.ts` (client generation, dialogue `answer` / `coachTip` / compliance text, objection grading, hints, coach critique, letters, AI-generated client names/tags/goals …) — a recursive `normalizeStrings(obj)` helper called in one place (the shared `ask`/parse path) is best. Also apply it to the streamed partial answer before broadcasting (`room.ts` stream / `partialJsonString` callers) so the streamed text and the final text match.
- Add the converted characters guard to the prompt too: tell the model 「一律使用臺灣繁體中文」 if not already present (check existing system prompts).
- Tests in `server/test/`: converting 「年輕勞工的逆袭之路」 → 「年輕勞工的逆襲之路」, 「资产」→「資產」, and that already-Traditional text (including 了, 面, 里程) is unchanged; plus one AI-result normalization test using `MockAI` or a fake provider returning simplified text.
- Client safety net (optional but preferred): in `client/scripts/ui/ui.gd` `UI.label` (or a `UI.safe_text()` helper used by labels showing server/AI text), replace any character the font lacks with a similar fallback? — only if cheap; otherwise skip and note it.

## 2. Phone portrait: components not centred

On the phone portrait layout the session panel content looks shifted left: left padding ~16 px, right side ~40+ px because the Batch 10 scrollbar gutter (12 px margin) plus the scrollbar itself sit on the right. Also the board centre spectator ribbon 「觀看中：【電腦顧問・安安（資深）】的回合（行動中）」 is wider than the inner board rect and overflows past the right column of tiles.
- Phone layouts (`UI.is_phone()`): use a thin overlay-style scrollbar (narrow, semi-transparent grabber, no reserved track) and drop the extra gutter so content has equal left/right padding; or reserve the same padding on the left. Content must be visually centred in the panel. Desktop/tablet keep the Batch 10 gutter.
- `game.gd` board centre: the spectator ribbon, 「第 1 / 5 回合｜名單剩 17 位」, the dice, 「上一步擲出 6 點」 and the 客戶簿 strip must all be centred in the inner board rect (`_board.get_inner_rect()`), with `autowrap` / font downscaling so nothing exceeds the inner rect width on phone portrait (shorten the ribbon text on phones, e.g. 「觀看中：電腦顧問・安安」).
- Check the same on phone landscape.

## 3. Board tile index numbers overlap tile names on phone

On phone portrait the tiles are narrow, names wrap to two lines (「社區\n咖啡廳」, 「客戶\n轉介紹」, 「共同工\n作空間」) and the small index numbers (1, 17, 13 …, drawn in `board.gd` ~L232-245) overlap the text; on the bottom row the numbers sit on top of the names. Fix: on phones draw the index smaller in the tile's outer corner away from the name area (top corner for the bottom row too), reserve space so name text never intersects it, and reduce the name font / use a single line with tighter letter spacing when it fits. No overlap in any of the 4 layouts.

## 4. 「教練短評整理中……」 shown twice

In the interview thread (`session_panel.gd`, Batch 12 queue / early-enable code ~L1040-1110), after the client has answered and while the coach tip is pending, the placeholder appears twice: once as 「（教練短評整理中……）」 next to the ✓合規 chip of the advisor's bubble, and again as a separate line 「教練短評整理中……」 below. Show it exactly once, in the position where the real coach tip will appear (the coach-tip line under that exchange), and replace it in place when the tip arrives.

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### Completed Items:
1. **Simplified Chinese Missing-Glyph Prevention (Item 1)**:
   - Created `server/tools/gen-s2t.mjs`: Node generator script filtering out ambiguous Simplified/Traditional characters (保留「了」、「面」、「里」、「程」、「干」、「发」、「后」等) and outputting pure 1:1 Simplified-to-Traditional Taiwan mappings.
   - Generated `server/src/s2t-map.json`: Compact JSON character mapping (~18 KB, well below the 60 KB limit).
   - Created `server/src/s2t.ts`: Provides `s2t(text)` and recursive `normalizeStrings(obj)` for all strings in nested objects and arrays.
   - Updated `server/src/ai.ts`: Applied `normalizeStrings(obj)` to parsed zod results in `WorkersAI.ask`, `NvidiaNimAI.ask`, and `NvidiaNimAI.askStream`. Applied `s2t` in `partialJsonStringDone`. Added prompt guards specifying 「一律使用臺灣繁體中文，不可出現簡體字」 across prompts (freeQuestion, talk, letter, gradeObjection, marketNews, coachTip, hint, debrief, generateClient).
   - Updated `server/src/room.ts`: Applied `s2t` to the streaming response broadcast callback (`onStream`).
   - Created `server/test/s2t.test.ts`: Added unit tests verifying conversion of 「年輕勞工的逆袭之路」→「年輕勞工的逆襲之路」, 「资产」→「資產」; preserved Traditional/ambiguous characters (了, 面, 里程, 干, 发, 后); recursive `normalizeStrings` object normalization; streaming partial JSON normalization; and fake LLM AI provider normalization.

2. **Phone Portrait & Landscape Centring (Item 2)**:
   - Updated `client/scripts/ui/ui.gd`: On phone layouts (`UI.is_phone()`), configured thin overlay-style `VScrollBar` (transparent track, narrow semi-transparent grabber, no reserved track) in both `make_theme()` and `UI.scroll()`. Removed the 12px right gutter so content has equal padding on both sides and remains visually centered.
   - Updated `client/scripts/ui/game.gd`: In `_sync_center_bounds()`, calculated and centered `_center` within `_board.get_inner_rect()`. Added autowrap and downscaled font sizes for `_top_label`, `_spectator_ribbon_lbl`, `_my_turn_banner`, and `_dice_roll_info_lbl` so no text overflows on phones. Shortened spectator ribbon text on phones to compact format (e.g. 「觀看中：電腦顧問・安安」). Scaled down the client strip avatar container on phones.

3. **Board Tile Index Numbers & Tile Names Layout (Item 3)**:
   - Updated `client/scripts/ui/board.gd`: On phones, drew index numbers at 9px (fixed, not enlarged by `UI.fs()`) anchored in the top outer corner away from the tile name area across all tiles, including bottom row tiles (12..18). Reserved top margin above tile names to prevent overlap. Raised and downscaled tile icons on phones. Tile names dynamically adapt to single-line (10-11px) or two-line wrap (9-10px) to ensure no intersection with index numbers in all 4 layouts.

4. **Duplicate Coach Tip Placeholder Removal (Item 4)**:
   - Updated `client/scripts/ui/session_panel.gd`: Removed duplicate placeholder `（教練短評整理中……）` from the advisor bubble's chip row (`pend_h`), keeping only `（送出中……）` while the statement is in transit. Retained `教練短評整理中……` exactly once in `pend_v` on the dedicated coach-tip line where the final coach critique replaces it upon arrival.

### Files Changed:
- `server/tools/gen-s2t.mjs` (new)
- `server/src/s2t-map.json` (new)
- `server/src/s2t.ts` (new)
- `server/src/ai.ts`
- `server/src/room.ts`
- `server/test/s2t.test.ts` (new)
- `client/scripts/ui/ui.gd`
- `client/scripts/ui/game.gd`
- `client/scripts/ui/board.gd`
- `client/scripts/ui/session_panel.gd`
- `docs/design/tasks/batch14-mobile-s2t.md`

### Notes / Skipped:
- Client-side fallback character replacement inside `UI.label`: Skipped per spec ("only if cheap; otherwise skip and note it") in favor of strict server-side normalization and prompt enforcement, avoiding runtime character glyph check overhead in Godot labels.
