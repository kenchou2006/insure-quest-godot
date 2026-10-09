# Phone readability: larger text, no overlaps

Players report that on phones text is too small and sometimes overflows or overlaps images/borders.
Screenshots of every screen were rendered with the preview harness at real phone aspect ratios
(portrait 480x1040 canvas, landscape ~19.5:9). Fix the whole game for `phone_portrait` and `phone_landscape`.
Desktop and tablet must look exactly as they do now.

## 1. Phone font scale (central, not per screen)
Physical size math: a 390 CSS-px-wide phone shows the 480-wide portrait canvas at ~0.81x, so a 12 px label is ~9.7 CSS px (unreadable).
Target: body text >= 13 CSS px, secondary text >= 12 CSS px on a 390x844 phone.

- Add `static func fs(size: int) -> int` to `client/scripts/ui/ui.gd`:
  - `phone_portrait`: `maxi(roundi(size * 1.2), 15)`
  - `phone_landscape`: `maxi(roundi(size * 1.15), 15)`
  - otherwise: `size` unchanged.
- Apply it inside `UI.label`, `UI.rich`, `UI.button` (and any other UI helper that sets a font size), so every existing
  call site scales automatically. Also wrap the remaining direct `add_theme_font_size_override` calls and every
  `draw_string(..., font_size, ...)` in `board.gd`, `records.gd` (TrendChart), `session_panel.gd`, `game.gd` with `UI.fs()`.
  Do not double-apply (if a call site already passes a phone-specific size, keep the call but let fs() handle it — remove
  ad-hoc `if UI.is_phone_portrait()` font bumps only where they now double up).
- Phone landscape canvas: change `phone_landscape` content scale from 960x540 to 800x450 in `client/scripts/main.gd`
  (`_on_size_changed`) and in `client/scenes/preview/preview.gd` `SIZES`, so landscape UI is ~1.2x bigger physically.

## 2. Hard layout rules on phones
- No text may extend past its panel/button/card border, overlap an image, icon or another text, or be clipped mid-glyph.
- Long text wraps (autowrap Label inside a VBox or with a fixed/expand width — never an autowrap Label directly in an HBox
  without SIZE_EXPAND_FILL, it collapses to one character per line). Single-line labels that can be long use
  `text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS` with `clip_text = true` and a sensible min width.
- Cards/buttons with multi-line text must grow in height to fit their content (no fixed heights that clip).
- Horizontal rows that cannot fit at phone width wrap (HFlowContainer) or stack vertically.
- Self-drawn text (board tiles) must measure with `font.get_string_size()` and shrink, then ellipsize, to fit its rect; never draw
  text over the tile icon. If a tile is too short for ribbon + icon + name at a readable size (>= UI.fs(11)), drop the icon
  first, keeping ribbon and name.

## 3. Concrete problems seen in the screenshots (fix all, then re-check every other screen for the same patterns)
- Lobby (portrait): player rows wrap the tag badly — "電腦顧問・安安　電 / 腦", "你（王顧問）　房主 / （你）". Name and tag
  must stay on one line each (tag as a separate non-wrapping badge; name ellipsized if needed).
- Interview header (`session_panel.gd`, portrait): the step indicator's last box "4 結果預測" is cut off at the right edge;
  the twist badge "※ 長輩確診需長照" touches the border. Steps must fit 480 width (shorter labels on phone, e.g. "1 線索",
  "2 方案", "3 異議", "4 結果", or wrap), badges must wrap to a new line instead of overflowing.
- Interview plan (landscape): coverage card text is clipped at the card bottom ("降低治療與復健支出對目…"). Cards must grow.
- Board (landscape): tiles are short; the tile icon overlaps the place name (社區咖啡廳, 人生事件, 市場快訊…) and the ribbon
  text is ~9 px. Apply the board rules above.
- Board (portrait): long place names (社區咖啡廳, 客戶轉介紹, 共同工作空間, 顧問研討會) shrink to tiny text; with the new min
  size they must ellipsize or wrap to two lines inside the tile instead of overflowing.
- Status tab (portrait side panel): "動態" log has a fixed small height and the reaction buttons float mid-screen with a large
  empty area below; let the log expand to fill the remaining height on phones.
- Life event panel (`event_panel.gd`): option labels render as "【A:B】", "【B:C】", "【C:A】" and the scenario text appears twice
  (as subtitle and again in a box). Find the cause (label formatting / duplicated field) and show "A." "B." "C." and the text once.
- Event panel (landscape): a player token on the board is drawn above the event panel; the panel must be on top.
- Report header (portrait): "登入後可保存紀錄" + two buttons are cramped; let the hint wrap below the buttons on phones.

## Constraints
- Comments in English; player-facing text stays Traditional Chinese. No emoji.
- Godot 4.7, all UI scripts are `@tool`. Do not define methods named like native ones. `Button.flat = true` hides stylebox overrides.
- Do not change game logic, networking or server code.
- Do not run any shell commands. Work synchronously; do not start a background subagent.
- Report every file and function changed, and for each item in section 3 what you did.

---

## Round 2 (after re-rendering every screen with the round-1 changes)

Round 1 fixed the lobby, steps, event panel, report header and portrait header. Remaining / new problems:

1. **Board tile numbers are clipped to one digit** (portrait and landscape): tiles 10–23 show "1" or "2". The ribbon must
   always show the full index. Portrait ribbon: icon + full index (category word optional only if it fits). Measure and
   reserve the index width first, then fit/ellipsize the category text in the remaining space.
2. **Landscape board center overflows**: the dice box, "▶ 擲骰子" button and the legend extend past the inner rect and cover
   the bottom row of tiles. On phone landscape hide the legend, size the dice and button from the inner rect height, and
   make sure everything inside `_center` fits `get_inner_rect()` (check `_sync_center_bounds` and the center VBox min sizes;
   the center content must never be taller than the inner rect — shrink spacing/dice first). Check portrait center too.
3. **Landscape interview/event: give the panel the full width.** While the interview (`_session`) or event (`_event`) panel
   is open on phone landscape, hide the right side panel (`_side_panel`) and let the panel use the whole width; show the
   side panel again when they close.
4. **Landscape interview header is too tall** (~2/3 of the 450 px height): name, age/job, badges and goal wrap into a narrow
   column because the metric bars take the right side. On phone landscape use a compact header: row 1 = portrait + name +
   age/job (ellipsized) + badges; row 2 = goal (single line, ellipsized); row 3 = the five metric bars in one row.
   Target header height <= 120 px at the 800x450 canvas.
5. **Landscape main menu hero**: "INSURE QUEST" overflows under the right panel and the subtitle is cut off. Fit the hero
   texts to the left column width (shrink the title font to fit, wrap the subtitle lines).
6. **Inputs are not scaled**: LineEdit (顧問姓名, 房間代碼, interview free-text input, records filters), OptionButton
   (資深顧問 dropdown) and their placeholder text still use the small default size. Set phone font sizes for LineEdit,
   OptionButton, TextEdit and PopupMenu via `UI.make_theme()` using `UI.fs(16)` (and check any LineEdit created with a
   direct font override). The IME overlay in `web_text.gd` mirrors the LineEdit font size — keep it in sync.
7. **Plan allocation steppers (portrait)**: the − / + buttons stretch to ~100 px tall because the description beside them wraps
   to 3 lines. Put the description under the resource name spanning the row, and keep the − / + buttons square (~44 px).

Same constraints as above. Report each item.
