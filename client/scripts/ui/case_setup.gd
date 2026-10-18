extends Control
## Pre-game training case, three steps on one overlay: ① 接受任務 → ② 看線索 → ③ 選工具 (the
## briefcase page relabels the steps 看線索 → 選工具 → 開始會談).
## The system assigns the client — a new advisor gets the tutorial client (1 unlocked); later runs
## take the least-practised unlocked case. Nothing is drawn at random and the player never picks
## the client: the same client is carried from the mission file to the clues page and the briefcase,
## then sent as {"type": "setup"}. game.gd removes this overlay once the server records the case.
## Unlock progress is read from the player's real records (cloud profile and/or this device).

signal setup_sent(payload: Dictionary)

const LineIcon := preload("res://scripts/ui/line_icon.gd")
const MissionFile := preload("res://scripts/ui/mission_file.gd")
const BriefcaseView := preload("res://scripts/ui/briefcase_view.gd")
const BriefcaseData := preload("res://scripts/briefcase_data.gd")
const BG := preload("res://assets/startup/loading.png")
const BG_SHADER := preload("res://assets/startup/hall_backdrop.gdshader")
const LOGO := preload("res://assets/startup/title.png")
const LOGO_CROP := Rect2(8, 10, 1944, 760)
const FONT := preload("res://assets/fonts/regular.tres")
const BOLD := preload("res://assets/fonts/bold.tres")

const C_BG := Color("#062F2A")
const C_CARD := Color("#0D4038")
const C_GREEN := Color("#00A86B")
const C_TEXT := Color("#F3F0E7")
const C_MUTED := Color("#AABCB5")
const C_GOLD := Color("#C6A15B")
const C_LINE := Color(1, 1, 1, 0.12)
const GRADES := ["S", "A", "B", "C", "D"]
const STEP_DEFS := [["1", "doc_check", "接受任務"], ["2", "search", "看線索"], ["3", "briefcase", "選工具"]]
const BRIEFCASE_STEP_DEFS := [["1", "search", "看線索"], ["2", "briefcase", "選工具"], ["3", "chat_user", "開始會談"]]

## From unlock_info(): unlocked ids, total, served map, assigned client, first_time
var info: Dictionary = {}
## The assigned client (same dictionary on every step)
var client: Dictionary = {}
var _step := 1
var _tools: Array[String] = []
var _size := 3
var _sent := false
var _accepting := false
var _ready_to_accept := false
var _k := 1.0

var _top: Panel
var _logo: TextureRect
var _title: Label
var _right: HBoxContainer
var _steps: Control
var _step_items: Array = []
var _page: Control
var _strip: PanelContainer
var _strip_slots: HBoxContainer
var _strip_count: Label
var _strip_sep: Control
var _strip_note: Label
var _card_label: Label
var _file: Control
var _accept: AcceptButton
var _codex_link: Button
var _briefcase: Control
## current_customer for the briefcase (data file merged with the server's case option)
var _customer: Dictionary = {}
var _confirm: Button
var _status: Label
var _mute_icon: Control
var _entry_said := false
## Areas the tutorial keeps bright
var _steps_area: Control
var _clue_sheet: Control
var _tool_grid: Control
var _codex_panel: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var s: Dictionary = Net.state
	_size = int(s.get("briefcaseSize", 3))

	var base := ColorRect.new()
	base.color = C_BG
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	var bg := TextureRect.new()
	bg.texture = BG
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BG_SHADER
	bg.material = mat
	add_child(bg)

	_build_top()
	_build_steps()
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)

	# Unlock progress: this device now, the cloud profile when logged in
	_compute_info([])
	_show_mission()
	resized.connect(_layout)
	_layout()
	if Net.is_logged_in():
		_load_profile()
	else:
		_ready_to_accept = true
		_accept.set_enabled(true)
		_say_entry()


# --- Unlock progress ---------------------------------------------------------------------------

## served: client id → {count, best}; unlocked: tutorial + served (codex order); total from the roster
static func unlock_info(case_options: Array, codex: Array, profile_clients: Array, attempts: Array) -> Dictionary:
	var served := {}
	for c: Dictionary in profile_clients:
		var n := int(c.get("served", 0))
		if n > 0:
			served[str(c.get("id", ""))] = {"count": n, "best": str(c.get("bestGrade", ""))}
	for rec: Dictionary in attempts:
		var data: Dictionary = rec.get("data", {}) if rec.get("data") is Dictionary else {}
		var interviews: Dictionary = data.get("interviews", {}) if data.get("interviews") is Dictionary else {}
		for sess: Variant in interviews.values():
			if not sess is Dictionary or str(sess.get("step", "")) != "result":
				continue
			var cid := str((sess.get("client", {}) as Dictionary).get("id", "")) if sess.get("client") is Dictionary else ""
			if cid == "":
				continue
			var res: Dictionary = sess.get("result", {}) if sess.get("result") is Dictionary else {}
			var cur: Dictionary = served.get(cid, {"count": 0, "best": ""})
			# Cloud counts already include synced games; only add what the profile does not know
			if profile_clients.is_empty():
				cur.count = int(cur.count) + 1
			cur.best = _better(str(cur.best), str(res.get("grade", "")))
			served[cid] = cur
	var tutorial: Dictionary = {}
	for c: Dictionary in case_options:
		if str(c.get("difficulty", "")) == "入門":
			tutorial = c
			break
	if tutorial.is_empty() and not case_options.is_empty():
		tutorial = case_options[0]
	var unlocked: Array = []
	if not tutorial.is_empty():
		unlocked.append(str(tutorial.get("id", "")))
	var roster: Array = codex if not codex.is_empty() else profile_clients
	for c: Dictionary in roster:
		var id := str(c.get("id", ""))
		if served.has(id) and not unlocked.has(id):
			unlocked.append(id)
	for id: String in served:
		if not unlocked.has(id):
			unlocked.append(id)
	var total := roster.size() if not roster.is_empty() else maxi(case_options.size(), unlocked.size())
	var first_time := served.is_empty()
	var assigned := tutorial
	if not first_time:
		var best_n := 1 << 30
		for c: Dictionary in case_options:
			var id := str(c.get("id", ""))
			if not unlocked.has(id):
				continue
			var n := int((served.get(id, {"count": 0}) as Dictionary).get("count", 0))
			if n < best_n:
				best_n = n
				assigned = c
	return {"unlocked": unlocked, "total": total, "served": served, "assigned": assigned, "first_time": first_time}


