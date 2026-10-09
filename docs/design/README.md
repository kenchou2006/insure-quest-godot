# Gameplay and AI Revamp: Claude × agy Discussion Conclusions (2026-10-09)

Discussion log: round1-claude.md → round1-agy.md → round2-claude.md → round2-agy.md (includes Zod schema and system prompt outline for combined calls).

## Diagnosis (Consensus Between Both Parties)
1. AI is merely decorative: Across an entire interview, AI is used only for 1 open-ended question + 1 objection response; everything else is multiple choice.
2. Optimal solutions can be memorized: Pick 3 out of 5, 10 resource coins, and card combinations all have fixed answers.
3. The board is disconnected from interviews; the interview panel completely conceals the board.
4. Allocation errors only deduct points; players do not feel the consequences.

## Must-Dos Before Preliminary Round
| # | Item | Scope | Relevant Scoring |
|---|---|---|---|
| 1 | **Hybrid 3-Round Dialogue + Compliance Radar (Combined into a single LLM call)**: Suggested question buttons + free-form input; returns client response, revealed clues, trust / insight changes, compliance indicator (rules citations and phrasing suggestions), and coach brief feedback in a single call. Frontend uses rules-based keywords for immediate indicator lighting, overwritten once AI results arrive. AI calls per interview ≤ 3. | M–L | AI 20%, Experience 40%, Feasibility 20% |
| 2 | **Letter from ten years later**: Rule engine determines the outcome and shortfall amount, while AI is solely responsible for drafting the letter; guests use template letters. | S | Video 10%, Experience 40% |
| 3 | **Dynamic Life Variables**: Clients are randomly assigned 1 scenario Tag, which affects the stress test threshold and is injected into the AI persona; unit tests lock senior bot advisor performance to remain good. | S | Creativity, Replayability |
| 4 | **UI Keyhole Surgery**: Interviews switch to visual novel-style speech bubbles; quest cards collapsed by default and auto-collapse during interviews; client cards and Five Powers bars condensed into a single row; desktop interview panel occupies only 65%, keeping board thumbnail visible; step bar (already fixed). | M | Experience 40% |
| 5 | **Scene Illustrations**: Illustrations for meiling, yixiang, and peishan lack clue objects → regenerate, or update clues to match objects actually present in the images; guohua already calibrated. Garbled text in AI images addressed via regeneration or cropping. | S–M | Experience 40% |
| 6 | **Judges can experience AI** (Pending user decision; see below) | S | AI 20–30% |
| 7 | 2.5-minute demo video: Dialogue → violation triggers red light and correction → letter from ten years later | — | Video 10% |

## Do Before Semi-Finals
Vectorize RAG (FSC penalty cases and solicitation regulations), trainer dashboard (class-wide weakness heatmap, targeted client assignment), peer health check review (replacing rating predictions), advisor strategy cards, voice mode (Whisper + TTS).

## Will Not Do
Two advisors competing in real-time pitches for the same client (synchronous blocking; room freezes on disconnection), complete UI rewrite.

## Pending User Decision
- Currently, "Not logged in = No AI". If judges test the game as guests, they will not see any AI features. It is recommended to add a **Judge Demo Code** (`DEMO_CODES` environment variable, granting ~30 quota calls upon entry, still requiring login or device binding).
