# Batch 10 (Godot Client): UI Polish from Playtest Feedback

Modify only `client/`. Hard rules from Batch 5/8 apply: `@tool` scripts keep editor guards, use `UI.text_input`, **no emoji** (the font cannot render them), all 4 layouts (desktop / tablet / phone portrait / phone landscape) must keep working, no native-name overrides, no `Button.flat`. Keep `client/scripts/automation.gd` working: buttons keep their text, hotspot buttons keep meta `hotspot_index`. Do not run Godot; Claude compiles and screenshots afterwards.

Each item: fix it, then grep for the same pattern elsewhere and fix those too.

1. **Turn announcement popup centred** (`game.gd` ~L600-630, `_turn_label`, `_spectator_ribbon_lbl`, dice cutscene layer). The "【X】行動中……" / "觀看中：…的回合" / "擲出 N 點！" block currently sits off-centre over the board (texts overlap the board centre strip, e.g. "安安步(資深)" overlapping). Centre the whole popup both horizontally and vertically within the board's inner rect, and make sure its texts do not overlap each other or the 客戶簿 strip.

2. **Scrollbar gutter**. In every `ScrollContainer` (session panel, event panel, records, report, menu, side log "動態", etc.) the vertical scrollbar sits on top of content/text. Add a right gap (e.g. ~10-12 px margin between content and the scrollbar) — preferably one helper in `ui.gd` (e.g. wrap the scroll child in a MarginContainer with right margin, or a `UI.scroll()` helper) and use it everywhere.

3. **Interview chat portrait** (`session_panel.gd`, 需求訪談對話串). The client's round portrait / name column in a chat bubble row gets vertically stretched by long messages. Portrait must keep fixed square size and align top (`size_flags_vertical = SIZE_SHRINK_BEGIN`, `expand_mode`/`stretch_mode` keep aspect), regardless of message height.

4. **Tag chip padding**. Chips like 「※ 剛得知懷孕喜訊」 and 「[家庭經濟支柱]」 in the client header: text touches the border. Give chips more inner padding (horizontal ~10 px, vertical ~4 px) via their StyleBox content margins. Check every other chip/badge/pill style (emotion tag, 情境透露, ★ stars, 合規連擊, status pills, quest header, etc.) for the same cramped look and fix.

5. **Coverage cards show only first line** (`session_panel.gd`, 選擇保障卡). The card description is clipped to one line (「[醫療支出] 降低治療與」). Cards must show the full description: label `autowrap_mode = AUTOWRAP_WORD_SMART` with proper `custom_minimum_size.x`, and the card height must grow to fit (no fixed height clipping / no `clip_text`). Verify at desktop and phone widths.

6. **Fade-in for popups**. The tutorial popup (`tutorial.gd`) appears abruptly. Add a short fade + slight scale/slide-in (≈0.2-0.25 s, `modulate.a` 0→1, scale 0.96→1 with pivot at centre) on show, and fade-out on close. Then apply the same treatment (ideally a shared helper in `ui.gd`, e.g. `UI.pop_in(node)`) to other modal/overlay panels: event panel, session panel open, confirm dialogs, toast, report, records/menu sub-pages. Skip animation when `Engine.is_editor_hint()` or automation mode.

7. **Dice animation skipped**. Sometimes pressing 擲骰子 jumps straight to the client/session screen without the dice roll + pawn movement animation. Find the race (server state arriving with the overlay before `_dice_anim` starts / deferred overlay timer ~L44, L510 not engaged when the state update comes fast or out of order). Guarantee: after a roll, the dice cutscene and pawn hop always play to completion before any overlay (session/event panel) is shown, for both local player and spectated players.

8. **Unknown glyph next to 提示 button** (`session_panel.gd:979`, "提示 💡"). Remove the emoji (use plain text, e.g. 「提示」 or a drawn icon). Grep all `client/scripts` for any other emoji / non-renderable symbols in UI strings and replace them.