static func _better(a: String, b: String) -> String:
	if a == "":
		return b
	if b == "":
		return a
	var ia := GRADES.find(a)
	var ib := GRADES.find(b)
	if ia == -1:
		return b
	if ib == -1:
		return a
	return a if ia <= ib else b


func _compute_info(profile_clients: Array) -> void:
	var s: Dictionary = Net.state
	info = unlock_info(s.get("caseOptions", []), s.get("codex", []), profile_clients, Net.local_training_attempts())
	client = info.get("assigned", {})


func _load_profile() -> void:
	_accept.set_enabled(false)
	var done := false
	# Never wait on the network for more than 3 s; the device record is used meanwhile
	get_tree().create_timer(3.0).timeout.connect(func():
		if not done and is_instance_valid(self):
			done = true
			_ready_to_accept = true
			_accept.set_enabled(true)
			_say_entry()
	)
	var res: Array = await Net.fetch_profile()
	if done or not is_instance_valid(self) or _accepting:
		return
	done = true
	if bool(res[0]) and res[1] is Dictionary:
		_compute_info((res[1] as Dictionary).get("clients", []))
		_show_mission()
		_layout()
	_ready_to_accept = true
	_accept.set_enabled(true)
	_say_entry()


# --- Secretary ---------------------------------------------------------------------------------

func _secretary() -> Control:
	var main: Node = get_parent().get("main") if get_parent() else null
	if main and main.has_method("secretary_guide"):
		return main.secretary_guide()
	return null


## Names the state; the secretary picks the lines, portrait and voice (and plays each state once).
## First-time teaching runs as the 強制聚焦導覽, keeping these elements bright.
func _say(states: Array, modal := true) -> void:
	var g := _secretary()
	if g == null or not g.has_method("show_states"):
		return
	var targets := {
		"training_entry": [_steps_area],
		"first_assignment": [_file, _accept],
		"later_matching": [_file, _accept],
		"clue_review": [_clue_sheet],
		"tool_selection": [_tool_grid],
		"meeting_ready": [_confirm],
		"locked_client_info": [_codex_panel],
	}
	g.show_states(states, targets, modal)


func _say_entry() -> void:
	if _entry_said:
		return
	_entry_said = true
	var later := (info.get("unlocked", []) as Array).size() >= 2
	_say(["training_entry", "later_matching" if later else "first_assignment"])


# --- Top bar & steps ---------------------------------------------------------------------------

func _build_top() -> void:
	_top = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_BG, 0.88)
	sb.border_width_bottom = 1
	sb.border_color = Color(C_GOLD, 0.28)
	_top.add_theme_stylebox_override("panel", sb)
	add_child(_top)
	_logo = TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = LOGO
	at.region = LOGO_CROP
	_logo.texture = at
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(_logo)
	_title = _label("", 18, C_TEXT)
	_title.add_theme_font_override("font", BOLD)
	_top.add_child(_title)
	_right = HBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	_top.add_child(_right)
	var who := "訪客"
	if Net.is_logged_in():
		var lv: Dictionary = Net.get_level()
		who = "Lv.%d" % int(lv.get("level", 1)) if not lv.is_empty() else "已登入"
	var pill := _top_item("user", "%s｜%s" % [who, Net.player_name if Net.player_name != "" else "顧問"], Callable())
	pill.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_right.add_child(pill)
	_right.add_child(_top_item("gear", "設定", _open_settings))
	_right.add_child(_top_item("doc", "培訓紀錄", _open_records))
	var snd := _top_item("speaker_off" if MusicManager.muted else "speaker", "音效", Callable())
	_mute_icon = snd.get_node("Row/Icon")
	snd.pressed.connect(func():
		MusicManager.set_muted(not MusicManager.muted)
		_mute_icon.set("kind", "speaker_off" if MusicManager.muted else "speaker")
		_mute_icon.queue_redraw()
	)
	_right.add_child(snd)


