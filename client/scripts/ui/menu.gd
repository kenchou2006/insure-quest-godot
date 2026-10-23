@tool
extends Control
## Training hall (新人顧問培訓大廳), shown after the secretary choice: pick 單人實戰 or 多人演練.
## Keeps every menu function: guest / demo code / test / Google login, create / join multiplayer
## rooms, resume seat, records, guide, settings (volumes, secretary, account deletion). The player's
## advisor (新人顧問報到) shows in the top-right pill; 單人實戰 opens 本局對練配置 (1–3 named
## sparring advisors) and starts only on 確認配置. 返回選擇秘書 goes back one screen.
## Supports landscape/portrait adaptation and PWA update check.

const AutomationBridge := preload("res://scripts/automation.gd")
const ModeCard := preload("res://scripts/ui/mode_card.gd")
const HallSecretary := preload("res://scripts/ui/hall_secretary.gd")
const LineIcon := preload("res://scripts/ui/line_icon.gd")
const BackButton := preload("res://scripts/ui/back_button.gd")
const DemoCodeDialog := preload("res://scripts/ui/demo_code_dialog.gd")
## 本局對練配置 (shown under the cards once 單人實戰 is chosen)
const SparringSetup := preload("res://scripts/ui/sparring_setup.gd")
const HALL_BG := preload("res://assets/startup/loading.png")
const HALL_SHADER := preload("res://assets/startup/hall_backdrop.gdshader")
const BOLD := preload("res://assets/fonts/bold.tres")
## Cover logo (INSURE QUEST / 人生顧問局), cropped to its painted area
const LOGO := preload("res://assets/startup/title.png")
const LOGO_CROP := Rect2(8, 10, 1944, 760)


var main: Node
var _name: LineEdit
var _code: LineEdit
var _server: LineEdit
var _howto: Control
var _pwa_btn: Button
var _resume_container: VBoxContainer
var _pwa_cb: JavaScriptObject = null
var _target_version: String = ""
var _seat_check_gen: int = 0
var _portrait_mode := false
var _phone := false
var _selected_mode := ""
var _top: Panel
var _brand: TextureRect
var _brand_rule: ColorRect
var _id_pill: Button
var _id_icon: Control
var _id_label: Label
var _id_chev: Control
var _howto_btn: Button
var _howto_icon: Control
var _howto_label: Label
var _rec_btn: Button
var _rec_icon: Control
var _rec_label: Label
var _title_row: HBoxContainer
var _title_a: Label
var _title_b: Label
var _ornament: Control
var _subtitle: Label
var _solo_card: ModeCard
var _multi_card: ModeCard
var _solo_opts: PanelContainer
var _footer: Label
var _secretary: HallSecretary
var _id_catcher: Control
var _id_pop: PanelContainer
var _scroll: ScrollContainer
var _stack: VBoxContainer
var _stack_spacer: Control
var _auth_card_container: VBoxContainer
var _back: Button
var _last_account_id: String = ""
var _avatar_loading: bool = false


func _ready() -> void:
	if not Net.auth_changed.is_connected(_on_auth_changed):
		Net.auth_changed.connect(_on_auth_changed)
	_last_account_id = str(Net.get_user().get("id", ""))
	_build_ui()
	if OS.has_feature("web") and not Engine.is_editor_hint():
		_check_url_demo_code.call_deferred()


func _exit_tree() -> void:
	if Net.auth_changed.is_connected(_on_auth_changed):
		Net.auth_changed.disconnect(_on_auth_changed)
	if OS.has_feature("web") and not Engine.is_editor_hint():
		if JavaScriptBridge.pwa_update_available.is_connected(_on_pwa_update_avail):
			JavaScriptBridge.pwa_update_available.disconnect(_on_pwa_update_avail)


func _on_auth_changed() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var cur_id: String = str(Net.get_user().get("id", ""))
	if cur_id != _last_account_id:
		_last_account_id = cur_id
		if Net.is_logged_in():
			var acc_name: String = str(Net.get_user().get("name", "")).strip_edges()
			if acc_name != "" and _name:
				_name.text = acc_name
				_save()
	if _auth_card_container and is_instance_valid(_auth_card_container):
		_update_auth_card()
		_refresh_auth_ui()
	else:
		_build_ui()


func on_layout_changed(_is_portrait: bool) -> void:
	var cur_name: String = _name.text if _name else ""
	var cur_code: String = _code.text if _code else ""
	_build_ui()
	if _name and cur_name != "": _name.text = cur_name
	if _code and cur_code != "": _code.text = cur_code


