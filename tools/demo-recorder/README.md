# Playwright Demo Recorder (3-Minute Demo Video Footage)

This tool automatically drives the **Insure Quest (人生顧問局)** web client through scripted, reproducible scenarios using Playwright, recording raw video footage and generating chapter markers for the 3-minute hackathon demo video.

It builds upon the `window.iqAuto` automation bridge (`?automation=1&demo=1`) implemented in Batch 4 & 5.

---

## 1. Setup

Navigate to this folder and install dependencies:

```bash
cd tools/demo-recorder
npm install
npx playwright install chromium
```

> **Note**: If `ffmpeg` is installed and available on your system `PATH`, the script will also automatically cut individual `NN-<scene>.mp4` clips for each chapter marker (encoded as H.264, CRF 18, 30 fps).

---

## 2. Usage

Ensure your local game server is running (e.g. `http://127.0.0.1:8787` via `npm run dev` in `server/`).

### Quick Start
```bash
# Record all scenes with default settings (headed 1080p)
npm run record
```

### Command Line Options

```bash
node record.mjs [--url http://127.0.0.1:8787] [--size 1920x1080] [--headless] [--scenes menu,interview,result,trainer] [--code CARDIF-DEMO-2026]
```

| Flag | Default | Description |
|---|---|---|
| `--url <url>` | `http://127.0.0.1:8787` | Base URL of the running Insure Quest server |
| `--size <WxH>` | `1920x1080` | Viewport and video recording resolution |
| `--headless` | `false` | Run headless (default is headed; Chromium headed mode is more reliable for WebGL canvas) |
| `--scenes <list>` | `menu,interview,result,trainer` | Comma-separated list of scenes to record |
| `--code <code>` | `CARDIF-DEMO-2026` | Judge demo code (or set `DEMO_CODE` environment variable) |

---

## 3. Scenes & Chapter Markers

The script records the following key moments in sequence:

1. **`menu`** (`主選單與評審體驗登入`)
   - Title screen & menu hold for 3 seconds.
   - Judge demo code authentication & toast notification.
2. **`interview`** (`單人對戰與深度需求訪談`)
   - Start solo practice against 2 senior bots (`資深顧問`).
   - Roll dice on the board; deterministic demo seed lands on mortgage engineer client (劉家豪).
   - Click 2 life scene hotspots (`hotspot:0`, `hotspot:1`).
   - Type regulatory violation statement: `「這張保單保證年報酬 6%，比定存穩賺不賠」`.
   - Wait for compliance red light warning flash; hold 3 seconds for dramatic effect.
   - Type compliant open-ended question: `「如果收入中斷三個月，家裡哪些支出一定要先顧住？」`.
   - Click one suggested question from standard list.
3. **`result`** (`方案配置、異議處理與十年信件`)
   - Proceed to plan allocation (`進入方案配置 →`).
   - Adjust resource coins (decrement growth to unlock, increment protect).
   - Select 2 matching coverage cards: `工作能力防線` & `家庭責任防線`.
   - Submit plan (`提交方案 →`).
   - Objection handling: select best answer `「投資照樣留著長期成長」`.
   - Result screen: display score stamp, scroll smoothly through 90-day stress test.
   - Hold 4 seconds on the **10-Year Financial Timeline** chart (`十年財務人生`).
   - Scroll down and hold 4 seconds on the **Letter from 10 Years Later** (`申訴副本` triggered by the earlier violation).
   - Click `繼續 →`.
4. **`trainer`** (`講師管理與弱點熱力圖`, optional)
   - Open `培訓紀錄`.
   - Switch to `弱點熱力圖` (weakness heatmap) tab (active when logged in as trainer via `TRAINER_EMAILS`).
   - Hold 4 seconds.

---

## 4. Output Structure

Recordings are saved to `recordings/<YYYYMMDD-HHmm>/`:

```
recordings/
└── 20261009-2330/
    ├── raw.webm           # Full raw recording from start to finish
    ├── chapters.json      # Array of { scene, label, start, end } timestamps in seconds
    ├── 01-menu.mp4        # Individual chapter cut (if ffmpeg is available)
    ├── 02-interview.mp4   # Individual chapter cut
    ├── 03-result.mp4      # Individual chapter cut
    └── 04-trainer.mp4     # Individual chapter cut
```

If an error or step timeout occurs, an `error-<scene>.png` screenshot is captured in the current directory and the waiting element name is reported.

---

## 5. Tips for the Video Editor

- **High-Quality OBS / QuickTime Capture**:
  Playwright's built-in WebM video is compressed and optimized for draft review and chapter timing. For the final high-bitrate video footage, run the script headed (`node record.mjs`) and capture the browser window simultaneously at 60 fps using OBS Studio or QuickTime. Because the script executes the exact same deterministic sequence and cursor movements every time, you can re-run takes as needed.
- **Fixed vs. Live AI Responses**:
  - For rehearsals and predictable timing, set `AI_PROVIDER=mock` in `server/.dev.vars`. The mock provider returns instant, fixed responses.
  - For the final take, use the real provider (NVIDIA NIM / Workers AI) for authentic dialogue.
- **Selective Scene Re-Recording**:
  You can re-record any scene individually using `--scenes`. For example:
  ```bash
  node record.mjs --scenes interview
  node record.mjs --scenes result
  ```
- **Visible Cursor Styling**:
  The recorder automatically injects a semi-transparent cursor dot with a click pulsation effect, so viewer attention is naturally drawn to interactive UI elements.
