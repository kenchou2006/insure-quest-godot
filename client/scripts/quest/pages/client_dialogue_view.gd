extends "res://scripts/quest/pages/page_base.gd"
## ClientDialogueView (page 3) — 互動式客戶會談.
## Left: the client's portrait with a small, changing state (放鬆 / 思考中 / 猶豫 / 防備).
## Centre: the conversation, then 2–4 reply options in a fresh random order each round (every
## option is a reasonable advisor line; they differ in listening, need, compliance, timing), and a
## free line through the AI client. Nothing shows a score or a lean before the choice.
## After a choice: the client's words type out first, then the trust / need change and a short
## reason — never just right / wrong. A question that uncovers nothing costs meeting time.
## Right: client status, clues known so far, the 秘書提示 (once per meeting) and 整理需求線索.

const NO_KEY_COST := 20.0
const HINT_COST := 30.0

var _portrait: TextureRect
var _mood: PanelContainer
var _mood_label: Label
var _log: VBoxContainer
var _log_scroll: ScrollContainer
var _task: Label
var _options: VBoxContainer
var _reaction: PanelContainer
var _input: LineEdit
var _send: Button
var _input_row: Control
var _talk_note: Label
var _status: Control
var _known: VBoxContainer
var _next: Button
var _hint_btn: Button
var _hint_box: Label
var _shown_asked := 0
var _pending := false
var _before: Dictionary = {}
var _typing_label: Label = null
var _typing_tween: Tween
var _stream_label: Label = null
var _last_adv: Label = null
var _mood_tween: Tween
var _last_hint := ""


func guide_lines() -> Array:
	return ["這是客戶會談。每一輪挑一句最合適的話，先聽懂客戶，再談方案。", "選項順序每次都不同，也不會先告訴你哪一個比較好；選完才會看到客戶的反應與原因。"]


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
	# Left: who is talking
	var left := QuestUI.card(null, 0.92)
	var lv := QuestUI.vbox(10)
	left.add_child(lv)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.custom_minimum_size = Vector2(0, 150 if narrow() else (130 if compact() else 300))
	_portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL if not narrow() else Control.SIZE_FILL
	_portrait.material = UI.get_rounded_material(0.06)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.texture = GameState.client_portrait()
	lv.add_child(_portrait)
	var c := GameState.current_client()
	lv.add_child(QuestUI.title(str(c.get("name", "客戶")), 20))
	lv.add_child(QuestUI.label("%s%s" % ["%d 歲・" % int(c.get("age", 0)) if int(c.get("age", 0)) > 0 else "", str(c.get("job", ""))], 13, QuestUI.MUTED, true))
	_mood = PanelContainer.new()
	_mood_label = QuestUI.label("", 14, QuestUI.TEXT)
	_mood.add_child(_mood_label)
	lv.add_child(_mood)
	_set_mood("calm")
	var tw: Variant = GameState.my_session().get("twist")
	if tw is Dictionary and str(tw.get("title", "")) != "":
		lv.add_child(QuestUI.label("近況：" + str(tw.title), 13, QuestUI.GOLD, true))
	# Centre: conversation and choices
	var center := QuestUI.card(null, 0.94)
	var cv := QuestUI.vbox(10)
	center.add_child(cv)
	cv.add_child(QuestUI.header("chat", "客戶會談", "", QuestUI.MUTED))
	_log = QuestUI.vbox(10)
	_log_scroll = QuestUI.scroll(_log)
	_log_scroll.custom_minimum_size = Vector2(0, 130 if not compact() else 80)
	cv.add_child(_log_scroll)
	_task = QuestUI.label("", 15, QuestUI.GOLD, true)
	cv.add_child(_task)
	_options = QuestUI.vbox(8)
	cv.add_child(_options)
	_reaction = PanelContainer.new()
	_reaction.add_theme_stylebox_override("panel", QuestUI.card_box(0.6, Color(1, 1, 1, 0.1), 12, 12))
	_reaction.visible = false
	cv.add_child(_reaction)
	_input_row = QuestUI.vbox(4)
	var ir := QuestUI.hbox(8)
	_input = LineEdit.new()
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
	cv.add_child(_input_row)
	# Right: status, known clues; 下一步 / 返回 pinned under them
	_status = ClientStatusPanel.new(compact() or narrow())
	var known_card := QuestUI.card(null, 0.92)
	var kv := QuestUI.vbox(6)
	known_card.add_child(kv)
	kv.add_child(QuestUI.header("search", "已知線索"))
	_known = QuestUI.vbox(4)
	kv.add_child(_known)
	_hint_btn = QuestUI.button("請秘書給一次提示（−0:30）", _ask_hint, "quiet", "bulb")
	_hint_btn.name = "HintButton"
	_hint_box = QuestUI.label("", 14, QuestUI.TEXT, true)
	_hint_box.visible = false
	_next = QuestUI.button("下一步：整理需求線索", func(): go.emit("clues", {}), "primary", "next")
	_next.name = "NextStep"
	var back: Button = QuestUI.button("返回任務簡報", _back_to_brief, "quiet", "back")
	back.name = "BackButton"
	var right := side([_status, known_card, _hint_btn, _hint_box], [secretary_button(), _next, back])
	v.add_child(columns([QuestUI.scroll(left) if compact() and not narrow() else left, QuestUI.scroll(center) if not narrow() else center, right], [0.9, 1.7, 1.0]))
	Net.stream_text.connect(_on_stream)


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
	_status.call("refresh")
	_refresh_side(sess)
	if not _pending and _typing_label == null:
		_build_options(sess)
	var hint := str(sess.get("hint", "")) if sess.get("hint") != null else ""
	if hint != "" and hint != _last_hint:
		_last_hint = hint
		_show_hint(hint)


