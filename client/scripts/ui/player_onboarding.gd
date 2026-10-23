extends Control
## 新人顧問報到 (scenes/player_onboarding.tscn): between the cover and the secretary choice.
## Six player looks (none of them Aly, Kevin, a sparring advisor or a client), the advisor name
## (2–10 characters), a live preview, the starting level and the board token colour.
## 完成報到 validates, saves PlayerProfile, fades to deep green in 0.3 s and hands over (`done`).
## mode "flow": back → cover, done → secretary choice. mode "edit" (from the training-mode page's
## player pill): back / done → the training-mode page. Unconfirmed choices survive a back trip.
## No secretary is chosen yet on this page, so neither Aly nor Kevin appears here.

signal done
signal back

const BackButton := preload("res://scripts/ui/back_button.gd")
const AudioSettings := preload("res://scripts/ui/audio_settings.gd")
const MissionBrief := preload("res://scripts/ui/mission_brief.gd")
const BACKGROUND := preload("res://assets/unified/background.webp")
const LOGO := preload("res://assets/startup/title.png")
const LOGO_CROP := Rect2(8, 10, 1944, 760)

var main: Node
var mode := "flow"
var _avatar_id := "player_01"
var _token := "green"
var _cards: Dictionary = {}
var _tokens: Dictionary = {}
var _name: LineEdit
var _error: Label
var _preview: TextureRect
var _level: Label
var _confirm: Button
var _back: Button
var _fade: ColorRect
var _leaving := false
var _top: PanelContainer
var _title: HBoxContainer
var _body: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var d: Dictionary = PlayerProfile.draft
	if not d.is_empty():
		_avatar_id = str(d.get("avatar", _avatar_id))
		_token = str(d.get("token", _token))
	elif PlayerProfile.player_profile_created:
		_avatar_id = PlayerProfile.player_avatar_id
		_token = PlayerProfile.player_token_color
	_build()
	var start_name := str(d.get("name", PlayerProfile.player_name if PlayerProfile.player_profile_created else ""))
	if start_name == "" and Net.is_logged_in():
		start_name = str(Net.get_user().get("name", "")).strip_edges().substr(0, PlayerProfile.NAME_MAX)
	_name.text = start_name
	_select_avatar(_avatar_id, false)
	_select_token(_token, false)
	_intro()


## The confirm button sits below a scrolling body (phones and portrait screens)
func _pinned() -> bool:
	return _portrait() or _phone()


func _phone() -> bool:
	return UI.is_phone()


func _portrait() -> bool:
	return UI.is_portrait()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(QuestUI.BG, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var root := QuestUI.vbox(0)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_top = _top_bar()
	root.add_child(_top)
	var m := MarginContainer.new()
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pad := 10 if _phone() else 28
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, pad)
	m.add_theme_constant_override("margin_top", 8 if _phone() else 14)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var v := QuestUI.vbox(8 if _phone() else 12)
	m.add_child(v)
	# Back + title row (the title stays centred; the back button sits at the left)
	var head := Control.new()
	head.custom_minimum_size = Vector2(0, 104 if not (_phone() or _portrait()) else (124 if _portrait() else 62))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_back = BackButton.new("返回培訓方式" if mode == "edit" else "返回遊戲封面")
	_back.pressed.connect(_on_back)
	head.add_child(_back)
	var tv := QuestUI.vbox(4)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(tv)
	_title = QuestUI.hbox(0)
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	var big := 46 if not (_phone() or _portrait()) else 30
	if mode == "edit":
		_title.add_child(QuestUI.title("顧問檔案", big, QuestUI.TEXT))
		_title.add_child(QuestUI.title("設定", big, QuestUI.GOLD))
	else:
		_title.add_child(QuestUI.title("新人顧問", big, QuestUI.TEXT))
		_title.add_child(QuestUI.title("報到", big, QuestUI.GOLD))
	tv.add_child(_title)
	var orn := Ornament.new()
	orn.custom_minimum_size = Vector2(0, 12)
	tv.add_child(orn)
	var sub := QuestUI.label("建立你的顧問檔案，系統將記錄培訓成長與決策表現。", 19 if not _phone() else 15, Color(QuestUI.TEXT, 0.9), true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sub)
	var base_h := head.custom_minimum_size.y
	# The subtitle wraps, so the title block's height follows its width: place it again whenever
	# that changes and let the row grow to fit (never over the panels below)
	var place := func():
		var bw := _back.get_combined_minimum_size()
		_back.size = bw
		var need := 0.0
		if _portrait():
			_back.position = Vector2(0, 0)
			tv.position = Vector2(0, bw.y + 6)
			tv.size = Vector2(head.size.x, maxf(0.0, head.size.y - bw.y - 6))
			need = bw.y + 6 + tv.get_combined_minimum_size().y
		else:
			_back.position = Vector2(0, 0 if _phone() else 2)
			var side_w := bw.x + 12
			tv.position = Vector2(side_w, 0)
			tv.size = Vector2(maxf(10.0, head.size.x - side_w * 2), head.size.y)
			need = tv.get_combined_minimum_size().y
		head.custom_minimum_size.y = maxf(base_h, need)
	head.resized.connect(place)
	tv.minimum_size_changed.connect(place, CONNECT_DEFERRED)
	# Panels: looks on the left, the advisor card on the right
	var left := _looks_panel()
	var right := _profile_panel()
	var content: Control
	if _portrait():
		var sv := QuestUI.vbox(12)
		sv.add_child(left)
		sv.add_child(right)
		content = sv
	else:
		var row := QuestUI.hbox(14 if _phone() else 24)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.45
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.size_flags_stretch_ratio = 1.0
		row.add_child(left)
		row.add_child(right)
		content = row
	# Phones: the panels scroll and 完成報到 stays pinned below them
	if _pinned():
		var sc := QuestUI.scroll(content)
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(sc)
		var foot := QuestUI.vbox(4)
		foot.add_child(_confirm)
		v.add_child(foot)
	else:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(content)
	_body = v
	_fade = ColorRect.new()
	_fade.name = "LeaveFade"
	_fade.color = QuestUI.BG
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	add_child(_fade)