## Training hall (新人顧問培訓大廳): pick 單人實戰 or 多人演練. Identity / login live in the
## 「訪客｜顧問」 dropdown; solo options appear only after the 單人實戰 card is picked.
func _build_ui() -> void:
	UI.clear(self)
	_portrait_mode = UI.is_portrait()
	_phone = UI.is_phone()
	_selected_mode = ""

	# Backdrop: rainy Taipei office with 101, dimmed and slightly blurred
	var bg := TextureRect.new()
	bg.texture = HALL_BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat := ShaderMaterial.new()
	bg_mat.shader = HALL_SHADER
	bg.material = bg_mat
	add_child(bg)

	_build_topbar()
	_back = BackButton.new("返回選擇秘書")
	_back.pressed.connect(_on_back)

	_title_row = HBoxContainer.new()
	_title_row.add_theme_constant_override("separation", 0)
	_title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_a = _hall_label("選擇你的", 44, UI.TEXT)
	_title_b = _hall_label("培訓方式", 44, UI.GOLD)
	for t: Label in [_title_a, _title_b]:
		t.add_theme_font_override("font", BOLD)
		t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		t.add_theme_constant_override("shadow_offset_y", 2)
		_title_row.add_child(t)
	_ornament = Ornament.new()
	_subtitle = _hall_label("完成一場 8–12 分鐘的客戶會談，取得個人化顧問報告", 18, Color(UI.TEXT, 0.88))
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_solo_card = ModeCard.new()
	_solo_card.title = "單人實戰"
	_solo_card.tag = "初次建議"
	_solo_card.tag_primary = true
	_solo_card.icon = "chat_user"
	_solo_card.rows = [["user", "1 位情境客戶"], ["robot", "AI 顧問陪練"], ["doc", "個人化培訓報告"]]
	_solo_card.button_text = "進入單人實戰"
	_solo_card.primary = true
	_solo_card.picked.connect(func(): _pick_mode("solo"))
	# 進入單人實戰 opens 本局對練配置; the game starts on 確認配置
	_solo_card.activated.connect(func(): _pick_mode("solo", true))

	_multi_card = ModeCard.new()
	_multi_card.title = "多人演練"
	_multi_card.tag = "登入後開放"
	_multi_card.icon = "users"
	_multi_card.rows = [["users", "2–4 位顧問"], ["chart", "比較不同應對方法"], ["doc", "團隊演練紀錄"]]
	_multi_card.button_text = "建立多人房間"
	_multi_card.primary = true
	_multi_card.link_text = "房間代碼加入"
	_multi_card.picked.connect(func(): _pick_mode("multi"))
	_multi_card.activated.connect(_on_multi_pressed)
	_multi_card.link_pressed.connect(_open_join)

	_build_solo_options()

	_footer = _hall_label("情境與數值僅供教育訓練模擬；保障卡為功能概念，不對應任何實際保險商品，亦不構成保險或投資建議。", 11, Color(UI.MUTED, 0.75))
	_footer.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY

	if _portrait_mode:
		# Phone / tablet portrait: everything stacks in a scroll area under the top bar
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(_scroll)
		_stack = UI.vbox(16)
		_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(_stack)
		var title_wrap := UI.vbox(6)
		var top_gap := Control.new()
		top_gap.custom_minimum_size = Vector2(0, 10)
		title_wrap.add_child(top_gap)
		_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		title_wrap.add_child(_back)
		title_wrap.add_child(_title_row)
		title_wrap.add_child(_ornament)
		title_wrap.add_child(_subtitle)
		_subtitle.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_stack.add_child(title_wrap)
		for n: Control in [_solo_card, _solo_opts, _multi_card, _footer]:
			_stack.add_child(n)
		_stack_spacer = Control.new()
		_stack.add_child(_stack_spacer)
	else:
		for n: Control in [_back, _title_row, _ornament, _subtitle, _solo_card, _multi_card, _solo_opts, _footer]:
			add_child(n)
	_solo_opts.visible = false

	_secretary = HallSecretary.new()
	add_child(_secretary)
	var sel := "none"
	if main and main.has_method("secretary_guide"):
		var guide: Control = main.secretary_guide()
		if guide != null:
			sel = str(guide.selected_secretary())
	# The hall greeting runs as the secretary's 強制聚焦導覽 (first time only); the corner keeps the
	# round portrait (replays it) or, for 自行挑戰, the 「開啟引導」 pill
	_secretary.use_tutorial = sel != "none"
	_secretary.setup(sel, false)
	_secretary.portrait_pressed.connect(func(): _hall_tutorial(true))
	if sel != "none" and not Engine.is_editor_hint():
		# After the screen switch has finished (the switch dismisses any open dialog)
		get_tree().create_timer(0.4).timeout.connect(func():
			if is_instance_valid(self) and is_inside_tree():
				# Right after choosing Aly / Kevin: always the 強制聚焦導覽, no tap needed;
				# other visits only the first time
				var just_chosen: bool = main.has_method("take_hall_greeting") and main.take_hall_greeting()
				_hall_tutorial(just_chosen)
		)

	_build_identity_popup()
	_refresh_auth_ui()

	_howto = _build_howto()
	add_child(_howto)

	if not resized.is_connected(_layout):
		resized.connect(_layout)
	_layout()
	_intro()


func _hall_label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_topbar() -> void:
	_top = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UI.BG, 0.88)
	sb.border_width_bottom = 1
	sb.border_color = Color(UI.GOLD, 0.28)
	_top.add_theme_stylebox_override("panel", sb)
	_top.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_top)
	_brand = TextureRect.new()
	var logo := AtlasTexture.new()
	logo.atlas = LOGO
	logo.region = LOGO_CROP
	_brand.texture = logo
	_brand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_brand.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_brand)
	_brand_rule = ColorRect.new()
	_brand_rule.color = Color(UI.GOLD, 0.5)
	_brand_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_brand_rule)

	# Ongoing multiplayer seat (shown only when the server still holds it)
	_resume_container = UI.vbox(0)
	_top.add_child(_resume_container)
	_resume_container.child_entered_tree.connect(func(_n): _layout.call_deferred())
	_check_saved_seat()

	_id_pill = Button.new()
	_id_pill.focus_mode = Control.FOCUS_NONE
	_id_pill.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(UI.BG, 0.6)
	pill.set_corner_radius_all(22)
	pill.set_border_width_all(1)
	pill.border_color = Color(UI.TEXT, 0.4)
	pill.anti_aliasing = true
	var pill_h := pill.duplicate() as StyleBoxFlat
	pill_h.border_color = Color(UI.TEXT, 0.75)
	pill_h.bg_color = Color(UI.PANEL, 0.8)
	_id_pill.add_theme_stylebox_override("normal", pill)
	_id_pill.add_theme_stylebox_override("hover", pill_h)
	_id_pill.add_theme_stylebox_override("pressed", pill_h)
	_id_pill.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_id_pill.pressed.connect(func(): _toggle_identity())
	_top.add_child(_id_pill)
	# The player's own portrait (新人顧問報到); the line icon only before a profile exists
	if PlayerProfile.player_profile_created and PlayerProfile.portrait() != null:
		_id_icon = UI.RoundTex.new(PlayerProfile.portrait(), Vector2(28, 28), -1.0, PlayerProfile.token_color(), 2.0)
	else:
		_id_icon = LineIcon.new("user", UI.TEXT, 1.8)
	_id_icon.name = "PlayerAvatar"
	_id_pill.add_child(_id_icon)
	_id_label = _hall_label("", 15, UI.TEXT)
	_id_pill.add_child(_id_label)
	_id_chev = LineIcon.new("chevron_d", UI.TEXT, 1.8)
	_id_pill.add_child(_id_chev)

	_rec_btn = Button.new()
	_rec_btn.flat = true
	_rec_btn.focus_mode = Control.FOCUS_NONE
	_rec_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rec_btn.pressed.connect(func(): Sound.play("click", self); _save(); main.show_records())
	_top.add_child(_rec_btn)
	_rec_icon = LineIcon.new("doc", UI.GOLD, 1.8)
	_rec_btn.add_child(_rec_icon)
	_rec_label = _hall_label("培訓紀錄", 15, UI.TEXT)
	_rec_btn.add_child(_rec_label)
	_rec_btn.mouse_entered.connect(func(): _rec_label.add_theme_color_override("font_color", UI.GOLD))
	_rec_btn.mouse_exited.connect(func(): _rec_label.add_theme_color_override("font_color", UI.TEXT))

	_howto_btn = Button.new()
	_howto_btn.flat = true
	_howto_btn.focus_mode = Control.FOCUS_NONE
	_howto_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_howto_btn.pressed.connect(func(): Sound.play("click", self); _open_brief())
	_top.add_child(_howto_btn)
	_howto_icon = LineIcon.new("question", UI.GOLD, 1.8)
	_howto_btn.add_child(_howto_icon)
	_howto_label = _hall_label("玩法", 15, UI.TEXT)
	_howto_btn.add_child(_howto_label)
	_howto_btn.mouse_entered.connect(func(): _howto_label.add_theme_color_override("font_color", UI.GOLD))
	_howto_btn.mouse_exited.connect(func(): _howto_label.add_theme_color_override("font_color", UI.TEXT))


