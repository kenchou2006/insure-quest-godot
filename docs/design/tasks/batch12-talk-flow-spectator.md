# Batch 12: Faster Interview Talk Flow and Spectator Auto-Follow

Touches `server/` (small) and `client/`. Hard rules from Batch 5/8/10/11 apply to the client (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working: buttons keep their text). Do not run terminal commands; Claude compiles, runs `npm test` and screenshots.

## 1. Let the advisor pick the next message as soon as the client has answered

Current flow (需求訪談對話串, `client/scripts/ui/session_panel.gd` ~L830-930, server `server/src/game/game.ts` `case 'talk'` ~L740-820, AI `server/src/ai.ts` combined dialogue ~L240-260): one AI call returns a JSON with `answer`, `coachTip`, compliance and scores. Only `answer` is streamed (`partialJsonString(raw, 'answer')` → room broadcasts `{t:'stream', text}`, `room.ts` ~L97). The suggested-question buttons and the free-text input stay disabled (`_waiting_ai`, `sess.aiBusy`, `_streaming()`) until the whole call finishes, i.e. until the coach tip is also generated.

Wanted:
- As soon as the client's answer is complete, the advisor can already choose / type the next message.
- 「進入方案配置 →」 stays disabled until the client answer **and** the coach tip of every sent message have finished (no pending/queued talk, `aiBusy` false).

