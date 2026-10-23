extends "res://scripts/quest/pages/page_base.gd"
## ClientDialogueView（客戶訪談）— 銀行諮詢空間裡的互動會談。
## 左側場景：客戶立繪與資料（姓名、年齡、職業、家庭、每月預算、目前風險）、對話框、四項數值
## （信任／需求掌握／預算壓力／合規風險），以及三張顧問回應卡（每輪重新打亂，最好的一句不固定
## 在第一個）和用自己的話說（AI 客戶回應）。選擇前不顯示分數或傾向。
## 選擇後：客戶先打字回應，表情與姿勢跟著變，數值補間並浮出 +／−，再顯示「為什麼有效」或
## 「問題出在哪裡」與對真實顧問工作的影響；每一筆都寫進本局決策紀錄，供 AI 培訓報告使用。
## 右側：目前任務與已收集線索、秘書提示、公事包，下一步／上一步／返回主頁固定在下方。

const StatMeter := preload("res://scripts/quest/widgets/stat_meter.gd")
const BriefcaseDrawer := preload("res://scripts/quest/widgets/briefcase_drawer.gd")
const NO_KEY_COST := 20.0
const HINT_COST := 30.0
## 每輪顯示的回應數
const OPTION_COUNT := 3
const OPTION_ICONS := {"income": "wallet", "goal": "target", "coverage": "shield", "risk": "chart", "premium": "coins"}
const NEED_TARGET := 3

var _portrait: TextureRect
var _mood: PanelContainer
var _mood_label: Label
var _log: VBoxContainer
var _log_scroll: ScrollContainer
var _task: Label
var _options: BoxContainer
var _reaction: PanelContainer
var _input: LineEdit
var _send: Button
var _input_row: Control
var _talk_note: Label
var _known: VBoxContainer
var _clue_row: HBoxContainer
var _clue_count: Label
var _meters: Dictionary = {}
var _scene_scroll: ScrollContainer
var _next: Button
var _hint_btn: Button
var _hint_box: Label
var _bag_btn: Button
var _shown_asked := 0
var _pending := false
var _before: Dictionary = {}
var _typing_label: Label = null
var _typing_tween: Tween
var _stream_label: Label = null
var _last_adv: Label = null
var _mood_tween: Tween
var _last_hint := ""
var _hint_pending := false


func guide_lines() -> Array:
	return ["這是客戶訪談。每一輪挑一句最合適的回應，先聽懂客戶，再談方案。", "回應順序每次都不同，也不會先告訴你哪一個比較好；選完才會看到客戶的反應與原因。"]


func help_lines() -> Array:
	return ["先問生活與目標，再談預算。問到關鍵需求，信任和需求掌握都會上升。", "沒有帶出新線索的問題會花掉會談時間；完成 3 個問題後就能整理線索。"]


func idle_lines() -> Array:
	return ["不確定要問什麼時，先想想：客戶最不能失去的是什麼？從那裡開始問。"]


func key_rects() -> Array:
	return [rect_of(_next), rect_of(_send)]


func highlight_rects() -> Array:
	return [rect_of(_options)]