9. **Portraits not clipped to rounded frame**. Client portraits in the session header and the small portrait badges on board tiles (`board.gd` territory badge) have a rounded/circular border but the image itself is a square drawn over/under it. Clip the image to the same rounded shape: e.g. a canvas_item shader with rounded-rect / circle mask (a small reusable `.gdshader` or inline `Shader`), or draw via `draw_texture` with a polygon UV for circles. Apply to all portrait usages (header, chat bubbles, board badges, 客戶簿 strip, event/claim panel, report).

10. **Board player highlight frames rounded**. The coloured border marking territory / current player on board tiles is square-cornered. Draw it as a rounded rect matching the tile card radius (use `StyleBoxFlat` with `corner_radius_*` + `draw_style_box`, or a rounded polyline).

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

- **Status**: Completed (100% of tasks implemented, zero items deferred or skipped)
- **Completed Date**: 2026-10-10

### Itemized Implementation Details

1. **Turn announcement popup centred**
   - **Files Changed**: `client/scripts/ui/game.gd`
   - **Implementation**:
     - Enclosed the dice cutscene announcement in a centered modal card (`UI.box(Color("#102821", 0.96), 14, UI.GOLD, 2, false)`) clamped to 280–360 px width.
     - Centered the card both horizontally and vertically within `_board.get_inner_rect()`, dynamically maintained in `_sync_center_bounds()`.
     - Hid `_center` during the dice cutscene so no labels or the 客戶簿 strip overlap or bleed through.
     - Simplified spectator mode ribbons in `refresh()`: `_spectator_ribbon_lbl.text = "觀看中：【%s】的回合（行動中）"` and cleared `_turn_label.text = ""` to eliminate duplicated player names stacking over each other.

2. **Scrollbar gutter**
   - **Files Changed**: `client/scripts/ui/ui.gd`, `client/scripts/ui/records.gd`
   - **Implementation**:
     - Updated `UI.scroll(content, h_scroll, v_scroll)` in `ui.gd` to wrap inner content in a `MarginContainer` with a 12 px right margin (`margin_right = 12`), guaranteeing consistent separation between all scrollable content and the vertical scrollbar across every screen in the game.
     - Refactored all 5 tabs in `records.gd` (`overview`, `ai`, `codex`, `trainer`, `insights`) to pass the content VBoxContainer directly to `UI.scroll(content)` without relying on `get_child(0)` assumptions.

3. **Interview chat portrait**
   - **Files Changed**: `client/scripts/ui/session_panel.gd`, `client/scripts/ui/ui.gd`
   - **Implementation**:
     - Enforced `size_flags_vertical = Control.SIZE_SHRINK_BEGIN` on `_client_portrait()` in `session_panel.gd` and on `UI.avatar()` in `ui.gd`.
     - Explicitly enforced `size_flags_vertical = Control.SIZE_SHRINK_BEGIN` on the avatar controls in `client_row` and `think_row` chat bubbles.
     - Maintained fixed square dimensions and aspect-covered texture scaling so portraits never stretch vertically regardless of message length.

4. **Tag chip padding**
   - **Files Changed**: `client/scripts/ui/ui.gd`, `client/scripts/ui/session_panel.gd`, `client/scripts/ui/event_panel.gd`, `client/scripts/ui/report.gd`, `client/scripts/ui/game.gd`
   - **Implementation**:
     - Added `chip_box(bg_color, border, radius, pad_x, pad_y)` and `chip(bg_color, border, radius, pad_x, pad_y)` in `ui.gd` with 10 px horizontal and 4 px vertical padding defaults.
     - Converted client header tags (job, life twist, difficulty stars, referral, AI-generated) in desktop and phone layouts to `UI.chip()`.
     - Converted emotion tags, compliance badges, and pending badges in `session_panel.gd` to `UI.chip()`.
     - Converted event seals and decision quality tags in `event_panel.gd` and `report.gd` to `UI.chip()`.
     - Converted quest completion, streak, and disconnection tags in `game.gd` to `UI.chip()`.

