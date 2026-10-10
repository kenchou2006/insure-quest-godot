@tool
extends Control
## Main menu: name, member login (Google avatar and advisor level), solo practice, create/join multiplayer room, training records, illustrated game guide, settings (sound toggle, account deletion). Supports landscape/portrait adaptation and PWA update check.

const AutomationBridge := preload("res://scripts/automation.gd")

var main: Node
var _name: LineEdit
var _code: LineEdit
var _server: LineEdit
var _opponents := 2
var _level := "pro"
var _opp_label: Label
var _howto: Control
var _pwa_btn: Button
var _resume_container: VBoxContainer
var _pwa_cb: JavaScriptObject = null
var _target_version: String = ""
var _seat_check_gen: int = 0
var _root: BoxContainer
var _auth_card_container: VBoxContainer
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
	else:
		_build_ui()


func on_layout_changed(_is_portrait: bool) -> void:
	var cur_name: String = _name.text if _name else ""
	var cur_code: String = _code.text if _code else ""
	_build_ui()
	if _name and cur_name != "": _name.text = cur_name
	if _code and cur_code != "": _code.text = cur_code


func _build_ui() -> void:
	UI.clear(self)
	var portrait: bool = UI.is_portrait()
	_root = UI.vbox(0) if portrait else UI.hbox(0)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Key visual area
	var art := Control.new()
	if portrait:
		art.custom_minimum_size = Vector2(0, 175 if UI.is_phone_portrait() else 240)
	else:
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_stretch_ratio = 1.25
	art.clip_contents = true
	var img := TextureRect.new()
	img.texture = load("res://assets/title.jpg")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.add_child(img)

	# Left/bottom gradient overlay to ensure text readability while letting morning light shine
	var grad_rect := TextureRect.new()
	grad_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	var grad_tex := GradientTexture2D.new()
	if portrait:
		grad.set_color(0, Color(0.05, 0.14, 0.12, 0.82))
		grad.set_color(1, Color(0.05, 0.14, 0.12, 0.35))
		grad_tex.fill_from = Vector2(0.5, 1.0)
		grad_tex.fill_to = Vector2(0.5, 0.0)
	else:
		# Title text sits bottom-left: darken only the lower part so the morning light stays bright
		grad.set_color(0, Color(0.05, 0.14, 0.12, 0.85))
		grad.set_color(1, Color(0.05, 0.14, 0.12, 0.0))
		grad_tex.fill_from = Vector2(0.5, 1.0)
		grad_tex.fill_to = Vector2(0.5, 0.45)
	grad_tex.gradient = grad
	grad_tex.fill = GradientTexture2D.FILL_LINEAR
	grad_rect.texture = grad_tex
	grad_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.add_child(grad_rect)

	var title_box := UI.vbox(3 if UI.is_phone_portrait() else (4 if portrait else 6))
	if portrait:
		title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		title_box.alignment = BoxContainer.ALIGNMENT_CENTER
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		for s: String in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + s, 12 if UI.is_phone_portrait() else 16)
		margin.add_child(title_box)
		art.add_child(margin)
		title_box.add_child(UI.label("INSURE QUEST", 30 if UI.is_phone_portrait() else 36, UI.GOLD))
		title_box.add_child(UI.label("人生顧問局", 22 if UI.is_phone_portrait() else 26, UI.TEXT))
		title_box.add_child(UI.label("擲骰走過客戶的人生，練習用需求而不是商品說服人。", 13 if UI.is_phone_portrait() else 14, UI.MUTED, true))
	else:
		var is_phone_land: bool = UI.is_phone_landscape()
		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		var pad_l: int = 24 if is_phone_land else 48
		var pad_r: int = 16 if is_phone_land else 32
		var pad_b: int = 20 if is_phone_land else 36
		margin.add_theme_constant_override("margin_left", pad_l)
		margin.add_theme_constant_override("margin_right", pad_r)
		margin.add_theme_constant_override("margin_bottom", pad_b)
		margin.add_theme_constant_override("margin_top", 16)
		art.add_child(margin)

		title_box.alignment = BoxContainer.ALIGNMENT_END
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(title_box)

		var title_fs: int = 32 if is_phone_land else 54
		var sub_fs: int = 22 if is_phone_land else 40
		var desc1_fs: int = 13 if is_phone_land else 18
		var desc2_fs: int = 11 if is_phone_land else 14

		title_box.add_child(UI.label("INSURE QUEST", title_fs, UI.GOLD))
		title_box.add_child(UI.label("人生顧問局", sub_fs, UI.TEXT))
		title_box.add_child(UI.label("擲骰走過客戶的人生，練習用需求而不是商品說服人。", desc1_fs, UI.MUTED, true))
		title_box.add_child(UI.label("法國巴黎人壽 Cardif InsurHack｜1-1 保險大富翁・銷售與通路賦能", desc2_fs, UI.MUTED, true))
	_root.add_child(art)

	# Actions area
	var side := UI.panel(UI.PANEL, 0, 14 if UI.is_phone_portrait() else (20 if portrait else 32))
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(10 if UI.is_phone_portrait() else (12 if portrait else 14))
	side.add_child(UI.scroll(v))
	_root.add_child(side)

	# PWA update button
	_pwa_btn = UI.button("★ 有新版本，點此更新", _on_pwa_btn_pressed, 16, UI.GOLD)
	_pwa_btn.visible = false
	v.add_child(_pwa_btn)
	if OS.has_feature("web") and not AutomationBridge.is_active() and not Engine.is_editor_hint():
		_check_pwa_update()
		if not JavaScriptBridge.pwa_update_available.is_connected(_on_pwa_update_avail):
			JavaScriptBridge.pwa_update_available.connect(_on_pwa_update_avail)

	# Account / login status card
	for c in v.get_children():
		if c.name == "AuthCardPanel":
			v.remove_child(c)
			c.queue_free()
	var auth_card := UI.panel(UI.PANEL_2, 12, 10 if UI.is_phone_portrait() else 12)
	auth_card.name = "AuthCardPanel"
	_auth_card_container = UI.vbox(6)
	auth_card.add_child(_auth_card_container)
	v.add_child(auth_card)
	_update_auth_card()

	v.add_child(UI.label("顧問姓名", 15, UI.MUTED))
	_name = LineEdit.new()
	var default_name: String = Net.player_name
	if Net.is_logged_in():
		var acc_name: String = str(Net.get_user().get("name", "")).strip_edges()
		if acc_name != "" and (default_name == "顧問" or default_name == ""):
			default_name = acc_name
	_name.text = default_name
	_name.max_length = 12
	_name.placeholder_text = "輸入你的名字"
	_name.custom_minimum_size = Vector2(0, 44)
	v.add_child(_name)

	_resume_container = UI.vbox(0)
	v.add_child(_resume_container)
	_check_saved_seat()

	v.add_child(UI.label("單人練習（對電腦顧問）", 20, UI.TEXT))
	var opp := UI.hbox(8)
	opp.add_child(UI.label("對手", 15, UI.MUTED))
	opp.add_child(UI.button("－", func(): _opponents = max(0, _opponents - 1); _sync_opp(), 15, UI.PANEL_2))
	_opp_label = UI.label("", 16)
	opp.add_child(_opp_label)
	opp.add_child(UI.button("＋", func(): _opponents = min(3, _opponents + 1); _sync_opp(), 15, UI.PANEL_2))
	var lvl := OptionButton.new()
	lvl.add_item("資深顧問（示範正確做法）")
	lvl.add_item("新人顧問（常見錯誤）")
	lvl.add_item("混合")
	lvl.item_selected.connect(func(i: int): _level = ["pro", "novice", "mix"][i])
	# Let the dropdown shrink to the remaining width (ellipsized) instead of widening the whole menu on phones
	lvl.clip_text = true
	lvl.fit_to_longest_item = false
	lvl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lvl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opp.add_child(lvl)
	v.add_child(opp)
	_sync_opp()
	v.add_child(UI.button("▶ 開始單人練習", _start_solo, 20))

	v.add_child(HSeparator.new())
	v.add_child(UI.label("多人連線（2–4 人）", 20, UI.TEXT))
	if not Net.is_logged_in():
		v.add_child(UI.label("多人連線需先登入", 13, UI.MUTED))
	v.add_child(UI.button("建立多人房間", _create_multi, 18))
	var join := UI.hbox(8)
	_code = LineEdit.new()
	_code.placeholder_text = "房間代碼（5 碼）"
	_code.max_length = 5
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.text_submitted.connect(func(_t: String): _join())
	join.add_child(_code)
	_code.custom_minimum_size = Vector2(0, 44)
	join.add_child(UI.button("加入", _join, 18))
	v.add_child(join)

	v.add_child(HSeparator.new())
	var row := UI.hbox(8)
	row.add_child(UI.button("遊戲說明", func(): _open_howto(), 15, UI.PANEL_2))
	row.add_child(UI.button("培訓紀錄", func(): _save(); main.show_records(), 15, UI.PANEL_2))
	row.add_child(UI.button("設定", func(): _open_settings(), 15, UI.PANEL_2))
	v.add_child(row)

	if not Net.is_web():
		v.add_child(UI.label("伺服器位址（桌面版）", 13, UI.MUTED))
		_server = LineEdit.new()
		_server.text = Net.base_url
		_server.custom_minimum_size = Vector2(0, 44)
		v.add_child(_server)

	v.add_child(UI.label("情境與數值僅供教育訓練模擬；保障卡為功能概念，不對應任何實際保險商品，亦不構成保險或投資建議。", 12, UI.MUTED, true))

	_howto = _build_howto()
	add_child(_howto)


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
		name_lbl.text_overflow_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
		var h := UI.hbox(8)
		h.add_child(UI.label("訪客身分", 15, UI.MUTED))
		h.add_child(UI.spacer())
		if bool(Net.auth_config.get("google", true)):
			h.add_child(UI.button("Google 登入", _login_google, 14, UI.ACCENT))
		if bool(Net.auth_config.get("demo", false)):
			h.add_child(UI.button("評審體驗碼", _open_demo_dialog, 14, UI.GOLD))
		if bool(Net.auth_config.get("dev", false)):
			h.add_child(UI.button("測試登入", _login_dev, 14, UI.GOLD.darkened(0.3)))
		_auth_card_container.add_child(h)
		var guest_note := "訪客模式：單人練習在本機執行、AI 功能改用規則版、紀錄不保存，登入後可使用" if Net.local_available() else "訪客模式：AI 功能改用規則版、紀錄不保存，登入後可使用"
		_auth_card_container.add_child(UI.label(guest_note, 12, UI.MUTED, true))


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
	Net.google_sign_in()