func _top_item(icon: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic: Control = LineIcon.new(icon, C_GOLD if icon != "user" else C_TEXT, 1.8)
	ic.name = "Icon"
	ic.custom_minimum_size = Vector2(20, 20)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := _label(text, 14, C_TEXT)
	row.add_child(l)
	b.add_child(row)
	row.position = Vector2(8, 8)
	_fit_to_row(b, row, Vector2(16, 16))
	if cb.is_valid():
		b.pressed.connect(cb)
	b.mouse_entered.connect(func(): l.add_theme_color_override("font_color", C_GOLD))
	b.mouse_exited.connect(func(): l.add_theme_color_override("font_color", C_TEXT))
	return b


func _build_steps() -> void:
	_steps = Control.new()
	_steps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_steps)
	_steps_area = Control.new()
	_steps_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steps.add_child(_steps_area)
	var defs := STEP_DEFS
	for i in range(defs.size()):
		var item := StepItem.new(defs[i][0], defs[i][1], defs[i][2])
		_steps.add_child(item)
		_step_items.append(item)
		if i < defs.size() - 1:
			var chev: Control = LineIcon.new("chevron_r", Color(C_MUTED, 0.6), 1.8)
			chev.name = "Chev%d" % i
			_steps.add_child(chev)
	_sync_steps()


func _sync_steps() -> void:
	# Briefcase page: clues done, choosing tools now, the meeting next
	var briefcase := _step >= 3
	var defs: Array = BRIEFCASE_STEP_DEFS if briefcase else STEP_DEFS
	for i in range(_step_items.size()):
		var it: StepItem = _step_items[i]
		it.set_def(defs[i][0], defs[i][1], defs[i][2])
		var cur := 2 if briefcase else _step
		it.set_state("active" if i + 1 == cur else ("done" if i + 1 < cur else "todo"))


# --- Step 1: accept the assigned training file -------------------------------------------------

func _show_mission() -> void:
	UI.clear(_page)
	_strip = PanelContainer.new()
	_strip.add_theme_stylebox_override("panel", _panel_style(Color(C_BG, 0.82)))
	_page.add_child(_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_strip.add_child(row)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var h1 := _label("客戶圖鑑", 20, C_TEXT)
	h1.add_theme_font_override("font", BOLD)
	head.add_child(h1)
	head.add_child(_label("｜", 18, Color(C_MUTED, 0.6)))
	head.add_child(_label("已解鎖", 18, C_TEXT))
	_strip_count = _label("%d／%d" % [(info.get("unlocked", []) as Array).size(), int(info.get("total", 0))], 22, C_GOLD)
	_strip_count.add_theme_font_override("font", BOLD)
	head.add_child(_strip_count)
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(head)
	_strip_slots = HBoxContainer.new()
	_strip_slots.add_theme_constant_override("separation", 10)
	_strip_slots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_strip_slots)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.16)
	sep.custom_minimum_size = Vector2(1, 34)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sep)
	_strip_sep = sep
	var note := _label("完成培訓任務，逐步解鎖更多客戶", 15, C_MUTED)
	_strip_note = note
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	note.clip_text = true
	row.add_child(note)
	_fill_slots(8)

	var first := bool(info.get("first_time", true))
	_title.text = "單人實戰｜首次培訓" if first else "單人實戰｜培訓任務"
	_card_label = _label("首次培訓任務｜指定客戶" if first else "本次培訓任務｜指定客戶", 16, C_GOLD)
	_card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.add_child(_card_label)
	_file = MissionFile.new()
	_page.add_child(_file)
	_file.set_client(client)
	_file.unlocked.connect(func(): _go_step(2))
	_accept = AcceptButton.new("接受首次任務" if first else "接受培訓任務")
	_accept.activated.connect(_on_accept)
	_accept.set_enabled(_ready_to_accept)
	_page.add_child(_accept)
	_codex_link = _link_button("查看客戶圖鑑", _open_codex)
	_page.add_child(_codex_link)


## Unlocked portraits first, then dark silhouettes with a lock (up to `slots`)
func _fill_slots(slots: int) -> void:
	UI.clear(_strip_slots)
	var unlocked: Array = info.get("unlocked", [])
	var total := int(info.get("total", 0))
	var names := {}
	for c: Dictionary in Net.state.get("codex", []):
		names[str(c.get("id", ""))] = str(c.get("name", ""))
	for c: Dictionary in Net.state.get("caseOptions", []):
		names[str(c.get("id", ""))] = str(c.get("name", ""))
	var shown := mini(slots, maxi(total, unlocked.size()))
	for i in range(shown):
		if i < unlocked.size():
			var id := str(unlocked[i])
			var av := Portraits.create_avatar(id, str(names.get(id, "")), 44)
			av.custom_minimum_size = Vector2(44, 44)
			_strip_slots.add_child(av)
		else:
			_strip_slots.add_child(LockedSlot.new())


