# Batch 18: Skip the Tutorial After Local Play

Client only (`client/`). Hard rules from earlier batches apply (`@tool` guards, no emoji, `automation.gd` keeps working). Do not run terminal commands; Claude compiles and verifies.

## Problem
`client/scripts/ui/tutorial.gd` `should_show()` (~L80) skips the tutorial when the step is marked done locally, or the logged-in account has `games > 0`. It does not know whether this device has already played: a guest who played solo but left before a step appeared (e.g. never reached 方案配置) gets that step again, and a 0-game account logging in on a device where a guest already played also gets it.

## Change
- Record local play in `user://tutorial.cfg`: a counter `local_games` (section `progress`), incremented once per finished game on this device — solo or multiplayer, guest or logged in — when the game reaches `phase == "ended"` and the report is shown (`client/scripts/main.gd` ~L287 `"ended"` branch, or `report.gd` `_ready`). Guard so one game counts once (e.g. remember the room code / game id of the last counted game in the same cfg). Also count it when the player completed at least one interview as actor in a game they later left (optional; if cheap: increment on the first interview `result` step reached as actor, once per room).
- `should_show()`: after the existing `is_step_done` / `is_forced` checks, return false when `local_games > 0` (before the logged-in account check). Order stays: done step → no; forced → yes; local play → no; account games > 0 → no; profile not loaded → no; else yes.
- `reset_all()` (「重看教學」) keeps forcing the tutorial regardless of `local_games` (forced wins); do not reset the counter.
- Editor / automation mode unchanged (no writes in the editor).

When finished, append a "Completion Record" section to this file listing the changes and the files touched.

## Completion Record
- Implemented `get_local_games()`, `record_game()`, and `record_local_game()` in `client/scripts/ui/tutorial.gd` reading and writing `user://tutorial.cfg` under section `progress` (`local_games` counter and `last_game_id` guard).
- Updated `Tutorial.should_show()` to return false when `local_games > 0` after `is_step_done` and `is_forced` checks and before logged-in account checks, adhering strictly to the required precedence order (done step -> no; forced -> yes; local play -> no; account games > 0 -> no; profile not loaded -> no; else yes).
- Maintained `reset_all()` behavior so forcing tutorial continues to take precedence over `local_games` without resetting the `local_games` counter.
- Added game session token tracking in `client/scripts/net.gd` (`_game_id`, `_local_game_count`, `get_game_id()`) for both multiplayer/server room codes and unique local session tokens.
- Hooked `Tutorial.record_game()` in `client/scripts/main.gd` on `"ended"` phase transition and in `client/scripts/ui/report.gd` `_ready()`.
- Hooked `Tutorial.record_game()` in `client/scripts/ui/session_panel.gd` when the actor reaches interview `result` step, guarded against counting multiple times per room.
- Maintained `@tool` guards and editor safety (no writes in editor mode), ensured `automation.gd` compatibility, and avoided emoji.

Files Touched:
- `client/scripts/ui/tutorial.gd`
- `client/scripts/net.gd`
- `client/scripts/main.gd`
- `client/scripts/ui/report.gd`
- `client/scripts/ui/session_panel.gd`
- `docs/design/tasks/batch18-tutorial-local-games.md`
