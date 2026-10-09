@tool
class_name UI
## UI utilities: color palette, theme, and factory functions for common components. All screens are constructed in code for team maintainability and review.

const BG := Color("#0b1f2a")
const PANEL := Color("#13303f")
const PANEL_2 := Color("#1b4052")
const ACCENT := Color("#00a36c")
const ACCENT_2 := Color("#2fd197")
const GOLD := Color("#f2c14e")
const TEXT := Color("#eef6f3")
const MUTED := Color("#9fb8c2")
const GOOD := Color("#3ddc97")
const OK := Color("#f2c14e")
const BAD := Color("#ff6b6b")
const INFO := Color("#8ecae6")

const PLAYER_COLORS := [Color("#3ddc97"), Color("#f2a541"), Color("#7aa2ff"), Color("#ff6bb5")]

const METRIC_NAMES := {"trust": "客戶信任", "insight": "需求洞察", "fit": "方案適配", "risk": "風險管理", "compliance": "合規表達"}
const RES_NAMES := {"cash": "緊急預備", "protect": "風險保障", "growth": "目標成長"}
const TILE_COLORS := {
	"start": Color("#f2c14e"), "client": Color("#00a36c"), "life": Color("#e76f51"), "market": Color("#7aa2ff"),
	"training": Color("#9d7bea"), "referral": Color("#2fd197"), "audit": Color("#ff6b6b"), "seminar": Color("#8ecae6"),
}
const TILE_ICONS := {
	"start": "★", "client": "◎", "life": "✚", "market": "↗", "training": "✓", "referral": "♥", "audit": "⚠", "seminar": "◇",
}
const TILE_NAMES := {
	"start": "結算", "client": "客戶", "life": "人生", "market": "市場", "training": "合規", "referral": "轉介", "audit": "稽核", "seminar": "研討",
}


static func tile_icon(type_key: String) -> String:
	return TILE_ICONS.get(type_key, "※")


static func tile_name(type_key: String) -> String:
	return TILE_NAMES.get(type_key, "事件")


static func tile_badge(type_key: String, compact: bool = false) -> String:
	var ic: String = tile_icon(type_key)
	if compact:
		return ic
	return "%s %s" % [ic, tile_name(type_key)]

static var layout_profile: String = "desktop"
static var content_size: Vector2i = Vector2i(1280, 720)

static func is_portrait() -> bool:
	return layout_profile == "phone_portrait" or layout_profile == "tablet_portrait"

static func is_phone() -> bool:
	return layout_profile == "phone_portrait" or layout_profile == "phone_landscape"

static func is_phone_portrait() -> bool:
	return layout_profile == "phone_portrait"

static func is_phone_landscape() -> bool:
	return layout_profile == "phone_landscape"

static func set_layout_profile(profile: String, sz: Vector2i) -> void:
	layout_profile = profile
	content_size = sz


static func fs(size: int) -> int:
	if is_phone_portrait():
		return maxi(roundi(size * 1.2), 15)
	elif is_phone_landscape():
		return maxi(roundi(size * 1.15), 15)
	return size


## Value based on layout profile: first value for phone, second value for others
static func scale_val(phone_value: int, normal_value: int) -> int:
	return phone_value if is_phone() else normal_value


static func tone_color(tone: String) -> Color:
	match tone:
		"good": return GOOD
		"ok": return OK
		"bad": return BAD
	return INFO