func _on_accept() -> void:
	# Locks first: one accept only, no reselection
	if _accepting or not _ready_to_accept:
		return
	_accepting = true
	Sound.play("doc_confirm", self)
	_accept.set_loading("任務資料解鎖中…")
	_card_label.text = "正在開啟首次任務" if bool(info.get("first_time", true)) else "正在開啟培訓任務"
	_codex_link.disabled = true
	_codex_link.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_codex_link.modulate.a = 0.4
	_file.play_unlock()
	# Status line during the unlock animation: corner card, no lock
	_say(["dossier_unlocking"], false)
	# Safety: never stay on the file if an animation or image fails
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(self) and _step == 1:
			_go_step(2)
	)


# --- Step 2: clues for the same client ---------------------------------------------------------

func _go_step(n: int) -> void:
	if n <= _step:
		return
	_step = n
	_sync_steps()
	var build := func():
		UI.clear(_page)
		if n == 2:
			_show_clues()
		else:
			_show_tools()
		_layout()
		# After the page exists, so the tutorial can keep its clue sheet / tool grid bright
		_say(["clue_review"] if n == 2 else ["tool_selection"])
		if not UI.is_animation_disabled():
			_page.modulate.a = 0.0
			create_tween().tween_property(_page, "modulate:a", 1.0, 0.22)
	if UI.is_animation_disabled():
		build.call()
		return
	var tw := create_tween()
	tw.tween_property(_page, "modulate:a", 0.0, 0.14)
	tw.tween_callback(build)


