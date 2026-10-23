@tool
class_name QuestUI
## Shared look for the ten mission pages (精品金融 palette, 14px cards, 2px line icons).
## Factories only: every page builds real Controls from these so buttons, cards and type sizes match.

const BG := Color("#062F2A")
const CARD := Color("#0D4038")
const GREEN := Color("#00A86B")
const TEXT := Color("#F3F0E7")
const MUTED := Color("#AABCB5")
const GOLD := Color("#C6A15B")
const RED := Color("#D9685F")
const LINE := Color(1, 1, 1, 0.12)
const INK := Color("#04241F")

const FONT_BOLD := preload("res://assets/fonts/bold.tres")
const LOGO := preload("res://assets/startup/title.png")
const QuestButton := preload("res://scripts/quest/quest_button.gd")
const QuestIcon := preload("res://scripts/quest/quest_icon.gd")

## Type scale (desktop): main title 30, task title 19, body 16, small 13
const H1 := 30
const H2 := 19
const BODY := 16
const SMALL := 13


static func phone() -> bool:
	return UI.is_phone()


## Shrinks type a little on phones so every page fits 480×854 and 800×450
static func fs(size: int) -> int:
	if UI.is_phone_landscape():
		return maxi(11, int(round(size * 0.82)))
	if UI.is_phone_portrait():
		return maxi(12, int(round(size * 0.88)))
	return size


static func gap() -> int:
	return 10 if phone() else 16


static func card_box(alpha := 1.0, border := LINE, radius := 14, pad := -1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(CARD, alpha)
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = border
	var p := pad if pad >= 0 else (12 if phone() else 18)
	s.content_margin_left = p
	s.content_margin_right = p
	s.content_margin_top = p * 0.8
	s.content_margin_bottom = p * 0.8
	return s


static func card(content: Control = null, alpha := 1.0, border := LINE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_box(alpha, border))
	if content:
		p.add_child(content)
	return p


static func label(text: String, size := BODY, color := TEXT, wrap := false, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", FONT_BOLD)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 40
		# Wrapped text takes the row's free width (never squeezed to a column of single words)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := H1, color := TEXT) -> Label:
	return label(text, size, color, false, true)


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func icon(kind: String, sz := 22.0, color := TEXT) -> Control:
	return QuestIcon.new(kind, sz, color)


## Header row: line icon + bold title (+ optional right-side text)
static func header(icon_kind: String, text: String, right := "", right_color := GOLD) -> HBoxContainer:
	var h := hbox(8)
	h.add_child(icon(icon_kind, 22.0 if not phone() else 18.0, GOLD))
	var t := title(text, H2)
	h.add_child(t)
	h.add_child(spacer())
	if right != "":
		h.add_child(label(right, SMALL, right_color))
	return h


## Primary (green), secondary (outlined) and quiet buttons; all are real Buttons with
## hover / pressed / focus / disabled / loading states, pointer cursor and press scale.
static func button(text: String, cb: Callable, kind := "primary", icon_kind := "") -> Button:
	var b: Button = QuestButton.new()
	b.setup(text, kind, icon_kind)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func chip(text: String, color := GOLD, fill := 0.14, size := SMALL) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, fill)
	s.set_corner_radius_all(999)
	s.set_border_width_all(1)
	s.border_color = Color(color, 0.55)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, size, color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func divider(alpha := 0.12) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, alpha)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Metric bar row: caption, track, value (colour follows the value unless fixed)
static func metric_bar(caption: String, value: float, fixed := Color(0, 0, 0, 0), width := 0.0) -> HBoxContainer:
	var h := hbox(8)
	var c := label(caption, SMALL, TEXT)
	c.custom_minimum_size.x = 64 if not phone() else 52
	h.add_child(c)
	var track := Bar.new()
	track.value = value
	track.color = fixed if fixed.a > 0 else metric_color(value)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.custom_minimum_size = Vector2(maxf(width, 48.0), 10)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(track)
	var v := label(str(int(round(value))), SMALL, track.color)
	v.custom_minimum_size.x = 32
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(v)
	return h


static func metric_color(v: float) -> Color:
	if v >= 70:
		return GREEN
	if v >= 45:
		return GOLD
	return RED


static func portrait_tex(client_id: String) -> Texture2D:
	if client_id == "" or Engine.is_editor_hint():
		return null
	return Portraits.get_texture(client_id)


