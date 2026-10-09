# Mobile Portrait Board: Switch to Rectangular Tiles to Fill Height

Current screenshot: `docs/design/tasks/mobile-shots/board_phone_round1.png` (480x854). The board is square, constrained by width (~68px per tile), leaving ~160px blank space above and below, and text is still too small.

## Tasks (Modify `client/scripts/ui/board.gd` only, and `game.gd` if necessary)
- When `UI.is_phone_portrait()`, tile width `cw = size.x / COLS`, tile height `ch = minf(size.y / COLS, cw * 1.7)`, board overall `cw*7 x ch*7` centered. Desktop/tablet retains current square (`cw == ch`), with behavior completely unchanged.
- All places using geometry must consistently switch to cw / ch: `get_inner_rect()`, `tile_rect()`, `_point_on_ring()`, piece positions and jumping, tile drawing inside `_draw`, click detection (if any). Search the entire file for every `minf(size.x, size.y)` and `cw`.
- With taller tiles in phone portrait: icons enlarge (calculated based on `min(cw, ch)`), color band and location name font size can increase by 1–2 points (location name 13–15; text width still must not exceed tile width, reduce font size if too long).
- Central area (`get_inner_rect`) will become a vertical rectangle; `game.gd`'s `_sync_center_bounds` already uses it for positioning, verify that the central dice rolling area remains centered without overlapping.
- Game piece size calculated using `min(cw, ch)`, do not distort.

## Constraints
- Godot 4.7, `@tool`, no emojis, do not define methods with same name as native engine methods (e.g. `draw_ellipse`).
- Modify only the above scope; do not touch other features or server, do not add any network messages.
- Do not run any shell commands. Work synchronously; do not start a background subagent. List modified functions upon completion.
