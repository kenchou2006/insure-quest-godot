extends SceneTree
## Run: godot --headless --path client --script res://tests/onboarding_smoke.gd
## 封面 → 新人顧問報到 → 選擇培訓秘書 → 培訓方式 on the real main scene, with real clicks:
## six looks, the name check, token colours and the saved profile; every 返回 (unconfirmed
## choices kept); 本局對練配置 (1～3 模擬顧問, the player card stays); multiplayer without
## sparring advisors; 離開培訓; and the player's portrait, name and level on later screens.

const FEMALE := preload("res://assets/startup/advisor_f.png")
const MALE := preload("res://assets/startup/advisor_m.png")
const FILES := ["user://player_profile.cfg", "user://training_secretary.cfg", "user://prefs.json", "user://quest_profile.cfg"]

var failures := 0
var main: Control
var saved: Dictionary = {}
var pp: Node
var net: Node
var gs: Node
var _restored := false


class LeaveStub extends Node:
	var calls: Array = []
	func leave_training(keep: bool) -> void:
		calls.append(keep)


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	call_deferred("_run")


## The player's own files come back even when a step stalls or errors out
func _restore() -> void:
	if _restored:
		return
	_restored = true
	for path in saved:
		if saved[path] == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(saved[path])
			f.close()


func _watchdog() -> void:
	await create_timer(150.0).timeout
	printerr("FAIL: watchdog — the test stalled")
	_restore()
	quit(1)


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _frames(n := 3) -> void:
	for i in range(n):
		await process_frame


func _move(pos: Vector2) -> void:
	var w: Vector2 = root.get_final_transform() * pos
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	root.push_input(m)
	await process_frame


func _click(pos: Vector2) -> void:
	await _move(pos)
	var w: Vector2 = root.get_final_transform() * pos
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = w
		e.global_position = w
		root.push_input(e)
		await process_frame


func _type(t: String) -> void:
	for i in range(t.length()):
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = t.unicode_at(i)
		root.push_input(e)
		await process_frame
		var up := e.duplicate() as InputEventKey
		up.pressed = false
		root.push_input(up)
		await process_frame


## Like a player: point at the control (it must take the hover and show a hand), then click
func _press(c: Control, what: String, cursor := true) -> void:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		check(false, "%s on screen" % what)
		return
	var p := c.get_global_rect().get_center()
	check(root.get_visible_rect().has_point(p), "%s inside the screen (%s)" % [what, str(c.get_global_rect())])
	await _move(p)
	var hov := root.gui_get_hovered_control()
	check(hov == c or (hov != null and c.is_ancestor_of(hov)), "%s takes the click (hovered %s)" % [what, str(hov)])
	if cursor:
		check(c.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "%s shows a pointer cursor" % what)
	await _click(p)


func _kind() -> String:
	return str(main.get_screen_kind())


func _screen() -> Control:
	return main.get("_screen")


## Waits for the screen to be switched in and the veil lifted
func _until(kind: String, timeout := 6.0) -> bool:
	var t := 0.0
	while t < timeout:
		var veil: Control = main.get("_veil")
		if _kind() == kind and (veil == null or not veil.visible):
			await _wait(0.45)
			return true
		await _wait(0.05)
		t += 0.05
	return false


func _node(n: String, under: Node = null) -> Control:
	var r: Node = under if under != null else _screen()
	if r == null:
		return null
	for c in r.find_children(n, "Control", true, false):
		if (c as Control).is_visible_in_tree():
			return c
	return null


func _all_text(n: Node) -> String:
	var out := ""
	for c in n.find_children("*", "", true, false):
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is Label:
			out += (c as Label).text + " "
		elif c is Button:
			out += (c as Button).text + " "
		elif c is LineEdit:
			out += (c as LineEdit).text + " "
	return out


## Aly / Kevin portraits shown anywhere right now
func _secretary_portraits(n: Node) -> int:
	var found := 0
	for c in n.find_children("*", "TextureRect", true, false):
		var tr := c as TextureRect
		if not tr.is_visible_in_tree():
			continue
		var t: Texture2D = tr.texture
		if t is AtlasTexture:
			t = (t as AtlasTexture).atlas
		if t == FEMALE or t == MALE:
			found += 1
	return found


func _skip_cover_intro() -> Button:
	var cover := _screen()
	var enter: Button = cover.get("_enter")
	var t := 0.0
	while enter.mouse_filter != Control.MOUSE_FILTER_STOP and t < 10.0:
		await _click(Vector2(640, 120))
		await _wait(0.3)
		t += 0.3
	await _wait(0.3)
	return enter


