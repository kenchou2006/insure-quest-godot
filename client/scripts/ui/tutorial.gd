@tool
extends Control
class_name Tutorial
## 3-step First-Time User Experience (FTUE) spotlight overlay.
## Guides player through:
## 1. Clue observation (scene image)
## 2. Dialogue input (questions & compliance radar)
## 3. Plan allocation (10 coins & 2-3 cards)
## Remembers progress in user://tutorial.cfg and can be reset in Game Guide.

const CFG_PATH := "user://tutorial.cfg"

var _target: Control = null
var _step_id: String = ""
var _msg_text: String = ""
var _on_dismiss: Callable = Callable()
var _card_panel: PanelContainer = null

## Only one spotlight at a time; panels rebuild their UI on every refresh, so a repeated call re-targets it
static var _active: Tutorial = null


static func is_automation_mode() -> bool:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return false
	var href = JavaScriptBridge.eval("window.location.search || ''")
	if href != null and str(href) != "":
		var s: String = str(href)
		if "automation=1" in s and not ("tutorial=1" in s):
			return true
	return false


static func is_forced() -> bool:
	if Engine.is_editor_hint():
		return false
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return false
	return bool(cfg.get_value("tutorial", "forced", false))


static func is_step_done(step_id: String) -> bool:
	if Engine.is_editor_hint():
		return true
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return false
	return bool(cfg.get_value("tutorial", step_id, false))


static func mark_step_done(step_id: String) -> void:
	if Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("tutorial", step_id, true)
	var discover_done: bool = bool(cfg.get_value("tutorial", "discover", false))
	var talk_done: bool = bool(cfg.get_value("tutorial", "talk", false))
	var plan_done: bool = bool(cfg.get_value("tutorial", "plan", false))
	if discover_done and talk_done and plan_done:
		cfg.set_value("tutorial", "forced", false)
	cfg.save(CFG_PATH)


static func get_local_games() -> int:
	if Engine.is_editor_hint():
		return 0
	var cfg := ConfigFile.new()
	var err := cfg.load(CFG_PATH)
	if err != OK:
		return 0
	return int(cfg.get_value("progress", "local_games", 0))


static func record_game(game_id: String = "") -> void:
	if Engine.is_editor_hint() or is_automation_mode():
		return
	if game_id == "" and Net != null:
		if Net.has_method("get_game_id"):
			game_id = str(Net.get_game_id())
		elif Net.room_code != "":
			game_id = str(Net.room_code)
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	if game_id != "":
		var last_id: String = str(cfg.get_value("progress", "last_game_id", ""))
		if last_id == game_id:
			return
		cfg.set_value("progress", "last_game_id", game_id)
	var games: int = int(cfg.get_value("progress", "local_games", 0))
	cfg.set_value("progress", "local_games", games + 1)
	cfg.save(CFG_PATH)


static func record_local_game(game_id: String = "") -> void:
	record_game(game_id)


static func reset_all() -> void:
	if Engine.is_editor_hint():
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("tutorial", "discover", false)
	cfg.set_value("tutorial", "talk", false)
	cfg.set_value("tutorial", "plan", false)
	cfg.set_value("tutorial", "forced", true)
	cfg.save(CFG_PATH)


static func should_show(step_id: String, is_actor: bool) -> bool:
	if Engine.is_editor_hint() or not is_actor:
		return false
	if is_automation_mode():
		return false
	if is_step_done(step_id):
		return false
	if is_forced():
		return true
	if get_local_games() > 0:
		return false
	if Net != null and Net.is_logged_in():
		var lvl: Dictionary = Net.get_level()
		if lvl.is_empty():
			return false
		if int(lvl.get("games", 0)) > 0:
			return false
	return true



static func show_spotlight(parent: Control, target: Control, step_id: String, text: String, on_dismiss: Callable = Callable()) -> Tutorial:
	if not should_show(step_id, true):
		return null
	if parent == null or target == null or not parent.is_inside_tree():
		return null
	if _active != null and is_instance_valid(_active):
		# Same step: follow the rebuilt target node; another step: wait until the current one is dismissed
		if _active._step_id == step_id:
			_active._target = target
			_active._scroll_into_view.call_deferred()
		return null

	var t := Tutorial.new()
	t._target = target
	t._step_id = step_id
	t._msg_text = text
	t._on_dismiss = on_dismiss
	# Attach to the viewport root so the dim layer covers the whole screen, not just the panel
	parent.get_tree().root.add_child(t)
	_active = t
	t._scroll_into_view.call_deferred()
	return t