func build() -> void:
	add_background()
	var v := add_frame()
	var c := GameState.current_client()
	# 左：諮詢場景（立繪｜客戶資料＋對話；數值；回饋；三張回應卡；用自己的話說）
	var scene := QuestUI.card(null, 0.9)
	scene.name = "InterviewScene"
	var sv := QuestUI.vbox(8)
	scene.add_child(sv)
	var stage: BoxContainer = QuestUI.hbox(14) if not narrow() else QuestUI.vbox(8)
	_portrait = TextureRect.new()
	_portrait.name = "ClientPortrait"
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.custom_minimum_size = Vector2(150, 196) if not (narrow() or compact()) else Vector2(100, 124)
	_portrait.material = UI.get_rounded_material(0.06)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.texture = _portrait_texture()
	stage.add_child(_portrait)
	var talk := QuestUI.vbox(6)
	talk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 客戶資料列：{client_name}｜{client_age}・{client_job}・{family_status}，每月預算、目前風險、狀態
	var info := QuestUI.hbox(10)
	var cname := QuestUI.title(str(c.get("name", "客戶")), 22 if not phone() else 18)
	cname.name = "ClientName"
	info.add_child(cname)
	var who := QuestUI.label(_who_line(c), 13, QuestUI.MUTED, true)
	who.name = "ClientInfo"
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_child(who)
	_mood = PanelContainer.new()
	_mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mood_label = QuestUI.label("", 13, QuestUI.TEXT)
	_mood.add_child(_mood_label)
	info.add_child(_mood)
	talk.add_child(info)
	var facts := QuestUI.hbox(8)
	var budget := QuestUI.chip("每月預算：" + _monthly_budget(c), QuestUI.MUTED)
	budget.name = "ClientBudget"
	facts.add_child(budget)
	var risk := QuestUI.chip("目前風險：" + _current_risk(c), QuestUI.RED.lightened(0.1))
	risk.name = "ClientRisk"
	facts.add_child(risk)
	talk.add_child(facts)
	_log = QuestUI.vbox(8)
	_log.name = "Dialogue"
	_log_scroll = QuestUI.scroll(_log)
	_log_scroll.custom_minimum_size = Vector2(0, 110 if not compact() else 80)
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var log_sb := StyleBoxEmpty.new()
	log_sb.content_margin_top = 8
	_log_scroll.add_theme_stylebox_override("panel", log_sb)
	talk.add_child(_log_scroll)
	stage.add_child(talk)
	sv.add_child(stage)
	# 四項數值
	var meters: Container
	if narrow() or compact():
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 8)
		g.add_theme_constant_override("v_separation", 8)
		meters = g
	else:
		meters = QuestUI.hbox(8)
	meters.name = "Meters"
	for spec in [["trust", "信任", "heart", QuestUI.GREEN, false], ["insight", "需求掌握", "bulb", QuestUI.GOLD, false], ["budget", "預算壓力", "wallet", Color("#8FB3C4"), true], ["risk", "合規風險", "shield", Color("#C8D2CE"), true]]:
		var m: Control = StatMeter.new(spec[0], spec[1], spec[2], spec[3], spec[4])
		m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meters.add_child(m)
		_meters[spec[0]] = m
	sv.add_child(meters)
	# 選擇後的回饋：放在數值正下方，第一眼就看得到
	_reaction = PanelContainer.new()
	_reaction.name = "Reaction"
	_reaction.add_theme_stylebox_override("panel", QuestUI.card_box(0.6, Color(1, 1, 1, 0.12), 14, 12))
	_reaction.visible = false
	sv.add_child(_reaction)
	_task = QuestUI.label("", 15, QuestUI.GOLD, true)
	_task.name = "TaskLine"
	sv.add_child(_task)
	# 三張回應卡
	_options = QuestUI.hbox(10) if not (narrow() or compact()) else QuestUI.vbox(8)
	_options.name = "Options"
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(_options)
	_input_row = QuestUI.vbox(4)
	var ir := QuestUI.hbox(8)
	_input = LineEdit.new()
	_input.name = "FreeTalk"
	_input.placeholder_text = "用自己的話說（AI 客戶會回應）"
	_input.max_length = 150
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.custom_minimum_size = Vector2(0, 44)
	_input.add_theme_font_size_override("font_size", QuestUI.fs(15))
	_input.text_submitted.connect(func(_t): _send_talk())
	ir.add_child(_input)
	_send = QuestUI.button("說出口", _send_talk, "secondary", "send")
	_send.name = "SendTalk"
	ir.add_child(_send)
	_input_row.add_child(ir)
	_talk_note = QuestUI.label("", 12, QuestUI.MUTED, true)
	_input_row.add_child(_talk_note)
	sv.add_child(_input_row)
	# 右：目前任務、已收集線索、秘書提示、公事包
	var task_card := QuestUI.card(null, 0.92)
	var tv := QuestUI.vbox(8)
	task_card.add_child(tv)
	tv.add_child(QuestUI.header("target", "目前任務｜找出 %d 個核心需求" % NEED_TARGET))
	tv.add_child(QuestUI.label("透過對話收集關鍵線索，確認客戶真正在意的需求。", 13, QuestUI.MUTED, true))
	var ch := QuestUI.hbox(8)
	ch.add_child(QuestUI.label("已收集的線索", 14, QuestUI.TEXT))
	_clue_count = QuestUI.label("", 14, QuestUI.GOLD)
	_clue_count.name = "ClueCount"
	ch.add_child(_clue_count)
	tv.add_child(ch)
	_clue_row = QuestUI.hbox(10)
	_clue_row.name = "ClueSlots"
	tv.add_child(_clue_row)
	_known = QuestUI.vbox(4)
	tv.add_child(_known)
	_hint_btn = QuestUI.button("請秘書給一次提示（-0:30）", _ask_hint, "quiet", "bulb")
	_hint_btn.name = "HintButton"
	_hint_box = QuestUI.label("", 14, QuestUI.TEXT, true)
	_hint_box.visible = false
	_bag_btn = QuestUI.button("公事包（%d）" % BriefcaseDrawer.packed().size(), _open_briefcase, "secondary", "briefcase")
	_bag_btn.name = "BriefcaseButton"
	_next = QuestUI.button("下一步：整理需求線索", func(): go.emit("clues", {}), "primary", "next")
	_next.name = "NextStep"
	var back: Button = QuestUI.button("上一步：任務簡報", _back_to_brief, "quiet", "back")
	back.name = "BackButton"
	var home: Button = QuestUI.button("返回主頁", _go_home, "quiet", "house")
	home.name = "HomeButton"
	var nav := QuestUI.hbox(8)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	nav.add_child(home)
	var right := side([task_card, _hint_btn, _hint_box, _bag_btn], [secretary_button(), _next, nav])
	# 桌機約 70% / 30%；矮螢幕右欄放寬，讓下一步按鈕放得下
	scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scene_scroll = null if narrow() else QuestUI.scroll(scene)
	v.add_child(columns([scene if narrow() else _scene_scroll, right], [2.3, 1.0] if not compact() else [1.6, 1.0]))
	_set_mood("calm")
	_sync_meters(false)
	Net.stream_text.connect(_on_stream)


