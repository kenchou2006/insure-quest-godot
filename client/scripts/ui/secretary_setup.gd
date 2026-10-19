extends Control
## Choose a training secretary (Aly / Kevin) or challenge alone. Remembered; can be changed in Settings.
## Each card is a fixed Button (stable hover area); only its Visual child moves, so hover never flickers.
## Hover / press / select motion uses Tweens; a shader light follows the cursor inside the card.
signal selected(enabled: bool, role: String)
## 返回顧問報到, with the highlighted (not yet confirmed) choice so it can be restored
signal back_requested(current_key: String)

const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
const BACKGROUND := preload("res://assets/startup/loading.png")
const CURSOR_LIGHT := preload("res://assets/startup/cursor_light.gdshader")
const SecretaryVoice := preload("res://scripts/secretary_voice.gd")
const BackButton := preload("res://scripts/ui/back_button.gd")

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")

const IN_TIME := 0.18
const OUT_TIME := 0.16

const CHOICES := [
	{"key": "female", "name": "Aly", "enabled": true},
	{"key": "male", "name": "Kevin", "enabled": true},
	{"key": "solo", "name": "自行挑戰", "enabled": false},
]

## Card to preselect ("female", "male" or "solo"), e.g. the player's previous choice
var initial_key := ""
var _cards: Array = []
var _selected := -1
var _confirm: Button
var _confirm_arrow: Control
## Confirm bar: Button stays fixed, its Visual moves (like the cards)
var _bar_visual: Control
var _bar_bg: Panel
var _bar_check: Control
var _bar_left: Label
var _bar_sep: ColorRect
var _bar_right: Label
var _bar_hover := false
var _heading: Label
var _sub: Label
var _rule_l: ColorRect
var _rule_r: ColorRect
var _hint: Label
var _leaving := false
var _back: Button


