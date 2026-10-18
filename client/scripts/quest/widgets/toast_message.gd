extends Control
## ToastMessage: short messages at the top centre of the mission layer — tension reasons
## (gold for 注意, red for 危機, always with an icon and words, so they read with sound off),
## server errors and confirmations. One at a time, newest wins, never blinking.

var _panel: PanelContainer
var _icon: Control
var _label: Label
var _tween: Tween
var top_offset := 84.0


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
	s.bg_color = Color(QuestUI.INK, 0.94)
	s.set_corner_radius_all(12)
	s.set_border_width_all(1)
	s.border_color = Color(col, 0.85)
	s.content_margin_left = 16
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", s)
	_icon.set("kind", icon_kind)
	_icon.call("set_color", col)
	_label.text = text
	_label.add_theme_color_override("font_color", QuestUI.TEXT)
	_panel.visible = true
	_panel.reset_size()
	_place()
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


func _place() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	_panel.position = Vector2((size.x - _panel.size.x) * 0.5, top_offset)


func hide_now() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_panel.visible = false


func current_text() -> String:
	return _label.text if _panel.visible else ""
