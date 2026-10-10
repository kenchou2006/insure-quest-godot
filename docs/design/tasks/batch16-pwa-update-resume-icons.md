# Batch 16: PWA Update Button, Resume-Room Check, PWA Name, Android Icon

Touches `client/` and `server/` (worker + `server/tools/pack-web.mjs`, `server/tools/build-web.sh`). Hard rules from earlier batches apply (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working). Do not run terminal commands; Claude builds, tests on desktop and phone, and verifies.

## 1. 「★ 有新版本，點此更新」 shows when already up to date, and can reload repeatedly

`client/scripts/ui/menu.gd` ~L156-170 shows the button when `JavaScriptBridge.pwa_needs_update()` is true or `pwa_update_available` fires. Problems seen:
- It appears right after the new version has already loaded. Likely cause: `index.html`, `index.pck` etc. are served `no-cache` (see `_headers` written by `pack-web.mjs`), so the page already runs the new build, while the newly installed service worker is merely *waiting* → Godot reports "update available" although the running code is current.
- Pressing it several times triggers several reloads.

Fix:
- Introduce a real build version: `build-web.sh` / `pack-web.mjs` writes `version.json` (`{"version":"<build timestamp or git short sha>"}`) next to `index.html` with `Cache-Control: no-cache` in `_headers`, and stamps the same version into the client (e.g. inject `window.IQ_BUILD = "<version>"` into `index.html`, read via `JavaScriptBridge.eval`; the HTML is the build that is actually running).
- Show the button only when the fetched `version.json` (fetch with `cache: "no store"`) differs from the running `IQ_BUILD`. Check on menu open and when `pwa_update_available` fires; ignore `pwa_needs_update()` alone. If the versions are equal but a SW is waiting, silently activate it (no button, no reload).
- On press: disable the button immediately, change its label to 「更新中…」 (automation does not use this button), call `pwa_update()` once if a SW is waiting, otherwise `location.reload()` once. Guard with a `sessionStorage` flag (e.g. `iq-updating=<target version>`) so the page never reloads more than once per target version; clear it once the running version equals the target.
- Keep this web-only; native/editor unchanged.

## 2. 「回到進行中的房間 XXXXX」 shown for rooms that no longer exist

`menu.gd` ~L196 shows the resume button whenever `Net.saved_seat` (persisted in `user://` by `net.gd` ~L65-88) is non-empty; pressing it then fails with 「房間已不存在」. Fix: on menu build, if a saved seat exists, query the server first (the room Durable Object already has an `/info` endpoint returning 404 when the room is gone — `server/src/room.ts` ~L184; check how `server/src/index.ts` routes `/api/rooms/<code>/...` and expose a lightweight `GET /api/rooms/<code>/info` if not already reachable). Show the button only when the room exists, the game is not ended, and the saved `playerId` is still a player in it (return a minimal `{exists, phase, hasPlayer}`; do not leak other data). If the room is gone/ended or the player is not in it, clear `saved_seat` (and persist). While checking, show nothing (no flashing button); on network error keep the seat but don't show the button.

## 3. PWA name too long

The manifest name is 「INSURE QUEST 人生顧問局」 (from `config/name` in `client/project.godot`). Installed app labels get truncated. Set a short name: in `pack-web.mjs`, post-process `index.manifest.json` to `"name": "人生顧問局"`, `"short_name": "人生顧問局"` (Chinese only; keep `config/name` for the browser tab title). Also update `apple-mobile-web-app-title` / `application-name` meta tags in `html/head_include` (`client/export_presets.cfg`) to 「人生顧問局」.

## 4. Android icon still wrong (iOS OK)