## Bring the target into view inside its nearest ScrollContainer
func _scroll_into_view() -> void:
	# Wait for the rebuilt panel to finish layout, otherwise the scroll position is computed from stale sizes
	await get_tree().process_frame
	await get_tree().process_frame
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return
	var n: Node = _target.get_parent()
	while n != null:
		if n is ScrollContainer:
			var sc := n as ScrollContainer
			if not sc.get_global_rect().encloses(_target.get_global_rect()):
				sc.ensure_control_visible(_target)
			return
		n = n.get_parent()


func _ready() -> void:
	# Parent is the Window (not a Control), so anchors do not apply: size to the viewport explicitly
	_fit_viewport()
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP

	_build_card()
	queue_redraw()
	if not UI.is_animation_disabled():
		modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.22)
		if _card_panel != null:
			UI.pop_in(_card_panel, 0.22)


func _exit_tree() -> void:
	_target = null
	if _active == self:
		_active = null


func _build_card() -> void:
	if _card_panel != null:
		_card_panel.queue_free()

	_card_panel = UI.panel(Color("#0d2432"), 14, 14)
	_card_panel.add_theme_stylebox_override("panel", UI.box(Color("#0d2432"), 14, UI.GOLD, 12, false))
	_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var v := UI.vbox(8)
	var head := UI.hbox(6)
	head.add_child(UI.label("★ 顧問新手引導", 16, UI.GOLD))
	head.add_child(UI.spacer())
	head.add_child(UI.label("（點擊任意處繼續 ▶）", 12, UI.ACCENT_2))
	v.add_child(head)

	var msg_lbl := UI.label(_msg_text, 14 if UI.is_phone_portrait() else 15, UI.TEXT, true)
	v.add_child(msg_lbl)

	_card_panel.add_child(v)
	add_child(_card_panel)
	_update_card_position()


func _update_card_position() -> void:
	if _card_panel == null or _target == null or not is_instance_valid(_target):
		return

	var hole: Rect2 = _get_hole_rect()
	var card_w: float = minf(size.x - 32.0, 420.0)
	_card_panel.custom_minimum_size = Vector2(card_w, 0)
	_card_panel.size = Vector2(card_w, 0)

	var card_x: float = clampf(hole.position.x + (hole.size.x - card_w) * 0.5, 16.0, size.x - card_w - 16.0)
	var card_y: float = hole.end.y + 16.0

	# If bottom space is not enough, place above target
	if card_y + 110.0 > size.y and hole.position.y > 140.0:
		card_y = maxf(16.0, hole.position.y - 120.0)

	_card_panel.position = Vector2(card_x, card_y)


func _get_hole_rect() -> Rect2:
	if _target == null or not is_instance_valid(_target) or not _target.is_inside_tree():
		return Rect2(size * 0.25, size * 0.5)

	var t_global: Vector2 = _target.global_position
	var t_size: Vector2 = _target.size
	var local_pos: Vector2 = t_global - global_position
	var r := Rect2(local_pos, t_size)
	# Grow slightly to leave breathing room around highlighted element
	return r.grow(6.0)


var _lost_time := 0.0

func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _process(delta: float) -> void:
	_fit_viewport()
	# Target gone (panel closed or rebuilt without re-targeting): close quietly without marking the step done
	var visible_target := _target != null and is_instance_valid(_target) and _target.is_visible_in_tree()
	_lost_time = 0.0 if visible_target else _lost_time + delta
	if _lost_time > 0.6:
		queue_free()
		return
	_update_card_position()
	queue_redraw()


func _draw() -> void:
	var hole: Rect2 = _get_hole_rect()
	var dim_col := Color(0.0, 0.0, 0.0, 0.72)

	# Draw 4 dimming rectangles around the spotlight hole
	# Top
	if hole.position.y > 0.0:
		draw_rect(Rect2(0, 0, size.x, hole.position.y), dim_col)
	# Bottom
	if hole.end.y < size.y:
		draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), dim_col)
	# Left
	if hole.position.x > 0.0 and hole.size.y > 0.0:
		draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), dim_col)
	# Right
	if hole.end.x < size.x and hole.size.y > 0.0:
		draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y), dim_col)

	# Golden frame around hole
	var hole_box := UI.box(Color(0, 0, 0, 0), 12, UI.GOLD, 0, false)
	draw_style_box(hole_box, hole)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()
		accept_event()


var _dismissing: bool = false

func dismiss() -> void:
	if _dismissing:
		return
	_dismissing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _step_id != "":
		mark_step_done(_step_id)
	if _active == self:
		_active = null
	if _on_dismiss.is_valid():
		_on_dismiss.call()
	if UI.is_animation_disabled():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.18)
	if _card_panel != null and is_instance_valid(_card_panel):
		UI.pop_out(_card_panel, func(): queue_free(), 0.18)
	else:
		tw.tween_callback(queue_free)