func _show_clues() -> void:
	var c := client
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page.add_child(scroll)
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(wrap)
	var col := UI.vbox(16)
	wrap.add_child(col)
	var head := _label("系統指定客戶｜線索整理", 16, C_GOLD)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var body: BoxContainer = UI.vbox(14) if UI.is_portrait() else UI.hbox(18)
	col.add_child(body)

	# Client card: portrait, name, age, job, tag
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(Color(C_CARD, 0.94), 18))
	card.custom_minimum_size = Vector2(260, 0)
	var cv := UI.vbox(10)
	card.add_child(cv)
	var av := Portraits.create_avatar(str(c.get("id", "")), str(c.get("name", "")), 132)
	av.custom_minimum_size = Vector2(132, 132)
	av.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cv.add_child(av)
	var nm := _label(str(c.get("name", "")), 24, C_TEXT)
	nm.add_theme_font_override("font", BOLD)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(nm)
	var sub := _label("%d 歲・%s" % [int(c.get("age", 0)), str(c.get("job", ""))], 15, C_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	sub.custom_minimum_size = Vector2(228, 0)
	cv.add_child(sub)
	var tag := _label("%s｜難度 %s" % [str(c.get("tag", "")), str(c.get("difficulty", ""))], 14, C_GOLD)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(tag)
	body.add_child(card)

	# Clue sheet: family, income, budget, goal, background
	var sheet := PanelContainer.new()
	_clue_sheet = sheet
	sheet.add_theme_stylebox_override("panel", _panel_style(Color(C_CARD, 0.94), 20))
	sheet.custom_minimum_size = Vector2(420 if not UI.is_portrait() else 0, 0)
	var sv := UI.vbox(12)
	sheet.add_child(sv)
	var rows := [
		["user", "家庭狀況", str(c.get("family", ""))],
		["chart", "收入狀況", str(c.get("incomeInfo", ""))],
		["doc", "預算", str(c.get("amount", "")) if str(c.get("amount", "")) != "" else "會談中確認"],
		["search", "本次目標", str(c.get("goal", ""))],
		["book", "客戶背景", str(c.get("intro", ""))],
	]
	var shown := 0
	for r: Array in rows:
		if str(r[2]).strip_edges() == "":
			continue
		if shown == 0 or shown == 3:
			var sec := _label("三項線索" if shown == 0 else "任務資料", 14, C_GOLD)
			sec.add_theme_font_override("font", BOLD)
			sv.add_child(sec)
		shown += 1
		var h := UI.hbox(12)
		var ic: Control = LineIcon.new(str(r[0]), C_GOLD, 1.8)
		ic.custom_minimum_size = Vector2(22, 22)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
		var k := _label(str(r[1]), 15, C_MUTED)
		k.custom_minimum_size = Vector2(70, 0)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(k)
		var v := _label(str(r[2]), 16, C_TEXT)
		v.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		v.custom_minimum_size = Vector2(300 if not UI.is_portrait() else 200, 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		sv.add_child(h)
	body.add_child(sheet)

	var next := AcceptButton.new("下一步：選工具", "briefcase")
	next.custom_minimum_size = Vector2(360, 60)
	next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.set_enabled(true)
	next.activated.connect(func():
		Sound.play("doc_confirm", self)
		_go_step(3)
	)
	col.add_child(next)


# --- Step 3: briefcase for the same client -----------------------------------------------------

func _show_tools() -> void:
	_customer = BriefcaseData.customer(client)
	_briefcase = BriefcaseView.new()
	_page.add_child(_briefcase)
	_tool_grid = _briefcase.briefcase_area
	_confirm = _briefcase.start_button
	_status = _briefcase.status_label
	_briefcase.set_customer(_customer)
	_briefcase.set_tools(_tool_list(), _size)
	_briefcase.toggle_requested.connect(_on_toggle_tool)
	_briefcase.start_requested.connect(_on_confirm)
	_sync_tools()


## The six tools from data, with status from this player's progress and the server's tool list
func _tool_list() -> Array:
	var progress := {"served": (info.get("served", {}) as Dictionary).size()}
	return BriefcaseData.tools(progress, Net.state.get("tools", []), _tools)


func _on_toggle_tool(id: String) -> void:
	if _sent:
		return
	if _tools.has(id):
		_tools.erase(id)
	elif _tools.size() < _size:
		_tools.append(id)
	else:
		return
	Sound.play("click", self)
	_sync_tools()


func _sync_tools() -> void:
	var ready_to_go := not client.is_empty() and _tools.size() == _size and not _sent
	if _briefcase and is_instance_valid(_briefcase):
		_briefcase.set_sending(_sent)
		_briefcase.set_selected(Array(_tools))
	_confirm.disabled = not ready_to_go
	if _confirm.has_method("refresh_state"):
		_confirm.refresh_state()
	if ready_to_go:
		_say(["meeting_ready"])


func _on_confirm() -> void:
	if client.is_empty() or _tools.size() != _size or _sent:
		return
	_sent = true
	_sync_tools()
	var payload := {"type": "setup", "clientId": str(client.get("id", "")), "tools": _tools.duplicate()}
	setup_sent.emit(payload)
	Net.act(payload)
	# Re-enable if the server rejects it (game.gd removes this overlay on success)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(self):
			_sent = false
			_sync_tools()
	)


# --- Codex, settings, records ------------------------------------------------------------------

## Read-only codex: unlocked clients with best grade and meeting count; locked ones show how to unlock
func _open_codex() -> void:
	if _accepting:
		return
	var m := _modal("客戶圖鑑")
	_codex_panel = (m[1] as Control).get_parent()
	var v: VBoxContainer = m[1]
	var unlocked: Array = info.get("unlocked", [])
	var served: Dictionary = info.get("served", {})
	v.add_child(UI.label("已解鎖 %d／%d 位・本次任務客戶由系統指定，無法在此更換" % [unlocked.size(), int(info.get("total", 0))], 13, C_MUTED, true))
	var grid := GridContainer.new()
	grid.columns = 2 if UI.is_phone_portrait() else 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	v.add_child(scroll)
	var roster: Array = Net.state.get("codex", [])
	if roster.is_empty():
		roster = Net.state.get("caseOptions", [])
	for c: Dictionary in roster:
		var id := str(c.get("id", ""))
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", _panel_style(Color(C_CARD, 0.9) if unlocked.has(id) else Color("#0A2A26"), 10))
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := UI.hbox(10)
		cell.add_child(h)
		if unlocked.has(id):
			var av := Portraits.create_avatar(id, str(c.get("name", "")), 40)
			av.custom_minimum_size = Vector2(40, 40)
			h.add_child(av)
			var tv := UI.vbox(2)
			tv.add_child(UI.label(str(c.get("name", "")), 15, C_TEXT))
			tv.add_child(UI.label(str(c.get("job", "")), 12, C_MUTED, true))
			var sv: Dictionary = served.get(id, {})
			var best := str(sv.get("best", ""))
			tv.add_child(UI.label("最佳成績 %s・會談 %d 次" % [best if best != "" else "—", int(sv.get("count", 0))], 12, C_GOLD))
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(tv)
		else:
			h.add_child(LockedSlot.new())
			var tv := UI.vbox(2)
			tv.add_child(UI.label("？？？", 15, C_MUTED))
			tv.add_child(UI.label("解鎖條件：完成培訓任務", 12, C_MUTED, true))
			tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(tv)
		grid.add_child(cell)
	# First look at locked clients: explain how they unlock, keeping the codex bright
	if unlocked.size() < int(info.get("total", 0)):
		_say(["locked_client_info"])


func _open_settings() -> void:
	var m := _modal("設定")
	var v: VBoxContainer = m[1]
	v.add_child(UI.label("聲音", 14, C_MUTED))
	v.add_child(AudioSettings.new())


## Records live outside the game: confirm before leaving (progress is saved automatically)
func _open_records() -> void:
	var m := _modal("培訓紀錄")
	var dim: Control = m[0]
	var v: VBoxContainer = m[1]
	v.add_child(UI.label("查看培訓紀錄會離開這一局；目前進度已自動保存，可從培訓紀錄回顧。", 14, C_TEXT, true))
	var row := UI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.button("留在這裡", func(): dim.queue_free(), 14, UI.PANEL_2))
	row.add_child(UI.button("前往培訓紀錄", func():
		var main: Node = get_parent().get("main") if get_parent() else null
		if main:
			main.leave_to_menu()
			main.show_records()
	, 14, C_GREEN))
	v.add_child(row)


func _modal(title: String) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(C_CARD, 18))
	p.custom_minimum_size = Vector2(340 if UI.is_phone_portrait() else 560, 0)
	center.add_child(p)
	var v := UI.vbox(12)
	p.add_child(v)
	var head := UI.hbox(8)
	var t := _label(title, 18, C_GOLD)
	t.add_theme_font_override("font", BOLD)
	head.add_child(t)
	head.add_child(UI.spacer())
	var x := UI.button("×", func(): dim.queue_free(), 16, UI.PANEL_2)
	x.custom_minimum_size = Vector2(36, 36)
	head.add_child(x)
	v.add_child(head)
	dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and not p.get_global_rect().has_point(e.global_position):
			dim.queue_free()
	)
	UI.pop_in(p, 0.18)
	return [dim, v]


