# Round 1 (Claude): Gameplay, AI Application, and Interface

Background: Cardif InsurHack 1-1 "Insurance Monopoly". Scoring = Implementation Completeness & Experience 40%, AI Integration 20% (Semi-finals 30%), Feasibility & Commercial 20%, Creativity 10% (Preliminary), Demo Video 10%.
Current status (reviewed codebase and 9 preview screenshots in client/scenes/preview/):
- Monopoly board with 24 tiles; client tiles enter a 4-step interview (scene clue search → pick 3 out of 5 questions + 1 open-ended question → 10 resource coins + 2–3 coverage cards → objection → 90-day stress simulation).
- Life events / Market news / Compliance training / Audit / Referrals / Seminars / Quarterly settlement; current game quests, badges of honor, spectator predictions.
- AI (Workers AI qwen): answers open-ended questions, scores free-form objection responses, coach hints, settlement critique, AI generation of new clients; guests = rules-based.

## A. Gameplay Issues I Identified
1. **AI is merely "decorative"**: Across an entire interview, AI appears only in 1 open-ended question + 1 objection free-form response; the rest are entirely multiple-choice questions. Judges see a "multiple-choice game + minor AI features", where AI is not the core engine solving pain points (at a disadvantage for 20–30% of the score).
2. **Optimal solutions can be memorized**: Pick 3 out of 5, 10-coin allocation, and card combinations are fixed answers (senior bot advisors simply look up tables); players memorize them after 2–3 games, resulting in low replay value.
3. **Monopoly board layer disconnected from interview layer**: Dice rolls only determine "which type of tile is next", with no route choices, resource trade-offs, or player interactions; board time is mostly waiting.
4. **Consequences lack drama**: Penalties for misallocation are just numerical scores; players do not "feel" that the client is left unprotected because of them.

## B. My Proposals (Ranked by ROI)
1. **Multi-round AI client dialogue replacing "Pick 3 of 5"** (Core): Revamp interviews into N rounds of open dialogue with the AI client (time bar = interview time). The AI client maintains hidden need state (JSON: revealed clues, trust, emotion), returning structured results each round; keep option buttons as "suggested questions" to lower typing friction. Fall back to current rules-based options for guests or when quota is exhausted.
2. **Real-time Compliance Radar**: Every sentence spoken by the player is sent to AI for evaluation (guaranteed returns, exaggeration, disparaging competitors, undisclosed fees), providing immediate red/yellow indicators + rule citations (RAG: Vectorize storing FSC Treating Customers Fairly / Insurance Solicitation Regulations summaries). This addresses the industry's real pain point (penalty risks) and serves as a commercial selling point.
3. **Claim Moment (Ten Years Later)**: Before final settlement, draw a life event for each client. AI writes a "letter from ten years later" in the client's voice, expressing gratitude or regret depending on your allocation; highly emotionally impactful for videos.
4. **Board Interaction**: The same client can be contested by two advisors (pitch competition: AI client chooses after hearing two proposals); bifurcated path choices (high-risk high-reward routes); referral chains.
5. **Trainer Platform**: AI synthesizes class-wide weakness radars + automatically assigns "targeted client" homework (e.g., if the entire class forgot to ask about income disruption → assign 3 self-employed clients next week); daily challenges (same-seed leaderboard).
6. **Voice Mode (Bonus)**: Workers AI Whisper speech-to-text + TTS client voice; demo video can directly showcase "talking to the client".

## C. Does the Interface Need a Major Overhaul?
Full rewrite is not recommended; "keyhole surgery" is advised:
- Transform interviews to **visual novel style**: Large client illustration/expression on the left, speech bubbles + input field on the right; condense Five Powers into a single row of mini-gauges; remove duplicate numbering on step bars (currently 「2 ② 方案配置」("2 ② Plan Configuration")).
- When the interview opens, the board is completely covered, and the right-hand "Current Quests" permanently occupies the most prominent spot → collapse quests into a single line; during interviews, keep only client compendium and dialogue history in the sidebar.
- 60-second interactive tutorial for first-time play (currently text and illustrations only).
- Scene hotspots: In ~4 of the 13 new illustrations (meiling, peishan, yixiang, guohua), hotspots do not match objects, and AI images contain garbled text; re-annotation needed.

## Questions for agy
1. Which points do you agree or disagree with? Why? (Considering remaining schedule and scoring weights).
2. Your additional gameplay ideas (at least 3), with estimated effort (S/M/L).
3. Interface: Do you think it needs a major overhaul or surgery? List the top 5 UI elements to change.
4. Propose a split between "Must-do before preliminary round / Defer to semi-finals".