## Flat 2px line icons used on the cards
class LineIcon extends Control:
	var kind := ""
	var color := Color("#F3F0E7")

	func _init(icon_kind: String, sz: float, col: Color) -> void:
		kind = icon_kind
		color = col
		custom_minimum_size = Vector2(sz, sz)
		size = Vector2(sz, sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		var w := 2.0
		match kind:
			"mic":
				draw_arc(c + Vector2(0, -r * 0.35), r * 0.32, PI, TAU, 10, color, w, true)
				draw_line(c + Vector2(-r * 0.32, -r * 0.35), c + Vector2(-r * 0.32, r * 0.05), color, w, true)
				draw_line(c + Vector2(r * 0.32, -r * 0.35), c + Vector2(r * 0.32, r * 0.05), color, w, true)
				draw_arc(c + Vector2(0, r * 0.05), r * 0.32, 0, PI, 10, color, w, true)
				draw_arc(c + Vector2(0, r * 0.05), r * 0.58, 0.15, PI - 0.15, 12, color, w, true)
				draw_line(c + Vector2(0, r * 0.63), c + Vector2(0, r), color, w, true)
			"calendar":
				draw_rect(Rect2(c - Vector2(r * 0.85, r * 0.7), Vector2(r * 1.7, r * 1.6)), color, false, w)
				draw_line(c + Vector2(-r * 0.85, -r * 0.25), c + Vector2(r * 0.85, -r * 0.25), color, w, true)
				draw_line(c + Vector2(-r * 0.45, -r), c + Vector2(-r * 0.45, -r * 0.55), color, w, true)
				draw_line(c + Vector2(r * 0.45, -r), c + Vector2(r * 0.45, -r * 0.55), color, w, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, r * 0.25), c + Vector2(-r * 0.05, r * 0.52), c + Vector2(r * 0.4, 0.0)]), color, w, true)
			"bulb":
				draw_arc(c + Vector2(0, -r * 0.2), r * 0.6, PI * 0.8, PI * 2.2, 18, color, w, true)
				draw_line(c + Vector2(-r * 0.32, r * 0.28), c + Vector2(-r * 0.25, r * 0.6), color, w, true)
				draw_line(c + Vector2(r * 0.32, r * 0.28), c + Vector2(r * 0.25, r * 0.6), color, w, true)
				draw_line(c + Vector2(-r * 0.28, r * 0.62), c + Vector2(r * 0.28, r * 0.62), color, w, true)
				draw_line(c + Vector2(-r * 0.18, r * 0.85), c + Vector2(r * 0.18, r * 0.85), color, w, true)
			"speaker":
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.25), c + Vector2(-r * 0.35, -r * 0.25), c + Vector2(0, -r * 0.6), c + Vector2(0, r * 0.6), c + Vector2(-r * 0.35, r * 0.25), c + Vector2(-r * 0.7, r * 0.25), c + Vector2(-r * 0.7, -r * 0.25)]), color, w, true)
				draw_arc(c + Vector2(r * 0.1, 0), r * 0.35, -0.9, 0.9, 8, color, w, true)
				draw_arc(c + Vector2(r * 0.1, 0), r * 0.65, -0.9, 0.9, 10, color, w, true)
			"check":
				draw_circle(c, r, C_GREEN_CHECK)
				draw_arc(c, r, 0, TAU, 28, Color("#C6A15B"), 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.45, -r * 0.32)]), Color("#F3F0E7"), 2.5, true)
			"arrow":
				draw_polyline(PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.55), c + Vector2(r * 0.3, 0), c + Vector2(-r * 0.25, r * 0.55)]), color, w, true)
			"compass":
				var gold := Color("#C6A15B")
				draw_arc(c, r * 0.95, 0, TAU, 48, gold, 2.0, true)
				draw_arc(c, r * 0.8, 0, TAU, 48, Color(gold, 0.5), 1.0, true)
				for k in range(16):
					var a := TAU * k / 16.0
					var l := r * (0.08 if k % 2 == 0 else 0.04)
					draw_line(c + Vector2(cos(a), sin(a)) * r * 0.8, c + Vector2(cos(a), sin(a)) * (r * 0.8 + l), gold, 1.0, true)
				for k in range(4):
					var a := PI * 0.5 * k - PI * 0.5
					var tip := c + Vector2(cos(a), sin(a)) * r * 0.95
					var side_a := c + Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * r * 0.13
					var side_b := c + Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5)) * r * 0.13
					draw_colored_polygon(PackedVector2Array([c, side_a, tip]), Color(gold, 0.95))
					draw_colored_polygon(PackedVector2Array([c, tip, side_b]), Color(gold.darkened(0.35), 0.95))
				for k in range(4):
					var a := PI * 0.5 * k - PI * 0.25
					var tip := c + Vector2(cos(a), sin(a)) * r * 0.55
					draw_line(c, tip, Color(gold, 0.7), 1.5, true)

	const C_GREEN_CHECK := Color("#00A86B")


