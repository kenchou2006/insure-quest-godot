class_name UI
## 介面工具：配色、主題與常用元件的建構函式。所有畫面都以程式碼建構，方便團隊修改與審閱。

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
	"start": "結", "client": "客", "life": "事", "market": "市", "training": "訓", "referral": "介", "audit": "稽", "seminar": "研",
}

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


## 依版型取值：手機用第一個值，其餘用第二個值
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
	# VScrollBar 自訂樣式（寬度 12px，高對比度防隱形，含懸停與按下狀態）
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


static func label(text: String, size := 17, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
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
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r


static func button(text: String, cb: Callable, size := 17, color := ACCENT) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if color != ACCENT:
		b.add_theme_stylebox_override("normal", box(color, 10, Color(0, 0, 0, 0), 12))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.12), 10, Color(0, 0, 0, 0), 12))
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 10, Color(0, 0, 0, 0), 12))
	b.pressed.connect(func():
		Sound.play("click", b)
		cb.call()
	)
	return b


## 多行文字選項按鈕（長句子會自動換行）
static func option_button(text: String, cb: Callable, color := PANEL_2) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_stylebox_override("normal", box(color, 10, Color("#2d5a6e"), 12))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1), 10, ACCENT_2, 12))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.1), 10, ACCENT_2, 12))
	b.add_theme_stylebox_override("disabled", box(color.darkened(0.25), 10, Color(0, 0, 0, 0), 12))
	b.pressed.connect(func():
		Sound.play("click", b)
		cb.call()
	)
	return b


## 彈出動畫效果
static func pop_in(node: CanvasItem, duration := 0.25) -> void:
	node.modulate.a = 0.0
	node.scale = Vector2(0.95, 0.95)
	node.pivot_offset = node.size * 0.5
	var tw: Tween = node.create_tween().set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration)
	tw.tween_property(node, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 淡入向上飄動動畫
static func fade_in(node: CanvasItem, duration := 0.25, offset_y := 16.0) -> void:
	node.modulate.a = 0.0
	# Container 的子節點位置由容器決定；若補間 position 會寫回過期座標，造成與上方元素重疊
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
	# 讓滑鼠滾輪穿過卡片，交給外層 ScrollContainer 捲動
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
	var l := label(METRIC_NAMES.get(key, key), 13 if is_phone_portrait() else 14, MUTED)
	l.custom_minimum_size = Vector2(62 if is_phone_portrait() else 72, 0)
	h.add_child(l)
	var c := GOOD if value >= 75 else (OK if value >= 50 else BAD)
	var b := bar(value, c, 70 if is_phone_portrait() else 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	h.add_child(label(str(int(value)), 13 if is_phone_portrait() else 14, TEXT))
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


## 讓捲動區內的非輸入元件不吃滾輪（STOP 會阻止事件傳到外層 ScrollContainer）
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


static func portrait(client: Dictionary, size := 96) -> Control:
	var id: String = str(client.get("portrait", ""))
	if id == "" or id == "null":
		id = str(client.get("id", ""))
	if id != "" and id != "null":
		for ext: String in ["webp", "png", "jpg"]:
			var path := "res://assets/clients/%s.%s" % [id, ext]
			if ResourceLoader.exists(path):
				var tr := TextureRect.new()
				tr.texture = load(path)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				tr.custom_minimum_size = Vector2(size * 1.5, size)
				return tr
	# 沒有插圖的客戶：以姓氏頭像代替
	var p := panel(Color.from_hsv(fmod(str(client.get("name", "?")).hash() / 1000.0, 1.0), 0.45, 0.55), int(size / 2.0), 0)
	p.custom_minimum_size = Vector2(size, size)
	var l := label(str(client.get("name", "?")).substr(0, 1), int(size * 0.45), Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## 評級與結果印章（含輕微傾斜與撞擊動畫）
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


## S 級與簽約慶祝彩帶碎屑粒子（程式碼繪製與動態下落，<= 1.3 秒完成且不卡死遊戲）
static func spawn_confetti(parent: Control) -> void:
	if not parent or not parent.is_inside_tree():
		return
	# 碎屑放在 top_level 的普通 Control 裡：若直接加進 Container（如 PanelContainer），會被撐成整個面板大
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


## 文字輸入列：LineEdit＋送出（高度至少 44 方便觸控點選）
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