Design (keep the server's one-talk-at-a-time rule; do not run two AI calls on the same session concurrently):
- Server: detect when the `answer` string is closed in the partial JSON (add e.g. `partialJsonStringDone(raw, key)` or return `{text, done}` from the extractor; check `CombinedDialogueSchema` field order in `ai.ts` so `answer` is generated before `coachTip` — reorder the schema/prompt field list if needed). Broadcast `{t:'stream', text, answerDone: true}` once. Non-streaming providers / rule mode: no change needed (the whole result arrives at once).
- Client (`net.gd` stream signal + `session_panel.gd`): when `answerDone` arrives, re-enable the suggested-question buttons and free input for the actor (show the coach tip area as 「教練短評整理中……」 under that exchange). If the advisor sends while `aiBusy` is still true, queue the message client-side: show it immediately as the advisor's bubble with a small 「排隊中」 note, disable further input (one queued message max), and send it automatically when the state arrives with the previous exchange's coach tip (asked length increased, `aiBusy` false). Cancel/clear the queue on server error, on step change or when the session ends.
- If a talk action still reaches the server while `aiBusy` is true, the server must reject it with a clear message (verify there is such a guard in `case 'talk'`; add it if missing) — the client queue is the normal path.
- 「進入方案配置」 button: disabled while `aiBusy`, streaming, or a queued message exists; label stays the same text (automation relies on it).
- Add/adjust a server test for the `aiBusy` rejection in `server/test/game.test.ts`.

## 2. Spectator auto-follow

When watching another player's interview or event (`session_panel.gd`, `event_panel.gd`; spectator = `not _actor`), the spectator currently has to scroll manually. Make the panel follow the acting player automatically:
- After each refresh / stream update that changes content, smoothly scroll (tween `scroll_vertical`, ~0.3 s) so the most recently changed area is visible: discover → newest chat bubble / thinking bubble (and the scene explore area while clues are being found); plan → the coin allocation and card grid (scroll to the card grid once cards change); objection → the current objection; result → top of the result; event panel → the chosen option / result block.
- Use deferred scrolling after layout (`await get_tree().process_frame` or `call_deferred`), and `ensure_control_visible`-style targeting of the actual node, not a fixed pixel value.
- Do not fight the spectator: if they scrolled manually in the last 4 seconds, skip auto-follow until then.
- Only for spectators; the actor's own scrolling behaviour stays as it is (except item 1 above).

When finished, append a "Completion Record" section to this file listing each item, the files changed, and anything not done.

## Completion Record

### 1. Faster Interview Talk Flow
- **Server partial answer extraction & stream broadcast**:
  - Added and exported `partialJsonStringDone(raw: string, key: string): { text: string; done: boolean }` in `server/src/ai.ts`. Made `partialJsonString` delegate to it. Properly ignores escaped quotes inside string values.
  - Verified `CombinedDialogueSchema` in `server/src/ai.ts` generates `answer` before `coachTip`.
  - In `LLMAI.talk` (`server/src/ai.ts`), detected `answerDone` from `partialJsonStringDone` and invoked `onAnswer(res.text, true)` once, stopping subsequent delta streaming once `answer` finishes.
  - Updated `FallbackRawAI.talk`, `MockAI.talk`, and `MeteredAI.talk` in `server/src/ai.ts` and `RawAI`/`AIService` in `server/src/rule-ai.ts` to accept and forward `onAnswer(partial, answerDone)`.
  - In `server/src/room.ts`, `makeCtx` flushes the stream buffer immediately and broadcasts `{ t: 'stream', text, answerDone: true }` upon receiving `answerDone`.
- **Server `aiBusy` guard**:
  - Added guards in `server/src/game/game.ts` (`case 'talk'`, `case 'to_plan'`, `case 'ask'`, `case 'ask_free'`) returning `'客戶正在回應中，請稍候'` when `sess.aiBusy` is true.
  - Wrapped `ctx.ai.talk` in `try { ... } finally { sess.aiBusy = false; }` to guarantee `aiBusy` reset on error.
  - Added unit test in `server/test/game.test.ts` verifying concurrent action rejection while `sess.aiBusy` is true and testing `partialJsonStringDone`.
- **Client talk queue & early re-enable**:
  - In `client/scripts/net.gd`, added `signal stream_answer_done()`, emitted when `answerDone: true` arrives in stream messages.
  - In `client/scripts/ui/session_panel.gd`, connected `Net.stream_answer_done` and handled `_on_stream_answer_done()`.
  - Re-enabled suggested-question buttons and free input as soon as `_stream_answer_done` is true (when `talkLeft > 1`).
  - Added advisor message queue `_queued_talk`: shows immediately in dialogue thread with `（排隊中）` badge and `（教練短評整理中……）` under the in-flight exchange.
  - Auto-sends queued message in `refresh()` as soon as the previous exchange finishes (`asked` length increments and `aiBusy` is false).
  - Clears `_queued_talk` on server error, step change, or session switch.
  - Preserved 「進入方案配置 →」 button text verbatim and kept it disabled while `sess.aiBusy`, `_streaming()`, or `_queued_talk` exists.

### 2. Spectator Auto-Follow
- **Manual scroll detection & 4-second timeout**:
  - Added `_on_scroll_input(event)` in both `client/scripts/ui/session_panel.gd` and `client/scripts/ui/event_panel.gd` listening to mouse wheel, pan gestures, and mouse dragging on both the `ScrollContainer` and its `VScrollBar`.
  - Cancels running tweens and records `_last_manual_scroll_time`. Auto-follow checks `now - _last_manual_scroll_time < 4.0` and skips smoothly if manual scroll happened within 4 seconds.
- **Smooth scrolling with target node bounds**:
  - Implemented `_auto_follow_deferred(target: Control)` waiting 1 frame (`await get_tree().process_frame`) for Godot layout pass.
  - Implemented `_smooth_scroll_to(target: Control, duration: float = 0.3)` calculating difference between viewport global rect and target global rect, handling controls taller than viewport by aligning top, clamped to scrollbar min/max, animated via ease-out tween.
- **Section and node targeting in `session_panel.gd`**:
  - `discover`: follows thinking bubble / streaming label, queued advisor bubble, pending row, clues explore section when new clues are discovered, or newest client exchange row.
  - `plan`: follows coin allocation section initially, and card grid once cards change.
  - `objection`: follows current objection section.
  - `result`: follows top of result.
- **Node targeting in `event_panel.gd`**:
  - `dilemma`: follows chosen option button, or outcome panel once outcome is revealed.
  - `review`: follows chosen option button, or outcome panel once outcome is revealed.
  - `quiz`: follows chosen option button.
  - `lines`: follows latest event feedback lines.
  - `claim`: follows claim service card with result seal and progress bar.
  - `checkup`: follows checkup card.
- **Hard rules adherence**:
  - All signal connections, tweens, and input hooks guarded with `if not Engine.is_editor_hint():`.
  - No emojis used.
  - Four responsive layouts intact.
  - All button texts preserved for `automation.gd`.
  - No terminal commands run.

### Files Changed
- `server/src/rule-ai.ts`
- `server/src/ai.ts`
- `server/src/room.ts`
- `server/src/game/game.ts`
- `server/test/game.test.ts`
- `client/scripts/net.gd`
- `client/scripts/ui/session_panel.gd`
- `client/scripts/ui/event_panel.gd`
- `docs/design/tasks/batch12-talk-flow-spectator.md`

### Anything Not Done
- None. All items from the task specification have been fully implemented.