The generated manifest only lists 144/180/512 icons, no 192 and no `maskable` icon, and still has the old `background_color` `#0b1f2a`; Android Chrome then shows a default/letter icon or a badly cropped one. The repo already has `client/icons/android/icon-192.png`, `client/icons/android/adaptive-foreground-432.png`, `client/icons/icon-512.png`, `client/icons/icon-foreground.svg`.
- In `pack-web.mjs`, copy the needed icon files into the web output (e.g. `icons/icon-192.png`, `icons/icon-512.png`, `icons/maskable-512.png`) and rewrite the manifest `icons` to: 192 `any`, 512 `any`, 512 `maskable` (maskable must have the artwork inside the central 80% safe zone on a full-bleed `#0d231e` background — generate it from `icon-foreground.svg` / the adaptive foreground with a tool script, or add a prepared PNG under `client/icons/android/maskable-512.png`; if you cannot render images, write the generator script (e.g. `server/tools/gen-maskable.mjs` using `sharp` if already available, otherwise document) and Claude will run it).
- Manifest `background_color` and `theme_color` → `#0d231e`; `export_presets.cfg` `progressive_web_app/background_color` to the same.
- Bump the service worker cache so installed PWAs pick up the new manifest/icons (pack-web already resets `CACHE_VERSION`; make sure the new icon files are in the SW cache list or excluded consistently).
- Note in the Completion Record that already-installed Android PWAs may need to be reinstalled to refresh the home-screen icon.

## 5. Ten-years-later letters still show the draft first

Batch 15 made the final coach comment wait for AI, but the letters in `client/scripts/ui/report.gd` still render the rule-based draft with the header 「AI 潤稿中……（先顯示草稿）」 and then swap in the AI version while `s.aiPending` is true. Apply the Batch 15 pattern: while the letters are pending for an AI player, show a waiting state in place of each letter body (「AI 正在撰寫十年後的來信……」 with the same subtle pulse used for the coach comment) and no draft text; render the letters once they arrive. On AI failure/timeout the server already falls back to the rule text — make sure `aiPending` is cleared in that case too (check `enrichCoach` in `server/src/game/game.ts` and the timeout), so the waiting state never hangs. Guests/bots/rules mode keep showing the rule letters immediately.

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### 1. 「★ 有新版本，點此更新」 shows when already up to date, and can reload repeatedly
- **Changes**:
  - `server/tools/pack-web.mjs`: Added build version determination (`IQ_BUILD` env var or `git rev-parse --short HEAD` with timestamp fallback). Emits `version.json` with `Cache-Control: no-cache` in `_headers`. Stamps `window.IQ_BUILD = "<version>"` into `index.html`.
  - `server/tools/build-web.sh`: Exports `IQ_BUILD` so Godot web export and `pack-web.mjs` share the identical build stamp.
  - `client/scripts/ui/menu.gd`: Refactored PWA update check. Now fetches `/version.json` with `{ cache: "no-store" }` on menu open and upon `pwa_update_available`. If the server version matches `window.IQ_BUILD`, any waiting Service Worker is silently claimed with `postMessage('claim')` without showing the button or reloading. The button is only displayed when server version differs and has not already been reloaded for in the current session. On press, disables the button immediately, sets label to 「更新中…」, records `sessionStorage.setItem('iq-updating', targetVersion)`, and calls `pwa_update()` / `location.reload()`. The sessionStorage flag is cleared once running version matches target. Web-only, guarded against editor and automation.
- **Files changed**:
  - `server/tools/pack-web.mjs`
  - `server/tools/build-web.sh`
  - `client/scripts/ui/menu.gd`

### 2. 「回到進行中的房間 XXXXX」 shown for rooms that no longer exist
- **Changes**:
  - `server/src/index.ts`: Updated `/api/rooms/<code>/(ws|info)` forward to preserve URL search params (`url.search`), enabling `?playerId=...` queries to reach the Durable Object.
  - `server/src/room.ts`: Updated `GET /info` endpoint to verify player presence and return minimal `{ exists, phase, hasPlayer }` without leaking additional room data; returns 404 if room does not exist.
  - `client/scripts/net.gd`: Added `check_saved_room(code, playerId)` to query `/api/rooms/<code>/info?playerId=...` over HTTP with error classification (`"valid"`, `"invalid"`, `"network_error"`).
  - `client/scripts/ui/menu.gd`: On menu build, places a dedicated empty `_resume_container` (no flashing button while checking). If a saved seat exists, calls `check_saved_room()`. If valid (`exists`, `phase != "ended"`, and `hasPlayer`), renders the resume button. If invalid (room 404, game ended, or player absent), clears `Net.saved_seat` and persists via `Net.save_prefs()`. On network error, retains `saved_seat` in prefs without rendering the button.