# --- Layout ------------------------------------------------------------------------------------

func _layout() -> void:
	if _top == null or size.x < 10:
		return
	var portrait := UI.is_portrait()
	_k = clampf(minf(size.x / 1280.0, size.y / 720.0), 0.62, 1.6) if not portrait else clampf(size.x / 480.0, 0.8, 1.4)
	var k := _k
	var top_h := 56.0 * k
	_top.position = Vector2.ZERO
	_top.size = Vector2(size.x, top_h)
	var side := (28.0 if not portrait else 12.0) * k
	var lh := top_h * 0.82
	_logo.size = Vector2(lh * LOGO_CROP.size.x / LOGO_CROP.size.y, lh)
	_logo.position = Vector2(side, (top_h - lh) * 0.5)
	_title.add_theme_font_size_override("font_size", roundi(18 * k))
	_title.reset_size()
	_title.position = Vector2((size.x - _title.size.x) * 0.5, (top_h - _title.size.y) * 0.5)
	_title.visible = not portrait
	_right.reset_size()
	_right.position = Vector2(size.x - side - _right.size.x, (top_h - _right.size.y) * 0.5)
	for i in range(_right.get_child_count()):
		var item: Control = _right.get_child(i)
		item.visible = not portrait or i != 0

	# Steps: centered row under the top bar
	var sy := top_h + 12.0 * k
	var sh := 40.0 * k
	var widths: Array = []
	var total := 0.0
	for it: StepItem in _step_items:
		# Phones keep only the current step's label so the row fits
		it.set_scale_k(k, portrait and it.state != "active")
		widths.append(it.size.x)
		total += it.size.x
	var gap := (44.0 if not portrait else 22.0) * k
	total += gap * (_step_items.size() - 1)
	var x := (size.x - total) * 0.5
	_steps_area.position = Vector2(x - 6.0 * k, sy - 2.0 * k)
	_steps_area.size = Vector2(total + 12.0 * k, sh + 4.0 * k)
	for i in range(_step_items.size()):
		var it: StepItem = _step_items[i]
		it.position = Vector2(x, sy + (sh - it.size.y) * 0.5)
		x += float(widths[i])
		if i < _step_items.size() - 1:
			var chev: Control = _steps.get_node("Chev%d" % i)
			chev.size = Vector2(16, 16) * k
			chev.position = Vector2(x + (gap - chev.size.x) * 0.5, sy + (sh - chev.size.y) * 0.5)
			x += gap

	var py := sy + sh + 10.0 * k
	_page.position = Vector2(0, py)
	_page.size = Vector2(size.x, size.y - py)
	var margin := (60.0 if not portrait else 12.0) * k
	if _step == 1 and _strip and is_instance_valid(_strip):
		_layout_mission(margin, portrait)
	else:
		if _step >= 3:
			margin = (28.0 if not portrait else 12.0) * k
		if _briefcase and is_instance_valid(_briefcase):
			# Bottom bar stays clear of the secretary's round corner portrait
			var g := _secretary()
			var on: bool = g != null and bool(g.get("enabled"))
			_briefcase.reserve_right = ((58.0 if not portrait else 70.0) * k) if on else 0.0
			_briefcase.set_k(k)
		for n: Node in _page.get_children():
			if n is Control:
				(n as Control).position = Vector2(margin, 0)
				(n as Control).size = Vector2(size.x - margin * 2, _page.size.y - 16.0 * k)


func _layout_mission(margin: float, portrait: bool) -> void:
	var k := _k
	var w := _page.size.x
	_strip.position = Vector2(margin, 0)
	_strip.size = Vector2(w - margin * 2, 0)
	_strip.reset_size()
	_strip.size.x = w - margin * 2
	# Phones: three slots and no side note so the strip never overflows
	var slots := 8 if not portrait else 3
	_strip_sep.visible = not portrait
	_strip_note.visible = not portrait
	if _strip_slots.get_child_count() != mini(slots, maxi(int(info.get("total", 0)), (info.get("unlocked", []) as Array).size())):
		_fill_slots(slots)
	var y := _strip.size.y + 18.0 * k
	_card_label.add_theme_font_size_override("font_size", roundi(16 * k))
	_card_label.reset_size()
	_card_label.size.x = w
	_card_label.position = Vector2(0, y)
	y += _card_label.size.y + 8.0 * k
	var btn_h := 64.0 * k
	var link_h := 30.0 * k
	var avail := _page.size.y - y - btn_h - link_h - 34.0 * k
	var ch := clampf(avail, 180.0 * k, 300.0 * k)
	var cw := ch * 222.0 / 290.0
	_file.size = Vector2(cw, ch)
	_file.position = Vector2((w - cw) * 0.5, y)
	y += ch + 18.0 * k
	var bw := minf(440.0 * k, w - 32.0)
	_accept.size = Vector2(bw, btn_h)
	_accept.position = Vector2((w - bw) * 0.5, y)
	_accept.set_k(k)
	y += btn_h + 8.0 * k
	_codex_link.reset_size()
	_codex_link.position = Vector2((w - _codex_link.size.x) * 0.5, y)