## 本局對練配置 (shown after 單人實戰 is picked): the player plus 1–3 named sparring advisors
func _build_solo_options() -> void:
	_solo_opts = SparringSetup.new(_portrait_mode, _phone)
	_solo_opts.connect("confirmed", _start_solo)
	# Its height is known only after its wrapped hint is laid out: place the page again then
	_solo_opts.minimum_size_changed.connect(func():
		if _solo_opts.visible and not _portrait_mode:
			_layout()
	, CONNECT_DEFERRED)


## 「訪客｜顧問」 dropdown: advisor name, login options, records and settings
func _build_identity_popup() -> void:
	_id_catcher = Control.new()
	_id_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_id_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_id_catcher.visible = false
	_id_catcher.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_toggle_identity(false)
	)
	add_child(_id_catcher)

	_id_pop = UI.panel(UI.PANEL, 14, 16)
	_id_pop.visible = false
	_id_pop.custom_minimum_size = Vector2(340, 0)
	add_child(_id_pop)
	var v := UI.vbox(10)
	_id_pop.add_child(v)

	v.add_child(UI.label("身分設定", 17, UI.GOLD))
	# The advisor from 新人顧問報到: portrait, name, real level; edited on its own page
	var who := UI.hbox(10)
	if PlayerProfile.portrait() != null:
		who.add_child(UI.RoundTex.new(PlayerProfile.portrait(), Vector2(52, 52), -1.0, PlayerProfile.token_color(), 2.0))
	var who_v := UI.vbox(2)
	who_v.add_child(UI.label(PlayerProfile.player_name if PlayerProfile.player_name != "" else Net.player_name, 17, UI.TEXT))
	who_v.add_child(UI.label(PlayerProfile.level_text(), 13, UI.GOLD))
	who.add_child(who_v)
	v.add_child(who)
	var edit := UI.button("修改顧問檔案（形象・名稱・棋子）", func():
		_toggle_identity(false)
		if main and main.has_method("show_onboarding"):
			main.show_onboarding("edit")
	, 14, UI.PANEL_2)
	edit.name = "EditProfile"
	v.add_child(edit)
	_name = null

	# PWA update button (kept hidden; updates install silently)
	_pwa_btn = UI.button("★ 有新版本，點此更新", _on_pwa_btn_pressed, 14, UI.GOLD)
	_pwa_btn.visible = false
	v.add_child(_pwa_btn)
	if OS.has_feature("web") and not AutomationBridge.is_active() and not Engine.is_editor_hint():
		_check_pwa_update()
		if not JavaScriptBridge.pwa_update_available.is_connected(_on_pwa_update_avail):
			JavaScriptBridge.pwa_update_available.connect(_on_pwa_update_avail)

	var auth_card := UI.panel(UI.PANEL_2, 12, 10)
	auth_card.name = "AuthCardPanel"
	_auth_card_container = UI.vbox(6)
	auth_card.add_child(_auth_card_container)
	v.add_child(auth_card)
	_update_auth_card()

	if not Net.is_web():
		v.add_child(UI.label("伺服器位址（桌面版）", 13, UI.MUTED))
		_server = LineEdit.new()
		_server.text = Net.base_url
		_server.custom_minimum_size = Vector2(0, 40)
		v.add_child(_server)

	var row := UI.hbox(8)
	var rec := UI.button("培訓紀錄", func(): _save(); _toggle_identity(false); main.show_records(), 14, UI.PANEL_2)
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rec)
	var st := UI.button("設定（聲音・秘書）", func(): _save(); _toggle_identity(false); _open_settings(), 14, UI.PANEL_2)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(st)
	v.add_child(row)


## Dropdown under the pill. Wrapped labels report their real height only after one layout pass,
## so the panel is measured again on the next frame.
func _fit_identity() -> void:
	if _id_pop == null or not is_instance_valid(_id_pop) or _id_pill == null:
		return
	_id_pop.size = Vector2(_id_pop.custom_minimum_size.x, 0)
	_id_pop.reset_size()
	_id_pop.position = Vector2(clampf(_id_pill.position.x + _id_pill.size.x - _id_pop.size.x, 8, size.x - _id_pop.size.x - 8), _top.size.y + 8)


func _toggle_identity(force: Variant = null) -> void:
	if _id_pop == null:
		return
	var show: bool = (not _id_pop.visible) if force == null else bool(force)
	if not show and _id_pop.visible:
		_save()
	_id_pop.visible = show
	_id_catcher.visible = show
	if show:
		_fit_identity()
		UI.pop_in(_id_pop, 0.18)
		await get_tree().process_frame
		_fit_identity()


func _refresh_auth_ui() -> void:
	if _id_label == null or not is_instance_valid(_id_label):
		return
	# Player name and real level: the account level when logged in, else this device's training level
	var level := PlayerProfile.advisor_level
	if Net.is_logged_in():
		var lv: Dictionary = Net.get_level()
		if not lv.is_empty():
			level = int(lv.get("level", level))
	var n: String = PlayerProfile.player_name if PlayerProfile.player_profile_created else ""
	if n == "":
		n = _name.text.strip_edges() if _name else Net.player_name
	_id_label.text = "%s　Lv.%d" % [n if n != "" else "顧問", level]
	if _multi_card:
		var open := Net.is_logged_in()
		_multi_card.set_tag("已開放" if open else "登入後開放", open)
	_layout()


