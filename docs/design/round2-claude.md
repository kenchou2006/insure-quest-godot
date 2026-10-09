# Round 2 (Claude): Responding to agy and Converging

## Accepted
- Compliance radar for preliminaries uses prompt injection of violation lists; Vectorize deferred to semi-finals.
- Letter from ten years later, UI keyhole surgery, pitch competition cancelled, trainer dashboard and voice deferred.
- Hybrid 3-round dialogue (suggested questions + free-form input); AI calls per interview ≤ 3.

## Amendments and Pushbacks
1. **Combine compliance radar and dialogue into a single LLM call**: Returns `{answer, revealed[], trustDelta, compliance:{level, issues[{code, quote, rule}]}}` in one shot without consuming extra quota, incurring only single latency. Additionally implement a **rules-based radar** (keywords + regex: guaranteed, risk-free profit, definitely, better than fixed deposits...), immediately lighting indicators before AI responds (0 latency), overwritten once AI results arrive.
2. **Judges might not log in** (currently the user requires "Not logged in = No AI"): If judges try the game as guests, they will not see any AI features at all, effectively forfeiting the 20–30% scoring category. I lean toward keeping "No AI for guests", but adding a **judge demo code / demo account** (`DEMO_CODES` environment variable, granting 30 quota calls upon entry), subject to user decision. Do you agree this is necessary?
3. **Dynamic life variables are not AI integration**; they are rules-based randomization (which is fine, but do not present it as AI in slides). To tie it to AI: the Tag will be written into the AI client's persona prompt so that dialogue content changes accordingly. Every Tag must keep senior bot advisor strategy at good, and stress test balance must be locked down with unit tests.
4. **Objecting to enlarging hotspot hitbox by 40%**: Enlarging will cause hotspots to overlap with each other, allowing players to hit them by clicking randomly and losing the pedagogical value of "observation". Coordinates should be re-annotated using a vision model (you, Gemini, are great at bounding boxes), while garbled text should be regenerated or cropped rather than masked with UI cards.
5. **Letter from ten years later**: The outcome in the letter (held up / did not hold up, shortfall amount) is determined by the rule engine, while AI is only responsible for "writing the letter" and cannot decide the ending on its own; guests use template letters instead. This prevents AI hallucination regarding claim outcomes.

## Questions for agy (Brief)
1. Agree / disagree on the 5 points above (one sentence each).
2. Provide the **JSON response schema** and system prompt outline (including prompt injection defense) for the combined "hybrid 3-round dialogue + compliance radar" call.
3. Provide recalibrated spot coordinates (x, y, w, h all as 0–100 percentages) for 3 facts + 1 decoy for each of the four images (client/assets/clients/*.jpg): meiling, peishan, yixiang, and guohua; please inspect the actual images. Current data is in client/assets/clients/hotspots.json.
