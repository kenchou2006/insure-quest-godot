extends Control
## Modal tutorial overlay (強制聚焦導覽) for the training secretary: a full-screen deep green-black
## dim (60%) that swallows every click while its dialog is up, rounded bright "holes" over the
## interface elements being explained, the secretary's portrait and a gold-framed dialog on top
## (scales in from 95%),
## typed subtitles, a voice progress bar, a fixed top-right 「跳過」 and, once the line has been
## spoken, 「繼續」 / 「我知道了」. Only a view: training_secretary.gd drives the lines and voice.

signal skip_pressed
signal continue_pressed
signal mute_pressed

const SPOT := preload("res://assets/startup/spotlight.gdshader")
const GOLD := Color("#C6A15B")
const CREAM := Color("#F3F0E7")
const MUTED := Color("#AABCB5")
const GREEN := Color("#00A86B")

var _shade: ColorRect
var _rings: Control
var _portrait: TextureRect
var _dialog: Panel
var _heading: Label
var _text: Label
var _bar_bg: ColorRect
var _bar: ColorRect
var _bar_label: Label
var _continue: Button
var _mute: Button
var _skip: Button
var _targets: Array = []
var _hole_rects: Array = []
var _progress := 0.0
var _anim: Tween
var is_shown := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = SPOT
	_shade.material = m
	# Swallows every click so nothing behind can be pressed
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_rings = Rings.new(self)
	add_child(_rings)

	_dialog = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.98)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = GOLD
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	_dialog.add_theme_stylebox_override("panel", sb)
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dialog)
	_heading = _label(14, GOLD)
	_dialog.add_child(_heading)
	_text = _label(19, CREAM)
	_text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_dialog.add_child(_text)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.12)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = GOLD
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_bar)
	_bar_label = _label(12, MUTED)
	_dialog.add_child(_bar_label)
	_mute = _button("關閉語音", false)
	_mute.pressed.connect(func(): mute_pressed.emit())
	_dialog.add_child(_mute)
	_continue = _button("我知道了", true)
	_continue.pressed.connect(func(): continue_pressed.emit())
	_continue.visible = false
	_dialog.add_child(_continue)

	# Portrait in front of the dialog (both on the top layer, above the dim)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)

	# Skip: fixed top-right, always last so nothing covers it
	_skip = _button("跳過", false)
	_skip.pressed.connect(func(): skip_pressed.emit())
	add_child(_skip)
	resized.connect(_layout)


