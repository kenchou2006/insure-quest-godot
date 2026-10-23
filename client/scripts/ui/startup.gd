extends Control
## Layered Life Advisor Bureau cover, shown after loading finishes.
## The background always fills the screen; advisors slide in from the sides, the title drops in,
## then the entry button appears. Clicking or pressing a key during the intro skips to the end.

signal entered

const DemoCodeDialog := preload("res://scripts/ui/demo_code_dialog.gd")
const BACKGROUND := preload("res://assets/startup/loading.png")
const TITLE := preload("res://assets/startup/title.png")
const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")

## Horizontal span (in cover-image units) that must stay on screen: title and button.
const SAFE_SPAN := 0.48

var _backdrop: TextureRect
var _stage: Control
var _female: TextureRect
var _male: TextureRect
var _title: TextureRect
var _enter: Button
var _button_material: ShaderMaterial
var _account_area: PanelContainer
var account_area: PanelContainer:
	get:
		return _account_area
var _buttons_ready: bool = false
var _intro: Tween

func _ready() -> void:
	var base := ColorRect.new()
	base.color = Color("0d231e")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	# Full-bleed background: covers the whole screen at any aspect ratio (no side bars).
	_backdrop = TextureRect.new()
	_backdrop.texture = BACKGROUND
	_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	clip_contents = true
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_female = _add_art(FEMALE, Vector2(-0.035, 0.055), Vector2(0.36, 0.97))
	_male = _add_art(MALE, Vector2(0.675, 0.055), Vector2(0.36, 0.97))
	_title = _add_art(TITLE, Vector2(0.275, 0.30), Vector2(0.45, 0.30))
	_enter = Button.new()
	_enter.text = "進 入 顧 問 培 訓"
	_enter.pressed.connect(_on_entered)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		_enter.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		_enter.add_theme_color_override(state, Color("fffbea"))
	_enter.add_theme_color_override("font_shadow_color", Color("003c30"))
	_enter.add_theme_constant_override("shadow_offset_y", 2)
	var gloss := TextureRect.new()
	var fill := GradientTexture2D.new()
	gloss.texture = fill
	gloss.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gloss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gloss.show_behind_parent = true
	_button_material = ShaderMaterial.new()
	_button_material.shader = preload("res://assets/startup/entry_button.gdshader")
	gloss.material = _button_material
	_enter.add_child(gloss)
	_enter.mouse_entered.connect(func(): _button_material.set_shader_parameter("highlight", 1.0))
	_enter.mouse_exited.connect(func(): _button_material.set_shader_parameter("highlight", 0.0))
	_enter.tooltip_text = "進入顧問培訓（Enter／空白鍵）"
	_enter.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_stage.add_child(_enter)

	_build_account_area()
	if not Net.auth_changed.is_connected(_on_auth_changed):
		Net.auth_changed.connect(_on_auth_changed)
	if Net.has_signal("avatar_loaded") and not Net.avatar_loaded.is_connected(_on_avatar_loaded):
		Net.avatar_loaded.connect(_on_avatar_loaded)
	_refresh_account()

	resized.connect(_layout_cover)
	_layout_cover()
	_play_intro.call_deferred()

func _add_art(texture: Texture2D, origin: Vector2, extent: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.anchor_left = origin.x
	art.anchor_top = origin.y
	art.anchor_right = origin.x + extent.x
	art.anchor_bottom = origin.y + extent.y
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(art)
	return art

func _build_account_area() -> void:
	var bg_col := Color("0d231e")
	bg_col.a = 0.72
	_account_area = UI.panel(bg_col, 10, 8)
	_account_area.name = "AccountArea"
	_account_area.modulate.a = 0.0
	_account_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_account_area)

func _on_auth_changed() -> void:
	if not is_inside_tree():
		return
	_refresh_account()

func _on_avatar_loaded(_tex: Texture2D) -> void:
	if not is_inside_tree():
		return
	_refresh_account()

func refresh_account() -> void:
	_refresh_account()

