# Batch 11: Pawn Avatars and Corner Tile Bands

Touches `server/` (small) and `client/`. Hard rules from Batch 5/8/10 apply to the client: `@tool` editor guards, no emoji, 4 layouts, keep `automation.gd` working. Do not run terminal commands; Claude compiles, runs tests and screenshots.

## 1. Pawn avatars (own + other players' Google photos)

Today the board pawns (`client/scripts/ui/board.gd` ~L356-410, "Draw player tokens") are coloured coins with the first character of the name. Show each player's avatar inside the pawn instead.

### Server: carry the Google picture URL into player state
- `server/src/room.ts`: `AccountHeader` is `{ id, name }` → add `picture?: string`. `Attachment` gets `accountPicture: string | null`, filled in the `/ws` handler next to `accountName`.
- `server/src/index.ts` ~L213: include `picture: user.picture` in the header JSON (only if it is an `https://` URL).
- `server/src/game/types.ts` `PlayerState`: add `avatar?: string | null` (Google photo URL; null for guests and bots). `addPlayer` in `server/src/game/game.ts` accepts and stores it; `room.ts` L220 passes `att.accountPicture`. Make sure `publicView` sends it to clients (check whether players are copied field by field). `server/src/local/local-room.ts` passes `null`.
- Keep `server/test/game.test.ts` passing; add one assertion that `avatar` round-trips through `addPlayer` → `publicView`.

### Client: avatar cache and drawing
- Add a small player-avatar cache (e.g. in `client/scripts/ui/portraits.gd` or a new static helper): `get_player_avatar(url) -> Texture2D` returns cached texture or null and starts one `HTTPRequest` download per URL (reuse the decoding approach in `net.gd` `fetch_avatar()` ~L220-294: jpg/png/webp sniffing). Emit a signal / call a callback when loaded so `board.gd` can `queue_redraw()`. Never retry a failed URL in the same session; max 4 concurrent requests. For the local player prefer `Net.avatar_tex` (already cached with TTL).
- In `board.gd` token drawing: if a texture is available, draw it clipped to the pawn circle (reuse `_draw_circle_texture()` in `board.gd`, but compute UVs for a cover crop so non-square images are not squashed), keep the existing gold rim, drop shadow, hop/squash animation (apply squash/stretch to the circle radii) and the white "current player" aura. Add a thin ring in the player's colour between photo and gold rim so players stay distinguishable. Fallback stays the current coloured coin with initial (guests, bots, failed downloads).
- Also use the avatar in the right-hand player list (`game.gd` scoreboard rows, the coloured dot before each name) when available — small round 18-22 px avatar replacing the dot, with the player colour as its ring.
- Editor/preview: no network in the editor (`Engine.is_editor_hint()`), fallback only.

## 2. Corner tile bands

`board.gd` ~L210-230: corner tiles (0, 6, 12, 18) draw two overlapping category bands (one horizontal, one vertical) as separate rounded boxes, so the corner where they meet looks lumpy/notched, and the bands' rounded ends do not follow the tile's rounded corner. Redraw the band on corner tiles as a single L-shaped band hugging the outer corner: the outer corner follows the tile's corner radius (8), the inner corner of the L is a clean rounded joint, both arms end with matching rounded caps. Simplest: build one polygon (outer rounded corner arc + straight arms + inner arc) and `draw_colored_polygon` with antialiasing, or draw the outer rounded rect clipped. Edge (non-corner) tile bands should also have their ends inset/rounded consistently with the tile card radius so they do not poke past the card corners.

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### Item 1: Pawn avatars (own + other players' Google photos)
- **Server changes**:
  - `server/src/room.ts`: Added `picture?: string` to `AccountHeader`, added `accountPicture: string | null` to `Attachment`, filled `accountPicture` from parsed header in `/ws`, passed `avatar: att.accountPicture` to `addPlayer` in the `hello` message handler.
  - `server/src/index.ts`: Included `picture: user.picture` in `ACCOUNT_HEADER` JSON forward when `user.picture` starts with `https://`.
  - `server/src/game/types.ts`: Added `avatar?: string | null` to `PlayerState`.
  - `server/src/game/game.ts`: `addPlayer` accepts and stores `avatar` (set to `null` for bots). In `publicView`, `avatar: p.avatar ?? null` is included in the mapped `players` state.
  - `server/src/local/local-room.ts`: Passed `avatar: null` in `addPlayer`.
  - `server/test/game.test.ts`: Added test asserting that `avatar` round-trips from `addPlayer` to `publicView` for both users and bots.
- **Client changes**:
  - `client/scripts/ui/portraits.gd`: Implemented player avatar cache (`_player_cache`, `_failed_urls`, `_in_flight`, `_queue`, max 4 concurrent `HTTPRequest` downloads). Reused header sniffing for jpeg/png/webp. Added `get_player_avatar(url)`, `add_player_avatar_callback(cb)`, and `remove_player_avatar_callback(cb)`. Favors `Net.avatar_tex` for local player. Editor guard (`Engine.is_editor_hint()`) prevents network requests.
  - `client/scripts/ui/board.gd`: Connected avatar loaded callbacks in `_ready()` / cleaned up in `_exit_tree()` to trigger `queue_redraw()`. In pawn token drawing, draws avatar clipped to pawn circle with squash/stretch elliptical deformation, thin ring in player colour between photo and gold rim, gold rim, drop shadow, and active player aura. Fallback remains coloured coin with initial. Updated `_draw_circle_texture` with cover-crop UV calculation for non-square textures.
  - `client/scripts/ui/game.gd`: Subscribed to avatar load events in `_ready()` / `_exit_tree()`. Replaced the colored dot before each name in the scoreboard rows with a small round 20px `UI.RoundTex` avatar framed by the player color ring when available; falls back to colored dot when null or in editor.

### Item 2: Corner tile bands
- `client/scripts/ui/board.gd`:
  - Replaced overlapping rounded rectangles on corner tiles (0, 6, 12, 18) with a dedicated `_draw_corner_tile_band()` drawing a single continuous L-shaped polygon hugging the outer corner. The outer corner follows the tile card's corner radius (8.0), the inner corner of the L is a clean rounded joint (radius 3.5), and both arms end with matching rounded caps (radius 3.5). Antialiased outline drawn with `draw_polyline`.
  - Edge (non-corner) tile bands now have ends inset by 5.0px and rounded with radius 3.5px (`band_sz * 0.5`) so they do not poke past the tile card corners.
  - Updated tile index label positioning for corner tiles to avoid colliding with the L-bands.

### Files Changed
- `server/src/room.ts`
- `server/src/index.ts`
- `server/src/game/types.ts`
- `server/src/game/game.ts`
- `server/src/local/local-room.ts`
- `server/test/game.test.ts`
- `client/scripts/ui/portraits.gd`
- `client/scripts/ui/board.gd`
- `client/scripts/ui/game.gd`
- `docs/design/tasks/batch11-pawn-avatars.md`

### Anything Not Done
- None. All requirements implemented as specified. No terminal commands were run.

