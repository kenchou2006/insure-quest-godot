extends Control
## 主控：畫面切換、單人／多人流程、提示訊息。

const MenuScreen := preload("res://scripts/ui/menu.gd")
const LobbyScreen := preload("res://scripts/ui/lobby.gd")
const GameScreen := preload("res://scripts/ui/game.gd")
const ReportScreen := preload("res://scripts/ui/report.gd")
const RecordsScreen := preload("res://scripts/ui/records.gd")

signal layout_changed(is_portrait: bool)

var _screen: Control = null
var _screen_kind := ""
var _toasts: VBoxContainer
var _solo_bots: Array = []
var _solo := false
var _busy_label: Label


var _was_quota_exhausted := false


func _ready() -> void:
	theme = UI.make_theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 台北城市生活低對比背景紋理（暗底、低細節、營造溫暖顧問氛圍）
	if ResourceLoader.exists("res://assets/title.jpg"):
		var bg_tex := TextureRect.new()
		bg_tex.texture = load("res://assets/title.jpg")
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_tex.modulate = Color(0.35, 0.45, 0.55, 0.16)
		add_child(bg_tex)

	_toasts = UI.vbox(6)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.position.y = 12
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.z_index = 100

	_busy_label = UI.label("", 16, UI.GOLD)
	_busy_label.z_index = 100

	get_tree().root.size_changed.connect(_on_size_changed)
	_on_size_changed()

	Net.welcomed.connect(_on_welcomed)
	Net.state_changed.connect(_on_state)
	Net.server_error.connect(func(m): toast(m, UI.BAD))
	Net.connection_changed.connect(_on_connection)
	Net.reaction.connect(func(from_name, emoji): toast("%s %s" % [from_name, emoji], UI.INFO))
	Net.quota_changed.connect(func(_used: int, _limit: int, exhausted: bool):
		if exhausted:
			if not _was_quota_exhausted:
				_was_quota_exhausted = true
				toast("今日 AI 額度已用完，已改用規則版", UI.OK)
		else:
			_was_quota_exhausted = false
	)
	_init_auth()
	show_menu()
	add_child(_toasts)
	add_child(_busy_label)


func _init_auth() -> void:
	await Net.fetch_auth_config()
	var r: Array = await Net.fetch_me()
	if bool(r[0]) and Net.is_logged_in():
		var u: Dictionary = Net.get_user()
		var un: String = str(u.get("name", "")).strip_edges()
		if un != "" and (Net.player_name == "顧問" or Net.player_name == ""):
			Net.player_name = un
			Net.save_prefs()


func _on_size_changed() -> void:
	var win_size: Vector2 = Vector2(get_tree().root.size)
	if win_size.x <= 0 or win_size.y <= 0:
		return
	var scale_factor: float = 1.0
	if DisplayServer.has_method("screen_get_scale"):
		scale_factor = maxf(1.0, float(DisplayServer.screen_get_scale()))
	var css_size: Vector2 = win_size / scale_factor

	var profile: String = "desktop"
	var target_scale: Vector2i = Vector2i(1280, 720)

	if win_size.y > win_size.x:
		# 直向：手機 (<600) vs 平板 (>=600)
		if css_size.x < 600.0:
			profile = "phone_portrait"
			target_scale = Vector2i(480, 854)
		else:
			profile = "tablet_portrait"
			target_scale = Vector2i(720, 1280)
	else:
		# 橫向：手機橫放 (<500) vs 電腦 (>=500)
		if css_size.y < 500.0:
			profile = "phone_landscape"
			target_scale = Vector2i(960, 540)
		else:
			profile = "desktop"
			target_scale = Vector2i(1280, 720)

	var changed: bool = profile != UI.layout_profile
	UI.set_layout_profile(profile, target_scale)

	if get_tree().root.content_scale_size != target_scale:
		get_tree().root.content_scale_size = target_scale

	if changed:
		emit_signal("layout_changed", UI.is_portrait())
		if _screen != null and is_instance_valid(_screen) and _screen.has_method("on_layout_changed"):
			_screen.on_layout_changed(UI.is_portrait())


func _set_screen(kind: String, node: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = node
	_screen_kind = kind
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	if _toasts and _toasts.get_parent() == self:
		move_child(_toasts, get_child_count() - 1)
		move_child(_busy_label, get_child_count() - 1)


func show_menu() -> void:
	var m := MenuScreen.new()
	m.main = self
	_set_screen("menu", m)
	Net.fetch_me()


func show_records(user_id: String = "") -> void:
	var r := RecordsScreen.new()
	r.main = self
	r.target_user_id = user_id
	_set_screen("records", r)


func toast(text: String, color := UI.TEXT, secs := 3.0) -> void:
	var p := UI.panel(UI.PANEL_2, 10, 10)
	p.add_child(UI.label(text, 16, color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	_toasts.position.x = (size.x - 420) / 2.0
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func set_busy(text: String) -> void:
	_busy_label.text = text
	_busy_label.position = Vector2(16, size.y - 36)


# ───────── 流程 ─────────

func create_and_join(solo_bots: Array, solo: bool) -> void:
	set_busy("建立房間中……")
	var r := await Net.create_room()
	set_busy("")
	if not r[0]:
		toast(str(r[1]), UI.BAD, 4.0)
		return
	_solo_bots = solo_bots
	_solo = solo
	Net.join(str(r[1]))
	set_busy("連線中……")


func resume_seat() -> void:
	_solo_bots = []
	_solo = false
	Net.join(str(Net.saved_seat.get("room", "")), true)
	set_busy("回到房間中……")


func join_room(code: String) -> void:
	_solo_bots = []
	_solo = false
	Net.join(code)
	set_busy("連線中……")


func leave_to_menu() -> void:
	Net.leave()
	_solo_bots = []
	_solo = false
	show_menu()


func _on_welcomed(_data: Dictionary) -> void:
	set_busy("")
	if Net.spectator:
		toast("遊戲已開始，你將以旁觀者身分觀看", UI.INFO)
	if _solo:
		# 單人模式：自動加入電腦對手並開始
		_solo = false
		for level in _solo_bots:
			Net.send({"t": "add_bot", "level": level})
		_solo_bots = []
		Net.send({"t": "settings", "rounds": 5})
		Net.send({"t": "start"})


func _on_connection(online: bool) -> void:
	if not online and Net.room_code != "":
		set_busy("連線中斷，重新連線中……")
	elif online:
		set_busy("")


func _on_state(state: Dictionary) -> void:
	var phase := str(state.get("phase", ""))
	match phase:
		"lobby":
			if _screen_kind != "lobby":
				var l := LobbyScreen.new()
				l.main = self
				_set_screen("lobby", l)
		"playing":
			if _screen_kind != "game":
				var g := GameScreen.new()
				g.main = self
				_set_screen("game", g)
		"ended":
			if _screen_kind != "report":
				var r := ReportScreen.new()
				r.main = self
				_set_screen("report", r)
	if _screen and _screen.has_method("refresh"):
		_screen.refresh(state)