# --- Helpers -----------------------------------------------------------------------------------

func _label(t: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel_style(bg: Color, pad := 16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = C_LINE
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.75
	sb.content_margin_bottom = pad * 0.75
	sb.anti_aliasing = true
	return sb


func _link_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic: Control = LineIcon.new("book", C_TEXT, 1.8)
	ic.custom_minimum_size = Vector2(22, 22)
	row.add_child(ic)
	var l := _label(text, 15, C_TEXT)
	l.add_theme_constant_override("underline_spacing", 2)
	row.add_child(l)
	var chev: Control = LineIcon.new("chevron_r", C_TEXT, 1.8)
	chev.custom_minimum_size = Vector2(14, 22)
	row.add_child(chev)
	b.add_child(row)
	var underline := ColorRect.new()
	underline.color = Color(C_TEXT, 0.6)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(underline)
	row.position = Vector2(4, 0)
	_fit_to_row(b, row, Vector2(8, 6))
	row.resized.connect(func():
		underline.position = Vector2(4 + l.position.x, row.size.y)
		underline.size = Vector2(l.size.x, 1)
	)
	b.pressed.connect(cb)
	b.mouse_entered.connect(func(): l.add_theme_color_override("font_color", C_GOLD))
	b.mouse_exited.connect(func(): l.add_theme_color_override("font_color", C_TEXT))
	return b


## Buttons do not size to their children: follow the row once it has been measured
func _fit_to_row(b: Button, row: Control, pad: Vector2) -> void:
	var fit := func():
		if is_instance_valid(b) and is_instance_valid(row):
			b.custom_minimum_size = row.get_combined_minimum_size() + pad
			b.reset_size()
			_layout.call_deferred()
	row.minimum_size_changed.connect(fit)
	fit.call_deferred()


## Step indicator: number circle (gold when active, check when done), line icon and label
class StepItem extends Control:
	var num := ""
	var icon_kind := ""
	var text := ""
	var state := "todo"
	var _k := 1.0
	var _icon: Control
	var _label: Label

	func _init(n: String, ic: String, t: String) -> void:
		num = n
		icon_kind = ic
		text = t
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon = LineIcon.new(ic, C_TEXT, 1.8)
		add_child(_icon)
		_label = Label.new()
		_label.text = t
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)

	func set_def(n: String, ic: String, t: String) -> void:
		num = n
		icon_kind = ic
		text = t
		_icon.set("kind", ic)
		_label.text = t

	func set_state(s: String) -> void:
		state = s
		var col := C_GREEN if s == "active" else (C_TEXT if s == "done" else Color(C_MUTED, 0.6))
		_label.add_theme_color_override("font_color", C_TEXT if s == "active" else col)
		_label.add_theme_font_override("font", BOLD if s == "active" else FONT)
		_icon.set("color", C_GREEN if s == "active" else col)
		_icon.queue_redraw()
		queue_redraw()

	func set_scale_k(k: float, compact := false) -> void:
		_k = k
		_label.add_theme_font_size_override("font_size", roundi(18 * k))
		_label.reset_size()
		_label.visible = not compact
		var d := 34.0 * k
		var ic := 26.0 * k
		_icon.size = Vector2(ic, ic)
		_icon.position = Vector2(d + 12.0 * k, (d - ic) * 0.5)
		_label.position = Vector2(_icon.position.x + ic + 8.0 * k, (d - _label.size.y) * 0.5)
		size = Vector2((_label.position.x + _label.size.x) if not compact else (_icon.position.x + ic), d)
		queue_redraw()

	func _draw() -> void:
		var d := 34.0 * _k
		var c := Vector2(d * 0.5, d * 0.5)
		if state == "active":
			draw_circle(c, d * 0.5, Color(C_GOLD, 0.95))
			draw_arc(c, d * 0.5 + 2.0, 0, TAU, 48, Color(C_GOLD, 0.35), 1.0, true)
		elif state == "done":
			draw_circle(c, d * 0.5, Color(C_GREEN, 0.9))
		else:
			draw_circle(c, d * 0.5, Color(C_MUTED, 0.22))
			draw_arc(c, d * 0.5, 0, TAU, 48, Color(C_MUTED, 0.4), 1.0, true)
		if state == "done":
			var s := d * 0.5
			draw_line(c + Vector2(-s * 0.4, 0), c + Vector2(-s * 0.1, s * 0.3), C_TEXT, 2.0, true)
			draw_line(c + Vector2(-s * 0.1, s * 0.3), c + Vector2(s * 0.45, -s * 0.3), C_TEXT, 2.0, true)
		else:
			var fs := roundi(18 * _k)
			var tw := FONT.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(FONT, c + Vector2(-tw.x * 0.5, tw.y * 0.32), num, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_BG if state == "active" else Color(C_TEXT, 0.7))


## Dark silhouette with a lock for clients not yet unlocked
class LockedSlot extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(44, 44)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("#0A2A26"))
		draw_arc(c, r - 0.5, 0, TAU, 48, Color(1, 1, 1, 0.14), 1.0, true)
		var col := Color(C_MUTED, 0.55)
		var bw := r * 0.62
		var bh := r * 0.46
		var top := c.y - r * 0.02
		var body := Rect2(Vector2(c.x - bw * 0.5, top), Vector2(bw, bh))
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.set_border_width_all(1)
		sb.border_color = col
		sb.set_corner_radius_all(3)
		draw_style_box(sb, body)
		# Shackle: two legs and an arc, clearly above the body
		var sr := bw * 0.3
		var leg := r * 0.12
		draw_line(Vector2(c.x - sr, top), Vector2(c.x - sr, top - leg), col, 1.6, true)
		draw_line(Vector2(c.x + sr, top), Vector2(c.x + sr, top - leg), col, 1.6, true)
		draw_arc(Vector2(c.x, top - leg), sr, PI, TAU, 16, col, 1.6, true)
		draw_circle(Vector2(c.x, top + bh * 0.5), 1.4, col)


