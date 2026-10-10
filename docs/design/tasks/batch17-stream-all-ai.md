# Batch 17: Stream Every AI Text to the Screen

Touches `server/` and `client/`. Hard rules from earlier batches apply (`@tool` guards, no emoji, 4 layouts, `automation.gd` keeps working: buttons keep their text). Do not run terminal commands; Claude compiles, runs `npm test` and verifies. Builds on Batch 12 (talk streaming + `answerDone`), Batch 14 (`s2t` on streamed text) and Batch 15/16 (waiting states for AI text).

## Goal
Every AI-written text the player waits for should appear progressively (typed out as it is generated) instead of a waiting placeholder followed by the whole text at once. Today only the client's dialogue `answer` streams.

## Current plumbing (reuse it)
- `server/src/ai.ts`: `LLMAI.ask(schema, system, user, maxTokens, onText?)` — NIM provider streams via `askStream` and calls `onText(rawAccumulatedJson)`; `partialJsonString` / `partialJsonStringDone(raw, key)` extract a string field from incomplete JSON (already applies `s2t`). Workers AI and rule/mock providers do not stream (they return at once) — that must keep working.
- `server/src/room.ts` `makeCtx`: throttled broadcast `{t:'stream', text, answerDone?}` to all connections.
- Client `client/scripts/net.gd` emits `stream_text` / `stream_answer_done`; `session_panel.gd` renders the partial answer in the thinking bubble.

## Changes
1. **Generic keyed stream channel.** Generalise the room broadcast to `{t:'stream', key, text, done?}` where `key` identifies the target, e.g. `talk` (keep current behaviour + `answerDone`), `hint`, `objection`, `seminar:<playerId>`, `coach:<playerId>` (final debrief), `letter:<playerId>:<clientId>`, `market`. Keep the throttle per key (~80-120 ms) and always flush the final text. Keep backwards compatibility for `talk` so the Batch 12 queue logic is untouched (or update it consistently).
2. **Server: pass `onText` through for each AI feature** and extract the human-readable field from the partial JSON with `partialJsonString` (pick the field that is shown: hint text, objection feedback/comment, seminar tip, debrief comment, letter body, market headline). Add an optional `onStream?: (key, text) => void` (or similar) to the AI methods in `ai.ts`, the `AIService` wrappers (`FallbackRawAI`, `MeteredAI`, rule/mock providers ignore it), and call them from `game.ts` / `room.ts` with the right key. The authoritative final text still comes from the validated result (normalised, `s2t`), which replaces the streamed text when the state update arrives.
3. **Client: render partial text in place.** In every place that now shows a waiting state for AI text (Batch 15/16: 「AI 教練評語產生中……」, letters 「AI 正在撰寫十年後的來信……」, hint 「教練思考中……」, objection 「AI 講師評分中……」, seminar / event panels), subscribe to the keyed stream and, as soon as the first chunk arrives, replace the placeholder with the growing text (same label, update `.text` only — no rebuild, no flicker, same pattern as `_think_label` in `session_panel.gd`). Spectators see the same streamed text. When the final state arrives, swap to the authoritative text silently (it will usually be identical).
4. **Typing feel when the provider does not stream.** If the result arrives in one piece (Workers AI fallback, or a stream that only produced the final chunk), reveal it with a short typewriter effect (`visible_ratio` tween, ~25-40 chars/s, capped at 1.5 s; skip in automation mode and the editor) so it still feels progressive. Do not apply the typewriter to text that already streamed.
5. **Certificate / waiting rules stay.** 「儲存圖片」 stays disabled until the final coach comment is in the state (not just streamed). Batch 12 rules for 「進入方案配置」 unchanged.
6. **Tests:** server test with a fake streaming provider for one non-talk feature (e.g. hint or debrief) asserting the keyed stream callback receives growing partial text and the final state holds the validated text; `partialJsonString` coverage for the new fields if needed.

When finished, append a "Completion Record" section to this file listing each AI feature, whether it now streams or uses the typewriter fallback, the files changed, and anything not done.


## Completion Record

### AI Features and Streaming / Typewriter Status
| AI Feature | Stream Key | Progressive Stream Support | Typewriter Fallback (Non-streaming) | Details |
|---|---|---|---|---|
| Client Dialogue Answer (`talk`) | `talk` | Yes (NIM streaming with `partialJsonStringDone(..., 'answer')`, backward-compatible `stream_text` & `answerDone`) | Skipped (handled by talk queue/bubble) | In place typing in `_think_label`, queue logic preserved. |
| AI Coach Hint (`hint`) | `hint` | Yes (NIM streaming with `partialJsonStringDone(..., 'content')`) | Yes (`UI.typewriter`, ~30 chars/s, clamped [0.25, 1.5]s) | In-place reveal in `_hint_label` inside coach hint panel. |
| Free Objection Response Grading (`objection`) | `objection` | Yes (NIM streaming with `partialJsonStringDone(..., 'body')`) | Yes (`UI.typewriter` on `rep.body` in `_build_result`) | In-place feedback reveal in `_obj_think_label`, typewriter on debrief body if not streamed. |
| Market News Event (`market`) | `market` | Yes (NIM streaming with `partialJsonStringDone(..., 'text')`) | Yes (`UI.typewriter` in `event_panel.gd`) | Streams into `_body_label` in event panel; typewriter fallback if not streamed. |
| Seminar Coach Tip (`seminar`) | `seminar:<playerId>` | Yes (NIM streaming with `partialJsonStringDone(..., 'text')`) | Yes (`UI.typewriter` in `event_panel.gd`) | Streams into `_body_label` in event panel; typewriter fallback if not streamed. |
| Endgame AI Coach Feedback (`debrief`) | `coach:<playerId>` | Yes (NIM streaming with `partialJsonStringDone(..., 'body')`) | Yes (`UI.typewriter` in `report.gd`) | Streams into both `_coach_label` and certificate card `_cert_coach_label`; "儲存圖片" remains disabled until authoritative state arrives. |
| Letter from 10 Years Later (`letter`) | `letter:<playerId>:<clientId>` | Yes (NIM streaming with `partialJsonStringDone(..., 'content')`) | Yes (`UI.typewriter` on `LetterBodyLabel`) | Streams into `LetterBodyLabel` in letter card in `report.gd`; typewriter fallback if not streamed. |

