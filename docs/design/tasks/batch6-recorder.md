# Batch 6: Playwright Demo Recorder (raw footage for the 3-minute video)

Goal: a teammate edits the video; we give them **reproducible, clean raw clips** of the key moments, recorded by a script instead of by hand. Prerequisites: Batch 4 (demo code, `settings.demo` seed) and Batch 5 item 8 (`window.iqAuto` automation bridge, `?automation=1&demo=1`).

Create a standalone folder `tools/demo-recorder/` (own `package.json`, do not add Playwright to `server/`). Add `tools/demo-recorder/node_modules/` and `recordings/` to `.gitignore`.

## Files
- `package.json`: devDependency `playwright` (pin an exact version), script `"record": "node record.mjs"`.
- `record.mjs` (ESM, Node 22, no TypeScript build step).
- `README.md`: setup (`npm i && npx playwright install chromium`), usage, flags, and tips for the editor (below).

## Behaviour
- `node record.mjs [--url http://127.0.0.1:8787] [--size 1920x1080] [--headless] [--scenes menu,interview,result,trainer] [--code CARDIF-DEMO-2026]`.
- Default headed Chromium (WebGL is more reliable headed), viewport = `--size`, `deviceScaleFactor: 1`, `recordVideo: { dir, size }` at the same size. Launch args: `--autoplay-policy=no-user-gesture-required`.
- Open `${url}/?automation=1&demo=1` and wait until `window.iqAuto` exists (timeout 60 s, Godot load).
- Helpers built on the bridge: `waitFor(text)` (poll `iqAuto.find` every 200 ms), `click(text)` (move the mouse in ~15 steps to the button centre, short pause, click — smooth cursor motion looks better on video), `typeHuman(text)` (focus the DOM `#iq-input` overlay and type with ~90 ms per char), `hold(ms)` (pause so the editor has breathing room; default 1500 ms after each important beat).
- Show a visible cursor: inject a small CSS dot that follows `mousemove` (Playwright does not render the OS cursor in video).
- Login: if the menu shows 「評審體驗碼」, use `--code` (or env `DEMO_CODE`); otherwise use 測試登入 when available (local dev).

## Scenes (each writes a chapter marker: `{ scene, label, start, end }` seconds from video start)
1. `menu`: title/menu visible 3 s → enter judge code → toast.
2. `interview`: start solo (2 bots, 資深) → roll dice → (demo seed lands on the mortgage client) → click 2 scene hotspots (find their positions via `iqAuto.list()`; the bridge should expose hotspot rects with text like the clue title or `hotspot:<n>`) → type the violation line 「這張保單保證年報酬 6%，比定存穩賺不賠」 → wait for the red light → hold 3 s → type a compliant question 「如果收入中斷三個月，家裡哪些支出一定要先顧住？」 → click one suggested question.
3. `result`: go to plan → set coins (cash/protect/growth via ＋/－) and pick 2 cards matching the mortgage client → objection: pick the best option → result: scroll slowly (mouse wheel in small steps) through stress test, the 10-year timeline chart, and the letter (complaint version because of the violation) → hold 4 s on the chart and on the letter.
4. `trainer` (optional, only if the logged-in user is a trainer locally via `TRAINER_EMAILS` + test login): open 培訓紀錄 → heatmap tab → hold 4 s.
- After all scenes: close the context to flush the video, rename to `recordings/<YYYYMMDD-HHmm>/raw.webm`, write `chapters.json`, and if `ffmpeg` is on PATH also cut `NN-<scene>.mp4` per chapter (H.264, CRF 18, 30 fps) — skip cutting with a message if ffmpeg is absent.
- Any step timing out: save a screenshot `error-<scene>.png`, print which text it was waiting for, exit 1.

## README tips for the editor (write these)
- Playwright's built-in video is compressed (good for drafts and timing). For final-quality footage run the script headed and capture the window with OBS / QuickTime at 60 fps at the same time; the script gives the exact same sequence every time.
- AI replies differ between runs; with `AI_PROVIDER=mock` in `server/.dev.vars` they are fixed (use for rehearsals), use the real provider for the final take.
- Each scene can be re-recorded alone with `--scenes`.

## Finish
Append a "Completion Record" to this file. Do not run `npm install` if you cannot; Claude will install and run it.