## Rounded portrait card
static func portrait(client_id: String, sz: Vector2) -> Control:
	var tex := portrait_tex(client_id)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.custom_minimum_size = sz
	r.material = UI.get_rounded_material(0.1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func logo(height := 54.0) -> TextureRect:
	var t := TextureRect.new()
	t.name = "LogoTexture"
	t.texture = LOGO
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var ratio := float(LOGO.get_width()) / maxf(1.0, float(LOGO.get_height()))
	t.custom_minimum_size = Vector2(height * ratio, height)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func margin(child: Control, m: int) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc


static func motion_off() -> bool:
	return UI.is_animation_disabled()


## Fade + 12px rise; instant when motion is reduced
static func fade_in(node: CanvasItem, delay := 0.0, dur := 0.28, rise := 12.0) -> void:
	if motion_off() or not is_instance_valid(node):
		node.modulate.a = 1.0
		return
	node.modulate.a = 0.0
	var ctl := node as Control
	var target := Vector2.ZERO
	if ctl:
		target = ctl.position
	var tw := node.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if ctl and rise != 0.0 and not (ctl.get_parent() is Container):
		ctl.position = target + Vector2(0, rise)
		tw.parallel().tween_property(ctl, "position", target, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## One short horizontal shake (problem card); never loops
static func shake(node: Control, amount := 6.0) -> void:
	if motion_off() or not is_instance_valid(node):
		return
	if node.has_meta("shaking"):
		return
	node.set_meta("shaking", true)
	var tw := node.create_tween()
	var base := node.position
	if node.get_parent() is Container:
		# Containers own position: shake with a pivoted rotation instead
		node.pivot_offset = node.size * 0.5
		for k in range(4):
			tw.tween_property(node, "rotation", (0.012 if k % 2 == 0 else -0.012) * amount / 6.0, 0.05)
		tw.tween_property(node, "rotation", 0.0, 0.05)
	else:
		for k in range(4):
			tw.tween_property(node, "position", base + Vector2(amount if k % 2 == 0 else -amount, 0), 0.05)
		tw.tween_property(node, "position", base, 0.05)
	tw.tween_callback(func(): node.remove_meta("shaking"))


## Single soft pulse (scale 1 → 1.05 → 1)
static func pulse_once(node: Control, amount := 1.05) -> void:
	if motion_off() or not is_instance_valid(node):
		return
	node.pivot_offset = node.size * 0.5
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * amount, 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_SINE)


## Fisher–Yates on a copy (option order differs every visit)
static func shuffled(arr: Array) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
	return a


static func mmss(seconds: float) -> String:
	var s := int(ceil(absf(seconds)))
	return "%s%02d:%02d" % ["-" if seconds < 0 else "", s / 60, s % 60]


## Thin rounded progress track
class Bar extends Control:
	var value := 0.0:
		set(v):
			value = clampf(v, 0, 100)
			queue_redraw()
	var color := Color("#00A86B"):
		set(c):
			color = c
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := minf(size.y, 10.0)
		var y := (size.y - h) * 0.5
		var r := h * 0.5
		var back := StyleBoxFlat.new()
		back.bg_color = Color(1, 1, 1, 0.1)
		back.set_corner_radius_all(int(r))
		draw_style_box(back, Rect2(0, y, size.x, h))
		if value > 0:
			var fill := StyleBoxFlat.new()
			fill.bg_color = color
			fill.set_corner_radius_all(int(r))
			draw_style_box(fill, Rect2(0, y, maxf(h, size.x * value / 100.0), h))


## Ring with an optional gap (broken = coverage incomplete); closes when ratio reaches 1
class Ring extends Control:
	var ratio := 0.0:
		set(v):
			ratio = clampf(v, 0.0, 1.0)
			queue_redraw()
	var color := Color("#00A86B")
	var track := Color(1, 1, 1, 0.1)
	var thickness := 8.0
	var broken := false:
		set(v):
			broken = v
			queue_redraw()
	var center_text := ""
	var sub_text := ""
	var text_color := Color("#F3F0E7")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - thickness
		draw_arc(c, r, 0, TAU, 64, track, thickness, true)
		var start := -PI * 0.5
		if broken:
			# Visible break at the top: the ring cannot close while a need is uncovered
			var span := TAU * minf(ratio, 0.9)
			draw_arc(c, r, start + 0.22, start + 0.22 + span, 64, color, thickness, true)
		elif ratio > 0:
			draw_arc(c, r, start, start + TAU * ratio, 64, color, thickness, true)
		var font := get_theme_default_font()
		if center_text != "":
			var fsz := int(r * 0.62)
			draw_string(QuestUI.FONT_BOLD, Vector2(0, c.y + fsz * 0.32 - (8 if sub_text != "" else 0)), center_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, fsz, text_color)
		if sub_text != "":
			var ssz := int(maxf(11, r * 0.22))
			draw_string(font, Vector2(0, c.y + r * 0.42 + ssz * 0.3), sub_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, ssz, Color(text_color, 0.75))