- **Files changed**:
  - `server/src/index.ts`
  - `server/src/room.ts`
  - `client/scripts/net.gd`
  - `client/scripts/ui/menu.gd`

### 3. PWA name too long
- **Changes**:
  - `server/tools/pack-web.mjs`: Rewrites `index.manifest.json` after Godot export to set `"name": "人生顧問局"` and `"short_name": "人生顧問局"` (keeping `client/project.godot` for the browser tab title).
  - `client/export_presets.cfg`: Added `<meta name="apple-mobile-web-app-title" content="人生顧問局"><meta name="application-name" content="人生顧問局">` into `html/head_include`.
- **Files changed**:
  - `server/tools/pack-web.mjs`
  - `client/export_presets.cfg`

### 4. Android icon still wrong (iOS OK)
- **Changes**:
  - `server/tools/gen-maskable.mjs`: Created generator tool script to composite `client/icons/icon-foreground.svg` within the 80% safe zone over a full-bleed `#0d231e` background. Outputs `client/icons/android/maskable-512.svg` and renders `client/icons/android/maskable-512.png` via `sharp`. No terminal commands were run during this task; Claude can run `node tools/gen-maskable.mjs` to render the PNG.
  - `server/tools/pack-web.mjs`: Copies `icons/icon-192.png`, `icons/icon-512.png`, and `icons/maskable-512.png` into the web output `icons/` folder (falls back to 512 PNG if maskable PNG has not yet been rendered). Rewrites `index.manifest.json` `icons` array to: 192 `any`, 512 `any`, 512 `maskable`. Updates `background_color` and `theme_color` to `#0d231e`. Injects icon files into `CACHED_FILES` in `index.service.worker.js` and resets `CACHE_VERSION`. Adds `/icons/*` caching rule to `_headers`.
  - `client/export_presets.cfg`: Updated `progressive_web_app/background_color` to `Color(0.05098, 0.137255, 0.117647, 1)` (`#0d231e`).
  - *Note*: Already-installed Android PWAs may need to be uninstalled and reinstalled from Chrome to refresh the cached home-screen icon.
- **Files changed**:
  - `server/tools/gen-maskable.mjs` (new)
  - `server/tools/pack-web.mjs`
  - `server/tools/build-web.sh`
  - `client/export_presets.cfg`

### 5. Ten-years-later letters still show the draft first
- **Changes**:
  - `server/src/game/types.ts`: Added `lettersPending?: boolean` to `FinalRow`.
  - `server/src/game/game.ts`: Set `lettersPending: aiWillBeUsed && hasLetters` in `endGame()`. In `enrichCoach()`, wrapped `ai.letter(...)` in `Promise.race` with a 25s timeout and guaranteed `row.lettersPending = false` in `finally`.
  - `server/src/room.ts`: In `finish()`, guards setting `g.aiPending = true` only when at least one human player has AI enabled, ensuring `aiPending = false` in `finally`.
  - `server/src/local/local-room.ts`: For local solo practice (guests with `RuleAI`), keeps `g.aiPending = false` so rule letters display immediately without flashing pending state.
  - `client/scripts/ui/ui.gd`: Added `pending: bool = false` parameter to `UI.letter_card()`. When `pending` is true, replaces the letter body text with a pulsing label 「AI 正在撰寫十年後的來信……」 (using the same subtle alpha tween as the coach feedback card, guarded with `@tool` and animation settings).
  - `client/scripts/ui/report.gd`: Removed draft notification header label 「AI 潤稿中……（先顯示草稿）". Determines `letters_pending` for logged-in AI players and passes it to `UI.letter_card()`. Once the AI version arrives, re-renders with the final content. Guests, bots, and rules mode immediately render the rule-based letters.
- **Files changed**:
  - `server/src/game/types.ts`
  - `server/src/game/game.ts`
  - `server/src/room.ts`
  - `server/src/local/local-room.ts`
  - `client/scripts/ui/ui.gd`
  - `client/scripts/ui/report.gd`

### Anything not done
- None. All items implemented according to specification. Terminal commands were avoided as instructed; `server/tools/gen-maskable.mjs` is prepared and ready for build execution.