## One selectable card. The Button never moves; Visual carries every transform.
class Card extends Button:
	signal preview(card: Button)
	var info: Dictionary
	var visual: Control
	var background: Panel
	var portrait: TextureRect
	var emblem: Control
	var light: ColorRect
	var name_label: Label
	var divider: ColorRect
	var desc_box: Control
	var gold_border: Panel
	var speaker: Button
	var speaker_icon: Control
	var check: Control
	var is_selected := false
	var hovered := false
	var _tw: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.1, 0.09, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	_heading = _text("選擇培訓秘書", 40, C_TEXT)
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = _text("可隨時更換或關閉導覽", 16, C_MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rule_l = ColorRect.new()
	_rule_r = ColorRect.new()
	for rule: ColorRect in [_rule_l, _rule_r]:
		rule.color = Color(C_GOLD, 0.7)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rule)

	for info: Dictionary in CHOICES:
		var card := _build_card(info)
		add_child(card)
		_cards.append(card)

	# Selection confirm bar (not a second "enter game" button): ✓ 已選 Aly ｜ 使用 Aly 進入培訓 →
	_confirm = Button.new()
	_confirm.flat = true
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_confirm.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_confirm.pressed.connect(_on_confirm)
	_confirm.mouse_entered.connect(func(): _confirm_hover(true))
	_confirm.mouse_exited.connect(func(): _confirm_hover(false))
	_bar_visual = Control.new()
	_confirm.add_child(_ignore(_bar_visual))
	_bar_bg = Panel.new()
	_bar_visual.add_child(_ignore(_bar_bg))
	_bar_check = LineIcon.new("check", 22, C_GOLD)
	_bar_visual.add_child(_bar_check)
	_bar_left = Label.new()
	_bar_left.add_theme_font_size_override("font_size", 15)
	_bar_left.add_theme_color_override("font_color", C_MUTED)
	_bar_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_visual.add_child(_ignore(_bar_left))
	_bar_sep = ColorRect.new()
	_bar_sep.color = Color(C_GOLD, 0.35)
	_bar_visual.add_child(_ignore(_bar_sep))
	_bar_right = Label.new()
	_bar_right.add_theme_font_size_override("font_size", 18)
	_bar_right.add_theme_color_override("font_color", C_TEXT)
	_bar_right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_visual.add_child(_ignore(_bar_right))
	_confirm_arrow = LineIcon.new("arrow", 20, C_TEXT)
	_bar_visual.add_child(_confirm_arrow)
	add_child(_confirm)

	_hint = _text("", 13, C_MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back = BackButton.new("返回顧問報到")
	_back.pressed.connect(_on_back)
	add_child(_back)
	resized.connect(_layout)
	_layout()
	for i in range(_cards.size()):
		if str((_cards[i] as Card).info.key) == initial_key:
			_selected = i
			_set_selected(_cards[i], true)
	_refresh_confirm()


func _text(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _ignore(node: Control) -> Control:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


# ───────── Card construction ─────────

func _build_card(info: Dictionary) -> Card:
	var card := Card.new()
	card.info = info
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		card.add_theme_stylebox_override(st, StyleBoxEmpty.new())

	var visual := Control.new()
	visual.clip_contents = true
	card.add_child(_ignore(visual))
	card.visual = visual

	var back := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(C_CARD, 0.94)
	bsb.set_corner_radius_all(14)
	back.add_theme_stylebox_override("panel", bsb)
	visual.add_child(_ignore(back))
	card.background = back

	if info.key == "solo":
		var emblem := LineIcon.new("compass", 160, C_GOLD)
		visual.add_child(emblem)
		card.emblem = emblem
	else:
		var art := TextureRect.new()
		var atlas := AtlasTexture.new()
		var tex: Texture2D = FEMALE if info.key == "female" else MALE
		atlas.atlas = tex
		atlas.region = Rect2(Vector2(0, 0), Vector2(tex.get_width(), tex.get_height() * 0.62))
		art.texture = atlas
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		visual.add_child(_ignore(art))
		card.portrait = art
		# Fade the portrait into the card so name and features stay readable
		var fade := TextureRect.new()
		var grad := Gradient.new()
		grad.set_color(0, Color(C_CARD, 0.0))
		grad.set_color(1, Color(C_CARD, 0.98))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		fade.texture = gt
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.name = "Fade"
		visual.add_child(_ignore(fade))

	var light := ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = CURSOR_LIGHT
	mat.set_shader_parameter("strength", 0.0)
	light.material = mat
	light.color = Color.WHITE
	visual.add_child(_ignore(light))
	card.light = light

	var name_label := Label.new()
	name_label.text = str(info.name)
	name_label.add_theme_color_override("font_color", C_TEXT)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	name_label.add_theme_constant_override("shadow_offset_y", 2)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	visual.add_child(_ignore(name_label))
	card.name_label = name_label

	var divider := ColorRect.new()
	divider.color = C_GOLD
	visual.add_child(_ignore(divider))
	card.divider = divider

	if info.key == "solo":
		var d := Label.new()
		d.text = "關閉語音與提示"
		d.add_theme_color_override("font_color", C_MUTED)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		visual.add_child(_ignore(d))
		card.desc_box = d
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		for f: Array in [["mic", "語音導覽"], ["calendar", "任務提醒"], ["bulb", "操作提示"]]:
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 6)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var ic := LineIcon.new(f[0], 30, C_GOLD)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(ic)
			var l := Label.new()
			l.text = f[1]
			l.add_theme_color_override("font_color", C_TEXT)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(_ignore(l))
			row.add_child(_ignore(col))
		visual.add_child(_ignore(row))
		card.desc_box = row

	var border := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0, 0, 0, 0)
	gsb.set_corner_radius_all(14)
	gsb.set_border_width_all(2)
	gsb.border_color = C_GOLD
	border.add_theme_stylebox_override("panel", gsb)
	border.modulate.a = 0.25
	visual.add_child(_ignore(border))
	card.gold_border = border

	if info.key != "solo":
		# Listen button stays clickable on top of the card (the only child that takes the mouse)
		var sp := Button.new()
		sp.focus_mode = Control.FOCUS_NONE
		sp.tooltip_text = "試聽語音"
		sp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(C_BG, 0.55)
		ssb.set_corner_radius_all(22)
		ssb.set_border_width_all(1)
		ssb.border_color = Color(C_TEXT, 0.6)
		for st: String in ["normal", "hover", "pressed", "focus"]:
			sp.add_theme_stylebox_override(st, ssb)
		var sic := LineIcon.new("speaker", 22, C_TEXT)
		sp.add_child(sic)
		sp.pressed.connect(func(): card.preview.emit(card))
		visual.add_child(sp)
		card.speaker = sp
		card.speaker_icon = sic
		sp.modulate.a = 1.0 if _touch() else 0.0

	var check := LineIcon.new("check", 36, C_GOLD)
	check.modulate.a = 0.0
	visual.add_child(check)
	card.check = check

	card.mouse_entered.connect(func(): _hover(card, true))
	card.mouse_exited.connect(func(): _hover(card, false))
	card.pressed.connect(func(): _press(card))
	card.gui_input.connect(func(ev: InputEvent): _track_light(card, ev))
	card.preview.connect(_preview)
	card.resized.connect(func(): _layout_card(card))
	return card