func _pick_mode(mode: String, reveal := false) -> void:
	if _selected_mode == mode:
		if reveal and _portrait_mode and _scroll and _solo_opts.visible:
			_scroll.ensure_control_visible(_solo_opts)
		return
	_selected_mode = mode
	_solo_card.set_selected(mode == "solo")
	_multi_card.set_selected(mode == "multi")
	# Chosen card: 「已選擇」 and its frame lit; the other card dims
	_solo_card.set_tag("已選擇" if mode == "solo" else "初次建議", true)
	if mode != "multi":
		_multi_card.set_tag("已開放" if Net.is_logged_in() else "登入後開放", Net.is_logged_in())
	for pair in [[_solo_card, mode == "multi"], [_multi_card, mode == "solo"]]:
		var card: Control = pair[0]
		var target := Color(0.62, 0.62, 0.62) if pair[1] else Color(1, 1, 1)
		if UI.is_animation_disabled():
			card.modulate = target
		else:
			create_tween().tween_property(card, "modulate", target, 0.2)
	var show := mode == "solo"
	if show == _solo_opts.visible:
		return
	_solo_opts.visible = show
	_layout()
	if show and not UI.is_animation_disabled():
		_solo_opts.modulate.a = 0.0
		var y := _solo_opts.position.y
		if not _portrait_mode:
			_solo_opts.position.y = y - 8
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_solo_opts, "modulate:a", 1.0, 0.25)
		if not _portrait_mode:
			_solo_opts.position.y = y + 24
			tw.tween_property(_solo_opts, "position:y", y, 0.28)
			tw.finished.connect(_layout)
	if show and _portrait_mode and _scroll:
		await get_tree().process_frame
		_scroll.ensure_control_visible(_solo_opts)


func _on_multi_pressed() -> void:
	_pick_mode("multi")
	if not Net.is_logged_in():
		if main:
			main.toast("多人演練需先登入", UI.INFO)
		_toggle_identity(true)
		return
	_create_multi()


## Room code entry for joining a multiplayer room
func _open_join() -> void:
	var m := _open_modal("JoinDialog", "加入多人房間", UI.ACCENT_2)
	if m.is_empty():
		return
	var dim: Control = m[0]
	var v: VBoxContainer = m[1]
	if not Net.is_logged_in():
		v.add_child(UI.label("多人連線需先登入，可從右上角「訪客｜顧問」登入。", 13, UI.MUTED, true))
	var join := UI.hbox(8)
	_code = LineEdit.new()
	_code.placeholder_text = "房間代碼（5 碼）"
	_code.max_length = 5
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.custom_minimum_size = Vector2(0, 44)
	_code.text_submitted.connect(func(_t: String): _join())
	join.add_child(_code)
	join.add_child(UI.button("加入", _join, 16))
	v.add_child(join)
	dim.tree_exiting.connect(func(): _code = null)
	_code.grab_focus.call_deferred()


func _layout() -> void:
	if _top == null or not is_instance_valid(_top) or size.x < 10:
		return
	var view := size
	var k := clampf(minf(view.x / 1280.0, view.y / 720.0), 0.62, 1.6)
	if _portrait_mode:
		k = clampf(view.x / 480.0, 0.85, 1.4)
	var top_h := (64.0 if not _portrait_mode else 56.0) * k

	# Top bar
	_top.position = Vector2.ZERO
	_top.size = Vector2(view.x, top_h)
	var side := (32.0 if not _portrait_mode else 14.0) * k
	var logo_h := top_h * 0.88
	_brand.size = Vector2(logo_h * LOGO_CROP.size.x / LOGO_CROP.size.y, logo_h)
	_brand.position = Vector2(side, (top_h - logo_h) * 0.5)
	_brand_rule.size = Vector2(1, 26 * k)
	_brand_rule.position = Vector2(_brand.position.x + _brand.size.x + 14 * k, (top_h - 26 * k) * 0.5)
	_brand_rule.visible = not _portrait_mode
	_howto_label.add_theme_font_size_override("font_size", roundi(15 * k))
	_howto_label.reset_size()
	var hi := 24.0 * k
	_howto_icon.size = Vector2(hi, hi)
	_howto_btn.size = Vector2(hi + 8 * k + _howto_label.size.x + 8 * k, 40 * k)
	_howto_btn.position = Vector2(view.x - side - _howto_btn.size.x, (top_h - _howto_btn.size.y) * 0.5)
	_howto_icon.position = Vector2(4 * k, (_howto_btn.size.y - hi) * 0.5)
	_howto_label.position = Vector2(hi + 12 * k, (_howto_btn.size.y - _howto_label.size.y) * 0.5)
	_rec_label.add_theme_font_size_override("font_size", roundi(15 * k))
	_rec_label.reset_size()
	_rec_icon.size = Vector2(hi, hi)
	_rec_label.visible = not _portrait_mode
	_rec_btn.size = Vector2(hi + 8 * k + (_rec_label.size.x + 8 * k if _rec_label.visible else 0.0), 40 * k)
	_rec_btn.position = Vector2(_howto_btn.position.x - 14 * k - _rec_btn.size.x, (top_h - _rec_btn.size.y) * 0.5)
	_rec_icon.position = Vector2(4 * k, (_rec_btn.size.y - hi) * 0.5)
	_rec_label.position = Vector2(hi + 12 * k, (_rec_btn.size.y - _rec_label.size.y) * 0.5)
	_id_label.add_theme_font_size_override("font_size", roundi(15 * k))
	_id_label.reset_size()
	var pi := 22.0 * k
	var ph := 38.0 * k
	_id_pill.size = Vector2(12 * k + pi + 10 * k + _id_label.size.x + 10 * k + 14 * k + 14 * k, ph)
	_id_pill.position = Vector2(_rec_btn.position.x - 16 * k - _id_pill.size.x, (top_h - ph) * 0.5)
	_id_icon.custom_minimum_size = Vector2(pi, pi)
	_id_icon.size = Vector2(pi, pi)
	_id_icon.position = Vector2(12 * k, (ph - pi) * 0.5)
	_id_label.position = Vector2(_id_icon.position.x + pi + 10 * k, (ph - _id_label.size.y) * 0.5)
	_id_chev.size = Vector2(14 * k, 14 * k)
	_id_chev.position = Vector2(_id_label.position.x + _id_label.size.x + 10 * k, (ph - 14 * k) * 0.5)
	if _resume_container.get_child_count() > 0:
		_resume_container.reset_size()
		_resume_container.position = Vector2(_id_pill.position.x - 16 * k - _resume_container.size.x, (top_h - _resume_container.size.y) * 0.5)
		if _resume_container.position.x < _brand_rule.position.x + 16 * k:
			_resume_container.position.x = _brand_rule.position.x + 16 * k
	_fit_identity()

	for t: Label in [_title_a, _title_b]:
		t.add_theme_font_size_override("font_size", roundi((48.0 if not _portrait_mode else 30.0) * k))
	_subtitle.add_theme_font_size_override("font_size", roundi((18.0 if not _portrait_mode else 14.0) * k))
	_footer.add_theme_font_size_override("font_size", maxi(10, roundi(11 * k)))

	_secretary.layout(view, k, _phone)

	if _portrait_mode:
		_scroll.position = Vector2(0, top_h)
		_scroll.size = Vector2(view.x, view.y - top_h)
		var cw := view.x - 32 * k
		_stack.add_theme_constant_override("separation", roundi(16 * k))
		_stack.custom_minimum_size = Vector2(view.x, 0)
		for n: Control in [_solo_card, _multi_card]:
			n.custom_minimum_size = Vector2(cw, cw * 292.0 / 406.0)
			n.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_solo_opts.custom_minimum_size = Vector2(cw, 0)
		_solo_opts.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_ornament.custom_minimum_size = Vector2(cw, 12 * k)
		_subtitle.custom_minimum_size = Vector2(cw, 0)
		_subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_footer.custom_minimum_size = Vector2(cw, 0)
		_footer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		# Leave room so the last card can scroll above the secretary
		_stack_spacer.custom_minimum_size = Vector2(0, view.y - _secretary.occupied_rect().position.y + 12 * k)
		return

	# Landscape: title, two cards, solo options; the block centers vertically when the screen is tall
	var oy := maxf(0.0, (view.y - 720.0 * k) * 0.5)
	# 本局對練配置 open: the cards get shorter and the line-up panel takes the lower part
	var cfg := _solo_opts.visible
	if cfg:
		oy = 0.0
	_back.reset_size()
	_back.position = Vector2(side, top_h + 12 * k)
	_title_row.reset_size()
	_title_row.position = Vector2((view.x - _title_row.size.x) * 0.5, top_h + (8.0 if cfg else 14.0) * k + oy)
	_ornament.size = Vector2(160 * k, 12 * k)
	_ornament.position = Vector2((view.x - _ornament.size.x) * 0.5, _title_row.position.y + _title_row.size.y + 2 * k)
	_subtitle.reset_size()
	_subtitle.position = Vector2((view.x - _subtitle.size.x) * 0.5, _ornament.position.y + _ornament.size.y + 6 * k)

	var cw := (372.0 if cfg else 406.0) * k
	var ch := (214.0 if cfg else 292.0) * k
	var gap := 22.0 * k
	var x0 := (view.x - (cw * 2 + gap)) * 0.5
	var cy := _subtitle.position.y + _subtitle.size.y + (12.0 if cfg else 22.0) * k
	var sec_rect := _secretary.occupied_rect()
	var sec_left := sec_rect.position.x
	var px := 24.0 * k
	var right := view.x - 24 * k
	# Low screens: the line-up panel must fit whole — the subtitle steps aside, then the cards get shorter
	var tight := false
	if cfg:
		var sec_right := minf(right, sec_left - 14 * k) if sec_rect.size.x > 0 and sec_rect.position.y < view.y - 4 else right
		_solo_opts.size = Vector2(maxf(200.0, sec_right - px), 0)
		var need: float = _solo_opts.call("min_height")
		var bottom := view.y - 6 * k - need - 12 * k
		if cy + ch > bottom:
			tight = true
			cy = _ornament.position.y + 4 * k
			ch = clampf(bottom - cy, 84.0 * k, ch)
	_ornament.visible = not tight
	_subtitle.visible = not tight
	_solo_card.size = Vector2(cw, ch)
	_solo_card.position = Vector2(x0, cy)
	_multi_card.size = Vector2(cw, ch)
	_multi_card.position = Vector2(x0 + cw + gap, cy)

	# Line-up panel under the cards, left of the secretary corner
	var top_y := cy + ch + 12 * k
	if sec_rect.size.x > 0 and sec_rect.position.y < view.y - 4 and sec_rect.end.y > top_y:
		right = minf(right, sec_left - 14 * k)
	_solo_opts.size = Vector2(maxf(200.0, right - px), 0)
	if cfg:
		_solo_opts.call("fit_height", view.y - top_y - 6 * k)
	_solo_opts.reset_size()
	var oh := maxf(_solo_opts.get_combined_minimum_size().y, view.y - top_y - 10 * k)
	_solo_opts.size = Vector2(maxf(200.0, right - px), minf(oh, view.y - top_y - 6 * k))
	_solo_opts.position = Vector2(px, top_y)
	_footer.visible = not cfg
	_footer.custom_minimum_size = Vector2(minf(sec_left - 48 * k, 820 * k), 0)
	_footer.reset_size()
	_footer.position = Vector2(24 * k, view.y - _footer.size.y - 12 * k)


