# 3D 客戶生活圈

參考使用者提供的城市圖，以實際 3D 幾何重新建構環形道路、弧形玻璃顧問中心、商辦、醫院停機坪、幼兒園、屋頂泳池會館、住宅陽台、工地吊車、河岸與橋樑。這是適合即時運作的程序化模型版本，並非原圖的照片級複製。

## 執行

- 正式遊戲沿用 `client/scripts/ui/board.gd`，24 格順序、伺服器位置和領地資料不變。
- 在 Godot 開啟 `client/scenes/preview/12_city_studio.tscn`，按 F6，進入城市建模工作室。建築配置是本次本機預覽，不會同步至多人房間，也不會存檔。
- 滾輪或 ＋／－ 縮放；中鍵拖曳平移；右鍵拖曳旋轉；「邊移」切換滑鼠邊緣平移；「復位」重設鏡頭。手機可使用縮放按鈕。
- 點選圓形節點查看名稱、類型與簽約客戶。領地外圈使用擁有者顏色。
- 工作室的「放置建築」使用 2×2 格樣板；綠色可放置，紅色代表重疊、道路或界外。「旋轉」旋轉 90 度。

## 模組

- `scripts/city/city_grid.gd`：XZ 整數網格，負座標向下取整，明確的 footprint、防重疊、旋轉占地、釋放占用、半透明放置預覽與向上彈出 Tween。
- `scripts/city/city_camera.gd`：正交投影、縮放界限、平移範圍、可選邊緣平移與軌道旋轉。由棋盤 Control 路由輸入，操作旁邊的 UI 不會移動鏡頭。
- `scripts/ui/city_architecture.gd`：建築幾何、玻璃窗格、樓層、屋頂、入口、台階、道路、橋墩、欄杆、植栽與地景。亂數固定種子，畫面可重現。
- `scripts/ui/board_city.gd`：組合場景、相機、光影、任務節點、棋子、領地及地標占地；依材質合併靜態幾何，減少繪製呼叫。
- `scripts/city/city_traffic.gd`：96 個單向圓環 AStar3D 節點，連接兩側橋樑；汽車依剩餘移動距離逐段行駛並朝向道路方向。車流為裝飾性，不含號誌、碰撞避讓或遊戲經濟邏輯。

## 換成 GLB / PackedScene

Godot 匯入 `.glb` 後可作為 PackedScene。模型需以地面中心為原點，單位為公尺，局部 XZ 邊界（含屋簷與旋轉後外緣）應完全落於宣告占地內。此網格依明確 footprint 驗證占用，不會推測任意模型的包圍盒；請先在建模工具校正尺寸／原點。

```gdscript
var scene: PackedScene = load("res://assets/buildings/office.glb")
grid.begin_preview(scene, Vector2i(4, 3))
grid.update_preview(mouse_ground_position, quarter_turns)
var instance: Node3D = grid.commit_preview() # invalid -> null
# Or place directly:
var placed: Node3D = grid.place(scene, Vector2i(-6, -9), Vector2i(4, 3), 1)
```

現有地標、道路與外緣綠化已預留占地。修改地標尺寸或位置時，同步更新 `_reserve_landmarks()`；自訂地標應先 `reserve()` 成功再放置幾何。新增建築不會更改回合規則。

## 光影

預設仍使用專案的 GL Compatibility / Web 渲染器。夕陽方向 `(-42, -32, 0)`、暖光 `#ffddb0`、能量 `0.85`；環境光 `#a5c2cd`、能量 `0.38`。玻璃材質 roughness `0.24`、metallic `0.25`，窗戶 emission `0.25`。水面使用程序化細波紋 shader。

Godot 4.7 Compatibility 可使用簡化 SSAO，本場景設定 radius `1.5`、intensity `1.3`。`board_city.gd` 的 `high_quality_lighting` 預設關閉；桌面以 Forward+ 執行且開啟此選項時才啟用 SDFGI / Glow。未將 Web 改為 Forward+。可依 GPU 降低或關閉 SSAO；目前未量測各型手機的 FPS，也未實測 Forward+ 進階選項。

官方文件：[渲染器差異](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html)、[環境與 SSAO](https://docs.godotengine.org/en/latest/tutorials/3d/environment_and_post_processing.html)、[AStar3D](https://docs.godotengine.org/en/4.5/classes/class_astar3d.html)。

## 驗證

```powershell
godot --headless --path client res://tests/city_systems.tscn
```

測試涵蓋占用、界外、空占地、旋轉、釋放、紅綠預覽、Tween、24 節點、擲骰暫停、跨起點、領地、相機投影點選、縮放和平移界限、橋樑尋路、車輛前進與離場棋子清理。預覽場景與測試不包含於 Web 匯出。

## 材質來源

`client/assets/city/glass-facade.png` 使用內建 imagegen 產生，作為 3D 玻璃外牆貼圖；城市與建築本體都是可旋轉檢視的幾何。沒有使用付費或外部授權 3D 模型。完整提示詞見同目錄 `imagegen-prompt.txt`。