func _cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(pp.PATH)
	return cfg


func _close_greeting() -> void:
	var g: Control = main.get("_guide")
	await _wait(1.0)
	if g.call("is_open"):
		var ov: Control = g.get("_overlay")
		var shade: Control = ov.get("_shade")
		check(ov.visible and shade.mouse_filter == Control.MOUSE_FILTER_STOP, "secretary focus mask takes the clicks while open")
		var skip: Variant = ov.get("_skip")
		if skip is Button and (skip as Button).is_visible_in_tree():
			await _press(skip, "略過導覽", false)
		else:
			g.call("_close_modal", true)
		await _wait(0.5)
		if g.call("is_open"):
			g.call("_close_modal", true)
			await _wait(0.3)
		check(not ov.visible and ov.mouse_filter == Control.MOUSE_FILTER_IGNORE, "focus mask released after the greeting")


func _run() -> void:
	pp = root.get_node("PlayerProfile")
	net = root.get_node("Net")
	gs = root.get_node("GameState")
	for path in FILES:
		saved[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_watchdog()
	pp.reset_for_tests()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(await _until("startup"), "cover first (%s)" % _kind())

	# 1. Cover → 新人顧問報到 (no profile yet)
	var enter := await _skip_cover_intro()
	await _press(enter, "進入顧問培訓", false)
	check(await _until("onboarding"), "cover → 新人顧問報到 (%s)" % _kind())
	var page := _screen()
	var text := _all_text(page)
	check(text.contains("新人顧問") and text.contains("報到"), "title 新人顧問報到")
	check(text.contains("建立你的顧問檔案，系統將記錄培訓成長與決策表現。"), "onboarding subtitle")
	check(_secretary_portraits(main) == 0 and not _all_text(main).contains("Aly") and not _all_text(main).contains("Kevin"), "no Aly or Kevin before a secretary is chosen")
	check(not _all_text(main).contains("Lv.3"), "no placeholder Lv.3 before 報到")
	check((_node("StartLevel") as Label).text == "Lv.1 新人顧問", "initial level Lv.1 新人顧問")
	check(text.contains("外觀不影響培訓評分"), "appearance note")
	var back := _node("BackButton")
	check(back != null and (back as Button).text == "返回遊戲封面", "返回遊戲封面 top-left")
	check(back != null and back.size.x >= 48 and back.size.y >= 48, "back button at least 48×48")

	# 2. All six looks
	for i in range(1, 7):
		var id := "player_0%d" % i
		var card := _node("Avatar_" + id)
		await _press(card, "形象 0%d" % i)
		await _wait(0.25)
		check(str(page.get("_avatar_id")) == id, "形象 0%d selected" % i)
		var tex: Texture2D = (_node("AvatarPreview") as TextureRect).texture
		check(tex != null and tex.resource_path == str(pp.avatar(id).path), "preview shows 形象 0%d" % i)
		var marked := 0
		for c in page.find_children("Avatar_*", "Button", true, false):
			if bool(c.get("_sel")):
				marked += 1
		check(marked == 1 and bool(card.get("_sel")), "one gold-framed look at a time")
		if i == 3:
			check((card.get("visual") as Control).position.y < -2.0, "hovered look lifts")
	check(pp.AVATARS.slice(0, 3).all(func(a: Dictionary) -> bool: return a.gender == "female") and pp.AVATARS.slice(3).all(func(a: Dictionary) -> bool: return a.gender == "male"), "01–03 female, 04–06 male")

	# 3. Name check, colour, look
	var field := _node("AdvisorName") as LineEdit
	field.text = ""
	await _press(_node("ConfirmOnboarding"), "完成報到")
	await _wait(0.3)
	var err := page.find_child("NameError", true, false) as Label
	check(_kind() == "onboarding" and err.visible and err.text == "請輸入顧問名稱", "empty name: 請輸入顧問名稱 (%s)" % err.text)
	await _press(field, "顧問名稱", false)
	await _type("安")
	check(field.text == "安", "typing into the name field (%s)" % field.text)
	await _press(_node("ConfirmOnboarding"), "完成報到")
	await _wait(0.2)
	check(_kind() == "onboarding" and err.visible and err.text.contains("2～10"), "one character: 2～10 字 (%s)" % err.text)
	await _type("小安小安小安小安小安小安")
	check(field.text.length() == 10, "name stops at 10 characters (%d)" % field.text.length())
	field.text = ""
	await _type("林小安")
	check(field.text == "林小安" and not err.visible, "valid name clears the error")
	for key in ["blue", "gold", "red", "green", "blue"]:
		await _press(_node("Token_" + key), "棋子 " + key)
		check(str(page.get("_token")) == key, "token %s selected" % key)
	await _press(_node("Avatar_player_05"), "形象 05")
	check(not pp.player_profile_created, "nothing saved before 完成報到")

	# Back to the cover keeps the draft; the cover leads to 報到 again
	await _press(_node("BackButton"), "返回遊戲封面")
	check(await _until("startup"), "返回遊戲封面 → cover (%s)" % _kind())
	enter = await _skip_cover_intro()
	await _press(enter, "進入顧問培訓", false)
	check(await _until("onboarding"), "cover → 報到 again without a profile")
	page = _screen()
	check((_node("AdvisorName") as LineEdit).text == "林小安" and str(page.get("_avatar_id")) == "player_05" and str(page.get("_token")) == "blue", "unconfirmed name, look and colour kept")

	# 4. 完成報到 → saved → 選擇培訓秘書
	await _press(_node("ConfirmOnboarding"), "完成報到，選擇培訓秘書")
	await _wait(0.1)
	check((page.find_child("LeaveFade", true, false) as Control).visible, "deep-green fade before the next page")
	check(await _until("secretary_setup"), "報到 → 選擇培訓秘書 (%s)" % _kind())
	var cfg := _cfg()
	check(bool(cfg.get_value("player", "player_profile_created", false)), "player_profile_created saved")
	check(str(cfg.get_value("player", "player_name", "")) == "林小安", "player_name saved")
	check(str(cfg.get_value("player", "player_avatar_id", "")) == "player_05", "player_avatar_id saved")
	check(str(cfg.get_value("player", "player_portrait_path", "")) == "res://assets/advisors/player_05.webp", "player_portrait_path saved")
	check(str(cfg.get_value("player", "player_token_color", "")) == "blue", "player_token_color saved")
	check(int(cfg.get_value("player", "advisor_level", 0)) == 1 and int(cfg.get_value("player", "advisor_xp", -1)) == 0, "advisor_level / advisor_xp saved")
	check(net.player_name == "林小安", "the advisor name is the name sent to rooms")

	# Secretary 返回 → 報到 (highlighted secretary kept), then on again
	var setup := _screen()
	var female: Control = null
	for c in setup.get("_cards"):
		if str(c.get("info").key) == "female":
			female = c
	await _press(female, "女性培訓秘書")
	await _wait(0.3)
	var sback: Control = setup.get("_back")
	check(sback != null and (sback as Button).text == "返回顧問報到", "secretary page: 返回顧問報到")
	await _press(sback, "返回顧問報到")
	check(await _until("onboarding"), "secretary → 報到 (%s)" % _kind())
	check((_node("AdvisorName") as LineEdit).text == "林小安", "報到 shows the saved name")
	await _press(_node("ConfirmOnboarding"), "完成報到")
	check(await _until("secretary_setup"), "報到 → secretary again")
	setup = _screen()
	var sel: int = setup.get("_selected")
	check(sel >= 0 and str(setup.get("_cards")[sel].get("info").key) == "female", "highlighted secretary kept")

	# 5. Secretary → the training-mode page
	await _press(setup.get("_confirm"), "確認秘書", false)
	check(await _until("menu"), "secretary → 培訓方式 (%s)" % _kind())
	await _close_greeting()
	var m := _screen()
	var mback: Control = m.get("_back")
	check(mback != null and mback.is_visible_in_tree() and (mback as Button).text == "返回選擇秘書", "training mode: 返回選擇秘書")
	check(m.get("_id_icon") is UI.RoundTex, "top-right shows the player portrait")
	var id_label: Label = m.get("_id_label")
	check(id_label.text.contains("林小安") and id_label.text.contains("Lv.1"), "top-right: name and real level (%s)" % id_label.text)
	check(not _all_text(main).contains("Lv.3"), "no placeholder Lv.3 on the training-mode page")

	# 6. 單人實戰 opens 本局對練配置, nothing starts
	var solo_opts: Control = m.get("_solo_opts")
	check(not solo_opts.visible, "sparring setup hidden at first")
	await _press(m.get("_solo_card").get("button"), "單人實戰")
	await _wait(0.45)
	check(solo_opts.visible, "單人實戰 opens 本局對練配置")
	check(_kind() == "menu" and net.room_code == "", "picking solo does not start the game")
	check((m.get("_solo_card").get("_tag_label") as Label).text == "已選擇", "solo card: 已選擇")
	check((m.get("_multi_card") as Control).modulate.r < 0.7, "multiplayer card dims")
	var count := _node("AdvisorCount", solo_opts) as Label
	check(count.text == "玩家 1 位 ＋ 模擬顧問 2／3", "count header (%s)" % count.text)
	var sp_text := _all_text(solo_opts)
	for s in ["沈知妍", "同理洞察型", "顧承宇", "數據配置型", "程雅寧", "合規策略型", "加入第三位", "林小安", "Lv.1 新人顧問", "單人實戰共 2～4 位顧問；你的會談計時只在你的回合進行。", "確認配置，開始單人實戰", "恢復初次建議"]:
		check(sp_text.contains(s), "sparring setup shows %s" % s)
	check(not sp_text.contains("電腦顧問") and not sp_text.contains("CPU"), "no 電腦顧問 / CPU names")
	check(solo_opts.get("selected") == ["shen", "gu"], "default 沈知妍 + 顧承宇 (%s)" % str(solo_opts.get("selected")))
	var cheng := _node("Advisor_cheng", solo_opts)
	check(absf((cheng.get("visual") as Control).modulate.r - 0.55) < 0.05, "unselected advisor at 55%")

	# 7. 1–3 advisors
	await _press(cheng, "程雅寧")
	await _wait(0.3)
	check(solo_opts.get("selected") == ["shen", "gu", "cheng"] and count.text.contains("3／3"), "third advisor added (%s)" % count.text)
	check((cheng.get("visual") as Control).modulate.r > 0.95, "selected advisor at full brightness")
	await _press(_node("Advisor_shen", solo_opts), "沈知妍")
	await _press(_node("Advisor_gu", solo_opts), "顧承宇")
	await _wait(0.3)
	check(solo_opts.get("selected") == ["cheng"] and count.text.contains("1／3"), "down to one advisor (%s)" % count.text)
	await _press(cheng, "程雅寧")
	await _wait(0.2)
	check(solo_opts.get("selected") == ["cheng"], "the last advisor cannot be removed")
	check((_node("SparringHint", solo_opts) as Label).text.contains("至少保留 1 位"), "at least one advisor: hint")

	# 8. The player card is fixed
	var pcard := _node("PlayerCard", solo_opts)
	check(not (pcard is BaseButton) and pcard.find_children("*", "BaseButton", true, false).is_empty(), "player card has no remove control")
	await _click(pcard.get_global_rect().get_center())
	check(pcard.is_visible_in_tree() and solo_opts.get("selected") == ["cheng"], "clicking the player card changes nothing")
	await _press(_node("ResetSparring", solo_opts), "恢復初次建議")
	check(solo_opts.get("selected") == ["shen", "gu"], "恢復初次建議 → 沈知妍 + 顧承宇")
	await _press(cheng, "程雅寧")
	# 確認配置 saves the line-up (the room itself is covered by hall_smoke and the live run)
	check(solo_opts.is_connected("confirmed", m.get("_start_solo")), "確認配置 starts the solo game")
	solo_opts.disconnect("confirmed", m.get("_start_solo"))
	var fired: Array = []
	solo_opts.connect("confirmed", func(): fired.append(true))
	await _press(_node("ConfirmSparring", solo_opts), "確認配置，開始單人實戰")
	check(fired.size() == 1, "確認配置 confirmed")
	check(pp.selected_simulated_advisors == ["shen", "gu", "cheng"] and pp.sparring_levels() == ["pro", "novice", "pro"], "line-up and bot levels")
	cfg = _cfg()
	check(cfg.get_value("sparring", "selected_simulated_advisors", []) == ["shen", "gu", "cheng"] and int(cfg.get_value("sparring", "simulated_advisor_count", 0)) == 3, "selected_simulated_advisors / simulated_advisor_count saved")

	# 9. 多人連線: no sparring advisors
	if net.is_logged_in():
		m.call("_pick_mode", "multi")
	else:
		await _press(m.get("_multi_card").get("button"), "多人連線")
	await _wait(0.45)
	check(not solo_opts.visible, "multiplayer hides 本局對練配置")
	check(_node("Advisor_shen", m) == null and _node("Advisor_cheng", m) == null, "no sparring advisor on the multiplayer path")
	check((m.get("_solo_card") as Control).modulate.r < 0.7, "solo card dims for multiplayer")
	if not net.is_logged_in():
		check((m.get("_id_pop") as Control).visible, "guest multiplayer asks to log in")

	# 10a. The top-right avatar re-opens the advisor profile (edit), 返回 keeps the draft
	if not (m.get("_id_pop") as Control).visible:
		await _press(m.get("_id_pill"), "玩家頭像")
		await _wait(0.2)
	var edit := _node("EditProfile", m)
	await _press(edit, "修改顧問檔案")
	check(await _until("onboarding"), "player avatar → 顧問檔案 (%s)" % _kind())
	page = _screen()
	check(str(page.get("mode")) == "edit" and (_node("BackButton") as Button).text == "返回培訓方式", "edit mode: 返回培訓方式")
	await _press(_node("Token_red"), "棋子 red")
	await _press(_node("BackButton"), "返回培訓方式")
	check(await _until("menu"), "edit 返回 → training mode")
	check(pp.player_token_color == "blue", "unconfirmed colour not saved")
	await _close_greeting()
	m = _screen()
	await _press(m.get("_id_pill"), "玩家頭像")
	await _wait(0.2)
	await _press(_node("EditProfile", m), "修改顧問檔案")
	check(await _until("onboarding"), "edit again")
	check(str(_screen().get("_token")) == "red", "unconfirmed colour kept for next time")
	await _press(_node("ConfirmOnboarding"), "儲存顧問檔案")
	check(await _until("menu"), "save → training mode")
	check(pp.player_token_color == "red" and str(_cfg().get_value("player", "player_token_color", "")) == "red", "new colour saved")
	await _close_greeting()

	# 10b. 返回選擇秘書, then the returning player: cover → secretary (no 報到)
	m = _screen()
	await _press(m.get("_back"), "返回選擇秘書")
	check(await _until("secretary_setup"), "training mode → secretary (%s)" % _kind())
	main.call("show_startup")
	check(await _until("startup"), "cover")
	enter = await _skip_cover_intro()
	await _press(enter, "進入顧問培訓", false)
	check(await _until("secretary_setup"), "returning player: cover → secretary (%s)" % _kind())

	# 10c. 離開培訓 after the board game started
	var leave_script: GDScript = load("res://scripts/quest/widgets/leave_dialog.gd")
	var stub := LeaveStub.new()
	root.add_child(stub)
	for want: Variant in [null, true, false]:
		var d: Control = leave_script.new(stub)
		root.add_child(d)
		await _wait(0.3)
		check(_all_text(d).contains("要離開本次培訓嗎？"), "leave dialog title")
		check(bool(gs.holds.get("leave_dialog", false)), "clock held while the dialog is open")
		var bname: String = {null: "StayInTraining", true: "SaveAndLeave", false: "AbandonTraining"}[want]
		await _press(_node(bname, d), bname)
		await _frames(2)
		check(not is_instance_valid(d) or d.is_queued_for_deletion(), "%s closes the dialog" % bname)
		check(not bool(gs.holds.get("leave_dialog", false)), "%s releases the clock" % bname)
	check(stub.calls == [true, false], "儲存並返回主畫面 keeps, 放棄本次培訓 abandons (%s)" % str(stub.calls))

	# 11. The player in the game: names, colours and portraits
	net.player_id = "p1"
	net.is_solo = true
	net.state = {"players": [
		{"id": "p1", "name": "林小安"},
		{"id": "b1", "name": "電腦顧問・安安（資深）", "isBot": true},
		{"id": "b2", "name": "電腦顧問・小賴（新人）", "isBot": true},
		{"id": "b3", "name": "電腦顧問・阿哲（資深）", "isBot": true},
	]}
	var ps: Array = net.state.players
	check(pp.display_name(ps[0]) == "林小安", "own name")
	check(pp.display_name(ps[1]) == "沈知妍" and pp.display_name(ps[2]) == "顧承宇" and pp.display_name(ps[3]) == "程雅寧", "bots shown as the chosen advisors")
	check(pp.localize("電腦顧問・小賴（新人） 抵達地產") == "顧承宇 抵達地產", "log lines use the advisor names")
	check(pp.player_color(ps[0], 0) == pp.TOKEN_COLORS.red.color, "own pawn in the chosen colour")
	var own_tex: Texture2D = pp.portrait_of(ps[0])
	check(own_tex != null and own_tex.resource_path == "res://assets/advisors/player_05.webp", "own portrait on the board")
	var header: Control = load("res://scripts/quest/widgets/game_header.gd").new(false)
	root.add_child(header)
	await _frames(2)
	var chip := header.get("player_chip") as Control
	check(chip.visible and _all_text(chip).contains("林小安") and _all_text(chip).contains("Lv.1 新人顧問"), "mission header shows the advisor (%s)" % _all_text(chip))
	header.queue_free()
	net.state = {}
	net.is_solo = false

	main.queue_free()
	stub.queue_free()
	await _frames(2)
	_restore()
	print("onboarding_smoke: ", "OK" if failures == 0 else "%d failure(s)" % failures)
	quit(1 if failures else 0)