## Entrance: title and cards fade up in sequence
func _intro() -> void:
	if UI.is_animation_disabled():
		return
	var items: Array = [_title_row, _subtitle, _solo_card, _multi_card] if not _portrait_mode else [_stack]
	for i in range(items.size()):
		var n: CanvasItem = items[i]
		n.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(n, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Hall greeting with both mode cards kept bright; replay=true from the corner portrait
func _hall_tutorial(replay: bool) -> void:
	if main == null or not main.has_method("secretary_guide"):
		return
	var guide: Control = main.secretary_guide()
	if guide == null:
		return
	var targets := {"hall_intro": [_solo_card, _multi_card]}
	if replay:
		guide.replay_states(["hall_intro"], targets)
	else:
		guide.show_states(["hall_intro"], targets)


## Gold rule with a small diamond under the hall title
class Ornament extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var g := Color("#C6A15B", 0.85)
		var half := minf(size.x * 0.5, 80.0)
		draw_line(Vector2(c.x - half, c.y), Vector2(c.x - 8, c.y), g, 1.0, true)
		draw_line(Vector2(c.x + 8, c.y), Vector2(c.x + half, c.y), g, 1.0, true)
		var d := 4.0
		draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), g, 1.2, true)


func _update_auth_card() -> void:
	if _auth_card_container == null or not is_instance_valid(_auth_card_container):
		return
	# Free immediately (not queue_free) so a rebuild within the same frame can never leave a stale second card
	for c in _auth_card_container.get_children():
		_auth_card_container.remove_child(c)
		c.free()
	if Net.is_logged_in():
		var u: Dictionary = Net.get_user()
		var u_name: String = str(u.get("name", "顧問"))
		var is_trainer: bool = bool(u.get("trainer", false))
		var lv: Dictionary = Net.get_level()

		var h := UI.hbox(8)
		# Google avatar (displays initial before download completes or if no avatar)
		h.add_child(UI.avatar(Net.avatar_tex, u_name, 40))
		if Net.avatar_tex == null:
			# Deferred: a cached avatar loads synchronously and would re-enter this function mid-build, adding a second card
			_load_avatar.call_deferred()

		var info_v := UI.vbox(2)
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tag_text: String = " ［講師］" if is_trainer else ""
		# No autowrap: before the first layout pass a zero-width wrapping label renders as a tall multi-line block
		var name_lbl := UI.label(u_name + tag_text, 15, UI.TEXT)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_lbl.custom_minimum_size.x = 0
		info_v.add_child(name_lbl)
		# Advisor level and EXP bar (EXP = sum of scores across matches)
		if not lv.is_empty():
			var lv_row := UI.hbox(6)
			lv_row.add_child(UI.label("Lv.%d %s" % [int(lv.get("level", 1)), str(lv.get("title", ""))], 12, UI.GOLD))
			var nxt: Variant = lv.get("next")
			var xp: int = int(lv.get("xp", 0))
			if nxt != null:
				var floor_xp: int = int(lv.get("floor", 0))
				var pct: float = 100.0 * float(xp - floor_xp) / float(maxi(1, int(nxt) - floor_xp))
				var b := UI.bar(pct, UI.GOLD, 70)
				b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				lv_row.add_child(b)
				lv_row.add_child(UI.label("%d / %d" % [xp, int(nxt)], 11, UI.MUTED))
			else:
				lv_row.add_child(UI.label("最高等級・經驗 %d" % xp, 11, UI.MUTED))
			info_v.add_child(lv_row)
		h.add_child(info_v)

		h.add_child(UI.button("登出", _logout, 13, UI.BAD.darkened(0.4)))
		_auth_card_container.add_child(h)
	else:
		_auth_card_container.add_child(UI.label("訪客身分", 15, UI.MUTED))
		var google := UI.button("使用 Google 登入", _login_google, 15, UI.ACCENT)
		google.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_auth_card_container.add_child(google)
		var h := HFlowContainer.new()
		h.add_theme_constant_override("h_separation", 8)
		h.add_theme_constant_override("v_separation", 8)
		if bool(Net.auth_config.get("demo", false)):
			h.add_child(UI.button("評審體驗碼", _open_demo_dialog, 14, UI.GOLD))
		# Local development only (server allows it on localhost with DEV_LOGIN)
		if bool(Net.auth_config.get("dev", false)):
			h.add_child(UI.button("測試登入", _login_dev, 14, UI.GOLD.darkened(0.3)))
		if h.get_child_count() > 0:
			_auth_card_container.add_child(h)
		var guest_note := "登入 Google 後，培訓紀錄保存到你的帳號，換裝置也能查看，並可使用 AI 功能；訪客紀錄只保存在此裝置。"
		var guest_note_lbl := UI.label(guest_note, 12, UI.MUTED, true)
		guest_note_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_auth_card_container.add_child(guest_note_lbl)