## 立繪：客戶頭像，載入失敗時用預設圖
func _portrait_texture() -> Texture2D:
	var t := GameState.client_portrait()
	if t != null:
		return t
	# 依性別與年齡取通用頭像，再不行用中性預設圖
	var c := GameState.current_client()
	var gender := str(c.get("gender", ""))
	var g := "f" if gender in ["女", "f", "female"] else ("m" if gender in ["男", "m", "male"] else "")
	var key := "pool_%s_%ds" % [g, clampi(int(c.get("age", 30)) / 10 * 10, 20, 60)] if g != "" else "pool_x"
	push_warning("客戶訪談：找不到「%s」的立繪，改用預設圖 %s" % [GameState.client_name(), key])
	t = Portraits.get_texture(key)
	return t if t != null else Portraits.get_texture("pool_x")


func _who_line(c: Dictionary) -> String:
	var bits: Array = []
	if int(c.get("age", 0)) > 0:
		bits.append("%d 歲" % int(c.age))
	for k in ["job", "family"]:
		if str(c.get(k, "")) != "":
			bits.append(str(c[k]))
	return "・".join(bits)


func _monthly_budget(c: Dictionary) -> String:
	var f: Variant = c.get("finance")
	if f is Dictionary and int(f.get("income", 0)) > 0:
		var spare := int(f.get("income", 0)) - int(f.get("expense", 0))
		return "約 %s" % (("%d 萬" % (spare / 10000)) if spare % 10000 == 0 else ("%.1f 萬" % (spare / 10000.0)))
	var info := str(c.get("incomeInfo", ""))
	return info if info != "" else "會談中確認"


func _current_risk(c: Dictionary) -> String:
	var tw: Variant = GameState.my_session().get("twist")
	if tw is Dictionary and str(tw.get("title", "")) != "":
		return str(tw.title)
	var tag := str(c.get("tag", ""))
	return tag if tag != "" else "待確認"


## 後端指標 → 四項數值（預算壓力在方案設計前顯示待評估）
func _sync_meters(animate: bool) -> void:
	if _meters.is_empty():
		return
	var m := GameState.metrics()
	(_meters.trust as Control).call("set_value", int(m.get("trust", 50)), animate)
	(_meters.insight as Control).call("set_value", int(m.get("insight", 0)), animate)
	var fit := int(m.get("fit", 0))
	(_meters.budget as Control).call("set_value", (100 - fit) if fit > 0 else -1, animate)
	(_meters.risk as Control).call("set_value", 100 - int(m.get("compliance", 100)), animate)


func _open_briefcase() -> void:
	if find_child("BriefcaseDrawer", false, false) != null:
		return
	if not QuestFlow.claim(0.3):
		return
	var d: Control = BriefcaseDrawer.new()
	d.connect("free_question_requested", _focus_free)
	d.tree_exited.connect(func(): GameState.hold("briefcase", false))
	GameState.hold("briefcase", true)
	add_child(d)


## 家庭責任圖：多出來的自由提問，用自己的話問客戶
func _focus_free() -> void:
	_input_row.visible = true
	_input.grab_focus()
	if layer:
		layer.call("show_toast", "家庭責任圖：多 1 次自由提問，用自己的話問客戶的家庭責任", "info")


## 返回主頁：先確認（繼續培訓／儲存並返回主畫面／放棄本次培訓）
func _go_home() -> void:
	if layer:
		layer.call("_leave")


func _back_to_brief() -> void:
	GameState.set_flag("arrived", false)
	go.emit("brief", {})


