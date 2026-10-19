@tool
extends Node
## QuestFlow（全域）：單人培訓大富翁流程的狀態機。
##   MAP_IDLE → DICE_ROLLING → PLAYER_MOVING → MISSION_BRIEFING → CLIENT_INTERVIEW
##   → MISSION_RESULT → NEXT_STAGE_UNLOCKED → MAP_IDLE
## 點數、站點、會談與分數一律由後端規則引擎決定；這裡只記錄畫面現在處於哪個狀態，並在動畫
## 與畫面切換期間擋下重複點擊，讓流程不會因快速連點而錯亂。
## 不在 NEXT 表內的切換仍會照後端狀態執行（畫面不能卡住），但會輸出警告方便追查。

signal state_changed(from: String, to: String)

const UiLock := preload("res://scripts/ui_lock.gd")

const MAP_IDLE := "MAP_IDLE"
const DICE_ROLLING := "DICE_ROLLING"
const PLAYER_MOVING := "PLAYER_MOVING"
const MISSION_BRIEFING := "MISSION_BRIEFING"
const CLIENT_INTERVIEW := "CLIENT_INTERVIEW"
const MISSION_RESULT := "MISSION_RESULT"
const NEXT_STAGE_UNLOCKED := "NEXT_STAGE_UNLOCKED"
const STATES := [MAP_IDLE, DICE_ROLLING, PLAYER_MOVING, MISSION_BRIEFING, CLIENT_INTERVIEW, MISSION_RESULT, NEXT_STAGE_UNLOCKED]
## 各狀態預期的下一步
const NEXT := {
	MAP_IDLE: [DICE_ROLLING, MISSION_BRIEFING, CLIENT_INTERVIEW, MISSION_RESULT],
	DICE_ROLLING: [PLAYER_MOVING, MAP_IDLE],
	PLAYER_MOVING: [MISSION_BRIEFING, CLIENT_INTERVIEW, MISSION_RESULT, MAP_IDLE],
	MISSION_BRIEFING: [CLIENT_INTERVIEW, MISSION_RESULT, MAP_IDLE],
	CLIENT_INTERVIEW: [MISSION_RESULT, MISSION_BRIEFING, MAP_IDLE],
	MISSION_RESULT: [NEXT_STAGE_UNLOCKED, MISSION_BRIEFING, CLIENT_INTERVIEW, MAP_IDLE],
	NEXT_STAGE_UNLOCKED: [MAP_IDLE, MISSION_BRIEFING],
}
## 動畫中的狀態：期間不接受玩家操作
const ANIMATING := [DICE_ROLLING, PLAYER_MOVING, NEXT_STAGE_UNLOCKED]
## 各狀態的中文名稱（除錯訊息與測試用）
const LABELS := {
	MAP_IDLE: "地圖待機", DICE_ROLLING: "擲骰中", PLAYER_MOVING: "棋子移動中", MISSION_BRIEFING: "任務簡報",
	CLIENT_INTERVIEW: "客戶訪談", MISSION_RESULT: "任務結算", NEXT_STAGE_UNLOCKED: "下一站解鎖",
}

var state := MAP_IDLE
## 最近 30 次切換：[from, to, 原因, 毫秒]
var history: Array = []
## 結算卡按「前往下一站」後，回到地圖時先播放解鎖動畫
var unlock_pending := false
## 防連點保護剩餘秒數（遊戲時間，和動畫同一個時間基準）
var _guard := 0.0


func _process(delta: float) -> void:
	if _guard > 0.0:
		_guard = maxf(0.0, _guard - delta)


func go(to: String, reason := "") -> bool:
	if not STATES.has(to):
		push_error("QuestFlow：未知的狀態「%s」（%s）" % [to, reason])
		return false
	if to == state:
		return false
	if not (NEXT.get(state, []) as Array).has(to):
		push_warning("QuestFlow：非預期的切換 %s → %s（%s），依後端狀態照樣切換" % [state, to, reason])
	var from := state
	state = to
	history.append([from, to, reason, Time.get_ticks_msec()])
	if history.size() > 30:
		history.pop_front()
	if not Engine.is_editor_hint():
		UiLock.log_event("flow:%s→%s %s" % [from, to, reason])
	state_changed.emit(from, to)
	return true


func is_animating() -> bool:
	return state in ANIMATING


## 動畫、頁面切換或剛按下按鈕的短暫保護期間
func busy() -> bool:
	if Engine.is_editor_hint():
		return false
	return is_animating() or SceneTransitionManager.active or _guard > 0.0


## 一次操作的防連點：成功時接下來 sec 秒內 busy() 為 true
func claim(sec := 0.35) -> bool:
	if busy():
		return false
	_guard = sec
	return true


func can_roll() -> bool:
	return state == MAP_IDLE and not busy()


func label(s := "") -> String:
	return str(LABELS.get(s if s != "" else state, s))


## 離開遊戲畫面或新的一局
func reset() -> void:
	unlock_pending = false
	_guard = 0.0
	if state != MAP_IDLE:
		go(MAP_IDLE, "reset")
