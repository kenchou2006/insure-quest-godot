@tool
extends Control
## Main controller: screen switching, solo/multiplayer flow, and toast messages.

const MenuScreen := preload("res://scripts/ui/menu.gd")
const LobbyScreen := preload("res://scripts/ui/lobby.gd")
const GameScreen := preload("res://scripts/ui/game.gd")
const ReportScreen := preload("res://scripts/ui/report.gd")
const RecordsScreen := preload("res://scripts/ui/records.gd")
const AutomationBridge := preload("res://scripts/automation.gd")

signal layout_changed(is_portrait: bool)

var _screen: Control = null
var _screen_kind := ""
var _toasts: VBoxContainer
var _solo_bots: Array = []
var _solo := false
var _busy_label: Label
var _auto: Node = null


var _was_quota_exhausted := false


func _ready() -> void:
	# When main.tscn is opened in editor, display main menu design (other screens see scenes/preview/)
	if Engine.is_editor_hint():
		var preview: Control = load("res://scenes/preview/preview.gd").new()
		preview.screen = "menu"
		add_child(preview)
		return
	theme = UI.make_theme()
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Taipei urban life low-contrast background texture (dark base, low detail, creating a warm advisor atmosphere)
	if ResourceLoader.exists("res://assets/title.jpg"):
		var bg_tex := TextureRect.new()
		bg_tex.texture = load("res://assets/title.jpg")
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_tex.modulate = Color(0.7, 0.85, 0.75, 0.16)
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
	Net.room_closed.connect(func(m: String):
		_solo_bots = []
		_solo = false
		set_busy("")
		toast(m, UI.INFO, 4.0)
		show_menu()
	)
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
	if AutomationBridge.is_active():
		_auto = AutomationBridge.new()
		_auto.set("main", self)
		add_child(_auto)


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
		# Portrait: phone (<600) vs tablet (>=600)
		if css_size.x < 600.0:
			profile = "phone_portrait"
			target_scale = Vector2i(480, 854)
		else:
			profile = "tablet_portrait"
			target_scale = Vector2i(720, 1280)
	else:
		# Landscape: phone landscape (<500) vs desktop (>=500)
		if css_size.y < 500.0:
			profile = "phone_landscape"
			target_scale = Vector2i(800, 450)
		else:
			profile = "desktop"
			target_scale = Vector2i(1280, 720)

	var changed: bool = profile != UI.layout_profile
	UI.set_layout_profile(profile, target_scale)

	if get_tree().root.content_scale_size != target_scale:
		get_tree().root.content_scale_size = target_scale

	if changed:
		theme = UI.make_theme()
		emit_signal("layout_changed", UI.is_portrait())
		if _screen != null and is_instance_valid(_screen) and _screen.has_method("on_layout_changed"):
			_screen.on_layout_changed(UI.is_portrait())


func _set_screen(kind: String, node: Control) -> void:
	if _screen and is_instance_valid(_screen):
		_screen.visible = false
		if _screen.get_parent() == self:
			remove_child(_screen)
		_screen.queue_free()
	_screen = node
	_screen_kind = kind
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	if _toasts and _toasts.get_parent() == self:
		move_child(_toasts, get_child_count() - 1)
		move_child(_busy_label, get_child_count() - 1)


func show_menu() -> void:
	if _screen_kind == "menu" and _screen != null and is_instance_valid(_screen) and not _screen.is_queued_for_deletion():
		Net.fetch_me()
		return
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
	UI.pop_in(p, 0.2)
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func set_busy(text: String) -> void:
	_busy_label.text = text
	_busy_label.position = Vector2(16, size.y - 36)


# ───────── Flow ─────────

func create_and_join(solo_bots: Array, solo: bool) -> void:
	if solo and not Net.is_logged_in() and Net.local_available():
		_solo_bots = solo_bots
		_solo = solo
		Net.is_solo = solo
		Net.join_local()
		set_busy("準備單人練習中……")
		return
	set_busy("準備單人練習中……" if solo else "建立房間中……")
	var r := await Net.create_room(solo)
	set_busy("")
	if not r[0]:
		toast(str(r[1]), UI.BAD, 4.0)
		return
	_solo_bots = solo_bots
	_solo = solo
	Net.is_solo = solo
	Net.join(str(r[1]))
	set_busy("連線中……")


func resume_seat() -> void:
	_solo_bots = []
	_solo = false
	Net.is_solo = false
	Net.join(str(Net.saved_seat.get("room", "")), true)
	set_busy("回到房間中……")


func join_room(code: String) -> void:
	_solo_bots = []
	_solo = false
	Net.is_solo = false
	Net.join(code)
	set_busy("連線中……")


func leave_to_menu() -> void:
	if Net.is_solo and not Net.is_local():
		Net.send({"t": "abandon"})
	Net.leave()
	_solo_bots = []
	_solo = false
	Net.is_solo = false
	show_menu()


func _on_welcomed(_data: Dictionary) -> void:
	set_busy("")
	if Net.spectator:
		toast("遊戲已開始，你將以旁觀者身分觀看", UI.INFO)
	if _solo:
		# Solo mode: automatically add bot opponents and start
		_solo = false
		for level in _solo_bots:
			Net.send({"t": "add_bot", "level": level})
		_solo_bots = []
		# Only logged-in users get AI real-time new clients; guests use rules version (server has separate check)
		var settings_dict: Dictionary = {"rounds": 5, "aiClients": Net.ai_enabled}
		if AutomationBridge.is_active():
			var demo_id := AutomationBridge.get_url_demo()
			if demo_id != "":
				settings_dict["demo"] = demo_id
		var full_settings := {"t": "settings"}
		full_settings.merge(settings_dict)
		Net.send(full_settings)
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


func get_screen_kind() -> String:
	return _screen_kind