## Notes from Claude's manual run of the bridge (read before writing record.mjs)
- `window.iqAuto.list()` / `find()` / `screen()` return plain JS objects (already parsed). Coordinates are page CSS pixels — pass them straight to `page.mouse`.
- `list()` also returns elements scrolled **outside** the viewport (e.g. y > innerHeight inside the interview panel). Before clicking, if the target centre is outside `[0, innerHeight]`, move the mouse over the session panel and `page.mouse.wheel(0, ±300)` in steps, re-querying `find()` until it is inside.
- The auth card is filled asynchronously (~3–8 s after load). Wait until `find('評審體驗碼')` or `find('登出')` exists before deciding how to log in. `?code=<CODE>` in the URL logs in automatically (the URL is cleaned afterwards); prefer that over typing the code.
- The text input is a real DOM `<input id="iq-input">` that only appears after clicking the Godot field (`find('輸入你想向客戶')`). Click it first, then `page.keyboard.type(text, { delay: 90 })` into `#iq-input`, then click 「送出」.
- AI replies take 5–15 s: after sending, wait until a new client bubble arrives — poll `screen()` / a button that only exists when idle (the suggested-question buttons are re-rendered) — with a 45 s timeout.
- Plan step: `＋` buttons are disabled (not listed) while 0 coins remain; press `－` first. Coverage cards are listed with their multi-line text (e.g. starts with 「工作能力防線」, 「家庭責任防線」 — right for 劉家豪).
- After 「提交方案」 the objection options are shuffled; pick the one whose text starts with 「投資照樣留著長期成長」 (best answer for 劉家豪).
- Result page: scroll to the 「十年財務人生」 chart and the 申訴副本 letter; then 「繼續 →」.

## Completion Record

- **Date**: 2026-10-09
- **Files Added**:
  - `tools/demo-recorder/package.json`: Standalone npm module, pinned devDependency `playwright@1.49.1`, `"record": "node record.mjs"`.
  - `tools/demo-recorder/record.mjs`: Pure ESM (Node 22) automation recorder script implementing:
    - CLI options: `--url`, `--size`, `--headless`, `--scenes`, `--code`.
    - Headed Chromium with WebGL reliability, `--autoplay-policy=no-user-gesture-required`, matching viewport & recording resolution.
    - Automation bridge connection (`window.iqAuto` with 60 s load timeout).
    - Smooth 15-step cursor movements, visible CSS cursor dot with click pulsation animation.
    - Out-of-viewport element scrolling via mouse wheel before clicking (Claude Note #38).
    - Prioritized `?code=<CODE>` query param login without page reload, with dialog typing fallback (Claude Note #39).
    - DOM `#iq-input` overlay human typing with 90 ms delay (Claude Note #40).
    - 4 scripted scenes:
      1. `menu`: 3 s title hold, demo code auth toast.
      2. `interview`: solo practice against 2 senior bots, dice roll, mortgage client (劉家豪), 2 hotspots, violation line + red light 3 s hold, compliant question + 45 s AI poll, suggested question.
      3. `result`: coin adjustment (`－` first per Note #42), 2 coverage cards (`工作能力防線`, `家庭責任防線`), best objection (`投資照樣留著長期成長` per Note #43), slow wheel scrolling through stress test, 10-year timeline chart (4 s hold), complaint letter (4 s hold), continue button.
      4. `trainer`: records screen, weakness heatmap tab (4 s hold, gracefully skipped if user is not a trainer).
    - Chapter markers exported to `recordings/<YYYYMMDD-HHmm>/chapters.json`.
    - Video flushed to `recordings/<YYYYMMDD-HHmm>/raw.webm` upon context close.
    - Automatic per-chapter MP4 cutting via `ffmpeg` (H.264, CRF 18, 30 fps) when available on PATH.
    - Timeout error handling with `error-<scene>.png` screenshot and descriptive error messages.
  - `tools/demo-recorder/README.md`: Setup instructions (`npm i && npx playwright install chromium`), usage guide, CLI parameters, and practical editor tips (OBS / QuickTime 60 fps concurrent capture, `AI_PROVIDER=mock` rehearsals, single scene re-recording).
- **Files Modified**:
  - `.gitignore`: Appended `tools/demo-recorder/node_modules/` and `recordings/`.

### Claude verification (2026-10-09)
`npm i && npx playwright install chromium`, then `node record.mjs --url http://localhost:8788 --headless --size 1280x720 --code CARDIF-DEMO-2026 --scenes menu,interview,result` completed: 89 s `raw.webm` + `chapters.json` (ffmpeg not installed, so no per-scene mp4). Frames checked: visible cursor, typed violation line, red light, grade C result, timeline chart, complaint letter. Fix applied: `waitFor` also matches on-screen labels via `iqAuto.findText`. The `trainer` scene was not run.
