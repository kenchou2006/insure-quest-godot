# Batch 13: Floating Spectator Prediction and New-Player-Only Tutorial

Client only (`client/`). Hard rules from Batch 5/8/10-12 apply (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working: buttons keep their text). Do not run terminal commands; Claude compiles and screenshots.

## 1. Spectator prediction bar floats

`client/scripts/ui/session_panel.gd` `_render_spectator_prediction()` (~L789) adds the 「旁觀競猜（預測其評級，猜中聲望 +2）」 bar with S/A/B/C buttons as the first item inside the scrolling `_content`. Since Batch 12 the spectator view auto-scrolls to the newest content, so the bar scrolls out of sight right when it matters.

- Move it out of the scroll content into a floating strip pinned to the bottom of the session panel (overlaying the scroll area, above it in z-order, with a small margin and the panel's rounded style + shadow). Reserve bottom padding in the scroll content equal to the strip height so nothing is hidden behind it.
- Before predicting: compact one-line strip 「旁觀競猜：猜評級，猜中聲望 +2」 + S A B C buttons (keep button text exactly "S", "A", "B", "C"). Phone portrait: two lines if needed.
- After predicting: collapse to a small pill 「已預測［A］· N 人參與」 (still floating, no buttons). Hide the strip entirely once the step is `result` (the result screen already shows prediction hits).
- Only for spectators during discover / plan / objection, same condition as today. Pop-in when it first appears (`UI.pop_in`), no re-animation on every refresh.
- Must not cover the Batch 12 auto-follow target: when computing the auto-follow scroll target, treat the visible viewport height as (scroll height − strip height).

## 2. Tutorial only for new players

`client/scripts/ui/tutorial.gd` stores progress per device in `user://tutorial.cfg`, so an experienced player on a new device/browser sees the tutorial again.

New rule in `Tutorial.should_show(step_id, is_actor)`:
- Logged-in player whose account already has at least one finished game (`Net.get_level().get("games", 0) > 0`, see `net.gd` ~L212) → never show automatically.
- Logged-in player with 0 games, or guest → show unless the step is marked done in `user://tutorial.cfg` (current behaviour).
- 「重看教學」 in the game guide (`menu.gd` ~L587-609, `Tutorial.reset_all()`) must still force the tutorial for anyone, including veterans: write a `forced = true` flag in the cfg on reset; `should_show` returns true for a not-done step when `forced` is set; clear `forced` once all three steps (`discover`, `talk`, `plan`) are done.
- If the profile has not loaded yet when the first step would show (level dict empty while logged in), treat as unknown and do not show yet; it can show on the next refresh once the profile is known.
- Automation mode and editor behaviour unchanged.

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### Completed Items
1. **Floating Spectator Prediction Bar** (`client/scripts/ui/session_panel.gd`):
   - Moved the spectator prediction bar out of scrolling `_content` into a floating container pinned to the bottom of the session panel, styled with rounded corners, border, panel background, shadow, and bottom margin.
   - Before predicting: compact one-line strip 「旁觀競猜：猜評級，猜中聲望 +2」 with "S", "A", "B", "C" buttons; adapts to two lines on phone portrait layout.
   - After predicting: collapses to a compact pill 「已預測［A］· N 人參與」 (floating, no buttons).
   - Hides entirely when step is `result` or when the user is an actor.
   - Only shown for spectators during `discover` / `plan` / `objection` steps. Animated with `UI.pop_in` on first appearance, with no re-animation on subsequent refreshes.
   - Added reserved bottom spacer padding to `_content` equal to the strip height so scrolled content is never hidden behind the strip.
   - Updated auto-follow in `_smooth_scroll_to` to treat visible viewport height as `(scroll height − strip height)`, ensuring auto-follow targets are never covered by the floating strip.

2. **Tutorial Only for New Players** (`client/scripts/ui/tutorial.gd`):
   - Updated `Tutorial.should_show(step_id, is_actor)`:
     - Logged-in players with finished games (`Net.get_level().get("games", 0) > 0`) never see the tutorial automatically.
     - Logged-in players with 0 games or guests see the tutorial unless the step is marked done in `user://tutorial.cfg`.
     - When profile is not loaded yet (`Net.get_level()` is empty while logged in), treated as unknown and does not show until profile is known.
     - `Tutorial.reset_all()` sets `forced = true` in `user://tutorial.cfg` so "重看教學" forces the tutorial for all players (including veterans).
     - `Tutorial.mark_step_done()` clears `forced` once all three tutorial steps (`discover`, `talk`, `plan`) are done.
     - Editor hint and automation mode behaviors remain preserved.

### Files Changed
- `client/scripts/ui/session_panel.gd`
- `client/scripts/ui/tutorial.gd`
- `docs/design/tasks/batch13-prediction-tutorial.md`

### Anything Not Done
- None. All items in the specification are fully implemented.