func _load_avatar() -> void:
	if Engine.is_editor_hint():
		return
	if _avatar_loading:
		return
	_avatar_loading = true
	var tex: Texture2D = await Net.fetch_avatar()
	_avatar_loading = false
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if tex != null:
		_update_auth_card()


func _login_google() -> void:
	_save()
	if not bool(Net.auth_config.get("google", true)):
		if main:
			main.toast("這台伺服器尚未設定 Google 登入（本機測試環境）；正式網址可使用 Google 登入。", UI.INFO, 4.0)
		return
	Net.google_sign_in()


func _login_dev() -> void:
	_save()
	Net.login_dev()


func _logout() -> void:
	await Net.logout()
	_update_auth_card()


## Centered modal (dimmed backdrop, title row with ✕). Returns [backdrop, content vbox]; null if one with this name is open.
func _open_modal(node_name: String, title: String, title_color: Color) -> Array:
	for c in get_children():
		if c.name == node_name:
			return []
	var dim := ColorRect.new()
	dim.name = node_name
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var p := UI.panel(UI.PANEL, 14, 18)
	p.custom_minimum_size = Vector2(340.0 if UI.is_phone_portrait() else 420.0, 0)
	var v := UI.vbox(12)
	p.add_child(v)

	var head := UI.hbox(8)
	head.add_child(UI.label(title, 18, title_color))
	head.add_child(UI.spacer())
	var close_btn := UI.button("×", func(): dim.queue_free(), 16, UI.PANEL_2)
	close_btn.custom_minimum_size = Vector2(36, 36)
	head.add_child(close_btn)
	v.add_child(head)

	center.add_child(p)
	add_child(dim)
	return [dim, v]


## Settings: volumes, and (when logged in) account deletion
func _open_settings() -> void:
	var m := _open_modal("SettingsDialog", "設定", UI.ACCENT_2)
	if m.is_empty():
		return
	var dim: Control = m[0]
	var v: VBoxContainer = m[1]

	v.add_child(UI.label("聲音", 14, UI.MUTED))
	v.add_child(AudioSettings.new())
	v.add_child(HSeparator.new())
	v.add_child(UI.label("畫面與陪伴", 14, UI.MUTED))
	var motion := CheckBox.new()
	motion.text = "減少介面動效"
	motion.button_pressed = UI.reduce_motion
	motion.toggled.connect(UI.set_reduce_motion)
	v.add_child(motion)
	v.add_child(UI.button("重新選擇語音秘書", func():
		dim.queue_free()
		if main and main.has_method("open_secretary_settings"):
			main.open_secretary_settings()
	, 15, UI.PANEL_2))

	if Net.is_logged_in():
		v.add_child(HSeparator.new())
		v.add_child(UI.label("帳號", 14, UI.MUTED))
		v.add_child(UI.label("刪除帳號會永久刪除你的培訓紀錄、學習檔案與 AI 使用紀錄，無法復原。", 12, UI.MUTED, true))
		v.add_child(UI.button("刪除帳號", func():
			dim.queue_free()
			_confirm_delete_account()
		, 14, UI.BAD.darkened(0.4)))


func _confirm_delete_account() -> void:
	var m := _open_modal("DeleteAccountDialog", "刪除帳號確認", UI.BAD)
	if m.is_empty():
		return
	var dim: Control = m[0]
	var v: VBoxContainer = m[1]

	v.add_child(UI.label("確定要刪除帳號嗎？此動作將永久刪除您的個人紀錄、學習檔案與 AI 配額資料，且無法復原。", 13, UI.MUTED, true))

	var btns := UI.hbox(8)
	btns.add_child(UI.spacer())
	btns.add_child(UI.button("取消", func(): dim.queue_free(), 13, UI.PANEL_2))
	btns.add_child(UI.button("確定刪除", func():
		dim.queue_free()
		await _delete_account()
	, 13, UI.BAD))
	v.add_child(btns)


func _delete_account() -> void:
	var res: Array = await Net.delete_account()
	if bool(res[0]):
		if main:
			main.toast("帳號及資料已成功刪除", UI.GOOD)
	else:
		if main:
			main.toast("刪除帳號失敗：" + str(res[1]), UI.BAD)
	_update_auth_card()