## Phones have no hover: the listen button stays visible and a tap selects directly
func _touch() -> bool:
	return UI.is_phone()


# ───────── Layout ─────────

func _layout() -> void:
	if _confirm == null or size.x < 10:
		return
	var compact := size.x < 760.0 or size.y < 520.0
	var portrait_screen := size.y > size.x
	var pad := 16.0 if compact else 40.0
	var hs := 26 if portrait_screen else (32 if compact else 44)
	_heading.add_theme_font_size_override("font_size", hs)
	_heading.reset_size()
	var top := maxf(pad * 0.6, 22.0)
	# 返回 sits top-left; on narrow screens the heading moves under it
	var bw := _back.get_combined_minimum_size()
	_back.size = bw
	_back.position = Vector2(pad * 0.6 if compact else pad * 0.6, top - 6.0)
	if portrait_screen or size.x < bw.x * 2 + _heading.size.x + 40:
		top += bw.y + 4.0
	_heading.position = Vector2((size.x - _heading.size.x) * 0.5, top)
	_sub.reset_size()
	_sub.position = Vector2((size.x - _sub.size.x) * 0.5, _heading.position.y + _heading.size.y + 2)
	var rule_w := clampf(size.x * 0.08, 30.0, 110.0)
	var ry := _heading.position.y + _heading.size.y * 0.55
	_rule_l.size = Vector2(rule_w, 1)
	_rule_l.position = Vector2(_heading.position.x - rule_w - 18, ry)
	_rule_r.size = Vector2(rule_w, 1)
	_rule_r.position = Vector2(_heading.position.x + _heading.size.x + 18, ry)
	_rule_l.visible = not portrait_screen
	_rule_r.visible = not portrait_screen

	var cards_top := _sub.position.y + _sub.size.y + (18.0 if compact else 30.0)
	var confirm_h := 64.0
	# Room for the confirm button and the hint line under it
	var bottom_room := confirm_h + (28.0 if not compact else 18.0) + 40.0
	var avail_h := size.y - cards_top - bottom_room
	var gap := 18.0 if not compact else 10.0
	if portrait_screen:
		# Phones: three wide rows
		var w := size.x - pad * 2
		var h := clampf((avail_h - gap * 2) / 3.0, 110.0, 200.0)
		for i in range(_cards.size()):
			var card: Card = _cards[i]
			card.position = Vector2(pad, cards_top + i * (h + gap))
			card.size = Vector2(w, h)
	else:
		var card_h := clampf(avail_h, 220.0, 560.0)
		var card_w := minf(card_h * 0.66, (size.x - pad * 2 - gap * 2) / 3.0)
		var total := card_w * 3 + gap * 2
		var x0 := (size.x - total) * 0.5
		for i in range(_cards.size()):
			var card: Card = _cards[i]
			card.position = Vector2(x0 + i * (card_w + gap), cards_top)
			card.size = Vector2(card_w, card_h)
	var last: Card = _cards[_cards.size() - 1]
	var cw := minf(420.0, size.x - pad * 2)
	_confirm.size = Vector2(cw, confirm_h)
	_confirm.position = Vector2((size.x - cw) * 0.5, last.position.y + last.size.y + (26.0 if not compact else 16.0))
	_layout_bar()
	_hint.reset_size()
	_hint.position = Vector2((size.x - _hint.size.x) * 0.5, _confirm.position.y + confirm_h + 6)


