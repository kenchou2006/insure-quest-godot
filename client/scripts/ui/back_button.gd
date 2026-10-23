@tool
extends Button
## Reusable 返回 button: left arrow + text, at least 48×48, hover brightens the background, press
## scales to 0.96, pointer cursor and a click sound. It only signals `pressed`; the screen that owns
## it decides where "back" goes (and keeps its unconfirmed choices).

const C_TEXT := Color("#F3F0E7")
const C_GOLD := Color("#C6A15B")
const C_BG := Color("#062F2A")

var _arrow: Control
var _tween: Tween


func _init(label_text := "返回") -> void:
	name = "BackButton"
	text = label_text
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(48, 48)
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_theme_font_size_override("font_size", 17)
	add_theme_color_override("font_color", C_TEXT)
	add_theme_color_override("font_hover_color", C_TEXT)
	add_theme_color_override("font_pressed_color", C_TEXT)
	add_theme_color_override("font_focus_color", C_TEXT)
	add_theme_color_override("font_disabled_color", Color(C_TEXT, 0.4))
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(1)
		s.content_margin_left = 46
		s.content_margin_right = 20
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		s.bg_color = Color(C_BG, 0.82)
		s.border_color = Color(C_GOLD, 0.45)
		match st:
			"hover":
				s.bg_color = Color("#0F4A40", 0.95)
				s.border_color = C_GOLD
			"pressed":
				s.bg_color = Color("#0A3A33", 0.95)
				s.border_color = C_GOLD
			"focus":
				s.bg_color = Color(0, 0, 0, 0)
				s.border_color = Color(C_GOLD, 0.9)
				s.set_border_width_all(2)
			"disabled":
				s.border_color = Color(1, 1, 1, 0.1)
		add_theme_stylebox_override(st, s)
	_arrow = Arrow.new()
	add_child(_arrow)
	button_down.connect(_scale.bind(0.96))
	button_up.connect(_scale.bind(1.0))
	pressed.connect(_click)
	resized.connect(_place)


func _ready() -> void:
	_place()


func _place() -> void:
	_arrow.size = Vector2(22, 22)
	_arrow.position = Vector2(16, (size.y - 22) * 0.5)
	pivot_offset = size * 0.5


func _scale(to: float) -> void:
	if UI.is_animation_disabled():
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * to, 0.07 if to < 1.0 else 0.12)


func _click() -> void:
	if Engine.is_editor_hint():
		return
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.call("play", "ui_back")


class Arrow extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.4
		var col := Color("#F3F0E7")
		draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), col, 2.0, true)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.2, -r * 0.8), c + Vector2(-r, 0), c + Vector2(-r * 0.2, r * 0.8)]), col, 2.0, true)