func server_error(_msg: String) -> void:
	_pending = false
	_send.call("set_loading", false)
	_hint_btn.call("set_loading", false)
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
	await get_tree().process_frame
	if is_instance_valid(_log_scroll):
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


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
		# 2–4 choices, fresh order every round (the best one is never fixed in place)
		remaining = QuestUI.shuffled(remaining)
		var shown := remaining.slice(0, mini(4, remaining.size()))
		for qd in shown:
			var b: Button = _option_button(str(qd.get("text", "")))
			b.name = "Option_" + str(qd.get("id", ""))
			var qid := str(qd.get("id", ""))
			b.pressed.connect(func(): _ask(qid))
			b.disabled = busy
			_options.add_child(b)
	# Follow-up on the life change, when the advisor chose to clarify it
	var tw: Variant = sess.get("twist")
	if bool(GameState.flag("twist_clarify", false)) and not bool(GameState.flag("twist_clarified", false)) and tw is Dictionary and int(sess.get("talkLeft", 0)) > 0:
		var line := "關於「%s」，最近對您的生活影響大嗎？" % str(tw.get("title", "最近的變化"))
		var tb: Button = _option_button(line)
		tb.name = "Option_twist"
		tb.pressed.connect(func():
			GameState.set_flag("twist_clarified", true)
			_talk(line)
		)
		tb.disabled = busy
		_options.add_child(tb)
	# Free line through the AI client
	var talk_left := int(sess.get("talkLeft", 0))
	var free_left := int(sess.get("freeLeft", 0))
	_input_row.visible = talk_left > 0 or free_left > 0
	_send.call("set_reason", "客戶正在回應" if busy else "")
	_input.editable = not busy
	_talk_note.text = ("對話剩 %d 輪" % talk_left) if talk_left > 0 else ("自由提問剩 %d 次" % free_left)
	if not QuestUI.motion_off():
		for i in range(_options.get_child_count()):
			QuestUI.fade_in(_options.get_child(i), i * 0.05, 0.2, 0.0)


func _option_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 48)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", QuestUI.fs(16))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(1)
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		# One neutral look for every option: the hover is the same gold frame for all
		s.bg_color = Color(QuestUI.CARD.lightened(0.04), 0.95)
		s.border_color = Color(1, 1, 1, 0.14)
		if st == "hover":
			s.border_color = QuestUI.GOLD
			s.bg_color = Color(QuestUI.CARD.lightened(0.1), 0.98)
		elif st == "pressed":
			s.bg_color = Color(QuestUI.CARD.darkened(0.1), 0.98)
		elif st == "focus":
			s.bg_color = Color(0, 0, 0, 0)
			s.border_color = Color(QuestUI.GOLD, 0.8)
		elif st == "disabled":
			s.bg_color = Color(QuestUI.CARD, 0.5)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", QuestUI.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(QuestUI.TEXT, 0.4))
	b.mouse_entered.connect(func():
		if not b.disabled:
			AudioManager.play("ui_hover")
	)
	b.pressed.connect(func(): AudioManager.play("ui_click"))
	return b


func _ask(qid: String) -> void:
	if _pending:
		return
	_pending = true
	_before = GameState.metrics().duplicate()
	_reaction.visible = false
	for b in _options.get_children():
		(b as Button).disabled = true
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
			reason += "（會談時間 −0:%02d）" % int(NO_KEY_COST)
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
	var nums := QuestUI.hbox(10)
	nums.add_child(QuestUI.chip("信任 %s%d" % ["+" if dt >= 0 else "", dt], QuestUI.GREEN if dt > 0 else (QuestUI.RED if dt < 0 else QuestUI.MUTED)))
	nums.add_child(QuestUI.chip("需求 %s%d" % ["+" if di >= 0 else "", di], QuestUI.GREEN if di > 0 else QuestUI.MUTED))
	if dc != 0:
		nums.add_child(QuestUI.chip("合規 %d" % dc, QuestUI.RED))
	rv.add_child(nums)
	rv.add_child(QuestUI.label(reason, 14, QuestUI.TEXT, true))
	_reaction.visible = true
	QuestUI.fade_in(_reaction, 0.0, 0.25, 0.0)
	GameState.add_decision("需求訪談", str(a.get("question", "")), reason, quality, {"trust": dt, "insight": di})
	_status.call("refresh")


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
	_mood_tween.tween_property(_portrait, "self_modulate", tone, 0.4)


func _refresh_side(sess: Dictionary) -> void:
	UI.clear(_known)
	var needs := GameState.client_needs()
	if needs.is_empty():
		_known.add_child(QuestUI.label("還沒有取得線索。", 13, QuestUI.MUTED, true))
	for n in needs:
		var r := QuestUI.hbox(6)
		r.add_child(QuestUI.icon("check", 14.0, QuestUI.GREEN))
		r.add_child(QuestUI.label(str(n), 14, QuestUI.TEXT, true))
		_known.add_child(r)
	var used := bool(sess.get("hintUsed", false))
	_hint_btn.call("set_reason", "這次會談已用過提示" if used else "")


func _ask_hint() -> void:
	if bool(GameState.my_session().get("hintUsed", false)):
		return
	_hint_btn.call("set_loading", true, "秘書整理中")
	GameState.spend_time(HINT_COST, "向秘書請求提示")
	GameState.record["hints"] = int(GameState.record.get("hints", 0)) + 1
	send({"type": "hint"})


func _show_hint(text: String) -> void:
	_hint_btn.call("set_loading", false)
	_hint_btn.call("set_reason", "這次會談已用過提示")
	GameState.add_decision("需求訪談", "請秘書提示", text, "ok")
	if not TutorialManager.explain("hint", [text]):
		_hint_box.text = "秘書提示：" + text
		_hint_box.visible = true