func _layout_card(card: Card) -> void:
	var v := card.visual
	var s := card.size
	v.size = s
	v.pivot_offset = s * 0.5
	card.background.size = s
	card.gold_border.size = s
	card.light.size = s
	var mat := card.light.material as ShaderMaterial
	mat.set_shader_parameter("aspect", s.x / maxf(1.0, s.y))
	var wide := s.x > s.y * 1.3
	var name_fs := int(clampf(s.y * 0.075, 22.0, 40.0)) if not wide else 24
	card.name_label.add_theme_font_size_override("font_size", name_fs if card.info.key != "solo" else name_fs - 4)
	if wide:
		# Row layout for phones: picture left, text right
		var pic := Rect2(Vector2.ZERO, Vector2(s.y * 0.9, s.y))
		if card.portrait:
			card.portrait.size = pic.size
			card.portrait.position = pic.position
			card.portrait.pivot_offset = pic.size * 0.5
			var fade := card.visual.get_node("Fade") as TextureRect
			fade.visible = false
		if card.emblem:
			var e := s.y * 0.7
			card.emblem.size = Vector2(e, e)
			card.emblem.position = Vector2((pic.size.x - e) * 0.5, (s.y - e) * 0.5)
		var tx := pic.size.x + 12
		card.name_label.size = Vector2(s.x - tx - 12, 34)
		card.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.name_label.position = Vector2(tx, s.y * 0.18)
		card.divider.size = Vector2(28, 2)
		card.divider.position = Vector2(tx, s.y * 0.18 + 38)
		card.desc_box.position = Vector2(tx - 6, s.y * 0.18 + 48)
		card.desc_box.size = Vector2(s.x - tx - 8, s.y * 0.45)
		_set_feature_font(card, 12)
	else:
		if card.portrait:
			card.portrait.size = Vector2(s.x, s.y * 0.78)
			card.portrait.position = Vector2.ZERO
			card.portrait.pivot_offset = card.portrait.size * 0.5
			var fade := card.visual.get_node("Fade") as TextureRect
			fade.visible = true
			fade.size = Vector2(s.x, s.y * 0.42)
			fade.position = Vector2(0, s.y * 0.4)
		if card.emblem:
			var e := s.x * 0.55
			card.emblem.size = Vector2(e, e)
			card.emblem.position = Vector2((s.x - e) * 0.5, s.y * 0.22)
		card.name_label.size = Vector2(s.x, name_fs + 12)
		card.name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.name_label.position = Vector2(0, s.y * 0.66)
		card.divider.size = Vector2(28, 2)
		card.divider.position = Vector2((s.x - 28) * 0.5, s.y * 0.66 + name_fs + 16)
		card.desc_box.size = Vector2(s.x - 16, s.y * 0.18)
		card.desc_box.position = Vector2(8, s.y * 0.66 + name_fs + 28)
		_set_feature_font(card, int(clampf(s.x * 0.042, 12.0, 15.0)))
	if card.speaker:
		var b := 40.0
		card.speaker.size = Vector2(b, b)
		card.speaker.position = Vector2(s.x - b - 14, 14)
		card.speaker.pivot_offset = Vector2(b, b) * 0.5
		card.speaker_icon.position = Vector2((b - 22) * 0.5, (b - 22) * 0.5)
	# Selected check sits top-right; on secretary cards it sits left of the listen button
	card.check.position = Vector2(s.x - 36 - 14 - (48 if card.speaker else 0), 16)
	if card.portrait:
		card.portrait.scale = Vector2.ONE * (1.035 if card.hovered else 1.0)