## Main action: document-check icon, label, arrow; press dips to 97%; loading shows a thin ring
class AcceptButton extends Button:
	signal activated
	var text_value := ""
	var icon_kind := "doc_check"
	var _visual: Panel
	var _icon: Control
	var _sep: ColorRect
	var _label: Label
	var _arrow: Control
	var _spinner: Spinner
	var _loading := false
	var _enabled := true
	var _k := 1.0

	func _init(t: String, ic := "doc_check") -> void:
		text_value = t
		icon_kind = ic

	func _ready() -> void:
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_visual = Panel.new()
		_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_visual)
		_icon = LineIcon.new(icon_kind, C_TEXT, 2.0)
		_visual.add_child(_icon)
		_spinner = Spinner.new()
		_spinner.visible = false
		_visual.add_child(_spinner)
		_sep = ColorRect.new()
		_sep.color = Color(C_TEXT, 0.25)
		_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_visual.add_child(_sep)
		_label = Label.new()
		_label.text = text_value
		_label.add_theme_color_override("font_color", C_TEXT)
		_label.add_theme_font_override("font", BOLD)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_visual.add_child(_label)
		_label.resized.connect(_layout)
		_arrow = LineIcon.new("chevron_r", C_TEXT, 2.0)
		_visual.add_child(_arrow)
		_restyle(false)
		mouse_entered.connect(func(): _restyle(true))
		mouse_exited.connect(func(): _restyle(false))
		pressed.connect(_on_pressed)
		resized.connect(_layout)
		_layout()

	func set_k(k: float) -> void:
		_k = k
		_layout()

	func set_enabled(on: bool) -> void:
		_enabled = on
		disabled = not on or _loading
		if _visual:
			_visual.modulate.a = 1.0 if on or _loading else 0.6

	func set_loading(t: String) -> void:
		_loading = true
		disabled = true
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		_label.text = t
		_icon.visible = false
		_spinner.visible = true
		_arrow.visible = false
		_restyle(false)
		_layout()

	func _restyle(hover: bool) -> void:
		if _visual == null:
			return
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_GREEN if not _loading else C_GREEN.darkened(0.35)
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(1)
		sb.border_color = Color(C_GOLD, 0.5) if not hover else Color(C_GOLD, 0.85)
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 3)
		sb.anti_aliasing = true
		_visual.add_theme_stylebox_override("panel", sb)
		var b := 1.06 if hover and not _loading else 1.0
		_visual.self_modulate = Color(b, b, b)

	func _layout() -> void:
		if _visual == null:
			return
		_visual.size = size
		_visual.pivot_offset = size * 0.5
		_label.add_theme_font_size_override("font_size", roundi(24 * _k))
		_label.reset_size()
		var ic := 34.0 * _k
		var gap := 18.0 * _k
		var aw := 16.0 * _k
		var group := ic + gap + 1.0 + gap + _label.size.x + (gap + aw if _arrow.visible else 0.0)
		var x := (size.x - group) * 0.5
		_icon.size = Vector2(ic, ic)
		_icon.position = Vector2(x, (size.y - ic) * 0.5)
		_spinner.size = Vector2(ic * 0.8, ic * 0.8)
		_spinner.position = Vector2(x + ic * 0.1, (size.y - ic * 0.8) * 0.5)
		_sep.size = Vector2(1, size.y * 0.5)
		_sep.position = Vector2(x + ic + gap, size.y * 0.25)
		_label.position = Vector2(_sep.position.x + 1.0 + gap, (size.y - _label.size.y) * 0.5)
		_arrow.size = Vector2(aw, aw)
		_arrow.position = Vector2(_label.position.x + _label.size.x + gap, (size.y - aw) * 0.5)

	func _on_pressed() -> void:
		if not _enabled or _loading:
			return
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_visual, "scale", Vector2.ONE * 0.97, 0.07)
		tw.tween_property(_visual, "scale", Vector2.ONE, 0.08)
		activated.emit()


## Thin circular progress ring
class Spinner extends Control:
	var _a := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if visible:
			_a = fmod(_a + delta * TAU * 0.9, TAU)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 1.5
		draw_arc(c, r, 0, TAU, 48, Color(C_TEXT, 0.2), 1.6, true)
		draw_arc(c, r, _a, _a + PI * 0.6, 24, C_TEXT, 1.8, true)