func on_open() -> void:
	_shown_asked = 0
	var sess := GameState.my_session()
	var asked: Array = sess.get("asked", [])
	# The client opens the conversation in their own words
	var c: Dictionary = sess.get("client", {})
	var opening := str(c.get("quote", "")).strip_edges()
	if opening == "":
		opening = str(c.get("intro", "")).strip_edges()
	if opening != "":
		_bubble(opening, true)
	for a in asked:
		_add_pair(a, false)
	_shown_asked = asked.size()
	_refresh_side(sess)
	_build_options(sess)
	if not narrow():
		QuestUI.fade_in(_portrait, 0.05, 0.35, 0.0)


func on_close() -> void:
	GameState.hold("briefcase", false)
	GameState.hold("review", false)
	if Net.stream_text.is_connected(_on_stream):
		Net.stream_text.disconnect(_on_stream)


func refresh(s: Dictionary) -> void:
	if not built:
		built = true
		return
	var sess := GameState.my_session()
	if sess.is_empty():
		return
	var asked: Array = sess.get("asked", [])
	if asked.size() > _shown_asked:
		for i in range(_shown_asked, asked.size()):
			_add_pair(asked[i], true)
			if _pending:
				_react(asked[i], _before, sess.get("metrics", {}))
		_shown_asked = asked.size()
		_pending = false
	elif not bool(sess.get("aiBusy", false)) and _pending and _stream_label == null:
		pass
	_sync_meters(true)
	_refresh_side(sess)
	if not _pending and _typing_label == null:
		_build_options(sess)
	var hint := str(sess.get("hint", "")) if sess.get("hint") != null else ""
	if hint != "" and hint != _last_hint:
		_last_hint = hint
		_show_hint(hint)


func server_error(_msg: String) -> void:
	_pending = false
	_hint_pending = false
	_send.call("set_loading", false)
	_hint_btn.call("set_loading", false)
	_hint_btn.disabled = bool(GameState.my_session().get("hintUsed", false))
	_build_options(GameState.my_session())


# --- Conversation -----------------------------------------------------------------------------

func _bubble(text: String, client: bool) -> Label:
	var row := QuestUI.hbox(8)
	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if client:
		s.bg_color = Color("#E9E4D6")
	else:
		s.bg_color = Color(QuestUI.GREEN, 0.22)
		s.set_border_width_all(1)
		s.border_color = Color(QuestUI.GREEN, 0.5)
	panel.add_theme_stylebox_override("panel", s)
	var inner := QuestUI.vbox(4)
	panel.add_child(inner)
	var l := QuestUI.label(text, 15, QuestUI.INK if client else QuestUI.TEXT, true)
	l.custom_minimum_size.x = 200
	inner.add_child(l)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 4.0
	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if client:
		row.add_child(panel)
		row.add_child(pad)
	else:
		row.add_child(pad)
		row.add_child(panel)
		# The player's own advisor portrait beside what they said
		if PlayerProfile.portrait() != null:
			var me := UI.RoundTex.new(PlayerProfile.portrait(), Vector2(30, 30), -1.0, PlayerProfile.token_color(), 2.0)
			me.size_flags_vertical = Control.SIZE_SHRINK_END
			me.tooltip_text = PlayerProfile.player_name
			row.add_child(me)
	_log.add_child(row)
	_scroll_down()
	return l


func _add_pair(a: Dictionary, animate: bool) -> void:
	var q := str(a.get("question", ""))
	var ans := str(a.get("answer", ""))
	if _stream_label != null and is_instance_valid(_stream_label):
		# Streamed reply already on screen: settle it with the final text
		_stream_label.text = ans
		_stream_label = null
		_mark_compliance(_last_adv, q, str(a.get("compliance", "")))
	else:
		if q != "":
			_mark_compliance(_bubble(q, false), q, str(a.get("compliance", "")))
		var lbl := _bubble("", true)
		if animate:
			_type(lbl, ans)
		else:
			lbl.text = ans


## Red underline only after the line was said (never before a choice)
func _mark_compliance(adv: Label, q: String, comp: String) -> void:
	if adv == null or not is_instance_valid(adv):
		return
	if comp == "violation" or comp == "warning":
		adv.add_theme_color_override("font_color", QuestUI.RED.lightened(0.35))
		adv.text = q + ("　⚠ 合規風險" if comp == "violation" else "　⚠ 話術瑕疵")
		adv.get_parent().add_child(_underline())


func _underline() -> Control:
	var u := ColorRect.new()
	u.color = QuestUI.RED
	u.custom_minimum_size = Vector2(0, 2)
	u.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return u


func _type(lbl: Label, text: String) -> void:
	lbl.text = "……"
	_typing_label = lbl
	var per := GameState.char_seconds(0.035)
	if _typing_tween and _typing_tween.is_valid():
		_typing_tween.kill()
	_typing_tween = create_tween()
	# A short beat of 思考中 before the words come
	_typing_tween.tween_interval(0.45 if per > 0 else 0.0)
	_typing_tween.tween_callback(func():
		lbl.text = text
		lbl.visible_ratio = 0.0 if per > 0 else 1.0
	)
	if per > 0:
		_typing_tween.tween_property(lbl, "visible_ratio", 1.0, maxf(0.2, text.length() * per))
	_typing_tween.tween_callback(func():
		_typing_label = null
		_scroll_down()
		_build_options(GameState.my_session())
	)