func _set_feature_font(card: Card, fs: int) -> void:
	if card.desc_box is Label:
		(card.desc_box as Label).add_theme_font_size_override("font_size", fs + 2)
		return
	for col in card.desc_box.get_children():
		for ch in col.get_children():
			if ch is Label:
				(ch as Label).add_theme_font_size_override("font_size", fs)


# ───────── Motion ─────────

func _reduced() -> bool:
	return UI.reduce_motion


func _hover(card: Card, on: bool) -> void:
	card.hovered = on
	if card._tw and card._tw.is_valid():
		card._tw.kill()
	var t := IN_TIME if on else OUT_TIME
	if _reduced():
		t = 0.01
	var tw := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card._tw = tw
	tw.tween_property(card.visual, "position:y", -8.0 if on else 0.0, t)
	tw.tween_property(card.visual, "scale", Vector2.ONE * (1.025 if on else 1.0), t)
	if card.portrait:
		tw.tween_property(card.portrait, "scale", Vector2.ONE * (1.035 if on else 1.0), t)
	tw.tween_property(card.gold_border, "modulate:a", 1.0 if (on or card.is_selected) else 0.25, t)
	if card.speaker and not _touch():
		tw.tween_property(card.speaker, "modulate:a", 1.0 if (on or card.is_selected) else 0.0, t)
		tw.tween_property(card.speaker, "rotation", deg_to_rad(6.0) if on else 0.0, t)
	var mat := card.light.material as ShaderMaterial
	tw.tween_method(func(v: float): mat.set_shader_parameter("strength", v), float(mat.get_shader_parameter("strength")), 0.22 if on else 0.0, t)


func _track_light(card: Card, ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var p: Vector2 = ev.position / card.size.max(Vector2.ONE)
		(card.light.material as ShaderMaterial).set_shader_parameter("center", p)


func _press(card: Card) -> void:
	for c: Card in _cards:
		_set_selected(c, c == card)
	if card._tw and card._tw.is_valid():
		card._tw.kill()
	var tw := card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card._tw = tw
	var back := 1.025 if card.hovered else 1.0
	tw.tween_property(card.visual, "scale", Vector2.ONE * 0.98, 0.06)
	tw.tween_property(card.visual, "scale", Vector2.ONE * back, 0.12)
	_selected = _cards.find(card)
	Sound.play("click", self)
	_refresh_confirm()


func _set_selected(card: Card, on: bool) -> void:
	card.is_selected = on
	var t := 0.01 if _reduced() else IN_TIME
	var tw := card.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card.check, "modulate:a", 1.0 if on else 0.0, t)
	tw.tween_property(card.gold_border, "modulate:a", 1.0 if (on or card.hovered) else 0.25, t)
	if card.speaker and not _touch():
		tw.tween_property(card.speaker, "modulate:a", 1.0 if (on or card.hovered) else 0.0, t)
	if on and not _reduced():
		card.check.scale = Vector2(0.6, 0.6)
		card.check.pivot_offset = card.check.size * 0.5
		tw.tween_property(card.check, "scale", Vector2.ONE, t).set_trans(Tween.TRANS_BACK)


func _refresh_confirm() -> void:
	_confirm.disabled = _selected < 0
	_confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _selected >= 0 else Control.CURSOR_ARROW
	if _selected < 0:
		_bar_left.text = ""
		_bar_right.text = "請先選擇培訓秘書"
		_bar_right.add_theme_color_override("font_color", Color(C_MUTED, 0.8))
	else:
		var info: Dictionary = _cards[_selected].info
		_bar_left.text = "已選 %s" % str(info.name)
		_bar_right.text = "不啟用秘書，直接開始" if not bool(info.enabled) else "使用 %s 進入培訓" % str(info.name)
		_bar_right.add_theme_color_override("font_color", C_TEXT)
	if _hint.text.begins_with("請先"):
		_hint.text = ""
	_layout_bar()


