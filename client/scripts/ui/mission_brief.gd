extends Control
## Game instructions as a one-screen mission brief: logo, four steps, what is scored, one action.
## The detailed six-page rules stay available through "查看詳細規則".
signal closed
signal details_requested

const BACKGROUND := preload("res://assets/startup/loading.png")
const TITLE := preload("res://assets/startup/title.png")

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")

const STEPS := [
	["01", "briefcase", "準備工具"],
	["02", "map", "拜訪客戶"],
	["03", "dialogue", "觀察・提問・決策"],
	["04", "report", "取得培訓報告"],
]

var _logo: TextureRect
var _heading: Label
var _sub: Label
var _rule_l: ColorRect
var _rule_r: ColorRect
var _cards: Array = []
var _arrows: Array = []
var _chips: Control
var _time_chip: Control
var _start: Button
var _start_visual: Control
var _start_arrow: Control
var _details: Button


## Gold line illustrations for the four steps, plus small chip icons
class Art extends Control:
	var kind := ""
	var color := Color("#C6A15B")
	var width := 2.5

	func _init(k: String, col: Color, w := 2.5) -> void:
		kind = k
		color = col
		width = w
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var w := width
		var fill := Color("#0D4038")
		match kind:
			"briefcase":
				var paper := Rect2(c + Vector2(-r * 0.2, -r * 0.95), Vector2(r * 1.05, r * 1.2))
				draw_rect(paper, Color(color, 0.18))
				draw_rect(paper, Color(color, 0.6), false, 1.5)
				for k in range(4):
					draw_line(paper.position + Vector2(r * 0.15, r * 0.25 + k * r * 0.2), paper.position + Vector2(r * 0.85, r * 0.25 + k * r * 0.2), Color(color, 0.5), 1.2)
				var body := Rect2(c + Vector2(-r, -r * 0.35), Vector2(r * 1.6, r * 1.15))
				draw_rect(body, fill)
				draw_rect(body, color, false, w)
				draw_line(body.position + Vector2(0, r * 0.4), body.position + Vector2(body.size.x, r * 0.4), color, w)
				draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.6), Vector2(r * 0.5, r * 0.25)), color, false, w)
				draw_rect(Rect2(c + Vector2(-r * 0.24, -r * 0.02), Vector2(r * 0.28, r * 0.18)), color)
			"map":
				var pts := PackedVector2Array([c + Vector2(-r, -r * 0.35), c + Vector2(-r * 0.35, -r * 0.55), c + Vector2(r * 0.3, -r * 0.35), c + Vector2(r, -r * 0.55), c + Vector2(r, r * 0.7), c + Vector2(r * 0.3, r * 0.9), c + Vector2(-r * 0.35, r * 0.7), c + Vector2(-r, r * 0.9), c + Vector2(-r, -r * 0.35)])
				draw_colored_polygon(pts, Color(fill, 0.9))
				draw_polyline(pts, color, w, true)
				draw_line(c + Vector2(-r * 0.35, -r * 0.55), c + Vector2(-r * 0.35, r * 0.7), Color(color, 0.5), 1.5)
				draw_line(c + Vector2(r * 0.3, -r * 0.35), c + Vector2(r * 0.3, r * 0.9), Color(color, 0.5), 1.5)
				var route := [c + Vector2(-r * 0.7, r * 0.5), c + Vector2(-r * 0.3, r * 0.2), c + Vector2(0, r * 0.35), c + Vector2(r * 0.35, -r * 0.05)]
				for k in range(route.size() - 1):
					var a: Vector2 = route[k]
					var b: Vector2 = route[k + 1]
					for d in range(4):
						draw_line(a.lerp(b, d / 4.0), a.lerp(b, d / 4.0 + 0.13), color, 2.0, true)
				draw_circle(c + Vector2(-r * 0.7, r * 0.5), r * 0.07, color)
				var pin := c + Vector2(r * 0.4, -r * 0.55)
				draw_circle(pin, r * 0.32, fill)
				draw_arc(pin, r * 0.32, 0, TAU, 28, color, w, true)
				draw_colored_polygon(PackedVector2Array([pin + Vector2(-r * 0.2, r * 0.22), pin + Vector2(r * 0.2, r * 0.22), pin + Vector2(0, r * 0.62)]), color)
				draw_arc(pin + Vector2(0, -r * 0.06), r * 0.09, 0, TAU, 12, color, 2.0, true)
				draw_arc(pin + Vector2(0, r * 0.2), r * 0.15, PI * 1.15, PI * 1.85, 8, color, 2.0, true)
			"dialogue":
				var bubble := Rect2(c + Vector2(-r, -r * 0.85), Vector2(r * 1.15, r * 0.8))
				var sb := StyleBoxFlat.new()
				sb.bg_color = fill
				sb.set_corner_radius_all(int(r * 0.2))
				sb.set_border_width_all(int(w))
				sb.border_color = color
				draw_style_box(sb, bubble)
				draw_colored_polygon(PackedVector2Array([bubble.position + Vector2(r * 0.25, bubble.size.y - 2), bubble.position + Vector2(r * 0.5, bubble.size.y - 2), bubble.position + Vector2(r * 0.15, bubble.size.y + r * 0.25)]), color)
				for k in range(3):
					draw_circle(bubble.position + Vector2(r * 0.3 + k * r * 0.28, bubble.size.y * 0.5), r * 0.07, color)
				var lens := c + Vector2(r * 0.3, r * 0.2)
				draw_circle(lens, r * 0.42, Color(fill, 0.95))
				draw_arc(lens, r * 0.42, 0, TAU, 32, color, w + 1, true)
				draw_arc(lens, r * 0.3, PI * 1.1, PI * 1.5, 8, Color(color, 0.6), 1.5, true)
				draw_line(lens + Vector2(r * 0.3, r * 0.3), lens + Vector2(r * 0.68, r * 0.68), color, w + 3, true)
			"report":
				var page := Rect2(c + Vector2(-r * 0.85, -r * 0.9), Vector2(r * 1.25, r * 1.6))
				draw_rect(Rect2(page.position + Vector2(r * 0.15, -r * 0.12), page.size), Color(color, 0.35), false, 1.5)
				draw_rect(page, Color("#e9dfc8"))
				draw_rect(page, color, false, 1.5)
				for k in range(3):
					draw_line(page.position + Vector2(r * 0.15, r * 0.2 + k * r * 0.16), page.position + Vector2(r * 1.0, r * 0.2 + k * r * 0.16), Color(fill, 0.6), 1.5)
				for k in range(4):
					var h := r * (0.2 + k * 0.15)
					draw_rect(Rect2(page.position + Vector2(r * 0.15 + k * r * 0.22, page.size.y - r * 0.12 - h), Vector2(r * 0.14, h)), fill)
				var sc := c + Vector2(r * 0.55, r * 0.35)
				var shield := PackedVector2Array([sc + Vector2(0, -r * 0.5), sc + Vector2(r * 0.42, -r * 0.35), sc + Vector2(r * 0.38, r * 0.1), sc + Vector2(0, r * 0.5), sc + Vector2(-r * 0.38, r * 0.1), sc + Vector2(-r * 0.42, -r * 0.35), sc + Vector2(0, -r * 0.5)])
				draw_colored_polygon(shield, fill)
				draw_polyline(shield, color, w, true)
				draw_polyline(PackedVector2Array([sc + Vector2(-r * 0.18, 0), sc + Vector2(-r * 0.03, r * 0.15), sc + Vector2(r * 0.2, -r * 0.13)]), color, w, true)
			"handshake":
				draw_polyline(PackedVector2Array([c + Vector2(-r, -r * 0.1), c + Vector2(-r * 0.35, -r * 0.5), c + Vector2(r * 0.2, -r * 0.1), c + Vector2(-r * 0.1, r * 0.3), c + Vector2(r * 0.4, r * 0.5), c + Vector2(r, 0)]), color, w, true)
				draw_line(c + Vector2(-r * 0.6, r * 0.05), c + Vector2(-r * 0.25, r * 0.4), color, w, true)
			"target":
				draw_arc(c, r * 0.85, 0, TAU, 28, color, w, true)
				draw_arc(c, r * 0.5, 0, TAU, 24, color, w, true)
				draw_circle(c, r * 0.16, color)
				draw_line(c, c + Vector2(r * 0.9, -r * 0.9), color, w, true)
			"shield":
				var s := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, -r * 0.7), c + Vector2(r * 0.72, r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.72, r * 0.2), c + Vector2(-r * 0.8, -r * 0.7), c + Vector2(0, -r)])
				draw_polyline(s, color, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, 0), c + Vector2(-r * 0.05, r * 0.3), c + Vector2(r * 0.4, -r * 0.25)]), color, w, true)
			"timer":
				draw_arc(c + Vector2(0, r * 0.1), r * 0.8, 0, TAU, 28, color, w, true)
				draw_line(c + Vector2(-r * 0.25, -r * 0.95), c + Vector2(r * 0.25, -r * 0.95), color, w, true)
				draw_line(c + Vector2(0, r * 0.1), c + Vector2(0, -r * 0.4), color, w, true)
				draw_line(c + Vector2(0, r * 0.1), c + Vector2(r * 0.35, r * 0.3), color, w, true)
			"arrow":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), color, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(r * 0.45, -r * 0.5), c + Vector2(r, 0), c + Vector2(r * 0.45, r * 0.5)]), color, w, true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.1, 0.09, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_logo = TextureRect.new()
	_logo.texture = TITLE
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_logo)

	_heading = _label("新人顧問任務", 44, C_TEXT)
	_sub = _label("在時間與預算內，找出需求並完成合規方案", 17, C_MUTED)
	_rule_l = _rule()
	_rule_r = _rule()

	for i in range(STEPS.size()):
		_cards.append(_step_card(STEPS[i]))
		if i < STEPS.size() - 1:
			var arrow := Art.new("arrow", C_GOLD, 2.0)
			add_child(arrow)
			_arrows.append(arrow)

	_chips = _chip([["handshake", "信任"], ["target", "需求"], ["shield", "合規"]])
	_time_chip = _chip([["timer", "每局 8–12 分鐘"]])

	_start = Button.new()
	_start.flat = true
	_start.focus_mode = Control.FOCUS_NONE
	_start.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "focus"]:
		_start.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_start_visual = Panel.new()
	_start_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_visual.add_theme_stylebox_override("panel", _bar_style(false))
	_start.add_child(_start_visual)
	var start_lbl := Label.new()
	start_lbl.name = "Text"
	start_lbl.text = "我知道了，開始任務"
	start_lbl.add_theme_font_size_override("font_size", 20)
	start_lbl.add_theme_color_override("font_color", C_TEXT)
	start_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_visual.add_child(start_lbl)
	_start_arrow = Art.new("arrow", C_TEXT, 2.0)
	_start_visual.add_child(_start_arrow)
	_start.mouse_entered.connect(func(): _start_hover(true))
	_start.mouse_exited.connect(func(): _start_hover(false))
	_start.pressed.connect(_on_start)
	add_child(_start)

	_details = Button.new()
	_details.flat = true
	_details.focus_mode = Control.FOCUS_NONE
	_details.text = "查看詳細規則"
	_details.add_theme_font_size_override("font_size", 14)
	_details.add_theme_color_override("font_color", C_MUTED)
	_details.add_theme_color_override("font_hover_color", C_GOLD)
	_details.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_details.pressed.connect(func(): details_requested.emit())
	add_child(_details)

	resized.connect(_layout)
	_layout()
	if not UI.is_animation_disabled():
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.2)


