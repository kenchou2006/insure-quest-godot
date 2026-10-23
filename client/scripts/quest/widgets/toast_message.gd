extends Control
## ToastMessage: short messages at the top centre of the mission layer — tension reasons
## (gold for 注意, red for 危機, always with an icon and words, so they read with sound off),
## server errors and confirmations. One at a time, newest wins, never blinking.

var header: Control = null:
	set(h):
		if header == h:
			return
		if header != null and is_instance_valid(header) and header.resized.is_connected(_place):
			header.resized.disconnect(_place)
		header = h
		if header != null and is_instance_valid(header):
			if not header.resized.is_connected(_place):
				header.resized.connect(_place)
		if is_inside_tree() and _panel != null and _panel.visible:
			_place()

var modal_page := false:
	set(m):
		modal_page = m
		if is_inside_tree() and _panel != null and _panel.visible:
			_place()

var top_offset := 26.0
var _panel: PanelContainer
var _icon: Control
var _label: Label
var _tween: Tween


func _init() -> void:
	name = "ToastMessage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	add_child(_panel)
	var h := QuestUI.hbox(8)
	_panel.add_child(h)
	_icon = QuestUI.icon("alert", 18.0, QuestUI.GOLD)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(_icon)
	_label = QuestUI.label("", 15, QuestUI.TEXT, false, true)
	h.add_child(_label)


func _ready() -> void:
	TensionManager.message.connect(func(t: String, lv: int): show_message(t, "danger" if lv >= 2 else "warning"))
	resized.connect(_place)


## kind: warning (gold), danger (red), info (green), error (red)
func show_message(text: String, kind := "info", secs := 3.6) -> void:
	var col := QuestUI.GREEN
	var icon_kind := "info"
	match kind:
		"warning":
			col = QuestUI.GOLD
			icon_kind = "alert"
		"danger", "error":
			col = QuestUI.RED
			icon_kind = "alert"
	var s := StyleBoxFlat.new()
	s.bg_color = Color(QuestUI.INK, 1.0)
	s.set_corner_radius_all(12)
	s.set_border_width_all(1)
	s.border_color = Color(col, 0.85)
	s.content_margin_left = 16
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", s)
	_icon.set("kind", icon_kind)
	_icon.call("set_color", col)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = 0
	_label.text = text
	_label.add_theme_color_override("font_color", QuestUI.TEXT)
	_panel.visible = true
	_place()
	call_deferred("_place")
	if kind in ["warning", "danger"]:
		AudioManager.play("toast")
	if _tween and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 0.0 if not QuestUI.motion_off() else 1.0
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tween.tween_interval(secs)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func(): _panel.visible = false)


func _get_header() -> Control:
	var p := get_parent()
	if p != null and is_instance_valid(p):
		if p.has_method("_get_header"):
			return p.call("_get_header") as Control
		var pg: Variant = p.get("page")
		if pg is Control and is_instance_valid(pg):
			var h: Variant = pg.get("header")
			if h is Control and is_instance_valid(h):
				return h
			return pg.find_child("GameHeader", true, false)
	return null


func _is_modal_page() -> bool:
	var p := get_parent()
	if p != null and is_instance_valid(p):
		var cur: String = str(p.get("current"))
		if p.has_method("_is_modal"):
			return bool(p.call("_is_modal", cur))
	return false


func _place() -> void:
	if _panel == null:
		return
	var is_modal := modal_page or _is_modal_page()
	var h := header if (header != null and is_instance_valid(header)) else _get_header()

	if is_modal or h == null or not is_instance_valid(h) or not h.is_inside_tree() or not h.is_visible_in_tree():
		# Modal pages or fallback: keep current top offset
		_label.add_theme_font_size_override("font_size", QuestUI.fs(15))
		_label.max_lines_visible = -1
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size.x = 0
		_panel.reset_size()
		if size.x > 0.0:
			var max_w := size.x - 32.0
			if _panel.size.x > max_w:
				_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_label.custom_minimum_size.x = maxf(120.0, max_w - 48.0)
				_panel.reset_size()
		var x := maxf(8.0, (size.x - _panel.size.x) * 0.5)
		var y := 12.0 if is_modal else (86.0 if UI.is_phone() and top_offset == 26.0 else top_offset)
		_panel.position = Vector2(x, y)
		return

	var gap: Rect2 = h.call("middle_gap")
	if gap.size.x >= 360.0:
		# Desktop / wide screens: inside the gap, centred, max width = gap width - 16, wrapping to at most 2 lines with a smaller font (13), vertically centred in the header
		var max_w := gap.size.x - 16.0
		_label.add_theme_font_size_override("font_size", QuestUI.fs(13))
		_label.max_lines_visible = 2
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size.x = 0
		_panel.reset_size()
		if _panel.size.x > max_w:
			_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_label.custom_minimum_size.x = maxf(120.0, max_w - 48.0)
			_panel.reset_size()
		var x := gap.position.x + (gap.size.x - _panel.size.x) * 0.5
		var y := gap.position.y + (gap.size.y - _panel.size.y) * 0.5
		_panel.position = Vector2(x, y)
	else:
		# Narrow screens / phones: directly below the header bar
		_label.add_theme_font_size_override("font_size", QuestUI.fs(14 if UI.is_phone() else 15))
		_label.max_lines_visible = -1
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size.x = 0
		_panel.reset_size()
		if size.x > 0.0:
			var max_w := size.x - 32.0
			if _panel.size.x > max_w:
				_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_label.custom_minimum_size.x = maxf(120.0, max_w - 48.0)
				_panel.reset_size()
		var x := maxf(8.0, (size.x - _panel.size.x) * 0.5)
		var y := h.get_global_rect().end.y + 6.0
		_panel.position = Vector2(x, y)


func hide_now() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_panel.visible = false


func current_text() -> String:
	return _label.text if _panel.visible else ""