func _check_url_demo_code() -> void:
	if Net.is_logged_in():
		return
	var code: String = Net.check_and_consume_url_demo_code()
	if code != "":
		var res: Array = await Net.submit_demo_code(code)
		if bool(res[0]):
			if main:
				main.toast("已啟用 AI 體驗模式", UI.GOOD)
		else:
			if main:
				main.toast(str(res[1]), UI.BAD)


func _open_demo_dialog() -> void:
	DemoCodeDialog.open(self, func():
		if main:
			main.toast("已啟用 AI 體驗模式", UI.GOOD)
	)


func _save() -> void:
	var n: String = PlayerProfile.player_name if PlayerProfile.player_profile_created else (_name.text.strip_edges() if _name else Net.player_name)
	Net.player_name = n if n != "" else "顧問"
	if _server:
		Net.base_url = _server.text.strip_edges().trim_suffix("/")
	Net.save_prefs()


## 確認配置: one server bot per chosen sparring advisor, in order (their names show on every screen)
func _start_solo() -> void:
	_save()
	var bots: Array = PlayerProfile.sparring_levels()
	main.create_and_join(bots, true)


func _on_back() -> void:
	_save()
	if main and main.has_method("open_secretary_settings"):
		main.open_secretary_settings()


func _create_multi() -> void:
	_save()
	if not Net.is_logged_in():
		main.toast("多人連線需先登入", UI.BAD)
		return
	main.create_and_join([], false)


func _join() -> void:
	_save()
	var c: String = _code.text.strip_edges().to_upper() if _code else ""
	if c.length() != 5:
		main.toast("請輸入 5 碼房間代碼", UI.BAD)
		return
	if not Net.is_logged_in():
		main.toast("多人連線需先登入", UI.BAD)
		return
	main.join_room(c)


## Game instructions: one-screen mission brief (logo, four steps); detailed rules one click away
func _open_brief() -> void:
	var brief: Control = preload("res://scripts/ui/mission_brief.gd").new()
	brief.z_index = 90
	brief.closed.connect(func(): brief.queue_free())
	brief.details_requested.connect(func():
		brief.queue_free()
		_open_howto()
	)
	add_child(brief)


func _open_howto() -> void:
	if _howto == null:
		return
	_howto.visible = true
	if _howto.get_child_count() > 0:
		var p = _howto.get_child(0)
		if p is Control:
			UI.pop_in(p, 0.22)


func _close_howto() -> void:
	if _howto == null:
		return
	if _howto.get_child_count() > 0:
		var p = _howto.get_child(0)
		if p is Control:
			UI.pop_out(p, func(): if is_instance_valid(_howto): _howto.visible = false, 0.18)
			return
	_howto.visible = false


func _build_howto() -> Control:
	var portrait: bool = UI.is_portrait()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.visible = false

	var p := UI.panel(UI.PANEL, 18, 14 if UI.is_phone_portrait() else (20 if portrait else 28))
	p.set_anchors_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 10 if UI.is_phone_portrait() else (20 if portrait else 100)
	p.offset_right = -10 if UI.is_phone_portrait() else (-20 if portrait else -100)
	p.offset_top = 12 if UI.is_phone_portrait() else (24 if portrait else 36)
	p.offset_bottom = -12 if UI.is_phone_portrait() else (-24 if portrait else -36)
	dim.add_child(p)

	var v := UI.vbox(10 if UI.is_phone_portrait() else 12)
	p.add_child(v)

	var head := UI.hbox(8)
	var title_lbl := UI.label("遊戲說明", 22 if UI.is_phone_portrait() else 26, UI.ACCENT_2)
	head.add_child(title_lbl)
	head.add_child(UI.spacer())
	var page_lbl := UI.label("1 / 6", 14, UI.MUTED)
	head.add_child(page_lbl)
	var close_btn := UI.button("×", func(): _close_howto(), 16, UI.PANEL_2)
	close_btn.custom_minimum_size = Vector2(32, 32)
	head.add_child(close_btn)
	v.add_child(head)

	var body := UI.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll_body := UI.scroll(body)
	v.add_child(scroll_body)

	var img_rect := TextureRect.new()
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img_rect.custom_minimum_size = Vector2(0, 160 if UI.is_phone_portrait() else (220 if portrait else 260))
	body.add_child(img_rect)

	var step_title := UI.label("", 18 if UI.is_phone_portrait() else 20, UI.GOLD, true)
	body.add_child(step_title)

	var step_desc := UI.rich("", 14 if UI.is_phone_portrait() else 15)
	body.add_child(step_desc)

	# Bottom pagination navigation
	var nav := UI.hbox(8)
	var prev_btn: Button = null
	var next_btn: Button = null

	var current_step: Array = [0]
	var steps_data: Array = [
		{
			"img": "res://assets/howto/01-roll-dice.webp",
			"title": "步驟 1：擲骰推進人生棋盤",
			"desc": "[b]你是新人保險顧問。[/b]擲骰前進，棋盤 24 格落點會解鎖不同事件：遇見新客戶、人生事件、市場波動或合規測驗。\n目標不是賣最多，而是把客戶服務好。"
		},
		{
			"img": "res://assets/howto/02-investigate.webp",
			"title": "步驟 2：觀察生活線索",
			"desc": "[b]理解一個人的生活脈絡。[/b]在客戶的生活場景中找出 3 個真正的需求線索。\n小心不是每個物件都是財務風險，有 1 個是無關的干擾物。"
		},
		{
			"img": "res://assets/howto/03-dialogue.webp",
			"title": "步驟 3：深度需求訪談",
			"desc": "[b]問對問題比背商品重要。[/b]5 個問題只能問 3 題，順序與時機會影響客戶信任。\n另有 1 次 [b]AI 自由提問[/b] 機會，用你自己的話發掘客戶沒明說的需求。"
		},
		{
			"img": "res://assets/howto/04-allocation.webp",
			"title": "步驟 4：有限資源方案配置",
			"desc": "[b]資源有限，必須取捨。[/b]將 10 枚資源幣分配給緊急預備、風險保障與目標成長。\n再依需求挑選 2–3 張功能型保障卡，避免過度配置造成預算壓力。"
		},
		{
			"img": "res://assets/howto/05-validation.webp",
			"title": "步驟 5：90 天未來壓力驗證",
			"desc": "[b]方案必須經得起未來檢驗。[/b]回應客戶異議後，模擬 90 天內三個人生事件連續發生。\n檢驗你的配置能承接多少衝擊，是否替客戶保留了夢想與選擇。"
		},
		{
			"img": "",
			"title": "棋盤格子圖例與多人競猜",
			"desc": "[color=#00a36c]◎ 客戶格[/color]：進行完整面談　[color=#e76f51]✚ 人生事件[/color]：考驗已簽約客戶\n[color=#7aa2ff]↗ 市場快訊[/color]：全體市場波動　[color=#9d7bea]✓ 合規訓練[/color]：合規小測驗\n[color=#ff6b6b]⚠ 合規稽核[/color]：抽查適合度　[color=#2fd197]♥ 轉介紹[/color]：滿意客戶介紹（信任 +10）\n[color=#8ecae6]◇ 研討會[/color]：AI 教練建議　[color=#f2c14e]★ 季度結算[/color]：滿意續約、不滿意解約\n\n[b]多人觀摩競猜[/b]：輪到其他顧問時可即時觀摩並預測其評級，猜中聲望 +2！"
		}
	]

	var update_page: Callable = func(idx: int) -> void:
		current_step[0] = clampi(idx, 0, steps_data.size() - 1)
		var cur_data: Dictionary = steps_data[current_step[0]]
		page_lbl.text = "%d / %d" % [current_step[0] + 1, steps_data.size()]
		step_title.text = str(cur_data.get("title", ""))
		step_desc.text = str(cur_data.get("desc", ""))

		var img_path: String = str(cur_data.get("img", ""))
		if img_path != "" and ResourceLoader.exists(img_path):
			img_rect.texture = load(img_path)
			img_rect.visible = true
		else:
			img_rect.visible = false

		if prev_btn != null:
			prev_btn.disabled = current_step[0] <= 0
		if next_btn != null:
			if current_step[0] >= steps_data.size() - 1:
				next_btn.text = "知道了 ✓"
			else:
				next_btn.text = "下一步 ▶"

	prev_btn = UI.button("◀ 上一步", func(): update_page.call(int(current_step[0]) - 1), 14, UI.PANEL_2)
	nav.add_child(prev_btn)
	nav.add_child(UI.spacer())
	var reset_tut_btn := UI.button("重看教學", func():
		Tutorial.reset_all()
		if main and main.has_method("toast"):
			main.toast("已重置教學，下次面談將重新引導", UI.GOOD)
	, 13, UI.PANEL_2)
	nav.add_child(reset_tut_btn)
	nav.add_child(UI.spacer())
	next_btn = UI.button("下一步 ▶", func():
		if int(current_step[0]) >= steps_data.size() - 1:
			_close_howto()
		else:
			update_page.call(int(current_step[0]) + 1)
	, 14, UI.ACCENT)
	nav.add_child(next_btn)
	v.add_child(nav)

	update_page.call(0)
	return dim