func _scroll_down() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(_log_scroll):
		var vsb := _log_scroll.get_v_scroll_bar()
		_log_scroll.scroll_vertical = int(maxf(0.0, vsb.max_value - vsb.page))


# --- Options ----------------------------------------------------------------------------------

func _build_options(sess: Dictionary) -> void:
	UI.clear(_options)
	var asked: Array = sess.get("asked", [])
	var covered: Array = sess.get("covered", [])
	var std_count := 0
	for a in asked:
		if str((a as Dictionary).get("qid", "")) != "free":
			std_count += 1
	var ready := bool(sess.get("ready", false))
	var busy := bool(sess.get("aiBusy", false)) or _pending or _typing_label != null
	if ready:
		_task.text = "訪談問題已完成（%d/3）。可以整理需求線索了，也可以再用自己的話多聊一句。" % mini(covered.size(), 3)
	else:
		_task.text = "目前要做什麼：挑一句話問客戶，找出他真正在意的事（已問 %d/3）" % mini(covered.size(), 3)
	if not ready:
		var remaining: Array = []
		for q in Net.static_data.get("questions", []):
			var qd := q as Dictionary
			if not covered.has(str(qd.get("id", ""))):
				remaining.append(qd)
		# 三張回應卡，每輪重新打亂（最好的一句不會固定在第一個）
		remaining = QuestUI.shuffled(remaining)
		var shown := remaining.slice(0, mini(OPTION_COUNT, remaining.size()))
		for k in range(shown.size()):
			var qd: Dictionary = shown[k]
			var qid := str(qd.get("id", ""))
			var card := OptionCard.new(k + 1, str(OPTION_ICONS.get(qid, "chat")), str(qd.get("text", "")), narrow() or compact())
			card.name = "Option_" + qid + "Card"
			card.btn.name = "Option_" + qid
			card.pressed.connect(func(): _ask(qid))
			card.disabled = busy
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.size_flags_vertical = Control.SIZE_FILL
			_options.add_child(card)
	# Follow-up on the life change, when the advisor chose to clarify it
	var tw: Variant = sess.get("twist")
	if bool(GameState.flag("twist_clarify", false)) and not bool(GameState.flag("twist_clarified", false)) and tw is Dictionary and int(sess.get("talkLeft", 0)) > 0:
		var line := "關於「%s」，最近對您的生活影響大嗎？" % str(tw.get("title", "最近的變化"))
		var tcard := OptionCard.new(_options.get_child_count() + 1, "info", line, narrow() or compact())
		tcard.name = "Option_twistCard"
		tcard.btn.name = "Option_twist"
		tcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tcard.size_flags_vertical = Control.SIZE_FILL
		tcard.pressed.connect(func():
			GameState.set_flag("twist_clarified", true)
			_talk(line)
		)
		tcard.disabled = busy
		_options.add_child(tcard)
	# Free line through the AI client
	var talk_left := int(sess.get("talkLeft", 0))
	var free_left := int(sess.get("freeLeft", 0))
	_input_row.visible = talk_left > 0 or free_left > 0
	_send.call("set_reason", "客戶正在回應" if busy else "")
	_input.editable = not busy
	_talk_note.text = ("自由對話剩 %d 輪" % talk_left) if talk_left > 0 else ("自由提問剩 %d 次" % free_left)
	if not QuestUI.motion_off():
		for i in range(_options.get_child_count()):
			QuestUI.fade_in(_options.get_child(i), i * 0.05, 0.2, 0.0)


func _ask(qid: String) -> void:
	if _pending:
		return
	_pending = true
	_before = GameState.metrics().duplicate()
	_reaction.visible = false
	for b in _options.get_children():
		b.set("disabled", true)
	send({"type": "ask", "qid": qid})


func _send_talk() -> void:
	var t := _input.text.strip_edges()
	if t.length() < 2:
		layer.call("show_toast", "請先輸入想說的話", "warning")
		return
	_input.text = ""
	_talk(t)


func _talk(t: String) -> void:
	if _pending:
		return
	var sess := GameState.my_session()
	_pending = true
	_before = GameState.metrics().duplicate()
	_reaction.visible = false
	for b in _options.get_children():
		b.set("disabled", true)
	_input.editable = false
	_send.call("set_loading", true, "客戶回應中")
	_last_adv = _bubble(t, false)
	_stream_label = _bubble("……", true)
	if int(sess.get("talkLeft", 0)) > 0:
		send({"type": "talk", "text": t})
	else:
		send({"type": "ask_free", "text": t})


