@tool
extends Button
## Training hall button: filled green (primary) or outlined. The Button stays fixed for hit-testing;
## its Visual child brightens 8% on hover (arrow slides 4px right), dips to 0.97 on click with a soft
## click sound, then `activated` fires 120 ms later.

signal activated

const LineIcon := preload("res://scripts/ui/line_icon.gd")
const GREEN := Color("#00A86B")
const CREAM := Color("#F3F0E7")

var label_text := ""
var primary := true
var font_size := 20
var show_arrow := true
var dimmed := false:
	set(v):
		dimmed = v
		if _visual:
			_visual.modulate.a = 0.55 if v else 1.0

var _visual: Panel
var _label: Label
var _arrow: Control
var _hover := false


func _init(text_value := "", is_primary := true, size_px := 20, arrow := true) -> void:
	label_text = text_value
	primary = is_primary
	font_size = size_px
	show_arrow = arrow


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_visual = Panel.new()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_theme_stylebox_override("panel", _style())
	add_child(_visual)
	_label = Label.new()
	_label.text = label_text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", CREAM)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visual.add_child(_label)
	if show_arrow:
		_arrow = LineIcon.new("chevron_r", CREAM, 2.0)
		_visual.add_child(_arrow)
	dimmed = dimmed
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	pressed.connect(_on_pressed)
	resized.connect(_layout)
	_layout()


func set_font_size(fs: int) -> void:
	if fs == font_size:
		return
	font_size = fs
	if _label:
		_label.add_theme_font_size_override("font_size", fs)
		_layout()


func set_label(t: String) -> void:
	label_text = t
	if _label:
		_label.text = t
		_layout()


func _style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	if primary:
		sb.bg_color = GREEN
		sb.border_color = Color(1, 1, 1, 0.18)
	else:
		sb.bg_color = Color("#062F2A", 0.55)
		sb.border_color = Color(CREAM, 0.55)
	sb.anti_aliasing = true
	return sb


func _layout() -> void:
	if _visual == null:
		return
	_visual.size = size
	_visual.pivot_offset = size * 0.5
	_label.reset_size()
	var arrow_w := 0.0 if _arrow == null else font_size * 0.8
	var gap := 0.0 if _arrow == null else 10.0
	var x := (size.x - (_label.size.x + gap + arrow_w)) * 0.5
	_label.position = Vector2(x, (size.y - _label.size.y) * 0.5)
	if _arrow:
		_arrow.size = Vector2(arrow_w, arrow_w)
		_arrow.position = Vector2(x + _label.size.x + gap + (4.0 if _hover else 0.0), (size.y - arrow_w) * 0.5)


func _set_hover(on: bool) -> void:
	if not on and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	_hover = on
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var bright := 1.08 if on else 1.0
	tw.tween_property(_visual, "modulate", Color(bright, bright, bright, _visual.modulate.a), 0.18)
	if _arrow:
		var ax := (size.x - (_label.size.x + 10.0 + font_size * 0.8)) * 0.5 + _label.size.x + 10.0
		tw.tween_property(_arrow, "position:x", ax + (4.0 if on else 0.0), 0.18)


func _on_pressed() -> void:
	Sound.play("click", self)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector2.ONE * 0.97, 0.06)
	tw.tween_property(_visual, "scale", Vector2.ONE, 0.06)
	tw.tween_callback(func(): activated.emit())