func _on_pwa_update_avail() -> void:
	if not AutomationBridge.is_active():
		_check_pwa_update()


func _check_pwa_update() -> void:
	if not OS.has_feature("web") or AutomationBridge.is_active() or Engine.is_editor_hint():
		return
	_pwa_cb = JavaScriptBridge.create_callback(func(args: Array):
		if args.is_empty():
			return
		var ver_str: String = str(args[0])
		if ver_str != "":
			# Newer build found: update silently instead of asking (the button stays hidden)
			_target_version = ver_str
			_on_pwa_btn_pressed()
	)
	var win = JavaScriptBridge.get_interface("window")
	if win:
		win.__iq_pwa_cb = _pwa_cb
		JavaScriptBridge.eval("""(function() {
			try {
				var cur = window.IQ_BUILD || '';
				if (!cur) return;
				var updating = sessionStorage.getItem('iq-updating');
				if (updating && updating === cur) {
					sessionStorage.removeItem('iq-updating');
					updating = null;
				}
				fetch('version.json', { cache: 'no-store' })
					.then(function(r) { return r.ok ? r.json() : null; })
					.then(function(d) {
						if (!d || !d.version) return;
						var sVer = d.version;
						if (sVer !== cur) {
							if (sessionStorage.getItem('iq-updating') === sVer) return;
							if (window.__iq_pwa_cb) window.__iq_pwa_cb(sVer);
						} else {
							if ('serviceWorker' in navigator) {
								navigator.serviceWorker.getRegistration().then(function(reg) {
									if (reg && reg.waiting) reg.waiting.postMessage('claim');
								});
							}
						}
					})
					.catch(function() {});
			} catch(e) {}
		})()""", true)


func _on_pwa_btn_pressed() -> void:
	if not OS.has_feature("web") or Engine.is_editor_hint():
		return
	if _pwa_btn:
		_pwa_btn.disabled = true
		_pwa_btn.text = "更新中…"
	JavaScriptBridge.eval("""(function(targetVer) {
		// Version-stamped navigation instead of reload, so the HTTP cache cannot serve the old page
		function reloadFresh() {
			try { var u = new URL(location.href); if (targetVer) u.searchParams.set('v', targetVer); location.replace(u.toString()); }
			catch (e) { location.reload(); }
		}
		try {
			if (targetVer) sessionStorage.setItem('iq-updating', targetVer);
			if ('serviceWorker' in navigator) {
				navigator.serviceWorker.getRegistration().then(function(reg) {
					if (reg && reg.waiting) {
						reg.waiting.postMessage('update');
						// The service worker navigates every client itself on "update"; only reload if that never happens
						setTimeout(function() { reloadFresh(); }, 5000);
					} else {
						reloadFresh();
					}
				}).catch(function() { reloadFresh(); });
			} else {
				reloadFresh();
			}
		} catch(e) {
			reloadFresh();
		}
	})(%s)""" % JSON.stringify(_target_version), true)


func _check_saved_seat() -> void:
	if Net.saved_seat.is_empty() or Engine.is_editor_hint():
		return
	var room: String = str(Net.saved_seat.get("room", "")).strip_edges().to_upper()
	var p_id: String = str(Net.saved_seat.get("playerId", "")).strip_edges()
	if room == "" or p_id == "":
		Net.saved_seat = {}
		Net.save_prefs()
		return

	_seat_check_gen += 1
	var cur_gen := _seat_check_gen
	var result: Array = await Net.check_saved_room(room, p_id)
	if cur_gen != _seat_check_gen:
		return
	var status: String = result[0]
	if status == "valid":
		if _resume_container and is_instance_valid(_resume_container):
			UI.clear(_resume_container)
			var resume_btn := UI.button("回到進行中的房間 %s" % room, func(): _save(); main.resume_seat(), 14, UI.GOLD.darkened(0.35))
			_resume_container.add_child(resume_btn)
	elif status == "invalid":
		Net.saved_seat = {}
		Net.save_prefs()
		if _resume_container and is_instance_valid(_resume_container):
			UI.clear(_resume_container)
	elif status == "network_error":
		if _resume_container and is_instance_valid(_resume_container):
			UI.clear(_resume_container)