func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(C_GOLD, 0.7)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _card_style(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = C_GOLD.lightened(0.2) if hover else Color(C_GOLD, 0.75)
	return sb


func _bar_style(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = C_GOLD.lightened(0.25) if hover else C_GOLD
	return sb


func _step_card(step: Array) -> Control:
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(card)
	var art := Art.new(str(step[1]), C_GOLD, 2.5)
	art.name = "Art"
	card.add_child(art)
	var title := Label.new()
	title.name = "Title"
	title.text = str(step[2])
	title.add_theme_color_override("font_color", C_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(title)
	var line := ColorRect.new()
	line.name = "Line"
	line.color = C_GOLD
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)
	# Number badge sits on the top edge of the card
	var badge := Panel.new()
	badge.name = "Badge"
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = C_BG
	bsb.set_corner_radius_all(30)
	bsb.set_border_width_all(1)
	bsb.border_color = C_GOLD
	badge.add_theme_stylebox_override("panel", bsb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	var num := Label.new()
	num.text = str(step[0])
	num.add_theme_color_override("font_color", C_TEXT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(num)
	card.set_meta("badge", badge)
	card.mouse_entered.connect(func(): _card_hover(card, true))
	card.mouse_exited.connect(func(): _card_hover(card, false))
	return card


func _chip(items: Array) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_CARD, 0.92)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(C_GOLD, 0.8)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	for i in range(items.size()):
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(C_GOLD, 0.45)
			sep.custom_minimum_size = Vector2(1, 26)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(sep)
		var art := Art.new(str(items[i][0]), C_GOLD, 2.0)
		art.custom_minimum_size = Vector2(30, 30)
		art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(art)
		var l := Label.new()
		l.text = str(items[i][1])
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", C_TEXT)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
	add_child(p)
	return p


func _layout() -> void:
	if _start == null or size.x < 10:
		return
	var phone := size.x < 700.0
	var pad := 16.0 if phone else 40.0
	# Logo top-left: the cover's transparent title layer
	var lw := clampf(size.x * 0.15, 120.0, 240.0)
	_logo.size = Vector2(lw, lw * TITLE.get_height() / TITLE.get_width())
	_logo.position = Vector2(pad, pad * 0.5)
	var hs := 28 if phone else 44
	_heading.add_theme_font_size_override("font_size", hs)
	_heading.reset_size()
	var top := _logo.position.y + _logo.size.y + 4.0 if phone else maxf(24.0, size.y * 0.05)
	_heading.position = Vector2((size.x - _heading.size.x) * 0.5, top)
	_sub.add_theme_font_size_override("font_size", 14 if phone else 17)
	_sub.reset_size()
	_sub.position = Vector2((size.x - _sub.size.x) * 0.5, _heading.position.y + _heading.size.y + 2)
	var rw := clampf(size.x * 0.07, 24.0, 100.0)
	_rule_l.size = Vector2(rw, 1)
	_rule_r.size = Vector2(rw, 1)
	_rule_l.position = Vector2(_heading.position.x - rw - 16, _heading.position.y + _heading.size.y * 0.55)
	_rule_r.position = Vector2(_heading.position.x + _heading.size.x + 16, _rule_l.position.y)
	_rule_l.visible = not phone
	_rule_r.visible = not phone

	var cards_top := _sub.position.y + _sub.size.y + (34.0 if not phone else 26.0)
	var bottom_h := 64.0 + 26.0 + 30.0 + (58.0 if not phone else 150.0)
	var avail_h := size.y - cards_top - bottom_h - 24.0
	var cols := 2 if phone else 4
	var gap := 14.0 if phone else 40.0
	var cw := minf((size.x - pad * 2 - gap * (cols - 1)) / cols, 300.0)
	var rows := 4 / cols
	var ch := clampf((avail_h - (rows - 1) * (gap + 14)) / rows, 120.0, 360.0)
	cw = minf(cw, ch * 0.9) if not phone else cw
	var total_w := cw * cols + gap * (cols - 1)
	var x0 := (size.x - total_w) * 0.5
	for i in range(_cards.size()):
		var card: Panel = _cards[i]
		var col := i % cols
		var row := i / cols
		card.position = Vector2(x0 + col * (cw + gap), cards_top + row * (ch + gap + 14))
		card.size = Vector2(cw, ch)
		card.pivot_offset = card.size * 0.5
		var art: Control = card.get_node("Art")
		var a := minf(cw * 0.62, ch * 0.5)
		art.size = Vector2(a, a)
		art.position = Vector2((cw - a) * 0.5, ch * 0.12)
		var title: Label = card.get_node("Title")
		title.add_theme_font_size_override("font_size", 15 if phone else int(clampf(cw * 0.085, 16.0, 24.0)))
		title.size = Vector2(cw, 32)
		title.position = Vector2(0, ch * 0.72)
		var line: ColorRect = card.get_node("Line")
		line.size = Vector2(24, 2)
		line.position = Vector2((cw - 24) * 0.5, ch * 0.72 + 38)
		var badge: Panel = card.get_meta("badge")
		var b := 32.0 if phone else 44.0
		badge.size = Vector2(b, b)
		badge.position = card.position + Vector2((cw - b) * 0.5, -b * 0.5)
		(badge.get_child(0) as Label).add_theme_font_size_override("font_size", 13 if phone else 18)
	for i in range(_arrows.size()):
		var arrow: Control = _arrows[i]
		arrow.visible = not phone
		var left: Panel = _cards[i]
		arrow.size = Vector2(gap * 0.8, 28)
		arrow.position = Vector2(left.position.x + cw + gap * 0.1, left.position.y + ch * 0.45)
	var last: Panel = _cards[_cards.size() - 1]
	var chips_y := last.position.y + ch + 28.0
	_chips.reset_size()
	_time_chip.reset_size()
	if phone:
		_chips.position = Vector2((size.x - _chips.size.x) * 0.5, chips_y)
		_time_chip.position = Vector2((size.x - _time_chip.size.x) * 0.5, chips_y + _chips.size.y + 10)
		chips_y += _chips.size.y + 10
	else:
		var gap2 := 40.0
		var row_w := _chips.size.x + gap2 + _time_chip.size.x
		_chips.position = Vector2((size.x - row_w) * 0.5, chips_y)
		_time_chip.position = Vector2(_chips.position.x + _chips.size.x + gap2, chips_y)
	var bw := minf(420.0, size.x - pad * 2)
	_start.size = Vector2(bw, 64)
	_start.position = Vector2((size.x - bw) * 0.5, chips_y + _chips.size.y + 26)
	_start_visual.size = _start.size
	_start_visual.pivot_offset = _start.size * 0.5
	var lbl: Label = _start_visual.get_node("Text")
	lbl.reset_size()
	lbl.position = Vector2((bw - lbl.size.x) * 0.5 - 14, (64 - lbl.size.y) * 0.5)
	_start_arrow.size = Vector2(22, 22)
	_start_arrow.position = Vector2(lbl.position.x + lbl.size.x + 16, 21)
	_details.reset_size()
	_details.position = Vector2((size.x - _details.size.x) * 0.5, _start.position.y + 64 + 4)


func _card_hover(card: Panel, on: bool) -> void:
	card.add_theme_stylebox_override("panel", _card_style(on))
	if UI.is_animation_disabled():
		return
	var tw := card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE * (1.02 if on else 1.0), 0.18 if on else 0.16)


func _start_hover(on: bool) -> void:
	_start_visual.add_theme_stylebox_override("panel", _bar_style(on))
	if UI.is_animation_disabled():
		return
	var tw := _start.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_start_visual, "position:y", -3.0 if on else 0.0, 0.18 if on else 0.16)
	var lbl: Label = _start_visual.get_node("Text")
	tw.tween_property(_start_arrow, "position:x", lbl.position.x + lbl.size.x + 16 + (5.0 if on else 0.0), 0.18 if on else 0.16)


func _on_start() -> void:
	if UI.is_animation_disabled():
		closed.emit()
		return
	var tw := _start.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_start_visual, "scale", Vector2.ONE * 0.98, 0.06)
	tw.tween_property(_start_visual, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func(): closed.emit())
