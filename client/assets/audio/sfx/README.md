# 音效插槽（可替換）

遊戲裡的每個音效都是一個「插槽」，由 `scripts/quest/audio_manager.gd`（autoload `AudioManager`）播放。

- 這個資料夾放了 `插槽名稱.ogg`、`.wav` 或 `.mp3` 時，就使用那個檔案。
- 沒有放檔案時，使用程式合成的柔和暫用音效，所以沒有任何插槽是無聲的。

同一個插槽不會疊加播放：重播時會重新開始，冷卻時間內的重複觸發會被略過。Master 匯流排上有硬式限幅器（-1 dB），避免音量突然爆大。

## 匯流排

| 匯流排 | 內容 | 跟隨的設定滑桿 |
| --- | --- | --- |
| Music | 背景音樂（MusicManager） | 背景音樂 |
| UI | 按鈕、卡片、結果音效 | 音效 |
| Tension | 倒數、危機節拍、合規警示 | 音效 |
| Voice | 培訓秘書語音（TTS） | 秘書語音 |
| Ambience | 辦公室／城市環境底噪 | 背景音樂 |

## 單次音效插槽

| 插槽 | 用途 |
| --- | --- |
| `ui_hover` | 按鈕滑鼠移入 |
| `ui_click` | 按鈕點擊 |
| `dice_roll` | 骰子滾動 |
| `dice_land` | 骰子落桌 |
| `piece_step` | 棋子每走一格 |
| `clue_scan` | 點選線索／掃描 |
| `card_flip` | 卡片翻面 |
| `gold_scan` | 關鍵線索正確分類的金色掃描 |
| `trust_up` / `trust_down` | 信任上升／下降 |
| `budget_over` | 方案超出預算 |
| `compliance_risk` | 標記到合規風險、說出不當說法 |
| `event_minor` / `event_major` | 一般／重大事件 |
| `mission_success` / `mission_fail` | 任務成功／失誤 |
| `node_unlock` | 新節點、新客戶解鎖 |
| `xp_gain` | 經驗值增加 |
| `confirm_soft` | 柔和確認（方案平衡、需求確認） |
| `timer_warn` | 剩 30 秒的提示音 |
| `timer_tick` / `timer_tick_strong` | 最後 10 秒每秒一次的低音節拍（最後 3 秒較明確） |
| `heartbeat` | 進入關鍵決策時的低沉心跳 |
| `toast` | 注意／危機訊息出現 |
| `page_whoosh` | 頁面轉場 |

## 循環層

循環層的淡入淡出約為 1–1.5 秒，不會突然切斷。

| 插槽 | 用途 |
| --- | --- |
| `tension_warn` | 注意狀態的低頻節拍 |
| `tension_danger` | 危機狀態的節奏與低音 |
| `tension_critical` | 關鍵決策時的節拍 |
| `ambience_room` | 環境底噪 |

## 音樂狀態

只有一首背景音樂（`late_night_ledger.ogg`）。不同狀態是用 Music 匯流排上的低通濾波與音量來區分，淡入淡出 1.2 秒：

| 狀態 | 用在哪裡 |
| --- | --- |
| `map` | 地圖 |
| `meeting` | 會談（較收斂，突出思考） |
| `critical` | 關鍵決策 |
| `result_success` | 結算（成功版本） |
| `result_reflect` | 結算（反思版本） |
| `report` | 培訓報告 |

拿到正式的分層音樂後，可以把各層改成獨立的循環檔案。
