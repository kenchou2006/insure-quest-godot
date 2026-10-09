# Batch 1 (Server): Dynamic Life Twists, 3-Round AI Dialogue + Compliance Radar, Letter from Ten Years Later

Based on `docs/design/README.md` and `docs/design/round2-agy.md` (schema and prompt outline). Modify only `server/`, **do not modify `client/`** (deferred to Batch 2).

## Hard Rules
- **Guests (no `accountId`) and bot advisors never use AI**: Always fall back to the rule-based fallback in `MeteredAI` (`server/src/ai.ts` already has this mechanism; new features reuse `MeteredAI.run`). Do not add any bypasses for login.
- Every new AI method: `RawAI` interface, `LLMAI` (prompt layer shared between Workers AI / Claude), `MockAI`, `RuleAI` / rule-based functions must all be implemented; AI return values must always be validated with zod. On validation failure, return null -> refund quota and fall back to rule-based.
- Player input is untrusted data: wrap inside the `<trainee_utterance>` block, and the system prompt must explicitly instruct to ignore any commands inside it (refer to `round2-agy.md`).
- Endings, scores, and stress test outcomes **must only be decided by the rules engine**; AI is only responsible for text.
- Do not use emojis (not available in the font); ✓×★●◆※ may be used. All copy is in Traditional Chinese.
- Existing tests (`server/test/*.test.ts`) must continue to pass; add new tests for new features. It's fine if commands cannot be run; Claude will run `npm run check` to verify.
- Protocol changes must be backward-compatible until client Batch 2 is complete: preserve existing `ask` / `ask_free` / `objection_free` actions.

## 1. Dynamic Life Twists (Rule Mechanism)
- In `src/game/`, add `LIFE_TWISTS`: 6–8 scenarios (e.g., senior family member diagnosed needing long-term care, recently changed jobs with unstable income, highly defensive due to past aggressive sales pitch, mortgage grace period expiring, spouse unemployed, just learned pregnancy). Each scenario has: `id, title, hint` (a sentence the client will disclose), adjustments to the client (e.g., increase need for a certain stress event, adjust `plan.ideal` or `plan.cards` weights, initial trust change).
- When starting an interview (where `game.ts` creates the session), draw 1 using `ctx.rng` and attach to session (`session.twist`); `publicView` exposes `twist: {id, title, hint}`.
- Adjusted client should be passed to `evaluatePlan` / `runStress` via a function (e.g., `applyTwist(client, twist)` returning a new `ClientProfile` copy); **do not mutate original `CLIENTS` data**.
- Bot advisors' (`bots.ts`) pro strategy must be able to see the adjusted client.
- Tests: For each client × each scenario, pro bot's plan remains good and passes stress test (mirroring existing "each client: pro bot plan evaluated as good" test).

