@tool
extends Control
## 編輯器預覽：在 Godot 2D 編輯器直接看到各畫面的設計（不必連線）。
## 資料來自 states.json（伺服器 tools/dump-preview-states.ts 跑一場電腦對局擷取）；也可以 F6 單獨執行這個場景。
## 這個節點同時扮演畫面需要的 main（toast、換頁等呼叫在預覽中都不做事）。

const MenuScreen := preload("res://scripts/ui/menu.gd")
const LobbyScreen := preload("res://scripts/ui/lobby.gd")
const GameScreen := preload("res://scripts/ui/game.gd")
const ReportScreen := preload("res://scripts/ui/report.gd")
const STATES_PATH := "res://scenes/preview/states.json"
const SIZES := {"desktop": Vector2i(1280, 720), "phone_portrait": Vector2i(480, 854)}

## 要預覽的畫面：menu 主選單、lobby 大廳、roll 棋盤、discover／plan／objection／result 面談各階段、event 人生事件、ended 結算報告
@export_enum("menu", "lobby", "roll", "discover", "plan", "objection", "result", "event", "ended") var screen: String = "roll":
	set(v):
		screen = v
		_queue_rebuild()
@export_enum("desktop", "phone_portrait") var layout: String = "desktop":
	set(v):
		layout = v
		_queue_rebuild()

## 0＝頂端、1＝捲到底：預覽畫面下方的內容（對話串、信件）
@export_range(0.0, 1.0) var scroll: float = 0.0:
	set(v):
		scroll = v
		_queue_rebuild()

var _pending := false


func _ready() -> void:
	# 延後建構：避免父節點仍在加入子節點時，畫面 _ready 內播放音效失敗
	_queue_rebuild()
	# 執行時加上 -- --capture=路徑.png：等動畫跑完後截圖並結束（用於文件與檢查）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			get_window().size = SIZES.get(layout, SIZES["desktop"])
			get_tree().root.content_scale_size = SIZES.get(layout, SIZES["desktop"])
			await get_tree().create_timer(6.0 if scroll > 0.0 else 3.0).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(10))
			get_tree().quit()


func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending:
		return
	_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_pending = false
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var sz: Vector2i = SIZES.get(layout, SIZES["desktop"])
	custom_minimum_size = Vector2(sz)
	size = Vector2(sz)
	UI.set_layout_profile(layout, sz)
	theme = UI.make_theme()

	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var data := _load_states()
	var key: String = "lobby" if screen == "menu" else screen
	var st: Dictionary = data.get(key, {})
	Net.static_data = data.get("static", {})
	Net.player_id = str(data.get("playerId", ""))
	Net.room_code = "DEMO"
	Net.is_solo = false
	Net.spectator = false
	Net.state = st
	# 主選單預覽顯示登入後的樣子（等級與頭像），其他畫面維持訪客
	if screen == "menu":
		Net.user_profile = {"user": {"id": "demo", "name": "王顧問", "email": "", "picture": null, "trainer": false},
			"level": {"level": 3, "title": "專業顧問", "xp": 520, "floor": 400, "next": 800, "games": 7}}
		Net.avatar_tex = load("res://icon.svg")
	else:
		Net.user_profile = {}
		Net.avatar_tex = null

	var node: Control
	match screen:
		"menu": node = MenuScreen.new()
		"lobby": node = LobbyScreen.new()
		"ended": node = ReportScreen.new()
		_: node = GameScreen.new()
	node.set("main", self)
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	if screen != "menu" and node.has_method("refresh") and not st.is_empty():
		node.refresh(st)
	if scroll > 0.0:
		_apply_scroll.call_deferred()


func _apply_scroll() -> void:
	# 面談／事件面板會延遲顯示（等擲骰過場）且重建時會歸零：輪詢到它可見且可捲動後再捲
	for _i in 16:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			return
		var done := false
		for sc in find_children("*", "ScrollContainer", true, false):
			var bar: VScrollBar = sc.get_v_scroll_bar()
			if sc.is_visible_in_tree() and bar.max_value > bar.page:
				sc.scroll_vertical = int((bar.max_value - bar.page) * scroll)
				done = true
		if done:
			return


func _load_states() -> Dictionary:
	var f := FileAccess.open(STATES_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


# ───────── 畫面會呼叫的 main 介面（預覽中不做事） ─────────

func toast(_text: String, _color := Color.WHITE, _secs := 3.0) -> void:
	pass

func create_and_join(_bots: Array, _solo: bool) -> void:
	pass

func join_room(_code: String) -> void:
	pass

func resume_seat() -> void:
	pass

func leave_to_menu() -> void:
	pass

func show_menu() -> void:
	pass

func show_records() -> void:
	pass
