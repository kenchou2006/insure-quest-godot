# Batch 9 (Art): Client Portraits and Warm Title Visual

Background: `docs/design/round4-summary.md`. Image generation uses the local-only endpoint `GET /api/dev/gen-img?prompt=` (Workers AI flux-1-schnell; requires `npm run dev:remote-ai` with `DEV_LOGIN=1`). Do not use any terminal/command tool; Claude runs the scripts and reviews every image.

## 1. `server/tools/generate-portraits.mjs` (new)
- Reads client ids, names, age, gender, job and a short look description from a table inside the script for **all 18 built-in clients** (ids in `server/src/game/data.ts` and `clients-extra.ts`; check each client's `age`, `gender`, `job`, `family`, `tag` and write a fitting look: clothing that matches the job, age-appropriate hair, a warm neutral expression).
- Shared style suffix (identical for every portrait so the set is consistent): `anime illustration in the style of a modern Japanese animated film, bust portrait, head and shoulders, facing the viewer, gentle natural expression, soft warm studio lighting, plain soft gradient background in muted sage green, clean line art, consistent character design, no text, no letters, no watermark, single person`.
- Usage: `node tools/generate-portraits.mjs [ids...] [--base http://localhost:8787]`; writes `client/assets/portraits/<id>.jpg` (skip existing unless `--force`), 3 attempts per image on HTTP error.
- Also support `title`: writes `client/assets/title.jpg` after backing up the current one to `client/assets/title.old.jpg` (only once). Title prompt: warm morning living room in a Taiwanese city apartment, sunlight through sheer curtains, coffee table with a cup of tea, a tablet showing a simple rising line chart with a small shield icon, plants, a framed family photo turned slightly away (no readable faces), Taipei skyline softly visible, hopeful calm mood, same anime film style, wide 16:9 composition with empty space on the left third for the logo text, no people, no text.
- The flux endpoint returns a square-ish image: request `width`/`height` if the endpoint supports them (check `server/src/index.ts` `/api/dev/gen-img`; extend it to pass optional `w`/`h` query params through to the model, clamped to 256–1536, still local-only).

## 2. Client usage contract (for Batch 8)
- Portrait path: `res://assets/portraits/<clientId>.jpg`; when missing (AI-generated clients) fall back to the existing initial-letter avatar.
- Add `portrait` lookup in `server/src/game/data.ts` only if needed for publicView; otherwise the client resolves by id.

## Finish
Append a "Completion Record" listing the 18 look descriptions.

---

## Completion Record (2026-10-10)

### 1. 修改清單
- `server/src/index.ts`：
  - 在 `/api/dev/gen-img` 處理區塊新增 `w`/`width` 與 `h`/`height` 查詢參數解析。
  - 數值限制於 256–1536 範圍內 (`Math.max(256, Math.min(1536, ...))`)。
  - 將解析出的 `width` 與 `height` 帶入 Workers AI 模型 `@cf/black-forest-labs/flux-1-schnell` 參數中。
  - 保留既有本機限定驗證 (`isLocal = env.DEV_LOGIN === '1' && ...`)，未改動任何其他 API 與 `server/src/game`。
- `server/tools/generate-portraits.mjs`：
  - 全新撰寫 Node.js ESM 腳本，支援自訂 `--base` (預設 `http://localhost:8787`)、`--force` 覆寫機制、特定客戶 ID 或 `all` 批次生成。
  - 內建 18 位客戶設定檔資料（ID、姓名、年齡、性別、職業、標籤、家庭、胸像外貌特徵描述）。
  - 套用一致風格後綴 (`SHARED_STYLE_SUFFIX`，日系現代動畫電影風、胸像、正面、溫暖表情、柔和暖光、鼠尾草綠微漸層背景、無文字無水印)。
  - 支援 `title` 參數生成新版 16:9 主視覺插畫（自動單次備份 `client/assets/title.jpg` 至 `client/assets/title.old.jpg`）。
  - 內建 HTTP 錯誤自動重試 3 次機制與指數退避延遲。
- `client/assets/portraits/README.md`：
  - 新增目錄說明檔，載明資源規範、檔案命名格式（`res://assets/portraits/<clientId>.jpg`）、客戶端 Batch 8 契約與缺圖 fallback 規則。

### 2. 18 位客戶外貌特徵描述清單 (Look Descriptions)

| # | ID | 姓名 | 年齡 / 性別 | 職業 / 標籤 | 外貌與服裝描述 (Look Description) |
|---|---|---|---|---|---|
| 1 | `yuqing` | 林雨晴 | 29 歲 / 女性 | 自由接案插畫家 / 收入波動型 | 29-year-old Taiwanese woman illustrator, shoulder-length wavy dark brown hair tied in a loose half-up bun, warm thoughtful brown eyes, wearing a comfortable oversized cream knit sweater, a supportive elastic wrist brace visible on her right wrist |
| 2 | `boting` | 陳柏廷 | 36 歲 / 男性 | 半導體工程師・新手爸爸 / 高收入高責任 | 36-year-old Taiwanese male semiconductor engineer and new father, neat short black hair, modern dark-rimmed rectangular glasses, warm slightly weary eyes with a tender smile, wearing a navy blue casual collared button-up shirt over a heather grey t-shirt |
| 3 | `wanting` | 蘇婉婷 | 43 歲 / 女性 | 獨立咖啡店老闆・單親家長 / 創業家庭型 | 43-year-old Taiwanese woman café owner and single mother, soft dark hair gathered in a relaxed low ponytail, serene confident smile, wearing a dark olive-green canvas barista apron over a rust-orange linen blouse with rolled sleeves |
| 4 | `ziyuan` | 周子安 | 25 歲 / 非二元 | 研究生・接案攝影師 / 低收入成長型 | 25-year-old Taiwanese non-binary graduate student photographer, androgynous layered dark shaggy wolf-cut hair, focused inquisitive hazel eyes, wearing a vintage khaki multi-pocket utility vest over a charcoal long-sleeve tee, woven camera strap around the neck |
| 5 | `zhiming` | 黃志明 | 58 歲 / 男性 | 計程車司機・家庭照顧者 / 準退休保障型 | 58-year-old Taiwanese male veteran taxi driver and caregiver, short salt-and-pepper hair, warm crinkles around kindly eyes, humble honest smile, wearing a clean sky-blue collared driving polo shirt over a white crewneck undershirt |
| 6 | `junhao` | 王俊豪 | 32 歲 / 男性 | 外送平台騎手 / 零工經濟型 | 32-year-old Taiwanese male food delivery courier, sun-tanned skin, sporty cropped black hair, cheerful spirited smile, wearing a lightweight windbreaker jacket with dark teal and black paneling, athletic build |
| 7 | `meiling` | 張美玲 | 36 歲 / 女性 | 公司行政助理・單親家長 / 單親家長型 | 36-year-old Taiwanese woman office administrative assistant and single mother, neat low ponytail with soft side bangs, gentle patient expression, wearing a modest pastel lilac knit cardigan over a white round-neck blouse |
| 8 | `jiahao` | 劉家豪 | 31 歲 / 男性 | 軟體工程師・新手爸爸 / 新手爸媽型 | 31-year-old Taiwanese male software engineer and new father, clean-cut dark hair, modern thin round metal glasses, friendly earnest gaze, wearing a comfortable heather-gray crewneck sweatshirt |
| 9 | `shufen` | 吳淑芬 | 45 歲 / 女性 | 會計主管 / 三明治世代 | 45-year-old Taiwanese woman accounting manager, elegant chin-length bob haircut, delicate tortoiseshell glasses, composed and intelligent expression, wearing a tailored dusty-rose blazer over an ivory silk inner blouse |
| 10 | `wenjie` | 鄭文傑 | 58 歲 / 男性 | 國中教師 / 退休準備型 | 58-year-old Taiwanese male middle school teacher, neatly parted silver-streaked hair, warm approachable smile, round tortoiseshell glasses, wearing a forest-green knitted vest over an ironed plaid collared button-up shirt |
| 11 | `yiting` | 蔡依婷 | 24 歲 / 女性 | 行銷專員 / 小資起步型 | 24-year-old Taiwanese woman fresh marketing graduate, cheerful bob with wispy bangs, bright sparkling eyes, bright optimistic smile, wearing a smart-casual light sage blazer over a plain white tee with a dainty silver pendant necklace |
| 12 | `zhiwei` | 林志偉 | 40 歲 / 男性 | 小吃店老闆 / 自營商家型 | 40-year-old Taiwanese male traditional eatery owner, robust build, short spiky black hair, friendly hearty smile, wearing a durable dark navy bib work apron over a breathable dark charcoal cotton t-shirt |
| 13 | `peishan` | 何佩珊 | 34 歲 / 女性 | 醫院護理師 / 輪班高壓型 | 34-year-old Taiwanese woman hospital shift nurse, hair neatly bound in a high practical bun, resolute yet compassionate eyes, wearing light seafoam-green hospital scrubs with a dark navy fleece zip jacket slightly open |
| 14 | `chengen` | 李承恩 | 29 歲 / 男性 | 科技公司資深工程師 / 高收入集中型 | 29-year-old Taiwanese male senior tech lead, sharp modern side-parted hairstyle, sleek rectangular wireframe glasses, confident analytical gaze, wearing a minimalist fine-knit black mock-neck pullover |
| 15 | `jiaming` | 許家銘 | 38 歲 / 男性 | 設計公司合夥人 / 頂客族型 | 38-year-old Taiwanese male design studio partner, cultured well-groomed look with a hint of neat designer stubble, stylish round horn-rim glasses, wearing an artistically tailored charcoal turtleneck sweater |
| 16 | `guohua` | 楊國華 | 50 歲 / 男性 | 計程車司機 / 高風險職業型 | 50-year-old Taiwanese male taxi driver, weathered sun-kissed face, short thinning hair, kind crinkled eyes, hardworking earnest smile, wearing a beige short-sleeve collared utility shirt over a white undershirt |
| 17 | `yijun` | 陳怡君 | 42 歲 / 女性 | 外商業務經理 / 高房貸家庭型 | 42-year-old Taiwanese woman multinational sales director, polished shoulder-length layered dark hair, elegant confident gaze, wearing a sharply tailored navy blue blazer over an ivory crepe blouse with subtle pearl stud earrings |
| 18 | `yixiang` | 高奕翔 | 27 歲 / 男性 | 健身教練（自由接課） / 身體即資本型 | 27-year-old Taiwanese male freelance fitness coach, athletic muscular build, clean high-and-tight fade haircut, healthy tan, radiant friendly smile, wearing a dark heather-grey athletic compression crewneck tee |


### Claude verification and changes (2026-10-10)
- Per user request, `/api/dev/gen-img` now tries **NVIDIA NIM first** (`https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-dev`, override with `NVIDIA_IMAGE_MODEL`; sizes snapped to multiples of 64 within 768–1344, 28 steps, 60 s timeout) and falls back to Workers AI `flux-1-schnell`. Response header `X-Image-Provider` says which one answered. NIM `flux.1-schnell` timed out in testing; `flux.1-dev` answers in ~5 s.
- NIM returns `finishReason: CONTENT_FILTERED` for essentially every human portrait prompt (tried anime / painterly / plain wording), so portraits come from the Workers AI fallback automatically; scenes and the title (no people) come from NIM.
- Workers AI flux-1-schnell rejects `width`/`height`, so the fallback no longer sends them (square output).
- Generated: new `client/assets/title.jpg` (NIM, 1344×768; previous kept as `title.old.jpg`) and all 18 portraits (`client/assets/portraits/*.jpg`, Workers AI). `wanting` and `ziyuan` were regenerated once to remove signature-like scribbles. All reviewed on a contact sheet: consistent style, no text.

### NIM portrait findings (2026-10-10, follow-up)
NIM can generate portraits; its content filter rejects certain wordings, not people in general. Tested triggers: numeric ages (`31-year-old`), `plain ... background`, and some clothing terms (`heather-gray crewneck sweatshirt`, likely also `compression`, `undershirt`). Seeds do not matter (same prompt filtered on seeds 0–4), so the check is on the text.
Fix: every client in `generate-portraits.mjs` has a short `nim` description (job, age in words, hair, glasses, simple clothing); the script sends it as `alt`, and `/api/dev/gen-img` tries NIM with the full prompt, then NIM with `alt`, then Workers AI. `nimSafe()` also rewrites numeric ages. Test: jiahao, yixiang, ziyuan, peishan all came back from NIM (`X-Image-Provider: nvidia-nim`). The 18 committed portraits were made before this fix (Workers AI) and were not replaced.

### Generic portraits for AI-generated clients (2026-10-10)
- 11 generic portraits `client/assets/portraits/pool_{m,f}_{20s,30s,40s,50s,60s}.jpg` + `pool_x.jpg`, all generated by NIM (`node tools/generate-portraits.mjs pool`), lossy import, 512 px.
- Server: `poolPortraitFor(age, gender)` in `server/src/ai.ts` sets `portrait` for AI-generated clients; `publicView` adds `portraits: { clientId: poolKey }` for generated clients.
- Client: `Portraits.get_texture(id)` resolves the id through `Net.state.portraits` first, so the board territory, client book and claim panels (which only know the id) show the face too.
- No runtime image generation (decided with the user: simpler and no quota use).