func _login_dev() -> void:
	_save()
	var n: String = _name.text.strip_edges()
	if n == "": n = "測試顧問"
	var u: String = Net.base_url + "/api/auth/dev-login?name=" + n.uri_encode() + "&return=/"
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.location.href='" + u + "'")
	else:
		OS.shell_open(u)


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


## Settings: sound, and (when logged in) account deletion
func _open_settings() -> void:
	var m := _open_modal("SettingsDialog", "設定", UI.ACCENT_2)
	if m.is_empty():
		return
	var dim: Control = m[0]
	var v: VBoxContainer = m[1]

	v.add_child(UI.label("音效", 14, UI.MUTED))
	var sound_btn: Button = UI.button("音效：關" if Sound.is_muted() else "音效：開", Callable(), 15, UI.PANEL_2)
	sound_btn.pressed.connect(func():
		var muted: bool = Sound.toggle_mute()
		sound_btn.text = "音效：關" if muted else "音效：開"
	)
	v.add_child(sound_btn)

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
	for c in get_children():
		if c.name == "DemoCodeDialog":
			return
	var dim := ColorRect.new()
	dim.name = "DemoCodeDialog"
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)

	var p := UI.panel(UI.PANEL, 14, 18)
	var max_w: float = 340.0 if UI.is_phone_portrait() else 420.0
	p.custom_minimum_size = Vector2(max_w, 0)
	var v := UI.vbox(10)
	p.add_child(v)

	var head := UI.hbox(8)
	head.add_child(UI.label("輸入評審體驗碼", 18, UI.ACCENT_2))
	head.add_child(UI.spacer())
	var close_btn := UI.button("×", func(): dim.queue_free(), 16, UI.PANEL_2)
	close_btn.custom_minimum_size = Vector2(36, 36)
	head.add_child(close_btn)
	v.add_child(head)

	v.add_child(UI.label("輸入評審體驗碼即可啟用完整 AI 功能。", 13, UI.MUTED, true))

	var err_lbl := UI.label("", 13, UI.BAD, true)
	err_lbl.visible = false
	v.add_child(err_lbl)

	var submitting := false
	var on_submit := func(code_text: String):
		if submitting:
			return
		submitting = true
		err_lbl.visible = false
		var res: Array = await Net.submit_demo_code(code_text)
		submitting = false
		if not is_instance_valid(dim):
			return
		if bool(res[0]):
			dim.queue_free()
			if main:
				main.toast("已啟用 AI 體驗模式", UI.GOOD)
		else:
			err_lbl.text = str(res[1])
			err_lbl.visible = true

	var input_row := UI.text_input("輸入體驗碼（如 CARDIF-DEMO-2026）", on_submit, 40)
	var submit_btn = input_row.get_child(1) as Button
	if submit_btn:
		submit_btn.text = "進入"
	v.add_child(input_row)

	center.add_child(p)
	add_child(dim)