func _top_bar() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(QuestUI.BG, 0.9)
	sb.border_width_bottom = 1
	sb.border_color = Color(QuestUI.GOLD, 0.28)
	sb.content_margin_left = 14 if _phone() else 32
	sb.content_margin_right = 14 if _phone() else 32
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", sb)
	var h := QuestUI.hbox(10)
	p.add_child(h)
	var logo := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = LOGO
	at.region = LOGO_CROP
	logo.texture = at
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var lh := 40.0 if _phone() else 52.0
	logo.custom_minimum_size = Vector2(lh * LOGO_CROP.size.x / LOGO_CROP.size.y, lh)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(logo)
	h.add_child(QuestUI.spacer())
	var rec := _link("doc", "培訓紀錄", func():
		_keep_draft()
		if main and main.has_method("show_records"):
			main.show_records()
	)
	rec.name = "RecordsLink"
	h.add_child(rec)
	var howto := _link("question", "玩法說明", _open_brief)
	howto.name = "HowtoLink"
	h.add_child(howto)
	var st := _link("gear", "設定", _open_settings)
	st.name = "SettingsLink"
	h.add_child(st)
	return p


func _link(icon_kind: String, t: String, cb: Callable) -> Button:
	var b: Button = QuestUI.button("" if _phone() else t, cb, "quiet", icon_kind)
	b.tooltip_text = t
	b.custom_minimum_size = Vector2(48 if _phone() else 0, 44)
	for st in ["normal", "disabled"]:
		var s := (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate() as StyleBoxFlat
		s.bg_color = Color(0, 0, 0, 0)
		s.border_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", QuestUI.TEXT)
	return b


# --- Looks ---------------------------------------------------------------------------------------

func _looks_panel() -> Control:
	var p := QuestUI.card(null, 0.9)
	p.name = "LooksPanel"
	var grid := GridContainer.new()
	grid.name = "AvatarGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10 if _phone() else 16)
	grid.add_theme_constant_override("v_separation", 10 if _phone() else 16)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(grid)
	for a in PlayerProfile.AVATARS:
		var card := AvatarCard.new(a, PlayerProfile.texture_for(str(a.path)), _phone() or _portrait())
		card.pressed.connect(func(): _select_avatar(str(a.id), true))
		grid.add_child(card)
		_cards[str(a.id)] = card
	return p


func _select_avatar(id: String, user := false) -> void:
	if PlayerProfile.avatar(id).is_empty():
		return
	var changed := id != _avatar_id
	_avatar_id = id
	for k in _cards:
		(_cards[k] as AvatarCard).set_selected(k == id)
	var tex := PlayerProfile.texture_for(str(PlayerProfile.avatar(id).path))
	if _preview:
		if user and changed and not UI.is_animation_disabled():
			_preview.modulate.a = 0.0
			_preview.texture = tex
			var tw := _preview.create_tween()
			tw.tween_property(_preview, "modulate:a", 1.0, 0.2)
		else:
			_preview.texture = tex
	if user:
		AudioManager.play("card_flip" if changed else "ui_click")
		_keep_draft()


# --- Profile card --------------------------------------------------------------------------------

func _profile_panel() -> Control:
	var p := QuestUI.card(null, 0.92)
	p.name = "ProfilePanel"
	var v := QuestUI.vbox(10 if _phone() else 14)
	p.add_child(v)
	v.add_child(_section("玩家顧問", 26 if not _phone() else 19))
	var h := QuestUI.hbox(16 if not _phone() else 10)
	v.add_child(h)
	_preview = TextureRect.new()
	_preview.name = "AvatarPreview"
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var ps := 116.0 if _phone() else 196.0
	_preview.custom_minimum_size = Vector2(ps, ps)
	_preview.material = UI.get_rounded_material(0.06)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := PanelContainer.new()
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.set_border_width_all(1)
	fs.border_color = Color(QuestUI.GOLD, 0.7)
	fs.set_corner_radius_all(10)
	fs.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", fs)
	frame.add_child(_preview)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(frame)
	var fields := QuestUI.vbox(6)
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(fields)
	fields.add_child(QuestUI.label("顧問名稱", 16, QuestUI.TEXT))
	_name = LineEdit.new()
	_name.name = "AdvisorName"
	_name.placeholder_text = "輸入 2～10 個字"
	_name.max_length = PlayerProfile.NAME_MAX
	_name.clear_button_enabled = true
	_name.custom_minimum_size = Vector2(0, 48)
	_name.add_theme_font_size_override("font_size", 20 if not _phone() else 16)
	_name.add_theme_stylebox_override("normal", _field_box(false))
	_name.add_theme_stylebox_override("focus", _field_box(true))
	_name.text_changed.connect(func(_t: String):
		if _error.visible:
			_show_error(PlayerProfile.name_error(_name.text))
		_keep_draft()
	)
	_name.text_submitted.connect(func(_t: String): _on_confirm())
	fields.add_child(_name)
	_error = QuestUI.label("", 13, QuestUI.RED.lightened(0.2))
	_error.name = "NameError"
	_error.visible = false
	fields.add_child(_error)
	fields.add_child(QuestUI.label("初始等級" if not PlayerProfile.player_profile_created else "目前等級", 16, QuestUI.TEXT))
	var lvl := PanelContainer.new()
	lvl.add_theme_stylebox_override("panel", _field_box(false))
	_level = QuestUI.label(PlayerProfile.level_text() if PlayerProfile.player_profile_created else "Lv.1 新人顧問", 17 if not _phone() else 14, QuestUI.TEXT)
	_level.name = "StartLevel"
	lvl.add_child(_level)
	fields.add_child(lvl)
	v.add_child(QuestUI.divider(0.14))
	v.add_child(_section("選擇棋子顏色", 18 if not _phone() else 15))
	var colors := QuestUI.hbox(18 if not _phone() else 12)
	colors.alignment = BoxContainer.ALIGNMENT_CENTER
	for key in PlayerProfile.TOKEN_ORDER:
		var c: Dictionary = PlayerProfile.TOKEN_COLORS[key]
		var b := TokenButton.new(str(key), c.color, str(c.label))
		b.pressed.connect(func(): _select_token(str(key), true))
		colors.add_child(b)
		_tokens[str(key)] = b
	v.add_child(colors)
	var info := QuestUI.hbox(8)
	info.add_child(QuestUI.icon("info", 18.0, QuestUI.MUTED))
	info.add_child(QuestUI.label("外觀不影響培訓評分", 15, QuestUI.MUTED))
	v.add_child(info)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	_confirm = QuestUI.button("儲存顧問檔案，返回培訓方式" if mode == "edit" else "完成報到，選擇培訓秘書", _on_confirm, "primary", "next")
	_confirm.name = "ConfirmOnboarding"
	if not _pinned():
		v.add_child(_confirm)
	return p


func _section(t: String, fs: int) -> HBoxContainer:
	var h := QuestUI.hbox(10)
	var bar := ColorRect.new()
	bar.color = QuestUI.GREEN
	bar.custom_minimum_size = Vector2(3, fs)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	h.add_child(QuestUI.title(t, fs))
	return h


func _field_box(focus: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(QuestUI.INK, 0.7)
	s.set_corner_radius_all(10)
	s.set_border_width_all(2 if focus else 1)
	s.border_color = QuestUI.GREEN if focus else Color(1, 1, 1, 0.16)
	s.content_margin_left = 16
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _select_token(key: String, user := false) -> void:
	if not PlayerProfile.TOKEN_COLORS.has(key):
		return
	_token = key
	for k in _tokens:
		(_tokens[k] as TokenButton).set_selected(k == key)
	if user:
		AudioManager.play("ui_click")
		_keep_draft()


func _show_error(msg: String) -> void:
	_error.text = msg
	_error.visible = msg != ""
	_name.add_theme_stylebox_override("normal", _field_box(false) if msg == "" else _error_box())


func _error_box() -> StyleBoxFlat:
	var s := _field_box(false)
	s.border_color = QuestUI.RED
	s.set_border_width_all(2)
	return s


func _keep_draft() -> void:
	PlayerProfile.draft = {"name": _name.text if _name else "", "avatar": _avatar_id, "token": _token}


# --- Leaving -------------------------------------------------------------------------------------

func _on_confirm() -> void:
	if _leaving:
		return
	var err := PlayerProfile.name_error(_name.text)
	if err != "":
		_show_error(err)
		QuestUI.shake(_name)
		AudioManager.play("trust_down")
		_name.grab_focus()
		return
	_show_error("")
	if not PlayerProfile.create(_name.text, _avatar_id, _token):
		_show_error("資料無法儲存，請再試一次")
		return
	_leaving = true
	_confirm.call("set_loading", true, "建立顧問檔案")
	AudioManager.play("confirm_soft")
	await _fade_out()
	done.emit()


func _on_back() -> void:
	if _leaving:
		return
	_keep_draft()
	_leaving = true
	await _fade_out()
	back.emit()


## 0.3 s deep-green fade before the next screen (the main veil then takes over, nothing old shows)
func _fade_out() -> void:
	_fade.visible = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	if UI.is_animation_disabled():
		_fade.modulate.a = 1.0
		return
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _open_brief() -> void:
	var brief: Control = MissionBrief.new()
	brief.z_index = 90
	brief.closed.connect(func(): brief.queue_free())
	brief.details_requested.connect(func(): brief.queue_free())
	add_child(brief)


func _open_settings() -> void:
	var dim := ColorRect.new()
	dim.name = "SettingsDialog"
	dim.color = Color(QuestUI.INK, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var p := QuestUI.card(null, 1.0, Color(QuestUI.GOLD, 0.5))
	p.custom_minimum_size = Vector2(minf(420.0, size.x - 32.0), 0)
	center.add_child(p)
	var v := QuestUI.vbox(12)
	p.add_child(v)
	var head := QuestUI.header("gear", "設定")
	head.add_child(QuestUI.button("關閉", func(): dim.queue_free(), "quiet", "close"))
	v.add_child(head)
	v.add_child(AudioSettings.new())
	var motion := CheckButton.new()
	motion.text = "減少動態效果"
	motion.button_pressed = UI.reduce_motion
	motion.toggled.connect(func(on: bool): UI.set_reduce_motion(on))
	v.add_child(motion)


func _intro() -> void:
	if UI.is_animation_disabled() or _body == null:
		return
	_body.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_body, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## One look: portrait, 「• 形象 0N •」 band; hover lifts 4px, press 0.97, selected gold frame + check
class AvatarCard extends Button:
	var info: Dictionary
	var visual: Control
	var _frame: Panel
	var _check: Control
	var _sel := false
	var _tw: Tween

	func _init(a: Dictionary, tex: Texture2D, small: bool) -> void:
		info = a
		name = "Avatar_" + str(a.id)
		toggle_mode = false
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(96, 120) if small else Vector2(150, 170)
		tooltip_text = str(a.label)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var e := StyleBoxEmpty.new()
			add_theme_stylebox_override(st, e)
		var focus_box := StyleBoxFlat.new()
		focus_box.draw_center = false
		focus_box.set_border_width_all(2)
		focus_box.border_color = Color("#C6A15B", 0.8)
		focus_box.set_corner_radius_all(16)
		add_theme_stylebox_override("focus", focus_box)
		visual = Control.new()
		visual.name = "Visual"
		visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(visual)
		var pic := TextureRect.new()
		pic.name = "Portrait"
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.material = UI.get_rounded_material(0.08)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(pic)
		var band := PanelContainer.new()
		band.name = "Band"
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color("#062F2A", 0.88)
		bs.corner_radius_bottom_left = 12
		bs.corner_radius_bottom_right = 12
		bs.border_width_top = 1
		bs.border_color = Color("#C6A15B", 0.55)
		band.add_theme_stylebox_override("panel", bs)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := QuestUI.label("•  %s  •" % str(a.label), 15 if small else 20, Color("#F3F0E7"))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		band.add_child(bl)
		visual.add_child(band)
		_frame = Panel.new()
		_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		visual.add_child(_frame)
		_check = CheckBadge.new()
		_check.visible = false
		visual.add_child(_check)
		resized.connect(_place)
		mouse_entered.connect(_hover.bind(true))
		mouse_exited.connect(_hover.bind(false))
		button_down.connect(_press.bind(true))
		button_up.connect(_press.bind(false))
		_restyle(false)

	func _place() -> void:
		visual.size = size
		visual.pivot_offset = size * 0.5
		var pic: Control = visual.get_node("Portrait")
		var band: Control = visual.get_node("Band")
		pic.position = Vector2.ZERO
		pic.size = size
		var bh := maxf(30.0, size.y * 0.16)
		band.position = Vector2(0, size.y - bh)
		band.size = Vector2(size.x, bh)
		_frame.position = Vector2.ZERO
		_frame.size = size
		var cs := clampf(size.x * 0.16, 24.0, 40.0)
		_check.size = Vector2(cs, cs)
		_check.position = Vector2(size.x - cs - 10, 10)

	func set_selected(on: bool) -> void:
		_sel = on
		_check.visible = on
		_restyle(false)

	func _restyle(hover: bool) -> void:
		var s := StyleBoxFlat.new()
		s.draw_center = false
		s.set_corner_radius_all(14)
		s.set_border_width_all(3 if _sel else 1)
		s.border_color = Color("#C6A15B") if _sel else (Color("#C6A15B", 0.7) if hover else Color(1, 1, 1, 0.16))
		_frame.add_theme_stylebox_override("panel", s)

	func _hover(on: bool) -> void:
		_restyle(on)
		if on:
			AudioManager.play("ui_hover")
		if UI.is_animation_disabled():
			return
		if _tw and _tw.is_valid():
			_tw.kill()
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_property(visual, "position:y", -4.0 if on else 0.0, 0.16)

	func _press(down: bool) -> void:
		if UI.is_animation_disabled():
			return
		var tw := create_tween()
		tw.tween_property(visual, "scale", Vector2.ONE * (0.97 if down else 1.0), 0.07 if down else 0.12)


class CheckBadge extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("#C6A15B"))
		draw_arc(c, r - 1, 0, TAU, 24, Color("#F3F0E7", 0.8), 1.5, true)
		draw_polyline(PackedVector2Array([c + Vector2(-r * 0.42, 0), c + Vector2(-r * 0.1, r * 0.32), c + Vector2(r * 0.45, -r * 0.32)]), Color("#062F2A"), 3.0, true)


## Round colour swatch: green ring and a check when chosen, gold ring on hover
class TokenButton extends Button:
	var key := ""
	var color := Color.WHITE
	var _sel := false
	var _hov := false

	func _init(k: String, c: Color, label_text: String) -> void:
		key = k
		color = c
		name = "Token_" + k
		tooltip_text = label_text + "色棋子"
		custom_minimum_size = Vector2(52, 52)
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))
		button_down.connect(_on_press.bind(true))
		button_up.connect(_on_press.bind(false))

	func _on_hover(on: bool) -> void:
		_hov = on
		queue_redraw()
		if on:
			AudioManager.play("ui_hover")

	func _on_press(down: bool) -> void:
		if UI.is_animation_disabled():
			return
		pivot_offset = size * 0.5
		scale = Vector2.ONE * (0.94 if down else 1.0)

	func set_selected(on: bool) -> void:
		_sel = on
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4
		if _sel:
			draw_arc(c, r + 2, 0, TAU, 40, Color("#00A86B"), 3.0, true)
		elif _hov:
			draw_arc(c, r + 2, 0, TAU, 40, Color("#C6A15B"), 2.0, true)
		draw_circle(c, r - 3, color)
		draw_arc(c, r - 3, 0, TAU, 40, Color(1, 1, 1, 0.35), 1.0, true)
		if _sel:
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.35, 0), c + Vector2(-r * 0.08, r * 0.28), c + Vector2(r * 0.38, -r * 0.28)]), Color("#F3F0E7"), 3.0, true)


class Ornament extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var g := Color("#C6A15B", 0.85)
		var half := minf(size.x * 0.5, 100.0)
		draw_line(Vector2(c.x - half, c.y), Vector2(c.x - 8, c.y), g, 1.0, true)
		draw_line(Vector2(c.x + 8, c.y), Vector2(c.x + half, c.y), g, 1.0, true)
		var d := 4.0
		draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), g, 1.2, true)