func _label(fs: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(t: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := StyleBoxFlat.new()
	n.set_corner_radius_all(10)
	n.set_border_width_all(1)
	n.content_margin_left = 16
	n.content_margin_right = 16
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	n.anti_aliasing = true
	if primary:
		n.bg_color = GREEN
		n.border_color = Color(1, 1, 1, 0.2)
	else:
		n.bg_color = Color("#062F2A", 0.85)
		n.border_color = Color(CREAM, 0.55)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = n.bg_color.lightened(0.08)
	h.border_color = GOLD
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", CREAM)
	return b


# --- API used by the secretary -----------------------------------------------------------------

## Shows the dim around a dialog that already holds its line. The layer is fully opaque from the
## first frame (only the dim and the dialog's scale ease in), so it can never sit invisible while
## swallowing clicks.
func show_overlay(portrait: Texture2D) -> void:
	if not dialog_built():
		return
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	if _anim:
		_anim.kill()
	modulate.a = 1.0
	_dialog.visible = true
	_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	is_shown = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	if UI.is_animation_disabled():
		_shade.modulate.a = 1.0
		_dialog.scale = Vector2.ONE
		return
	_shade.modulate.a = 0.0
	_dialog.scale = Vector2.ONE * 0.95
	_anim = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim.tween_property(_shade, "modulate:a", 1.0, 0.2)
	_anim.tween_property(_dialog, "scale", Vector2.ONE, 0.22)


## Closes at once and releases the lock (跳過, 我知道了, page and screen changes)
func close(_instant := true) -> void:
	is_shown = false
	if _anim:
		_anim.kill()
	if _shade:
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shade.modulate.a = 1.0
	if _dialog:
		_dialog.scale = Vector2.ONE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func dialog_built() -> bool:
	return _dialog != null and _text != null


## The dialog is on screen with a line in it (the only state in which the dim may stand)
func dialog_showing() -> bool:
	return visible and is_shown and dialog_built() and _dialog.visible and _text.text.strip_edges() != ""


func set_targets(controls: Array) -> void:
	_targets = controls.filter(func(c): return c is Control and is_instance_valid(c))
	_update_holes()
	_layout()


func set_line(heading: String, text: String) -> void:
	_heading.text = heading
	_text.text = text
	_text.visible_ratio = 0.0
	_continue.visible = false
	set_progress(0.0, "")


func set_typed(ratio: float) -> void:
	_text.visible_ratio = ratio


func set_progress(p: float, label: String) -> void:
	_progress = clampf(p, 0.0, 1.0)
	_bar_label.text = label
	_layout_bar()


func show_continue(label: String) -> void:
	_text.visible_ratio = 1.0
	_continue.text = label
	_continue.visible = true
	_layout()


func set_mute_label(t: String) -> void:
	_mute.text = t
	_layout()


func text_label() -> Label:
	return _text


func continue_visible() -> bool:
	return _continue.visible


# --- Spotlight ---------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if visible and not _targets.is_empty():
		_update_holes()


func _update_holes() -> void:
	_hole_rects.clear()
	var origin := get_global_rect().position
	for c: Control in _targets:
		if not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		var r := c.get_global_rect()
		r.position -= origin
		_hole_rects.append(r.grow(8.0))
		if _hole_rects.size() == 4:
			break
	var mat := _shade.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", size)
	mat.set_shader_parameter("hole_count", _hole_rects.size())
	var arr: Array = []
	for r: Rect2 in _hole_rects:
		arr.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	while arr.size() < 4:
		arr.append(Vector4.ZERO)
	mat.set_shader_parameter("holes", arr)
	_rings.queue_redraw()


func holes() -> Array:
	return _hole_rects


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _dialog == null or size.x < 10:
		return
	var portrait_screen := UI.is_portrait()
	var k := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.75, 1.5) if not portrait_screen else clampf(size.x / 480.0, 0.8, 1.3)
	var margin := 24.0 * k
	var h := 150.0 * k
	var ph := (250.0 if not portrait_screen else 170.0) * k
	var pw := ph * 0.76
	var pad := 18.0 * k
	# Candidate places for portrait + dialog; the one covering the bright elements least wins
	var best: Dictionary = {}
	var best_cover := INF
	for cand: Dictionary in _candidates(k, margin, h, ph, pw, portrait_screen):
		var cover := 0.0
		for r: Rect2 in _hole_rects:
			for part: Rect2 in [cand.dialog, cand.portrait]:
				var hit := (part as Rect2).intersection(r)
				cover += hit.get_area()
		if cover < best_cover - 0.5:
			best_cover = cover
			best = cand
	var d: Rect2 = best.dialog
	var x := d.position.x
	var y := d.position.y
	var w := d.size.x
	_dialog.size = d.size
	_dialog.position = d.position
	_dialog.pivot_offset = _dialog.size * 0.5
	_portrait.size = (best.portrait as Rect2).size
	_portrait.position = (best.portrait as Rect2).position
	# Text starts where the portrait ends when it overlaps the dialog's left side
	var tx := pad
	if _portrait.position.y + _portrait.size.y > y + 10.0 and _portrait.position.x < x + w * 0.5:
		tx = maxf(pad, _portrait.position.x + _portrait.size.x - x + 10.0 * k)
	var tw := w - tx - pad
	_heading.add_theme_font_size_override("font_size", roundi(14 * k))
	_heading.position = Vector2(tx, pad * 0.7)
	_heading.size = Vector2(tw, 0)
	_text.add_theme_font_size_override("font_size", roundi(19 * k))
	_text.position = Vector2(tx, pad * 0.7 + 22.0 * k)
	_text.size = Vector2(tw, h - pad * 0.7 - 22.0 * k - 46.0 * k)
	_text.custom_minimum_size = Vector2(tw, 0)
	for b: Button in [_continue, _mute, _skip]:
		b.add_theme_font_size_override("font_size", roundi(14 * k))
		b.reset_size()
	var by := h - pad * 0.7 - _continue.size.y
	_continue.position = Vector2(w - pad - _continue.size.x, by)
	_mute.position = Vector2((_continue.position.x - 10.0 * k - _mute.size.x) if _continue.visible else (w - pad - _mute.size.x), by)
	_bar_bg.position = Vector2(tx, by + _mute.size.y * 0.5 - 1.5)
	_layout_bar()
	# 跳過: top-right of the screen, clear of the portrait and the dialog
	_skip.position = Vector2(size.x - margin - _skip.size.x, 16.0 * k)
	_rings.position = Vector2.ZERO
	_rings.size = size


## Bottom band, top band, right column, left column (columns only where they are wide enough)
func _candidates(k: float, margin: float, h: float, ph: float, pw: float, portrait_screen: bool) -> Array:
	var out: Array = []
	var wide := minf(760.0 * k, size.x - margin * 2)
	for band: String in ["bottom", "top"]:
		var y := size.y - margin - h if band == "bottom" else 72.0 * k + ph - h
		var x := (size.x - wide) * 0.5
		var w := wide
		if not portrait_screen:
			x = maxf(margin + pw * 0.55, (size.x - wide) * 0.5 + pw * 0.3)
			w = minf(wide, size.x - x - margin)
		var dr := Rect2(x, y, w, h)
		var pr := Rect2(maxf(4.0 * k, x - pw * 0.55), y + h - ph, pw, ph)
		var top := pr.position.y
		for r: Rect2 in _hole_rects:
			if r.intersects(pr):
				top = maxf(top, r.end.y + 8.0 * k)
		if top > pr.position.y and y + h - top >= 90.0 * k:
			var nh := y + h - top
			pr = Rect2(maxf(4.0 * k, x - nh * 0.76 * 0.55), top, nh * 0.76, nh)
		out.append({"dialog": dr, "portrait": pr})
	if portrait_screen or _hole_rects.is_empty():
		return out
	var union: Rect2 = _hole_rects[0]
	for r: Rect2 in _hole_rects:
		union = union.merge(r)
	var min_w := 330.0 * k
	var right_x := union.end.x + margin
	if size.x - margin - right_x >= min_w:
		var w := minf(420.0 * k, size.x - margin - right_x)
		var dr := Rect2(size.x - margin - w, size.y - margin - h, w, h)
		out.append({"dialog": dr, "portrait": Rect2(dr.position.x + 6.0 * k, dr.position.y - ph * 0.9 + 6.0 * k, pw * 0.9, ph * 0.9)})
	if union.position.x - margin * 2 >= min_w:
		var w := minf(420.0 * k, union.position.x - margin * 2)
		var dr := Rect2(margin, size.y - margin - h, w, h)
		out.append({"dialog": dr, "portrait": Rect2(dr.position.x + 6.0 * k, dr.position.y - ph * 0.9 + 6.0 * k, pw * 0.9, ph * 0.9)})
	return out


func _layout_bar() -> void:
	if _bar_bg == null:
		return
	var w := maxf(40.0, _mute.position.x - 16.0 - _bar_bg.position.x - 110.0)
	_bar_bg.size = Vector2(w, 3)
	_bar.position = _bar_bg.position
	_bar.size = Vector2(w * _progress, 3)
	_bar_label.reset_size()
	_bar_label.position = Vector2(_bar_bg.position.x + w + 10.0, _bar_bg.position.y - _bar_label.size.y * 0.5 + 1.5)


## Gold hairline around each bright hole
class Rings extends Control:
	var o: Control

	func _init(owner_overlay: Control) -> void:
		o = owner_overlay
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for r: Rect2 in o.holes():
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.set_border_width_all(1)
			sb.border_color = Color(GOLD, 0.9)
			sb.set_corner_radius_all(14)
			sb.anti_aliasing = true
			draw_style_box(sb, r)
