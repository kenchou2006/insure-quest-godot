@tool
extends Control
## Training-mode card in the hall (單人實戰 / 多人演練). The root stays put for hit-testing; the Visual
## child lifts 4px in 180 ms on hover and its border turns BNP green. Clicking the body selects the
## card; the button inside emits `activated`.

signal picked
signal activated
signal link_pressed

const LineIcon := preload("res://scripts/ui/line_icon.gd")
const HallButton := preload("res://scripts/ui/hall_button.gd")
const GREEN := Color("#00A86B")
const CREAM := Color("#F3F0E7")
const MUTED := Color("#AABCB5")
const GOLD := Color("#C6A15B")

var title := ""
var tag := ""
var tag_primary := false
var icon := "users"
## [[icon, text], ...]
var rows: Array = []
var button_text := ""
var primary := false
var link_text := ""
var is_selected := false
var button: HallButton

var _visual: Panel
var _tag_chip: PanelContainer
var _tag_label: Label
var _icon: Control
var _title: Label
var _row_nodes: Array = []
var _link: Label
var _link_arrow: Control
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_visual = Panel.new()
	_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_visual)

	_tag_chip = PanelContainer.new()
	_tag_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_label = _text(tag, 14, Color("#062F2A") if tag_primary else MUTED)
	_tag_chip.add_child(_tag_label)
	_visual.add_child(_tag_chip)
	set_tag(tag, tag_primary)

	_icon = LineIcon.new(icon, GOLD, 2.0)
	_visual.add_child(_icon)
	_title = _text(title, 34, CREAM)
	_title.add_theme_font_override("font", load("res://assets/fonts/bold.tres"))
	_visual.add_child(_title)
	for r: Array in rows:
		var ic: Control = LineIcon.new(str(r[0]), GOLD, 1.8)
		var lb := _text(str(r[1]), 17, CREAM)
		_visual.add_child(ic)
		_visual.add_child(lb)
		_row_nodes.append([ic, lb])

	button = HallButton.new(button_text, primary, 20)
	button.activated.connect(func(): activated.emit())
	button.mouse_entered.connect(func(): _set_hover(true))
	_visual.add_child(button)

	if link_text != "":
		_link = _text(link_text, 14, MUTED)
		_link.mouse_filter = Control.MOUSE_FILTER_STOP
		_link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_link.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				link_pressed.emit()
		)
		_link_arrow = LineIcon.new("chevron_r", MUTED, 1.6)
		_link.mouse_entered.connect(func():
			_link.add_theme_color_override("font_color", CREAM)
			_link_arrow.set_color(CREAM)
		)
		_link.mouse_exited.connect(func():
			_link.add_theme_color_override("font_color", MUTED)
			_link_arrow.set_color(MUTED)
		)
		_visual.add_child(_link)
		_visual.add_child(_link_arrow)

	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked.emit()
	)
	resized.connect(_layout)
	_restyle()
	_layout()


func set_tag(text: String, is_primary: bool) -> void:
	tag = text
	tag_primary = is_primary
	if _tag_chip == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = GREEN if is_primary else Color(1, 1, 1, 0.12)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	_tag_chip.add_theme_stylebox_override("panel", sb)
	_tag_label.text = text
	_tag_label.add_theme_color_override("font_color", Color("#062F2A") if is_primary else MUTED)


func set_selected(on: bool) -> void:
	is_selected = on
	_restyle()


func _text(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _restyle() -> void:
	if _visual == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.94 if is_selected else 0.86)
	sb.set_corner_radius_all(14)
	var accent := is_selected or _hover
	sb.set_border_width_all(2 if is_selected else 1)
	sb.border_color = GREEN if accent else Color(1, 1, 1, 0.12)
	sb.anti_aliasing = true
	_visual.add_theme_stylebox_override("panel", sb)


func _layout() -> void:
	if _visual == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var k := size.x / 406.0
	# A shorter card (本局對練配置 open below) keeps its proportions: vertical metrics follow the
	# height; on a low screen the feature rows step aside (the card body still selects the mode)
	var rows_on := size.y >= maxf(200.0 * k, 160.0)
	var kv := minf(k, size.y / (292.0 if rows_on else 186.0))
	var pad := 22.0 * k
	_visual.size = size
	_tag_label.add_theme_font_size_override("font_size", maxi(12, roundi(14 * kv)))
	_tag_chip.reset_size()
	_tag_chip.position = Vector2(pad, pad * 0.8 * kv / k)
	var ic := 50.0 * kv
	_icon.size = Vector2(ic, ic)
	_icon.position = Vector2(pad + 6 * k, _tag_chip.position.y + 40 * kv)
	_title.add_theme_font_size_override("font_size", roundi(34 * kv))
	_title.reset_size()
	_title.position = Vector2(_icon.position.x + ic + 22 * k, _icon.position.y + (ic - _title.size.y) * 0.5)
	var y := _icon.position.y + ic + 14 * kv
	for pair: Array in _row_nodes:
		var ri: Control = pair[0]
		var rl: Label = pair[1]
		ri.visible = rows_on
		rl.visible = rows_on
		if not rows_on:
			continue
		var rs := 20.0 * kv
		ri.size = Vector2(rs, rs)
		ri.position = Vector2(pad + 22 * k, y + 4 * kv)
		rl.add_theme_font_size_override("font_size", maxi(12, roundi(17 * kv)))
		rl.reset_size()
		rl.position = Vector2(ri.position.x + rs + 14 * k, y + (28 * kv - rl.size.y) * 0.5)
		y += 28 * kv
	var bh := 48.0 * kv
	button.set_font_size(roundi(20 * kv))
	button.size = Vector2(size.x - pad * 2, bh)
	button.position = Vector2(pad, size.y - pad * kv / k - bh)
	if _link:
		_link.add_theme_font_size_override("font_size", maxi(12, roundi(14 * k)))
		_link.reset_size()
		var aw := 12.0 * k
		_link_arrow.size = Vector2(aw, aw)
		_link.position = Vector2(size.x - pad - aw - 2 * k - _link.size.x, pad * 0.8 + 2 * k)
		_link_arrow.position = Vector2(size.x - pad - aw, _link.position.y + (_link.size.y - aw) * 0.5)


func _set_hover(on: bool) -> void:
	if not on and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	if on == _hover:
		return
	_hover = on
	_restyle()
	if UI.is_animation_disabled():
		return
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "position:y", -4.0 if on else 0.0, 0.18)