static func box(color: Color, radius := 14, border := Color(0, 0, 0, 0), pad := 14, shadow := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.75
	s.content_margin_bottom = pad * 0.75
	if shadow:
		s.shadow_color = Color(0, 0, 0, 0.22)
		s.shadow_size = 4
		s.shadow_offset = Vector2(0, 2)
	if border.a > 0:
		s.set_border_width_all(2)
		s.border_color = border
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := ACCENT
		match state:
			"hover": c = ACCENT_2
			"pressed": c = ACCENT.darkened(0.2)
			"disabled": c = Color("#3a5563")
		var sb := box(c, 10, Color(0, 0, 0, 0), 12)
		if state == "focus":
			sb = box(Color(0, 0, 0, 0), 10, Color(1, 1, 1, 0.6), 12)
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#9fb8c2"))
	var input_fs := fs(16)
	t.set_font_size("font_size", "LineEdit", input_fs)
	t.set_font_size("font_size", "OptionButton", input_fs)
	t.set_font_size("font_size", "TextEdit", input_fs)
	t.set_font_size("font_size", "PopupMenu", input_fs)
	t.set_stylebox("normal", "LineEdit", box(Color("#0e2633"), 10, Color("#2d5a6e"), 10))
	t.set_stylebox("focus", "LineEdit", box(Color("#0e2633"), 10, ACCENT_2, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("background", "ProgressBar", box(Color("#0e2633"), 6, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT_2, 6, Color(0, 0, 0, 0), 0))
	t.set_stylebox("panel", "PopupMenu", box(PANEL_2))
	t.set_stylebox("normal", "OptionButton", box(PANEL_2, 10, Color(0, 0, 0, 0), 12))
	t.set_stylebox("hover", "OptionButton", box(PANEL_2.lightened(0.1), 10, Color(0, 0, 0, 0), 12))
	t.set_stylebox("normal", "SpinBox", box(PANEL_2))
	# VScrollBar custom style (12px width, high-contrast visibility protection, including hover and pressed states)
	var sb_scroll := StyleBoxFlat.new()
	sb_scroll.bg_color = Color("#0b1f2b", 0.85)
	sb_scroll.set_corner_radius_all(6)
	sb_scroll.content_margin_left = 5
	sb_scroll.content_margin_right = 5
	sb_scroll.content_margin_top = 4
	sb_scroll.content_margin_bottom = 4

	var sb_grabber := StyleBoxFlat.new()
	sb_grabber.bg_color = Color("#2d6a88")
	sb_grabber.set_corner_radius_all(5)
	sb_grabber.content_margin_left = 5
	sb_grabber.content_margin_right = 5
	sb_grabber.content_margin_top = 8
	sb_grabber.content_margin_bottom = 8

	var sb_grabber_hl := StyleBoxFlat.new()
	sb_grabber_hl.bg_color = Color("#3da8d5")
	sb_grabber_hl.set_corner_radius_all(5)
	sb_grabber_hl.content_margin_left = 5
	sb_grabber_hl.content_margin_right = 5
	sb_grabber_hl.content_margin_top = 8
	sb_grabber_hl.content_margin_bottom = 8

	var sb_grabber_pressed := StyleBoxFlat.new()
	sb_grabber_pressed.bg_color = ACCENT
	sb_grabber_pressed.set_corner_radius_all(5)
	sb_grabber_pressed.content_margin_left = 5
	sb_grabber_pressed.content_margin_right = 5
	sb_grabber_pressed.content_margin_top = 8
	sb_grabber_pressed.content_margin_bottom = 8

	t.set_stylebox("scroll", "VScrollBar", sb_scroll)
	t.set_stylebox("scroll_focus", "VScrollBar", sb_scroll)
	t.set_stylebox("grabber", "VScrollBar", sb_grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grabber_hl)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grabber_pressed)
	return t


## Symbols used as bullets/prefixes ("✓ 合規", "★ 教練短評"). Word-wrap may break right after them and leave the
## symbol alone on a line, so the following space is made non-breaking.
const GLUE_SYMBOLS := "✓×★◎※●◆△▶◀✚↗⚠♥◇→"

static func glue(text: String) -> String:
	for ch in GLUE_SYMBOLS:
		text = text.replace(ch + " ", ch + "\u00a0")
	return text


static func label(text: String, size := 17, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = glue(text) if wrap else text
	l.add_theme_font_size_override("font_size", fs(size))
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func rich(bbcode: String, size := 17) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s := fs(size)
	r.add_theme_font_size_override("normal_font_size", s)
	r.add_theme_font_size_override("bold_font_size", s)
	return r


static func button(text: String, cb: Callable, size := 17, color := ACCENT) -> Button:
	var b := Button.new()
	b.text = glue(text)
	b.add_theme_font_size_override("font_size", fs(size))
	if color != ACCENT:
		b.add_theme_stylebox_override("normal", box(color, 10, Color(0, 0, 0, 0), 12))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 10, Color(0, 0, 0, 0), 12))
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 10, Color(0, 0, 0, 0), 12))
	b.pressed.connect(func():
		Sound.play("click", b)
		cb.call()
	)
	return b


## Multi-line text option button (long sentences wrap automatically)
static func option_button(text: String, cb: Callable, color := PANEL_2) -> Button:
	var b := Button.new()
	b.text = glue(text)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", fs(15))
	b.add_theme_stylebox_override("normal", box(color, 10, Color("#2d5a6e"), 12))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1), 10, ACCENT_2, 12))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.1), 10, ACCENT_2, 12))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.25), 10, Color(0, 0, 0, 0), 12))
	b.pressed.connect(func():
		Sound.play("click", b)
		cb.call()
	)
	return b


