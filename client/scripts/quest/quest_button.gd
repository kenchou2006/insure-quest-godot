@tool
extends Button
## Mission button: real Button with normal / hover / pressed / focus / disabled / loading states.
## Pointer cursor, 0.97 press scale, hover + click sounds (no stacking), and a disabled reason that
## shows as tooltip and in an optional linked label, so a button never looks usable while it is not.

signal reason_changed(reason: String)

const C_GREEN := Color("#00A86B")
const C_CARD := Color("#0D4038")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_RED := Color("#D9685F")

var kind := "primary"
var loading := false
var disabled_reason := ""
var reason_label: Label = null
var _base_text := ""
var _dots := 0.0
var _icon_kind := ""
var _icon: Control = null
var _press_tween: Tween


func setup(text_value: String, button_kind := "primary", icon_kind := "") -> void:
	kind = button_kind
	_base_text = text_value
	text = text_value
	_icon_kind = icon_kind
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var h := 52.0 if kind == "primary" else (44.0 if kind in ["secondary", "danger"] else 36.0)
	if UI.is_phone_landscape():
		h = maxf(40.0, h - 8.0)
	custom_minimum_size = Vector2(0, h)
	add_theme_font_size_override("font_size", QuestUI.fs(19 if kind == "primary" else (16 if kind != "quiet" else 14)))
	if kind == "primary":
		add_theme_font_override("font", QuestUI.FONT_BOLD)
	_apply_styles()
	if icon_kind != "":
		_icon = QuestUI.icon(icon_kind, 20.0, C_TEXT if kind != "quiet" else C_MUTED)
		add_child(_icon)
		alignment = HORIZONTAL_ALIGNMENT_CENTER
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_press.bind(true))
	button_up.connect(_press.bind(false))
	pressed.connect(func(): AudioManager.play("ui_click"))
	resized.connect(_place_icon)


func _style(state: String) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var radius := 12 if kind == "primary" else 10
	s.set_corner_radius_all(radius)
	var px := 22 if kind == "primary" else 16
	s.content_margin_left = px + (26 if _icon_kind != "" else 0)
	s.content_margin_right = px
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	var base := C_GREEN
	match kind:
		"secondary":
			s.bg_color = Color(C_CARD, 0.9)
			s.set_border_width_all(1)
			s.border_color = Color(C_GOLD, 0.7)
		"danger":
			s.bg_color = Color(C_RED, 0.16)
			s.set_border_width_all(1)
			s.border_color = Color(C_RED, 0.7)
		"quiet":
			s.bg_color = Color(1, 1, 1, 0.04)
			s.set_border_width_all(1)
			s.border_color = Color(1, 1, 1, 0.12)
		_:
			s.bg_color = base
			s.set_border_width_all(1)
			s.border_color = Color(1, 1, 1, 0.18)
	match state:
		"hover":
			s.bg_color = s.bg_color.lightened(0.1) if kind == "primary" else Color(s.bg_color.lightened(0.12), maxf(s.bg_color.a, 0.2))
			s.border_color = C_GOLD if kind != "danger" else C_RED
		"pressed":
			s.bg_color = s.bg_color.darkened(0.14)
		"focus":
			s.bg_color = Color(0, 0, 0, 0)
			s.set_border_width_all(2)
			s.border_color = Color(C_GOLD, 0.9)
			s.set_corner_radius_all(radius + 2)
			s.expand_margin_left = 3
			s.expand_margin_right = 3
			s.expand_margin_top = 3
			s.expand_margin_bottom = 3
		"disabled":
			s.bg_color = Color(0.32, 0.38, 0.36, 0.55) if kind == "primary" else Color(1, 1, 1, 0.03)
			s.border_color = Color(1, 1, 1, 0.08)
	return s


func _apply_styles() -> void:
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(st, _style(st))
	var fc := C_TEXT
	if kind == "secondary":
		fc = C_GOLD.lightened(0.15)
	elif kind == "quiet":
		fc = C_MUTED
	elif kind == "danger":
		fc = C_RED.lightened(0.25)
	add_theme_color_override("font_color", fc)
	add_theme_color_override("font_hover_color", C_TEXT)
	add_theme_color_override("font_pressed_color", C_TEXT)
	add_theme_color_override("font_focus_color", fc)
	add_theme_color_override("font_disabled_color", Color(C_TEXT, 0.42))


func _place_icon() -> void:
	if _icon == null:
		return
	_icon.position = Vector2(16 if kind != "primary" else 20, (size.y - _icon.custom_minimum_size.y) * 0.5)


func _on_hover(on: bool) -> void:
	if disabled or loading:
		return
	if on:
		AudioManager.play("ui_hover")


func _press(down: bool) -> void:
	if QuestUI.motion_off():
		return
	pivot_offset = size * 0.5
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.tween_property(self, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.07 if down else 0.12)


## Disables with a visible reason, or enables when reason is ""
func set_reason(reason: String) -> void:
	disabled_reason = reason
	disabled = reason != "" or loading
	tooltip_text = reason
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
	if reason_label and is_instance_valid(reason_label):
		reason_label.text = reason
		reason_label.visible = reason != ""
	reason_changed.emit(reason)


func set_loading(on: bool, loading_text := "處理中") -> void:
	loading = on
	if on:
		_base_text = text if not text.begins_with(loading_text) else _base_text
		text = loading_text
		disabled = true
		mouse_default_cursor_shape = Control.CURSOR_WAIT
		set_process(true)
	else:
		text = _base_text
		set_process(false)
		set_reason(disabled_reason)


func set_label(t: String) -> void:
	_base_text = t
	if not loading:
		text = t


func set_icon(icon_kind: String) -> void:
	if _icon_kind == icon_kind:
		return
	var had_icon := _icon_kind != ""
	_icon_kind = icon_kind
	if icon_kind == "":
		if _icon != null and is_instance_valid(_icon):
			_icon.queue_free()
			_icon = null
		if had_icon:
			_apply_styles()
		return
	if _icon != null and is_instance_valid(_icon):
		_icon.set("kind", icon_kind)
		_icon.queue_redraw()
	else:
		_icon = QuestUI.icon(icon_kind, 20.0, C_TEXT if kind != "quiet" else C_MUTED)
		add_child(_icon)
		alignment = HORIZONTAL_ALIGNMENT_CENTER
		_place_icon()
		if not had_icon:
			_apply_styles()


func _ready() -> void:
	set_process(loading)


func _process(delta: float) -> void:
	if not loading:
		set_process(false)
		return
	_dots += delta * 3.0
	var n := int(_dots) % 4
	text = text.rstrip("．") + "．".repeat(n) if n > 0 else text.rstrip("．")