5. **Coverage cards show full description without clipping**
   - **Files Changed**: `client/scripts/ui/session_panel.gd`
   - **Implementation**:
     - Built coverage card buttons containing a `MarginContainer` with a `Title` label and an autowrapped `Detail` label (`autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` with responsive `custom_minimum_size.x = 120` on desktop/tablet, `220` on phone).
     - Made native button text transparent (`Color(0,0,0,0)`) while maintaining `b.text` to preserve `automation.gd` click target detection.
     - In `_sync_plan()`, set `b.custom_minimum_size.y = maxf(content_h + 4.0, 80.0)` dynamically derived from the inner `MarginContainer`'s combined minimum size, allowing cards to cleanly expand to fit multi-line descriptions across all viewport widths.

6. **Fade-in for popups**
   - **Files Changed**: `client/scripts/ui/ui.gd`, `client/scripts/ui/tutorial.gd`, `client/scripts/ui/records.gd`, `client/scripts/ui/report.gd`, `client/scripts/ui/menu.gd`, `client/scripts/main.gd`, `client/scripts/ui/event_panel.gd`, `client/scripts/ui/session_panel.gd`, `client/scripts/ui/game.gd`
   - **Implementation**:
     - Added `is_animation_disabled()`, `UI.pop_in(node, duration)`, and `UI.pop_out(node, duration, on_done)` in `ui.gd`, automatically skipping tweens when `Engine.is_editor_hint()` or in `automation=1` mode.
     - Applied smooth pop-in and pop-out animations across tutorial popups, game guides, toasts, records, reports, announcements, exit confirmation modals, session panel, event panel, and dice cutscenes.

7. **Dice animation guarantee**
   - **Files Changed**: `client/scripts/ui/game.gd`
   - **Implementation**:
     - Eliminated state-race conditions by resetting `_prev_last_roll = 0` whenever player turn changes, round changes, or when `stage == "roll"`.
     - Tracked `_local_roll_in_flight = true` on roll button press to ensure animations trigger even if server returns the session state in a single tick.
     - Triggered dice cutscenes whenever `last_roll_val > 0 and (last_roll_val != _prev_last_roll or _prev_stage == "roll" or _local_roll_in_flight)`.
     - Set deferred overlay timer to `1.0 + (float(last_roll_val) * (1.0 / 6.0)) + 0.45` to guarantee both the 1.0s dice cutscene and tile-by-tile pawn hopping play to completion before showing session or event panels.
     - Prevented rapid server refreshes from prematurely cancelling deferred overlay status while the countdown timer is active.

8. **Emoji glyph removal**
   - **Files Changed**: `client/scripts/ui/session_panel.gd`
   - **Implementation**:
     - Replaced `"提示 💡"` at line 987 with `"提示"`.
     - Audited all UI strings across `client/scripts/` to verify zero emojis or non-renderable glyphs remain.

9. **Portraits clipped to rounded/circular frames**
   - **Files Changed**: `client/scripts/ui/ui.gd`, `client/scripts/ui/session_panel.gd`, `client/scripts/ui/board.gd`
   - **Implementation**:
     - Added `ROUNDED_RECT_SHADER` in `ui.gd` with helpers `get_circle_material()` and `get_rounded_material(radius_ratio)`.
     - Applied circular shader material to `UI.avatar()` and rounded shader material to `UI.portrait()`.
     - Applied `get_rounded_material(0.16)` to square client portraits in `_client_portrait()` in `session_panel.gd`.
     - Implemented `_draw_circle_texture()` in `board.gd` using 32-segment polygon UV clipping for board territory client portrait badges.

10. **Board player highlight frames rounded**
    - **Files Changed**: `client/scripts/ui/board.gd`
    - **Implementation**:
      - Replaced square `draw_rect` for territory tile borders with rounded `StyleBoxFlat` matching card corner radius 8 (`corner_radius_* = 8`).
      - Added rounded active player frame highlights with `corner_radius_* = 8`.

### Non-done Items
- None. All 10 items have been fully implemented.