func _bar_style(hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var ready_to_go := _selected >= 0
	sb.bg_color = C_CARD if ready_to_go else Color("#1c3a35")
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = C_GOLD.lightened(0.25) if hover else (C_GOLD if ready_to_go else Color(C_GOLD, 0.3))
	return sb


func _arrow_x() -> float:
	return _confirm.size.x - 20.0 - 20.0


## Left: ✓ + selected name; right: main action + arrow. Nothing selected: one centred, muted prompt.
func _layout_bar() -> void:
	if _bar_visual == null:
		return
	var w := _confirm.size.x
	var h := _confirm.size.y
	_bar_visual.size = _confirm.size
	_bar_visual.pivot_offset = _confirm.size * 0.5
	_bar_bg.size = _confirm.size
	_bar_bg.add_theme_stylebox_override("panel", _bar_style(_bar_hover))
	var ready_to_go := _selected >= 0
	_bar_check.visible = ready_to_go
	_bar_sep.visible = ready_to_go
	_confirm_arrow.visible = ready_to_go
	_bar_check.position = Vector2(18, (h - 22) * 0.5)
	_bar_left.reset_size()
	_bar_left.position = Vector2(48, (h - _bar_left.size.y) * 0.5)
	var sep_x := 48.0 + _bar_left.size.x + 16.0
	_bar_sep.size = Vector2(1, h * 0.4)
	_bar_sep.position = Vector2(sep_x, h * 0.3)
	_bar_right.reset_size()
	if ready_to_go:
		_bar_right.position = Vector2(_arrow_x() - 10 - _bar_right.size.x, (h - _bar_right.size.y) * 0.5)
	else:
		_bar_right.position = Vector2((w - _bar_right.size.x) * 0.5, (h - _bar_right.size.y) * 0.5)
	_confirm_arrow.position = Vector2(_arrow_x() + (5.0 if _bar_hover else 0.0), (h - 20) * 0.5)


func _confirm_hover(on: bool) -> void:
	_bar_hover = on and _selected >= 0
	_bar_bg.add_theme_stylebox_override("panel", _bar_style(_bar_hover))
	var t := 0.01 if _reduced() else (IN_TIME if on else OUT_TIME)
	var tw := _confirm.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_visual, "position:y", -3.0 if _bar_hover else 0.0, t)
	tw.tween_property(_confirm_arrow, "position:x", _arrow_x() + (5.0 if _bar_hover else 0.0), t)


func _on_confirm() -> void:
	if _selected < 0 or _leaving:
		return
	_leaving = true
	var info: Dictionary = _cards[_selected].info
	var tw := _confirm.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_bar_visual, "scale", Vector2.ONE * 0.98, 0.06)
	tw.tween_property(_bar_visual, "scale", Vector2.ONE, 0.08)
	tw.tween_callback(func():
		if bool(info.enabled):
			selected.emit(true, str(info.key))
		else:
			selected.emit(false, "female")
	)


func _on_back() -> void:
	if _leaving:
		return
	_leaving = true
	var key := str((_cards[_selected] as Card).info.key) if _selected >= 0 else ""
	back_requested.emit(key)


## Listen button: greeting in this secretary's own voice (same mapping as the in-game guide)
func _preview(card: Button) -> void:
	var info: Dictionary = (card as Card).info
	var sid := SecretaryVoice.id_from_choice(bool(info.enabled), str(info.key))
	var p := SecretaryVoice.profile(sid)
	if SecretaryVoice.speak(sid, str(p.sample)):
		_hint.text = "「%s」" % str(p.sample)
	elif MusicManager.tts_volume() == 0:
		_hint.text = "秘書語音已關閉，可在「設定」調整音量"
	else:
		_hint.text = "此裝置沒有中文%s聲，選擇 %s 後會以字幕導覽" % ["男" if sid == "kevin" else "女", str(p.name)]
	_hint.reset_size()
	_hint.position.x = (size.x - _hint.size.x) * 0.5
