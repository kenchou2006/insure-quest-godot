extends Control
## QuestLayer: hosts the mission pages on the game screen and decides which one the server state
## calls for on the player's own turn. Spectators and ?classic=1 keep the original panels.
##   roll stage                → map (game.gd) + DiceRollOverlay when the dice fall
##   session (new meeting)     → ArrivalBriefModal
##   session discover          → ClientDialogueView ⇄ ClueBoardView
##   session plan              → ProposalBuilderView
##   session objection         → ObjectionBuilderView
##   session result            → ComplianceScanView → MissionResultModal
##   meeting paused (info)     → MissionResultModal (stage result)
##   any other event           → LifeEventModal
## Page switches go through SceneTransitionManager; modals over the map use their own entrance.
## 每次換頁後同步流程狀態（QuestFlow）：簡報／事件 → 任務簡報，五個計時頁 → 客戶訪談，
## 結算 → 任務結算，沒有頁面 → 地圖待機（剛按「前往下一站」則先播下一站解鎖）。
## Only the visible page takes the mouse; with no page up this layer ignores the mouse entirely.

const UiLock := preload("res://scripts/ui_lock.gd")
const DiceRollOverlay := preload("res://scripts/quest/pages/dice_roll_overlay.gd")
const ToastMessage := preload("res://scripts/quest/widgets/toast_message.gd")
const FocusOverlay := preload("res://scripts/quest/widgets/focus_overlay.gd")
const SettingsModal := preload("res://scripts/quest/widgets/settings_modal.gd")
const PAGES := {
	"arrival": preload("res://scripts/quest/pages/arrival_brief_modal.gd"),
	"dialogue": preload("res://scripts/quest/pages/client_dialogue_view.gd"),
	"clues": preload("res://scripts/quest/pages/clue_board_view.gd"),
	"proposal": preload("res://scripts/quest/pages/proposal_builder_view.gd"),
	"objection": preload("res://scripts/quest/pages/objection_builder_view.gd"),
	"compliance": preload("res://scripts/quest/pages/compliance_scan_view.gd"),
	"event": preload("res://scripts/quest/pages/life_event_modal.gd"),
	"result": preload("res://scripts/quest/pages/mission_result_modal.gd"),
}
## Pages that run the meeting clock
const TIMED := ["dialogue", "clues", "proposal", "objection", "compliance"]

var game: Control
var current := ""
var page: Control = null
var dice: Control
var toast: Control
var focus: Control
var settings: Control
var _pages_root: Control
var _switching := false
var _pending_state: Dictionary = {}
var _had_session := false
var _awaiting := false


func _init() -> void:
	name = "QuestLayer"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_pages_root = Control.new()
	_pages_root.name = "Pages"
	_pages_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pages_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pages_root)
	dice = DiceRollOverlay.new()
	dice.connect("skip_requested", func():
		if game and game.has_method("skip_move_animation"):
			game.skip_move_animation()
	)
	add_child(dice)
	focus = FocusOverlay.new()
	add_child(focus)
	toast = ToastMessage.new()
	add_child(toast)
	settings = SettingsModal.new()
	settings.connect("leave_requested", _leave)
	add_child(settings)
	Net.server_error.connect(_on_server_error)
	Net.state_changed.connect(_on_net_state)
	# A rebuilt layer (rotation / layout change) restores the page the record says we were on
	_had_session = not GameState.my_session().is_empty()


func active() -> bool:
	return not GameState.classic_ui


func has_page() -> bool:
	return page != null and is_instance_valid(page) and page.visible


## True when this layer shows the given state itself (game.gd hides the classic panels then)
func owns(s: Dictionary) -> bool:
	if not active() or str(s.get("phase", "")) != "playing":
		return false
	return not GameState.my_session().is_empty() or not GameState.my_event().is_empty()


func _on_net_state(_s: Dictionary) -> void:
	_awaiting = false


## Called by game.gd on every state (after its own deferral for dice / pawn motion)
func route(s: Dictionary) -> void:
	if not active():
		_close_page()
		return
	var want := _wanted(s)
	if _switching:
		_pending_state = s
		return
	if want == current and has_page():
		page.call("refresh", s)
		_sync_flags()
		return
	_switch(want, s)