func _on_stream(text: String) -> void:
	if _stream_label != null and is_instance_valid(_stream_label):
		_stream_label.text = text
		_scroll_down()


# --- Reaction ---------------------------------------------------------------------------------

func _react(a: Dictionary, before: Dictionary, after: Dictionary) -> void:
	_send.call("set_loading", false)
	var dt := int(after.get("trust", 0)) - int(before.get("trust", 0))
	var di := int(after.get("insight", 0)) - int(before.get("insight", 0))
	var dc := int(after.get("compliance", 100)) - int(before.get("compliance", 100))
	var key: Variant = a.get("key")
	var qid := str(a.get("qid", ""))
	var coach := ""
	for q in Net.static_data.get("questions", []):
		if str((q as Dictionary).get("id", "")) == qid:
			coach = str(q.get("coach", ""))
	var reason := ""
	var quality := "ok"
	if str(a.get("coachTip", "")) != "":
		reason = str(a.coachTip)
	if key != null and str(key) != "":
		reason = "取得線索：%s。%s" % [str(key), coach if coach != "" else reason]
		quality = "good" if dt >= 0 else "ok"
	else:
		reason = ("這句話沒有帶出新的需求線索，客戶也變得保留一些。%s" % coach) if qid != "free" else (reason if reason != "" else "客戶回應了，但沒有透露新的需求線索。")
		quality = "bad" if dt < 0 else "ok"
		if qid != "free":
			GameState.spend_time(NO_KEY_COST, "問題沒有帶出線索")
			reason += "（會談時間 -0:%02d）" % int(NO_KEY_COST)
	var comp := str(a.get("compliance", ""))
	if comp == "violation" or dc <= -10:
		quality = "bad"
		AudioManager.play("compliance_risk")
		TensionManager.set_flag("violation", true)
		reason = "這句話有合規風險（保證或施壓）：%s" % (reason if reason != "" else "改用說明風險與選擇的方式。")
	# The client's words came first (typewriter); the numbers and the reason follow
	var streamed := qid == "free" or str(a.get("source", "")) != ""
	var wait := 0.2 if streamed or GameState.char_seconds() <= 0 else 0.45 + str(a.get("answer", "")).length() * GameState.char_seconds(0.035)
	await get_tree().create_timer(wait).timeout
	if not is_instance_valid(self):
		return
	if dt > 0:
		AudioManager.play("trust_up")
	elif dt < 0:
		AudioManager.play("trust_down")
	_set_mood("relaxed" if dt >= 8 else ("guarded" if dt <= -6 else ("hesitant" if dt < 0 else "thinking")))
	if dt < 0:
		TensionManager.set_flag("hesitating", true)
		get_tree().create_timer(8.0).timeout.connect(func(): TensionManager.set_flag("hesitating", false))
	UI.clear(_reaction)
	var rv := QuestUI.vbox(6)
	_reaction.add_child(rv)
	# 為什麼有效／問題出在哪裡，以及對真實顧問工作的影響
	var good := quality == "good"
	var heading := QuestUI.hbox(8)
	heading.add_child(QuestUI.icon("circle_check" if good else ("alert" if quality == "bad" else "info"), 18.0, QuestUI.GREEN if good else (QuestUI.RED if quality == "bad" else QuestUI.GOLD)))
	var hl := QuestUI.label("為什麼有效" if good else ("問題出在哪裡" if quality == "bad" else "這一句的效果"), 16, QuestUI.GREEN if good else (QuestUI.RED.lightened(0.2) if quality == "bad" else QuestUI.GOLD), false, true)
	hl.name = "ReactionHeading"
	heading.add_child(hl)
	rv.add_child(heading)
	_sync_meters(true)
	var nums := QuestUI.hbox(10)
	nums.add_child(QuestUI.chip("信任 %s%d" % ["+" if dt >= 0 else "", dt], QuestUI.GREEN if dt > 0 else (QuestUI.RED if dt < 0 else QuestUI.MUTED)))
	nums.add_child(QuestUI.chip("需求 %s%d" % ["+" if di >= 0 else "", di], QuestUI.GREEN if di > 0 else QuestUI.MUTED))
	if dc != 0:
		nums.add_child(QuestUI.chip("合規 %d" % dc, QuestUI.RED))
	rv.add_child(nums)
	var rl := QuestUI.label(reason, 14, QuestUI.TEXT, true)
	rl.name = "ReactionReason"
	rv.add_child(rl)
	var impact := QuestUI.label(_impact(quality, comp, key != null and str(key) != ""), 13, QuestUI.MUTED, true)
	impact.name = "ReactionImpact"
	rv.add_child(impact)
	_reaction.visible = true
	QuestUI.fade_in(_reaction, 0.0, 0.25, 0.0)
	# 回饋一定要看得到：捲到回饋的位置
	if _scene_scroll != null:
		await get_tree().process_frame
		if is_instance_valid(_scene_scroll) and is_instance_valid(_reaction):
			_scene_scroll.ensure_control_visible(_reaction)
	GameState.add_decision("需求訪談", str(a.get("question", "")), reason, quality, {"trust": dt, "insight": di, "compliance": dc})