func _refresh_account() -> void:
	if not is_inside_tree() or _account_area == null:
		return
	UI.clear(_account_area)

	var v := UI.vbox(5)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_account_area.add_child(v)

	var stage_y: float = _stage.size.y if _stage != null and _stage.size.y > 0.0 else (size.y if size.y > 0.0 else 720.0)
	var btn_fs := maxi(13, int(stage_y * 0.021))
	var sub_fs := maxi(13, int(stage_y * 0.019))
	var note_fs := maxi(12, int(stage_y * 0.017))

	if Net.is_logged_in():
		var h := UI.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		var user_name := str(Net.get_user().get("name", Net.player_name)).strip_edges()
		if user_name == "":
			user_name = "顧問"
		if Net.avatar_tex != null:
			var av := UI.avatar(Net.avatar_tex, user_name, btn_fs * 2)
			h.add_child(av)
		var name_lbl := UI.label("已登入：" + user_name, btn_fs, UI.TEXT)
		h.add_child(name_lbl)
		var logout_btn := UI.button("登出", func():
			await Net.logout()
			if is_inside_tree():
				_refresh_account()
		, sub_fs, UI.BAD.darkened(0.4))
		logout_btn.focus_mode = Control.FOCUS_NONE
		h.add_child(logout_btn)
		v.add_child(h)
	else:
		var stage_x: float = _stage.size.x if _stage != null and _stage.size.x > 0.0 else (size.x if size.x > 0.0 else 1280.0)
		var init_content_w := maxf(0.0, stage_x * 0.30 - 16.0)
		var has_config: bool = not Net.auth_config.is_empty()
		var google_enabled: bool = bool(Net.auth_config.get("google", true))
		if google_enabled:
			var google_btn := UI.button("使用 Google 登入", func():
				Net.google_sign_in()
			, btn_fs, UI.ACCENT)
			google_btn.focus_mode = Control.FOCUS_NONE
			google_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(google_btn)
		else:
			var no_google_lbl := UI.label("此伺服器尚未設定 Google 登入", btn_fs, UI.MUTED, true)
			no_google_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			no_google_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
			no_google_lbl.custom_minimum_size.x = init_content_w
			v.add_child(no_google_lbl)

		var sub_row := UI.hbox(8)
		sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
		if has_config and bool(Net.auth_config.get("demo", false)):
			var demo_btn := UI.button("評審體驗碼", func():
				DemoCodeDialog.open(self, func():
					if is_inside_tree():
						_refresh_account()
				)
			, sub_fs, UI.GOLD)
			demo_btn.focus_mode = Control.FOCUS_NONE
			sub_row.add_child(demo_btn)
		if has_config and bool(Net.auth_config.get("dev", false)):
			var dev_btn := UI.button("測試登入", func():
				Net.login_dev()
			, sub_fs, UI.GOLD.darkened(0.3))
			dev_btn.focus_mode = Control.FOCUS_NONE
			sub_row.add_child(dev_btn)
		if sub_row.get_child_count() > 0:
			v.add_child(sub_row)

		var note_lbl := UI.label("登入後培訓紀錄會保存到帳號，並可使用 AI 功能", note_fs, UI.MUTED, true)
		note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		note_lbl.custom_minimum_size.x = init_content_w
		v.add_child(note_lbl)

	for btn: Button in _account_area.find_children("*", "Button", true, false):
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = not _buttons_ready
		btn.mouse_filter = Control.MOUSE_FILTER_STOP if _buttons_ready else Control.MOUSE_FILTER_IGNORE

	_layout_cover()

func _layout_cover() -> void:
	var image_size := BACKGROUND.get_size()
	# Cover the screen like the backdrop, but on narrow (portrait) screens shrink just enough
	# that the title and button stay fully visible; the advisors may then be cropped at the edges.
	var cover := maxf(size.x / image_size.x, size.y / image_size.y)
	var keep_center := size.x / (image_size.x * SAFE_SPAN)
	var scale_factor := minf(cover, keep_center)
	_stage.size = image_size * scale_factor
	_stage.position = (size - _stage.size) * 0.5
	_enter.custom_minimum_size = Vector2.ZERO
	_enter.add_theme_font_size_override("font_size", maxi(14, int(_stage.size.y * 0.04)))
	_enter.position = _stage.size * Vector2(0.35, 0.65)
	_enter.size = Vector2(_stage.size.x * 0.30, maxf(44.0, _stage.size.y * 0.11))
	_enter.pivot_offset = _enter.size * 0.5
	_button_material.set_shader_parameter("button_size", _enter.size)

	if _account_area:
		var enter_bottom := _enter.position.y + _enter.size.y
		var area_w := _stage.size.x * 0.30
		var area_x := (_stage.size.x - area_w) * 0.5
		var sb := _account_area.get_theme_stylebox("panel")
		var pad_h: float = (sb.content_margin_left + sb.content_margin_right) if sb else 16.0
		var content_w := maxf(0.0, area_w - pad_h)
		for lbl: Label in _account_area.find_children("*", "Label", true, false):
			if lbl.autowrap_mode != TextServer.AUTOWRAP_OFF:
				lbl.custom_minimum_size.x = content_w
		_account_area.custom_minimum_size = Vector2(area_w, 0)
		_account_area.size = Vector2(area_w, 0)
		var min_h := _account_area.get_combined_minimum_size().y
		var visible_bottom: float = -_stage.position.y + size.y
		var rem_h := maxf(0.0, visible_bottom - 8.0 - enter_bottom)
		var gap := maxf(6.0, _stage.size.y * 0.015)
		var area_y: float
		if rem_h > min_h and min_h > 0.0:
			area_y = enter_bottom + (rem_h - min_h) * 0.4
		else:
			area_y = enter_bottom + gap
		if area_y + min_h > visible_bottom - 8.0:
			area_y = visible_bottom - 8.0 - min_h
		area_y = maxf(area_y, enter_bottom + 6.0)
		_account_area.position = Vector2(area_x, area_y)
		_account_area.size = Vector2(area_w, min_h)