func _wanted(s: Dictionary) -> String:
	if str(s.get("phase", "")) != "playing":
		return ""
	var sess := GameState.my_session()
	if not sess.is_empty():
		_had_session = true
		if not bool(GameState.flag("arrived", false)):
			return "arrival"
		match str(sess.get("step", "")):
			"discover":
				return str(GameState.flag("discover_page", "dialogue"))
			"plan":
				return "proposal"
			"objection":
				return "objection"
			"result":
				# The objection page keeps the screen until its reaction and evaluation are read
				if bool(GameState.flag("hold_objection", false)):
					return "objection"
				return "result" if bool(GameState.flag("scan_done", false)) else "compliance"
		return ""
	# A meeting ended on this visit: the next one opens with a new arrival brief
	if _had_session:
		_had_session = false
		GameState.set_flag("arrived", false)
		GameState.set_flag("discover_page", "dialogue")
		GameState.set_flag("scan_done", false)
		GameState.set_flag("hold_objection", false)
	var ev := GameState.my_event()
	if not ev.is_empty():
		return "result" if _is_stage_pause(ev) else "event"
	return ""


## A paused primary-case meeting ("第一次會談完成｜…" / "方案已提交｜…")
func _is_stage_pause(ev: Dictionary) -> bool:
	if str(ev.get("kind", "")) != "info":
		return false
	var t := str(ev.get("title", ""))
	return t.begins_with("第一次會談完成") or t.begins_with("方案已提交")


func _switch(want: String, s: Dictionary) -> void:
	var from_modal := has_page() and bool(page.get("modal"))
	var to_modal := _is_modal(want)
	_switching = true
	if want == "" and not has_page():
		_switching = false
		current = ""
		_after_switch(s)
		return
	# Modal ↔ map: the modal's own fade; full pages: the deep-green veil
	if (want == "" and from_modal) or (to_modal and not has_page()):
		_swap(want, s)
		_switching = false
		_after_switch(s)
		return
	await SceneTransitionManager.run(func(): _swap(want, s))
	_switching = false
	_after_switch(s)


## 目前頁面對應的流程狀態
func _sync_flow(want: String) -> void:
	if Engine.is_editor_hint():
		return
	var to := ""
	if want == "arrival" or want == "event":
		to = QuestFlow.MISSION_BRIEFING
	elif want == "result":
		to = QuestFlow.MISSION_RESULT
	elif want in TIMED:
		to = QuestFlow.CLIENT_INTERVIEW
	elif want == "":
		# 骰子與棋子還在動：由 game.gd 在到站後再交給任務層
		if QuestFlow.state in [QuestFlow.DICE_ROLLING, QuestFlow.PLAYER_MOVING] and game and bool(game.get("_is_overlay_deferred")):
			return
		if QuestFlow.state == QuestFlow.NEXT_STAGE_UNLOCKED:
			return
		if QuestFlow.unlock_pending:
			QuestFlow.unlock_pending = false
			to = QuestFlow.NEXT_STAGE_UNLOCKED
		else:
			to = QuestFlow.MAP_IDLE
	if to != "":
		QuestFlow.go(to, "頁面：" + (want if want != "" else "地圖"))


func _is_modal(id: String) -> bool:
	return id in ["arrival", "event", "result"]


func _after_switch(s: Dictionary) -> void:
	_sync_flags()
	_sync_flow(current)
	if not _pending_state.is_empty():
		var p := _pending_state
		_pending_state = {}
		route(p)
	elif has_page():
		page.call("refresh", Net.state if not Net.state.is_empty() else s)


func _swap(want: String, s: Dictionary) -> void:
	_close_page()
	current = want
	if want == "":
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if game and game.has_method("on_map_shown"):
			game.on_map_shown()
		AudioManager.set_music_state("map")
		TensionManager.set_active(false)
		GameState.timed_page = false
		TutorialManager.set_page("")
		return
	# Page flags (budget, coverage, hesitation …) belong to the page that raised them
	TensionManager.flags.clear()
	var p: Control = PAGES[want].new()
	p.name = want.capitalize().replace(" ", "") + "Page"
	p.set("page_id", want)
	p.set("layer", self)
	p.connect("act", _act)
	p.connect("go", _go)
	_pages_root.add_child(p)
	page = p
	p.visible = true
	toast.set("top_offset", 12.0 if _is_modal(want) else 84.0)
	p.call("build")
	p.call("refresh", s)
	GameState.timed_page = want in TIMED
	TensionManager.set_active(want in TIMED or want == "event")
	AudioManager.set_music_state("meeting" if want in TIMED else ("map" if want == "event" else AudioManager.music_state()))
	TutorialManager.set_page(want, p.call("idle_lines"), Callable(p, "key_rects"))
	# 頁面一建好就切換流程狀態（不等轉場淡出）
	_sync_flow(want)
	p.call("on_open")
	_first_guide.call_deferred(p)