### Files Changed
1. `server/src/rule-ai.ts`
   - Added optional `onStream?: (text: string, done?: boolean) => void` parameter to `RawAI` and `AIService` interface methods (`freeQuestion`, `letter`, `gradeObjection`, `marketNews`, `coachTip`, `hint`, `debrief`).
   - Updated `RuleAI` implementations to accept and ignore/support `onStream`.
2. `server/src/ai.ts`
   - Updated `LLMAI` methods (`freeQuestion`, `letter`, `gradeObjection`, `marketNews`, `coachTip`, `hint`, `debrief`) to wire `onText` callback to `ask()` and extract partial JSON fields via `partialJsonStringDone` (`'answer'`, `'content'`, `'body'`, `'text'`).
   - Updated `FallbackRawAI`, `MockAI`, and `MeteredAI` to propagate `onStream`.
3. `server/src/room.ts`
   - Generalised `makeCtx` streaming into a per-key throttled streaming channel (~100ms window per slot) emitting `{ t: 'stream', key, text, done?, answerDone? }`.
   - Guaranteed immediate flush on `done` and `endStream()`.
   - Updated `finish()` to pass streaming callback to `enrichCoach` and flush via `ctx.endStream()`.
4. `server/src/game/types.ts`
   - Added optional `clientId?: string` property to `FinalRow['letters']`.
5. `server/src/game/game.ts`
   - Updated `Ctx` definition with keyed `onStream?: (key: string, text: string) => void`.
   - Wired keyed streaming callbacks in `resolveTile` (`market`, `seminar:${p.id}`), `applyActionInner` (`talk`, `objection`, `hint`), and `enrichCoach` (`coach:${row.playerId}`, `letter:${row.playerId}:${c.id}`).
   - Populated `clientId` in `letters` array in `endGame`.
6. `server/test/game.test.ts`
   - Added tests for `partialJsonStringDone` covering `'body'`, `'content'`, and `'text'` extraction from partial and complete JSON.
   - Added unit test simulating streaming provider for `hint`, `debrief`, and `letter`, asserting stream chunks are received and final state holds validated text.
7. `client/scripts/net.gd`
   - Added `signal stream_chunk(key: String, text: String, done: bool)`.
   - Updated `_handle("stream")` to emit `stream_chunk(skey, stext, sdone)` for all stream keys, while preserving `stream_text` and `stream_answer_done` for `key == "talk"`.
8. `client/scripts/ui/ui.gd`
   - Added `static func typewriter(lbl: Label, text: String, already_streamed: bool = false) -> void` helper with rate ~30 chars/s, clamped [0.25, 1.5]s, skipped if `already_streamed`, `Engine.is_editor_hint()`, or `is_animation_disabled()`.
   - Assigned `name = "LetterBodyLabel"` on both pending and content labels in `letter_card()`.
9. `client/scripts/ui/session_panel.gd`
   - Connected `Net.stream_chunk` in `_ready()` to handle `"hint"` and `"objection"`.
   - Updated `_render_coach_hint()` to display streaming text in place and apply typewriter fallback when final state arrives.
   - Updated `_build_objection()` to display progressive streaming text in `_obj_think_label`.
   - Updated `_build_result()` to apply `UI.typewriter` on `rep.body` if not streamed.
10. `client/scripts/ui/event_panel.gd`
    - Connected `Net.stream_chunk` in `_ready()` to handle `"market"` and `"seminar:<playerId>"`.
    - Updates label in place if open when chunk arrives.
    - Updated `refresh()` to apply `UI.typewriter` fallback for market and seminar body texts if not streamed.
11. `client/scripts/ui/report.gd`
    - Connected `Net.stream_chunk` in `_ready()` to handle `"coach:<playerId>"` and `"letter:<playerId>:<clientId>"`.
    - Updates coach label, certificate coach label, and letter's `LetterBodyLabel` in place.
    - Updated `refresh()` to apply `UI.typewriter` fallback when not streamed and silent swap when streamed.
    - Preserved disabled status on "儲存圖片" button until authoritative state arrives.

### Anything Not Done
- None. All requirements specified in `docs/design/tasks/batch17-stream-all-ai.md` have been fully implemented across `server/` and `client/`.