## 2. 3-Round AI Dialogue + Compliance Radar (Merged into Single Call)
- New action `{type: 'talk', text: string, suggested?: QuestionId}`: used in discover step, max 3 rounds per interview (`session.talkLeft = 3`). `suggested` indicates the player clicked a suggested question button (text matches that question's `QUESTIONS` text).
- Processing flow:
  1. First run **rule-based compliance radar** (new function `ruleCompliance(text)`: keywords/regex checking "guaranteed", "risk-free profit", "definitely profit", "better than fixed deposit", "regret not buying", "ruined if something happens", "today only", etc.), recording result into that round's record.
  2. Call `ai.talk(client, twist, history, text)`, returning `round2-agy.md`'s `CombinedDialogueSchema` (`answer`, `revealedFacts`, `trustDelta`, `insightDelta`, `emotion`, `compliance{level, penalty, issues[{code, quote, rule, suggestion}]}`, `coachTip`). Numeric values must be clamped once more on the server.
  3. Rule-based fallback (guest / quota exhausted / AI failure): If `suggested` is present, use existing `answers[qid]` logic; for free input, use existing `ruleFreeQuestion`; for compliance, use `ruleCompliance`.
  4. Compliance result: `level` takes whichever is more severe between rule-based and AI; `penalty` is deducted from `m.compliance`; `revealedFacts` can only match the client's real facts title (discard any not in the list); hits are credited to the existing clue/insight mechanism (refer to handling in `freeHits` and `ask`).
  5. Store in `session.asked` (reuse field, adding `compliance`, `emotion`, `coachTip`, `source: 'ai' | 'rule'`), so `sessionLogs`, decision logs (`decisions`), and weakness tags can use them (violations generate corresponding weakness tags, refer to `TAG_INFO`).
- Discover ends when 3 rounds are exhausted or player clicks 「進入方案配置」 ("Enter plan configuration") (existing `to_plan`). Retain legacy `ask` / `ask_free` for now.
- Bot advisors: have bots switch to `talk` with `suggested` (rule-based) to maintain balance.
- Tests: positive and negative cases for `ruleCompliance`, rule-based flow for `talk`, guests do not call `RawAI`, invalid JSON returned by AI falls back and refunds quota, `revealedFacts` filtered by whitelist, player text in prompt is wrapped in `<trainee_utterance>`.

## 3. Letter from Ten Years Later
- In result step (`game.ts` around lines 278–308 after `runStress`), the rules engine determines `letter`: `{ outcome: 'thanks' | 'regret' | 'mixed', event: title of a stress event occurring within 10 years, gap: gap amount (number, can be 0), signed }`.
- Rule-based template letter (guests and fallback): generate a 120–200 character client-tone letter based on `outcome`, mentioning `event` and `gap`.
- AI version: `ai.letter(client, twist, letterFacts)` may only polish tone; prompt explicitly gives fixed `outcome` / `event` / `gap` that cannot be altered; server checks that AI text **does not contain conclusions contradictory to outcome** (simple rule: for `thanks`, cannot contain 「沒有理賠」 ("no claim payout"), 「後悔」 ("regret"), etc.); if invalid, fall back to template.
- AI letter writing runs in background without blocking turns: can insert template first and update when AI returns (refer to `enrichCoach` approach), or batch generate at settlement. Final settlement report `FinalRow` exposes letter for each client (retain at most 3 most representative letters).
- Tests: outcome determined by stress test, template letter contains `event` and `gap`, AI giving contradictory conclusion replaced by template.

## After Completion
Append "Completion Record" to the bottom of `docs/design/tasks/batch1-server.md`: modified files, new protocol fields (for client Batch 2), and pending items.

---

## Completion Record

### 1. List of Modified and Added Files
- **Added `server/src/game/twists.ts`**:
  - Defined `LIFE_TWISTS` (7 dynamic life twist scenarios: senior family member diagnosed needing long-term care, recently changed jobs with unstable income, highly defensive due to past aggressive sales pitch, mortgage grace period expiring, spouse unemployed and job-seeking, pregnancy announcement, preparing side-business studio).
  - Implemented `applyTwist(client, twist)`: safely generates an adjusted `ClientProfile` copy without modifying original `CLIENTS`.
- **Added `server/src/game/compliance.ts`**:
  - Implemented `ruleCompliance(text)`: regex and keywords real-time detection for `PROMISE_RETURN` (guaranteed returns), `FEAR_MONGERING` (fear-based selling), `MISLEADING_COMPARISON` (misleading comparison), `EARLY_PRESSURE` (time/budget pressure closing), `INJECTION_ATTEMPT` (prompt injection attack).
  - Implemented `mergeCompliance(ruleComp, aiComp)`: merges rule-based preliminary filter with AI deep interpretation, taking the more severe level and larger penalty.
- **Added `server/src/game/letters.ts`**:
  - Implemented `determineLetter(client, signed, st)`: determines outcome tendency (`thanks` / `regret` / `mixed`), key event, and gap amount (number, in 10,000s TWD) based on stress rehearsal and contract status.
  - Implemented `generateTemplateLetter(client, facts)`: 120–200 character Traditional Chinese client template letter containing event and gap amount.
  - Implemented `validateLetterContent(content, outcome)`: server-side check on AI polished text length and prohibited conflicting conclusion phrases (`thanks` forbids 「後悔/沒有理賠」 ("regret / no claim payout"), `regret` forbids 「慶幸/還好有買」 ("relieved / glad I bought it")), automatically falling back to template letter when invalid.
- **Modified `server/src/game/types.ts`**:
  - Imported and extended type definitions (`LifeTwist`, `ClientLetter`, `ComplianceLevel`).
  - `SessionState`: added `twist?: LifeTwist | null`, `talkLeft?: number`; `asked` element extended with `compliance`, `emotion`, `coachTip`, `source`; `result` added `letter?: ClientLetter | null`.
  - `SessionLog`: added `twist` and `letter`.
  - `FinalRow`: added `letters?: { clientName: string; outcome: 'thanks' | 'regret' | 'mixed'; content: string }[]`.
  - `Action`: added action `{ type: 'talk'; text: string; suggested?: QuestionId }`.
- **Modified `server/src/ai.ts`**:
  - Added zod schemas `CombinedDialogueSchema` (defined per `round2-agy.md`, including client reply, facts whitelist, bidirectional trust and insight changes, client psychological state, compliance light and rules, coach tips) and `LetterSchema`.
  - Added `talk(...)` and `letter(...)` to `RawAI` and `AIService`.
  - `LLMAI` implementation:
    - `talk`: player input wrapped in `<trainee_utterance>`, includes dynamic variable Persona and anti-injection instructions, numbers clamped on server.
    - `letter`: given immutable factual parameters, returned after validation by `validateLetterContent`.
  - `RuleAI`, `MockAI`, `MeteredAI`: fully implemented `talk` and `letter`, seamlessly falling back to rule-based fallback for guests or when quota is exhausted.
- **Modified `server/src/game/game.ts`**:
  - `startSession`: draws 1 `twist` attached to session, applies `initialTrustDelta`, initializes `talkLeft = 3`.
  - `applyActionInner`: added handling for `talk` action (compliance radar, AI call, whitelist filter `revealedFacts` credited to clues and `freeHits`, deducts `talkLeft`, records into `asked` and weakness decisions).
  - `to_plan` and `interviewReady`: supports entering plan configuration after 3 dialogue rounds end or all standard questions are asked.
  - `plan` and `finishSession`: fully switched to using `applyTwist(c, sess.twist)` for suitability evaluation and stress testing; generates letter from ten years later, background non-blocking AI polish call.
  - `publicView`: exposes `session.twist`, `session.talkLeft`, `session.result.letter`.
  - `endGame`: `FinalRow` exposes representative letters for each advisor (up to 3 letters).
- **Modified `server/src/game/bots.ts`**:
  - Bot advisors switch to using `talk` with `suggested` during discover phase.
  - Pro strategy (`pro`) in plan phase optimizes configuration based on adjusted client from `applyTwist(c, sess.twist)`.
- **Added `server/test/batch1.test.ts`**:
  - Unit tests covering all new features: pro bot evaluated as good and passing stress test for each client × each dynamic scenario, positive/negative cases for compliance radar, `talk` action rule-based flow, guest and quota refunds, clue whitelist filtering, letter from ten years later and contradictory conclusion filtering, `publicView` and final settlement data field validations.

### 2. New Protocol Fields (For Client Batch 2 Integration)
1. **Action Request (`Action`)**:
   - `{ type: 'talk', text: string, suggested?: QuestionId }`:
     - `text`: text spoken by trainee advisor (suggested question text or free input).
     - `suggested` (optional): question ID (`'income' | 'goal' | 'coverage' | 'risk' | 'premium'`) passed when clicking suggested question button.
2. **Public State (`publicView.session`)**:
   - `twist: { id: string, title: string, hint: string } | null`: dynamic life twist randomly drawn for current interview, frontend can display directly on client card.
   - `talkLeft: number`: remaining dialogue rounds (initially 3, guide to "Enter plan configuration" when reaching 0).
   - `asked: Array<{ ..., compliance?: 'pass' | 'warning' | 'violation', emotion?: string, coachTip?: string, source?: 'ai' | 'rule' }>`: dialogue record including compliance indicator for that round, client defensiveness psychology, coach short tip, and generation source.
   - `result.letter: { outcome: 'thanks' | 'regret' | 'mixed', event: string, gap: number, signed: boolean, content: string } | null`: letter object from ten years later, including outcome tendency, associated event, gap amount (10,000s TWD), and full letter text (initially template letter; updated in real-time if logged in and AI polish completes).
3. **Settlement Report (`publicView.final`)**:
   - `letters?: Array<{ clientName: string, outcome: 'thanks' | 'regret' | 'mixed', content: string }>`: record of up to 3 most representative letters from each advisor's interviews, used for post-match review display.

### 3. Pending Items (Deferred to Subsequent Batches)
- **Client Batch 2 (Godot / Web Frontend)**:
  - Visual novel dialogue bubble styling and 3-round dialogue UI for interview panel.
  - Suggested question buttons + free input box + real-time frontend regex preliminary filter indicators.
  - Dynamic life twist Tag and display of client hints.
  - Dedicated stationery animated display panel for "Letter from ten years later" in result phase.
- **Demo and Reviewer Mechanism**:
  - Interface input and binding for reviewer demo codes (`DEMO_CODES`) to experience AI quota without login (Batch 2 or subsequent).
