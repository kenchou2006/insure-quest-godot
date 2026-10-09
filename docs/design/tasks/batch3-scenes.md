# Batch 3: Regenerate Scene Images for meiling, yixiang, peishan

Issue: These three images lack clue objects, so players cannot find them by visual observation.
- meiling (Meiling Chang, single-parent administrative assistant): lacks 「教育基金存摺」 ("Education fund passbook"); shift schedule is also unclear.
- yixiang (Yixiang Kao, fitness trainer): lacks 「膝蓋護具」 ("Knee brace"); learner booking roster and studio estimate are also unclear.
- peishan (Peishan Ho, hospital nurse): lacks 「夜班表」 ("Night shift roster"); lumbar support belt is also unclear.
All three images must clearly show 3 clue objects + 1 distractor object (see current titles in `client/assets/clients/hotspots.json` and `server/src/game/hotspots-extra.json`; do not change clue titles because they are bound to client data and facts).

## What You Need to Do (Edit files only; do not run commands)
1. **Local-Only Image Generation Endpoint**: In `server/src/index.ts`, add `GET /api/dev/gen-img?prompt=...`, existing only when `env.DEV_LOGIN === '1'` and the request hostname is `localhost` or `127.0.0.1`, returning 404 otherwise (must never become a public image generation API in production). Use Workers AI `@cf/black-forest-labs/flux-1-schnell` (`env.AI.run`, returns base64 image, `steps: 8`), returning `image/jpeg`.
2. **Rewrite `server/tools/generate-all-scenes.mjs`**:
   - Call `/api/dev/gen-img`; support `node tools/generate-all-scenes.mjs meiling yixiang peishan` to generate only specified clients; write output to `client/assets/clients/<id>.jpg`, backing up old files to `<id>.old.jpg` first. Note that cwd is `server/`, ensure paths are correct.
   - Rewrite the English prompts for these three: preserve original anime background style; **each clue object must be large, centered, separate from each other, non-overlapping**, distributed in different areas of the frame (e.g. bottom-left, center, right); clearly describe appearance (e.g.: bank passbook with blue cover lying open on the desk; black knee brace sleeve; night shift roster printed schedule pinned on a corkboard); **do not draw any readable text** (no text, no letters, no words, to avoid garbled AI text); no characters obstructing objects in the frame.
3. Write "Completion Record" at the bottom of this file, including expected screen regions for each object in each image.

After completion, Claude will run generation and ask you to inspect images to annotate hotspot coordinates.

---

## Completion Record

### 1. Local-Only Image Generation Endpoint Implementation (`server/src/index.ts`)
- Route: `GET /api/dev/gen-img?prompt=...`
- Security guard: Only permitted when `env.DEV_LOGIN === '1'` and request hostname is `localhost` or `127.0.0.1`, otherwise always responds with HTTP 404 (prevents exposing public image generation endpoint in production).
- Model: Workers AI `@cf/black-forest-labs/flux-1-schnell` (`steps: 8`).
- Format: Converts base64 to binary buffer, returning `Content-Type: image/jpeg`.

### 2. Batch Image Generation Tool Rewrite (`server/tools/generate-all-scenes.mjs`)
- API endpoint updated to call `/api/dev/gen-img`.
- Supports specifying clients via CLI: `node tools/generate-all-scenes.mjs meiling yixiang peishan`; defaults to processing all clients if no arguments provided.
- Path resolution: Resolves project root directory from script directory, outputting precisely to `client/assets/clients/<id>.jpg` (correctly points whether executed from project root or `server/`).
- Old file backup: Automatically backs up original image to `client/assets/clients/<id>.old.jpg` before overwriting.
- Prompt optimization: Continues Makoto Shinkai anime style, strictly setting "no character obstruction, objects large and separate without overlapping, distributed in distinct quadrants, no readable text (no text, no letters, no words)".

### 3. Expected Object Layout Regions for the Three Scene Images

| Client | Category | Object Title | Prompt Key Description | Expected Screen Region |
| :--- | :--- | :--- | :--- | :--- |
| **meiling**<br>(Meiling Chang) | Clue 1 | **教育基金存摺**<br>(Education fund passbook) | Dark blue cover open bank passbook, lying flat showing grid lines | **Bottom-Left Foreground** |
| | Clue 2 | **女兒的作業簿**<br>(Daughter's workbook) | Elementary school workbook with colorful cartoon illustration and doodles on cover, lying open | **Center Foreground** |
| | Clue 3 | **兩份工作的班表**<br>(Two-job shift roster) | Printed weekly dual-job shift schedule with colored boxes, pinned on wall | **Top Corkboard Wall** |
| | Distractor | **辦公室文具盒**<br>(Office stationery box) | Multi-compartment desk stationery organizer with colored pens, highlighters, and scissors | **Right Desk Area** |
| **yixiang**<br>(Yixiang Kao) | Clue 1 | **膝蓋護具**<br>(Knee brace) | Black professional athletic compression knee brace with silicone patella ring and elastic straps, spread flat | **Center Foreground** |
| | Clue 2 | **學員預約表**<br>(Learner booking roster) | Metal clipboard holding weekly schedule printed with one-on-one learner booking time slots | **Right Desk Area** |
| | Clue 3 | **工作室估價**<br>(Studio renovation estimate) | Fitness studio renovation blueprint quote and equipment procurement estimate sheet pinned on wall | **Top Corkboard Wall** |
| | Distractor | **乳清蛋白搖搖杯**<br>(Whey protein shaker) | Translucent high-protein sports shaker bottle with neon flip cap, standing upright | **Left Desk Area** |
| **peishan**<br>(Peishan Ho) | Clue 1 | **護腰**<br>(Lumbar support belt) | Ergonomic black-and-gray breathable medical lumbar belt with wide velcro and support stays, draped on chair back | **Left Chair Backrest** |
| | Clue 2 | **留學簡章**<br>(Study abroad brochure) | Open overseas nursing graduate study university prospectus brochure with campus photo and world map | **Center Foreground** |
| | Clue 3 | **夜班表**<br>(Night shift roster) | Large white hospital monthly night shift duty roster with clear calendar grid and shift icons | **Top Corkboard Wall** |
| | Distractor | **護理識別證**<br>(Nurse ID badge) | Blue nurse lanyard with transparent acrylic employee ID card, coiled stethoscope nearby | **Right Desk Area** |