func _set_mood(kind: String) -> void:
	var map := {"calm": ["平靜", QuestUI.MUTED], "relaxed": ["放鬆・願意多說", QuestUI.GREEN], "thinking": ["思考中", QuestUI.GOLD], "hesitant": ["猶豫", QuestUI.GOLD], "guarded": ["有些防備", QuestUI.RED]}
	var spec: Array = map.get(kind, map.calm)
	_mood_label.text = "客戶狀態：" + str(spec[0])
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(999)
	s.bg_color = Color(spec[1], 0.14)
	s.set_border_width_all(1)
	s.border_color = Color(spec[1], 0.6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	_mood.add_theme_stylebox_override("panel", s)
	# Subtle change on the portrait: a slight lean and tone, never a cartoon face
	if QuestUI.motion_off() or _portrait == null:
		return
	if _mood_tween and _mood_tween.is_valid():
		_mood_tween.kill()
	_mood_tween = create_tween()
	var tone := Color(1, 1, 1) if kind in ["calm", "relaxed"] else (Color(0.92, 0.9, 0.86) if kind in ["thinking", "hesitant"] else Color(0.85, 0.82, 0.8))
	# 姿勢：放鬆時微微前傾放大，防備時後退縮小，猶豫時稍微側身
	var lean: float = {"relaxed": 1.03, "guarded": 0.97}.get(kind, 1.0)
	var tilt: float = {"hesitant": -1.5, "thinking": 0.8}.get(kind, 0.0)
	_portrait.pivot_offset = _portrait.size * Vector2(0.5, 1.0)
	_mood_tween.set_parallel(true)
	_mood_tween.tween_property(_portrait, "self_modulate", tone, 0.4)
	_mood_tween.tween_property(_portrait, "scale", Vector2.ONE * lean, 0.4).set_trans(Tween.TRANS_CUBIC)
	_mood_tween.tween_property(_portrait, "rotation_degrees", tilt, 0.4).set_trans(Tween.TRANS_CUBIC)


func _refresh_side(sess: Dictionary) -> void:
	UI.clear(_known)
	var needs := GameState.client_needs()
	_clue_count.text = "%d/%d" % [mini(needs.size(), NEED_TARGET), NEED_TARGET]
	UI.clear(_clue_row)
	for k in range(NEED_TARGET):
		var got := k < needs.size()
		var slot := QuestUI.vbox(2)
		slot.add_child(QuestUI.icon("circle_check" if got else "question", 34.0, QuestUI.GOLD if got else QuestUI.MUTED))
		var cap := QuestUI.label(str(needs[k]) if got else "待發現", 12, QuestUI.TEXT if got else QuestUI.MUTED, true)
		cap.custom_minimum_size = Vector2(70, 0)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(cap)
		_clue_row.add_child(slot)
	if needs.is_empty():
		_known.add_child(QuestUI.label("還沒有取得線索。", 13, QuestUI.MUTED, true))
	for n in needs:
		var r := QuestUI.hbox(6)
		r.add_child(QuestUI.icon("check", 14.0, QuestUI.GREEN))
		r.add_child(QuestUI.label(str(n), 14, QuestUI.TEXT, true))
		_known.add_child(r)
	var used := bool(sess.get("hintUsed", false))
	_hint_btn.call("set_reason", "這次會談已用過提示" if used else "")
	if _hint_pending or used:
		_hint_btn.disabled = true


func _ask_hint() -> void:
	if _hint_pending or _pending or bool(_hint_btn.get("loading")) or _hint_btn.disabled:
		return
	if bool(GameState.my_session().get("hintUsed", false)):
		return
	_hint_pending = true
	_hint_btn.disabled = true
	_hint_btn.call("set_loading", true, "秘書整理中")
	GameState.spend_time(HINT_COST, "向秘書請求提示")
	GameState.record["hints"] = int(GameState.record.get("hints", 0)) + 1
	send({"type": "hint"})


func _show_hint(text: String) -> void:
	_hint_pending = false
	_hint_btn.call("set_loading", false)
	_hint_btn.disabled = true
	_hint_btn.call("set_reason", "這次會談已用過提示")
	GameState.add_decision("需求訪談", "請秘書提示", text, "ok")
	if not TutorialManager.explain("hint", [text]):
		_hint_box.text = "秘書提示：" + text
		_hint_box.visible = true


## 這個選擇對真實顧問工作的影響
func _impact(quality: String, comp: String, found_key: bool) -> String:
	if comp == "violation":
		return "真實會談中，保證獲利或施壓的說法可能違反金融消費者保護的規範，客戶也會失去信任。"
	if quality == "good" or found_key:
		return "真實會談中，先問到客戶最在意的事，後面的方案才有依據，客戶也更願意說出細節。"
	if quality == "bad":
		return "真實會談中，問不出需求的問題會讓客戶覺得被推銷，之後更難談到真正的風險。"
	return "真實會談中，每一個問題都要能幫你更了解客戶；問到線索才會讓方案更貼近需求。"


## 顧問回應卡：編號、圖示、回應內容、「選擇此回應」。整張卡為容器結構；滑過時邊框提亮，
## 按下縮放 0.96；底部的覆蓋按鈕接收點擊並轉發。
class OptionCard extends PanelContainer:
	signal pressed

	var btn: Button
	var visual: Control:
		get:
			return self
	var _sb: StyleBoxFlat
	var _label: Label
	var _pick: PanelContainer
	var _small := false
	var _hovered := false
	var _focused := false

	var disabled: bool:
		set(val):
			disabled = val
			if btn and is_instance_valid(btn):
				btn.disabled = val
			modulate.a = 0.45 if val else 1.0
			_update_style()
		get:
			if btn and is_instance_valid(btn):
				return btn.disabled
			return disabled

	func _init(no: int, icon_kind: String, line: String, small: bool) -> void:
		_small = small
		custom_minimum_size = Vector2(0, 122.0 if not small else 84.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color("#0D4038", 0.96)
		_sb.set_corner_radius_all(14)
		_sb.set_border_width_all(1)
		_sb.border_color = Color(1, 1, 1, 0.14)
		_sb.set_content_margin_all(12)
		add_theme_stylebox_override("panel", _sb)

		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n := QuestUI.label("%02d" % no, 14, QuestUI.GOLD)
		top.add_child(n)
		top.add_child(QuestUI.icon(icon_kind, 22.0, QuestUI.GOLD))
		v.add_child(top)

		_label = QuestUI.label(line, 15 if not small else 14, QuestUI.TEXT, true)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_label)

		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(spacer)

		_pick = PanelContainer.new()
		_pick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pick.size_flags_vertical = Control.SIZE_SHRINK_END
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(QuestUI.GOLD, 0.85)
		ps.set_corner_radius_all(10)
		ps.content_margin_top = 4
		ps.content_margin_bottom = 4
		_pick.add_theme_stylebox_override("panel", ps)
		var pl := QuestUI.label("選擇此回應　→", 13, QuestUI.INK, false, true)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_pick.add_child(pl)
		v.add_child(_pick)

		btn = Button.new()
		btn.flat = true
		btn.text = ""
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.tooltip_text = line
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		add_child(btn)

		btn.pressed.connect(func():
			AudioManager.play("ui_click")
			pressed.emit()
		)
		btn.mouse_entered.connect(_on_hover.bind(true))
		btn.mouse_exited.connect(_on_hover.bind(false))
		btn.button_down.connect(func(): _scale(0.96))
		btn.button_up.connect(func(): _scale(1.0))
		btn.focus_entered.connect(_on_focus.bind(true))
		btn.focus_exited.connect(_on_focus.bind(false))

	func set_line(line: String) -> void:
		tooltip_text = line
		if btn and is_instance_valid(btn):
			btn.tooltip_text = line
		if _label and is_instance_valid(_label):
			_label.text = line

	func _on_hover(on: bool) -> void:
		_hovered = on
		if disabled and on:
			return
		_update_style()
		if on:
			AudioManager.play("ui_hover")

	func _on_focus(on: bool) -> void:
		_focused = on
		_update_style()

	func _update_style() -> void:
		if _sb == null:
			return
		if _focused:
			_sb.border_color = Color(QuestUI.GOLD, 0.8)
			_sb.set_border_width_all(2)
		elif _hovered and not disabled:
			_sb.border_color = QuestUI.GOLD
			_sb.set_border_width_all(1)
		else:
			_sb.border_color = Color(1, 1, 1, 0.14)
			_sb.set_border_width_all(1)
		_sb.bg_color = Color("#0D4038", 0.96).lightened(0.08 if (_hovered and not disabled) else 0.0)

	func _scale(to: float) -> void:
		if QuestUI.motion_off():
			return
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2.ONE * to, 0.07 if to < 1.0 else 0.12)