## Pop-in animation effect
static func pop_in(node: CanvasItem, duration := 0.25) -> void:
	node.modulate.a = 0.0
	node.scale = Vector2(0.95, 0.95)
	node.pivot_offset = node.size * 0.5
	var tw: Tween = node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration)
	tw.tween_property(node, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Fade-in float-up animation
static func fade_in(node: CanvasItem, duration := 0.25, offset_y := 16.0) -> void:
	node.modulate.a = 0.0
	# Container child positions are managed by container; tweening position writes stale coords, causing overlap with elements above
	if node.get_parent() is Container:
		node.create_tween().tween_property(node, "modulate:a", 1.0, duration)
		return
	var orig_y: float = node.position.y
	node.position.y += offset_y
	var tw: Tween = node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration)
	tw.tween_property(node, "position:y", orig_y, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


static func panel(color := PANEL, radius := 14, pad := 14) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color, radius, Color(0, 0, 0, 0), pad))
	# Allow mouse wheel to pass through card to outer ScrollContainer for scrolling
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func bar(value: float, color := ACCENT_2, width := 140.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0
	b.max_value = 100
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 12)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("fill", box(color, 6, Color(0, 0, 0, 0), 0))
	return b


static func metric_row(key: String, value: float) -> HBoxContainer:
	var h := hbox(6 if is_phone_portrait() else 8)
	var l := label(METRIC_NAMES.get(key, key), 14, MUTED)
	l.custom_minimum_size = Vector2(68 if is_phone() else 72, 0)
	h.add_child(l)
	var c := GOOD if value >= 75 else (OK if value >= 50 else BAD)
	var b := bar(value, c, 70 if is_phone_portrait() else 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	h.add_child(label(str(int(value)), 14, TEXT))
	return h


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


## Make non-input controls inside scroll areas pass wheel events (STOP blocks events from propagating to outer ScrollContainer)
static func pass_wheel(n: Node) -> void:
	for c in n.get_children():
		if c is Control and not (c is LineEdit or c is TextEdit or c is ScrollContainer):
			if (c as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
				(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		pass_wheel(c)


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## Fallback scene mapping (all clients have dedicated illustrations; this mapping is only an ultimate fallback for extreme anomalies)
const FALLBACK_SCENES: Dictionary = {
	"junhao": "zhiming",   # 王俊豪 (delivery rider): vehicle and street
	"meiling": "wanting",  # 張美玲 (single-parent admin assistant): cozy apartment desk
	"jiahao": "boting",    # 劉家豪 (software engineer, new father): home tech workstation
	"shufen": "shufen",    # 吳淑芬 (accounting manager): executive desk
	"wenjie": "ziyuan",    # 鄭文傑 (middle school teacher): steady desk and lesson plans
	"yiting": "wanting",   # 蔡依婷 (marketing specialist): young budget rental desk
	"zhiwei": "yuqing",    # 林志偉 (diner owner): kitchen and food prep counter
	"peishan": "ziyuan",   # 何佩珊 (hospital nurse): hospital duty desk
	"chengen": "boting",   # 李承恩 (senior tech engineer): tech multi-monitor desk
	"jiaming": "wanting",  # 許家銘 (design firm partner): creative design studio
	"guohua": "zhiming",   # 楊國華 (taxi driver): taxi driver seat
	"yijun": "shufen",     # 陳怡君 (MNC sales manager): executive office and city view
	"yixiang": "boting",   # 高奕翔 (fitness coach): modern professional fitness space
}

## Find client scene or illustration path: prioritize dedicated illustration; fallback to thematically matched scene if none
static func client_scene_path(client_or_id) -> String:
	var id := ""
	var scene_name := ""
	if client_or_id is Dictionary:
		scene_name = str(client_or_id.get("scene", ""))
		id = str(client_or_id.get("id", ""))
		if id == "" or id == "null":
			id = str(client_or_id.get("portrait", ""))
		if scene_name == "" or scene_name == "null":
			scene_name = str(client_or_id.get("portrait", ""))
		if scene_name == "" or scene_name == "null":
			scene_name = id
	elif client_or_id is String:
		id = client_or_id
		scene_name = id

	# 1. First try dedicated name (or specified scene name)
	if scene_name != "" and scene_name != "null":
		for ext in ["webp", "png", "jpg"]:
			var p := "res://assets/clients/%s.%s" % [scene_name, ext]
			if ResourceLoader.exists(p):
				return p

	# 2. Second try searching by id
	if id != "" and id != "null" and id != scene_name:
		for ext in ["webp", "png", "jpg"]:
			var p := "res://assets/clients/%s.%s" % [id, ext]
			if ResourceLoader.exists(p):
				return p

	# 3. If no standalone illustration, fall back to style-matched scene based on occupation context
	var fb: String = str(FALLBACK_SCENES.get(id, ""))
	if fb == "" and scene_name != "":
		fb = str(FALLBACK_SCENES.get(scene_name, ""))
	if fb != "":
		for ext in ["webp", "png", "jpg"]:
			var p := "res://assets/clients/%s.%s" % [fb, ext]
			if ResourceLoader.exists(p):
				return p

	return ""


const CIRCLE_SHADER := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.47, 0.5, d);
	COLOR = c;
}
"""
static var _circle_mat: ShaderMaterial = null

## Circular avatar: crops image to circle if present, otherwise displays first character of name
static func avatar(tex: Texture2D, name_text: String, size := 40) -> Control:
	if tex != null:
		if _circle_mat == null:
			var sh := Shader.new()
			sh.code = CIRCLE_SHADER
			_circle_mat = ShaderMaterial.new()
			_circle_mat.shader = sh
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.custom_minimum_size = Vector2(size, size)
		tr.material = _circle_mat
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		return tr
	var av := panel(ACCENT, int(size / 2.0), 0)
	av.custom_minimum_size = Vector2(size, size)
	var l := label(name_text.substr(0, 1), int(size * 0.45), Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av.add_child(l)
	return av


static func portrait(client: Dictionary, size := 96) -> Control:
	var path := client_scene_path(client)
	if path != "":
		var clip_box := PanelContainer.new()
		clip_box.clip_contents = true
		clip_box.custom_minimum_size = Vector2(size * 1.35, size)
		clip_box.add_theme_stylebox_override("panel", box(Color("#10232e"), 10, Color("#1e475b"), 2))
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip_box.add_child(tr)
		# In horizontal layouts default stretches to full row height (longer bubble = longer avatar): fixed size, top-aligned
		clip_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		clip_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		return clip_box
	# Clients without illustrations: fallback to surname avatar
	var p := panel(Color.from_hsv(fmod(str(client.get("name", "?")).hash() / 1000.0, 1.0), 0.45, 0.55), int(size / 2.0), 0)
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := label(str(client.get("name", "?")).substr(0, 1), int(size * 0.45), Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Grade and result stamp (with slight tilt and impact animation)
static func stamp(text: String, col := GOLD, font_size := 22) -> Control:
	var p := panel(Color(0, 0, 0, 0), 8, 4)
	p.add_theme_stylebox_override("panel", box(Color(col.r, col.g, col.b, 0.15), 10, col, 8, false))
	p.pivot_offset = Vector2(50, 20)
	p.rotation = -0.08
	var l := label(text, font_size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.scale = Vector2(1.8, 1.8)
	var tw := p.create_tween()
	tw.tween_property(p, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return p


## S-grade and deal-signing celebration confetti particles (code-drawn dynamic fall, finishes <= 1.3s without freezing game)
static func spawn_confetti(parent: Control) -> void:
	if not parent or not parent.is_inside_tree():
		return
	# Confetti is in a top_level regular Control: if added directly to a Container (e.g. PanelContainer), it expands to full panel size
	var layer := Control.new()
	layer.top_level = true
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.clip_contents = true
	parent.add_child(layer)
	layer.global_position = parent.global_position
	layer.size = parent.size
	var colors: Array = [Color("#f2c14e"), Color("#3ddc97"), Color("#8ecae6"), Color("#ff6bb5"), Color("#ffffff")]
	var longest: float = 0.0
	for i: int in range(24):
		var c := ColorRect.new()
		c.color = colors[i % colors.size()]
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(randf_range(6.0, 12.0), randf_range(8.0, 16.0))
		c.position = Vector2(randf_range(layer.size.x * 0.1, layer.size.x * 0.9), randf_range(-40.0, -10.0))
		c.rotation = randf_range(-PI, PI)
		layer.add_child(c)
		var target_y: float = layer.size.y + randf_range(20.0, 80.0)
		var target_x: float = c.position.x + randf_range(-60.0, 60.0)
		var dur: float = randf_range(0.8, 1.3)
		longest = maxf(longest, dur)
		var tw := c.create_tween().set_parallel(true)
		tw.tween_property(c, "position", Vector2(target_x, target_y), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(c, "rotation", c.rotation + randf_range(-3.0, 3.0), dur)
		tw.tween_property(c, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65)
	layer.get_tree().create_timer(longest + 0.1).timeout.connect(layer.queue_free)


## Text input row: LineEdit + submit (height at least 44 for comfortable touch targeting)
static func text_input(placeholder: String, on_submit: Callable, max_len := 120) -> HBoxContainer:
	var h := hbox(8)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.max_length = max_len
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.custom_minimum_size = Vector2(0, 46)
	h.add_child(le)
	var submit := func():
		var t := le.text.strip_edges()
		if t != "":
			on_submit.call(t)
			le.text = ""
	le.text_submitted.connect(func(_t): submit.call())
	h.add_child(button("送出", submit))
	return h


## Letter from ten years later card (letter paper style: off-white base, dark text, handwritten-feel margins)
static func letter_card(letter: Dictionary, client_name: String) -> PanelContainer:
	var outcome: String = str(letter.get("outcome", "mixed"))
	var is_phone := is_phone_portrait()

	# Tone: thanks warm gold, regret grayish-blue, complaint red-grey paper, mixed neutral
	var accent_col: Color
	var bg_col: Color
	var tag_text: String
	if outcome == "complaint":
		accent_col = Color("#c94a4a")
		bg_col = Color("#f7f0f0")
		tag_text = "⚠ 客訴副本"
	elif outcome == "thanks":
		accent_col = Color("#c48b23")
		bg_col = Color("#fbf8ee")
		tag_text = "★ 暖心感謝"
	elif outcome == "regret":
		accent_col = Color("#4c6d8c")
		bg_col = Color("#f2f5f8")
		tag_text = "▲ 遺憾與感慨"
	else:
		accent_col = Color("#6d6961")
		bg_col = Color("#f5f2eb")
		tag_text = "● 百感交集"

	var p := PanelContainer.new()
	var pad := 14 if is_phone else 20
	p.add_theme_stylebox_override("panel", box(bg_col, 12, accent_col, pad, true))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := vbox(8 if is_phone else 10)
	p.add_child(v)

	# Header row
	var head := hbox(8)
	var title_text: String = ("十年後，%s 寄來的申訴副本" % client_name) if outcome == "complaint" else ("十年後，%s 寄來的信" % client_name)
	var title_lbl := label(title_text, 18, Color("#8c2323") if outcome == "complaint" else Color("#2b2219"), true)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_lbl)

	var tag_p := panel(Color(accent_col.r, accent_col.g, accent_col.b, 0.15), 6, 4)
	tag_p.add_theme_stylebox_override("panel", box(Color(accent_col.r, accent_col.g, accent_col.b, 0.15), 6, accent_col, 4, false))
	tag_p.add_child(label(tag_text, 12, accent_col))
	head.add_child(tag_p)
	v.add_child(head)

	# Event, gap and quote summary
	var ev_text: String = str(letter.get("event", ""))
	var gap_val: int = int(letter.get("gap", 0))
	var quote_str: String = str(letter.get("quote", ""))
	if ev_text != "" or letter.has("gap") or gap_val > 0 or quote_str != "":
		var summary_box := panel(Color(accent_col.r, accent_col.g, accent_col.b, 0.08), 8, 8)
		summary_box.add_theme_stylebox_override("panel", box(Color(accent_col.r, accent_col.g, accent_col.b, 0.08), 8, Color(accent_col.r, accent_col.g, accent_col.b, 0.3), 6, false))
		var sv := vbox(3)
		if quote_str != "":
			sv.add_child(label("※ 你當年說：『%s』" % quote_str, 13, Color("#8c2323") if outcome == "complaint" else Color("#3a3028"), true))
		if ev_text != "":
			sv.add_child(label("※ 經歷事件：%s" % ev_text, 13, Color("#3a3028"), true))
		if gap_val > 0:
			sv.add_child(label("※ 財務缺口：%d 萬元（方案未能完全承接）" % gap_val, 13, Color("#992b2b"), true))
		elif letter.has("gap") or ev_text != "":
			sv.add_child(label("※ 財務缺口：0 萬元（防護穩健，無缺口）", 13, Color("#26734d"), true))
		summary_box.add_child(sv)
		v.add_child(summary_box)

	# Letter body
	var content: String = str(letter.get("content", ""))
	if content != "":
		var body_lbl := label(content, 15, Color("#2c241d"), true)
		v.add_child(body_lbl)

	# Signature
	var sign_row := hbox(8)
	sign_row.add_child(spacer())
	var sign_lbl := label("—— %s 敬上" % client_name, 13, Color("#5e564c"))
	sign_row.add_child(sign_lbl)
	v.add_child(sign_row)

	return p