func _first_guide(p: Control) -> void:
	if p != page or not is_instance_valid(p):
		return
	await get_tree().create_timer(0.45).timeout
	# Never during a page change (the guide would open and close on the way out)
	while is_instance_valid(p) and p == page and (SceneTransitionManager.active or _switching):
		await get_tree().process_frame
	if p != page or not is_instance_valid(p) or not p.visible:
		return
	# 版面穩定後才取要照亮的位置：卡片進場、文字換行後按鈕還會移動，太早取會照亮錯的地方，
	# 秘書對話框也會因此蓋住真正的主要按鈕
	var last: Array = p.call("highlight_rects")
	for k in range(40):
		await get_tree().process_frame
		if p != page or not is_instance_valid(p):
			return
		var now: Array = p.call("highlight_rects")
		if now == last:
			break
		last = now
	var lines: Array = p.call("guide_lines")
	if not lines.is_empty():
		TutorialManager.first_time(str(p.get("page_id")), lines, p.call("highlight_rects"), p.call("key_rects"),
			{"highlights": Callable(p, "highlight_rects"), "avoid": Callable(p, "key_rects")})


## The secretary's small corner icon belongs to the other screens: on a mission page it would sit
## over the main button, and the page has its own 培訓秘書 button
func _process(_delta: float) -> void:
	if not has_page():
		return
	var g := GameState.secretary()
	if g == null:
		return
	var icon: Variant = g.get("_icon")
	if icon is Control and (icon as Control).visible:
		(icon as Control).visible = false


func _close_page() -> void:
	if toast:
		toast.call("hide_now")
	if page != null and is_instance_valid(page):
		page.call("on_close")
		page.queue_free()
	page = null
	current = ""
	TutorialManager.close()
	if focus and focus.visible:
		focus.call("close", true)


## The layer itself never takes the mouse; each page decides (a modal folded to peek at the map
## lets the map through)
func _sync_flags() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- Page requests --------------------------------------------------------------------------------

func _act(action: Dictionary) -> void:
	_awaiting = true
	UiLock.log_event("quest_act:" + str(action.get("type", "")))
	Net.act(action)


func _go(target: String, data: Dictionary) -> void:
	match target:
		"start_meeting":
			GameState.set_flag("arrived", true)
		"dialogue", "clues":
			GameState.set_flag("discover_page", target)
		"scan_done":
			GameState.set_flag("scan_done", true)
		"map":
			pass
	if data.has("toast"):
		toast.call("show_message", str(data.toast), str(data.get("kind", "info")))
	route(Net.state)


func _on_server_error(msg: String) -> void:
	if not has_page():
		return
	_awaiting = false
	toast.call("show_message", msg, "error", 4.0)
	page.call("server_error", msg)


## Critical decision around a control; awaits the player's answer (true = confirmed)
func critical(target: Control, heading: String, body: String, ok_text := "確認送出") -> bool:
	focus.call("open", target, heading, body, ok_text)
	var result: Array = [null]
	var on_ok := func(): result[0] = true
	var on_cancel := func(): result[0] = false
	focus.connect("confirmed", on_ok, CONNECT_ONE_SHOT)
	focus.connect("cancelled", on_cancel, CONNECT_ONE_SHOT)
	while result[0] == null and is_instance_valid(focus) and focus.visible:
		await get_tree().process_frame
	if result[0] == null:
		# Confirm fires after the overlay closes; give it the frame it needs
		await get_tree().process_frame
	if focus.is_connected("confirmed", on_ok):
		focus.disconnect("confirmed", on_ok)
	if focus.is_connected("cancelled", on_cancel):
		focus.disconnect("cancelled", on_cancel)
	return result[0] == true


func open_settings() -> void:
	settings.call("open")


func show_toast(text: String, kind := "info") -> void:
	toast.call("show_message", text, kind)


## 離開培訓 from the settings: 繼續培訓 / 儲存並返回主畫面 / 放棄本次培訓
func _leave() -> void:
	if game and game.has_method("_confirm_leave"):
		game.call("_confirm_leave")


## The roll animation for this turn (DiceRollOverlay); returns its duration
func play_dice(roller: String, value: int, mine: bool) -> float:
	return dice.call("play", roller, value, mine)


func _exit_tree() -> void:
	GameState.timed_page = false
	TensionManager.set_active(false)
	GameState.hold("critical", false)
	GameState.hold("settings", false)
	GameState.hold("paused", false)