func _play_intro() -> void:
	_set_button_ready(false)
	if UI.is_animation_disabled():
		_set_button_ready(true)
		return
	var w := maxf(size.x, _stage.size.x)
	_female.offset_left = -w * 0.6
	_female.offset_right = -w * 0.6
	_male.offset_left = w * 0.6
	_male.offset_right = w * 0.6
	_female.modulate.a = 0.0
	_male.modulate.a = 0.0
	var drop := _stage.size.y * 0.6
	_title.offset_top = -drop
	_title.offset_bottom = -drop
	_title.modulate.a = 0.0
	_enter.modulate.a = 0.0
	_enter.scale = Vector2(0.85, 0.85)
	if _account_area:
		_account_area.modulate.a = 0.0

	_intro = create_tween().set_parallel(true)
	# 1. Advisors enter from left and right
	for art: TextureRect in [_female, _male]:
		_intro.tween_property(art, "offset_left", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_intro.tween_property(art, "offset_right", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_intro.tween_property(art, "modulate:a", 1.0, 0.6)
	# 2. Title slides down from the top
	_intro.tween_property(_title, "offset_top", 0.0, 0.8).set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_title, "offset_bottom", 0.0, 0.8).set_delay(0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_intro.tween_property(_title, "modulate:a", 1.0, 0.5).set_delay(0.55)
	# 3. Entry button appears last
	_intro.tween_property(_enter, "modulate:a", 1.0, 0.4).set_delay(1.35)
	_intro.tween_property(_enter, "scale", Vector2.ONE, 0.45).set_delay(1.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _account_area:
		_intro.tween_property(_account_area, "modulate:a", 1.0, 0.4).set_delay(1.35)
	_intro.chain().tween_callback(_set_button_ready.bind(true))

func _set_button_ready(is_ready: bool) -> void:
	_buttons_ready = is_ready
	_enter.disabled = not is_ready
	_enter.mouse_filter = Control.MOUSE_FILTER_STOP if is_ready else Control.MOUSE_FILTER_IGNORE
	if _account_area:
		_account_area.modulate.a = 1.0 if is_ready else 0.0
		_account_area.mouse_filter = Control.MOUSE_FILTER_PASS if is_ready else Control.MOUSE_FILTER_IGNORE
		for btn: Button in _account_area.find_children("*", "Button", true, false):
			btn.disabled = not is_ready
			btn.mouse_filter = Control.MOUSE_FILTER_STOP if is_ready else Control.MOUSE_FILTER_IGNORE
			btn.focus_mode = Control.FOCUS_NONE
	if is_ready:
		_enter.grab_focus()

## Click or key press during the intro jumps straight to the finished cover.
func _input(event: InputEvent) -> void:
	if _intro == null or not _intro.is_running():
		return
	var skip: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if skip:
		get_viewport().set_input_as_handled()
		_intro.custom_step(10.0)

func _on_entered() -> void:
	_enter.disabled = true
	if _account_area:
		_account_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for btn: Button in _account_area.find_children("*", "Button", true, false):
			btn.disabled = true
	# First user gesture: the web build may start audio only now (no autoplay on page load)
	MusicManager.play_music()
	entered.emit()
