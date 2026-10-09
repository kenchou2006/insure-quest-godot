# Guest solo practice runs locally in the browser (no server room)

## Goal
Guests (not logged in) playing solo on the **web build** must not create a Room Durable Object.
The game runs entirely in the browser using the same TypeScript engine as the server.
Logged-in players (solo or multiplayer) keep using the server exactly as today. Multiplayer is already login-only.
The desktop (non-web) build keeps the current server path for guest solo — no change there.

## Server-side engine reuse (new file: `server/src/local/local-room.ts`)
Write `LocalRoom`, an in-browser equivalent of the **solo subset** of `server/src/room.ts`, speaking the
**same JSON message protocol** so the Godot client code does not change beyond the transport:
- Messages in: `hello`, `add_bot`, `settings`, `start`, `action`, `predict`, `react`, `abandon`, `ping`.
- Messages out: `welcome` (same shape as Room: playerId, spectator:false, static {board, questions, cards}, ai:false, me:null),
  `state` (via `publicView(game, playerId)`), `error`, `react`, `pong`, `closed` (on abandon).
- Reuse `createGame`, `addPlayer`, `startGame`, `applyAction`, `predict`, `publicView`, `enrichCoach`, `log`, `botAction`,
  `BOARD`, `CARDS`, `QUESTIONS` — do not copy game rules. AI: always `new RuleAI()` from `../ai.ts` (no LLM, no quota).
- Bot turns: replicate `scheduleBot()` timing with `setTimeout` (BOT_DELAY_MS 1300, BOT_READ_DELAY_MS 4500 while
  `turnStage === 'event'` or `session.step === 'result'`). No disconnect / AFK logic, no alarms, no records saved.
- When `phase` becomes `ended`, run `enrichCoach(g, () => new RuleAI())` like `Room.finish()` (set/clear `aiPending`, push state), but save nothing.
- Serialize message handling like `Room.run()` (a promise queue) because `applyAction` is async.
- Export `installLocalRoom()` which sets `window.iqLocal = { open(): void, send(text: string): void, drain(): string, close(): void }`:
  `open()` creates a fresh LocalRoom (code "LOCAL"), `send` takes a JSON string, `drain()` returns a JSON array string of
  queued outgoing messages and clears the queue (Godot polls it every frame), `close()` cancels timers and drops the room.
  Call `installLocalRoom()` at module top level so the bundle installs itself.
- Must not import `cloudflare:workers`, `room.ts`, `records.ts`, or `index.ts`.

## Godot client
- `client/scripts/net.gd`: add a local transport.
  - `func local_available() -> bool`: `OS.has_feature("web")` and `window.iqLocal` exists (use `JavaScriptBridge.eval("!!window.iqLocal", true)`).
  - `func join_local() -> void`: like `join()` but sets `_local = true`, `room_code = "LOCAL"`, calls `iqLocal.open()`
    (via `JavaScriptBridge.get_interface("iqLocal")`), and sends `hello` on the next frame.
  - `send()`: when `_local`, call `iqLocal.send(JSON.stringify(msg))` instead of the WebSocket.
  - `_process()`: when `_local`, call `iqLocal.drain()`, parse the JSON array, and pass each item (re-stringified) to `_handle()`.
    Skip all WebSocket/reconnect/ping logic in local mode. Emit `connection_changed(true)` once when local opens.
  - `is_online()` returns true in local mode. `leave()` calls `iqLocal.close()` and clears `_local`.
  - Never save a seat for local games (already true because `is_solo`).
- `client/scripts/main.gd` `create_and_join(solo_bots, solo)`: if `solo and not Net.is_logged_in() and Net.local_available()`,
  skip `Net.create_room` and call `Net.join_local()`; keep `_solo_bots`/`_solo`/`Net.is_solo` set the same way so the existing
  welcome → add bots → start flow runs unchanged. `leave_to_menu()` must not send `abandon` in local mode (just `Net.leave()`).
- The menu's guest note may mention "單人練習在本機執行" — keep player-facing text in Traditional Chinese.

## Constraints
- Comments and docs in **English**; player-facing strings stay Traditional Chinese.
- Godot 4.7, UI scripts are `@tool` (guard JavaScriptBridge calls with `OS.has_feature("web")` and `Engine.is_editor_hint()`).
- No emoji. Do not modify `room.ts`, `records.ts`, `index.ts` or the game rules.
- Do not touch build scripts; the bundling step (esbuild → `local-room.js` + `<script>` injection) is handled separately.
- Do not run any shell commands. Work synchronously; do not start a background subagent. Report every file and function you changed.