func _sync_opp() -> void:
	_opp_label.text = "%d 位" % _opponents if _opponents > 0 else "無（自主練習）"


func _save() -> void:
	var n: String = _name.text.strip_edges() if _name else ""
	Net.player_name = n if n != "" else "顧問"
	if _server:
		Net.base_url = _server.text.strip_edges().trim_suffix("/")
	Net.save_prefs()


func _start_solo() -> void:
	_save()
	var bots: Array = []
	for i: int in range(_opponents):
		bots.append(_level if _level != "mix" else (["pro", "novice"][i % 2]))
	main.create_and_join(bots, true)


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
			_target_version = ver_str
			if _pwa_btn and is_instance_valid(_pwa_btn):
				_pwa_btn.visible = true
				_pwa_btn.disabled = false
				_pwa_btn.text = "★ 有新版本，點此更新"
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
		try {
			if (targetVer) sessionStorage.setItem('iq-updating', targetVer);
			if ('serviceWorker' in navigator) {
				navigator.serviceWorker.getRegistration().then(function(reg) {
					if (reg && reg.waiting) {
						reg.waiting.postMessage('update');
						// The service worker navigates every client itself on "update"; only reload if that never happens
						setTimeout(function() { location.reload(); }, 5000);
					} else {
						location.reload();
					}
				}).catch(function() { location.reload(); });
			} else {
				location.reload();
			}
		} catch(e) {
			location.reload();
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
			var resume_btn := UI.button("回到進行中的房間 %s" % room, func(): _save(); main.resume_seat(), 18, UI.GOLD.darkened(0.35))
			_resume_container.add_child(resume_btn)
	elif status == "invalid":
		Net.saved_seat = {}
		Net.save_prefs()
		if _resume_container and is_instance_valid(_resume_container):
			UI.clear(_resume_container)
	elif status == "network_error":
		if _resume_container and is_instance_valid(_resume_container):
			UI.clear(_resume_container)
