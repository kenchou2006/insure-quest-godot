extends "res://scripts/quest/pages/modal_base.gd"
## LifeEventModal (page 8) — 隨機人生事件與壓力測試, and every other station event in the same frame.
## The map dims, the event card flips open from the centre, the impact on time / trust / budget /
## needs is laid out, then the player chooses what to do:
##   claim / market / audit / settlement / seminar / info → read and continue
##   quiz, dilemma, review → the server's own choices (they change reputation, satisfaction, plans)
##   life change of the primary client → 2–3 responses that change what comes next (an extra
##     clarifying question, a need the plan must carry, or only a note) at a real time cost
## Heavy events play a low impact; light ones a short tone. Never 緊急預備金 as a stock answer.

const TWIST_OPTIONS := [
	{"id": "clarify", "title": "先向客戶釐清狀況", "cost": 30.0, "desc": "下次會談多一個釐清這件事的提問。", "flag": "twist_clarify"},
	{"id": "plan", "title": "把這件事納入方案", "cost": 60.0, "desc": "方案配置時，這件事會成為必須承接的需求。", "flag": "twist_plan"},
	{"id": "note", "title": "先記下來，下次會談再看", "cost": 0.0, "desc": "不花時間；到站簡報會留下這行紀錄。", "flag": "twist_note"},
]

var _ev: Dictionary = {}
var _snap := ""
var _key := ""
var _continue: Button
var _reason: Label
var _choices: VBoxContainer
var _outcome: VBoxContainer
var _sending := false
var _twist_choice := ""
var _severity := 0


func guide_lines() -> Array:
	return ["地圖上發生了事件。先看清楚它對時間、信任、預算和需求的影響，再決定怎麼回應。", "你的選擇會改變之後的會談或方案，不只是看看而已。"]


func key_rects() -> Array:
	return [rect_of(_continue)]


func highlight_rects() -> Array:
	return [rect_of(_choices)]


func build() -> void:
	timed = false
	_ev = GameState.my_event().duplicate(true)
	_snap = JSON.stringify(GameState.my_event())
	_key = "%s|%s" % [_ev.get("kind", ""), _ev.get("title", "")]
	_severity = _severity_of(_ev)
	max_card_width = 900.0
	var body := add_card(Color(QuestUI.RED, 0.6) if _severity >= 2 else Color(QuestUI.GOLD, 0.55))
	_render(body)


func refresh(_s: Dictionary) -> void:
	var ev := GameState.my_event()
	if ev.is_empty():
		return
	var key := "%s|%s" % [ev.get("kind", ""), ev.get("title", "")]
	if key != _key:
		# A different event replaced this one: rebuild in place
		_key = key
		_ev = ev.duplicate(true)
		_snap = JSON.stringify(ev)
		_severity = _severity_of(ev)
		_sending = false
		_twist_choice = ""
		TensionManager.set_flag("event_severity", _severity)
		AudioManager.play("event_major" if _severity >= 2 else "event_minor")
		UI.clear(card_body)
		_render(card_body)
		relayout()
		return
	var snap := JSON.stringify(ev)
	var changed := snap != _snap
	_snap = snap
	_ev = ev.duplicate(true)
	if changed:
		_sending = false
		_render_outcome()
		_sync()
		relayout()


func server_error(_msg: String) -> void:
	_sending = false
	_continue.call("set_loading", false)
	_render_choices()
	_sync()


func on_open() -> void:
	TensionManager.set_flag("event_severity", _severity)
	AudioManager.play("event_major" if _severity >= 2 else "event_minor")
	await enter()
	# The card flips open from the centre
	if not QuestUI.motion_off() and is_instance_valid(card):
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2(0.02, 1.0)
		var tw := card.create_tween()
		tw.tween_property(card, "scale:x", 1.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		AudioManager.play("card_flip")


func on_close() -> void:
	TensionManager.set_flag("event_severity", 0)


func _severity_of(ev: Dictionary) -> int:
	var claim: Variant = ev.get("claim")
	if claim is Dictionary:
		var r := str(claim.get("result", ""))
		return 2 if r == "broken" else (1 if r == "partial" else 0)
	var bad := 0
	for l in ev.get("lines", []):
		if str((l as Dictionary).get("tone", "")) == "bad":
			bad += 1
	var kind := str(ev.get("kind", ""))
	if kind in ["market", "audit"]:
		return 2 if bad > 0 else 0
	if kind == "life":
		return 1
	if kind in ["review", "dilemma"]:
		return 1
	return 0


func _is_twist() -> bool:
	return str(_ev.get("kind", "")) == "life" and not (_ev.get("claim") is Dictionary) and str(_ev.get("title", "")).begins_with("人生事件｜")


func _render(body: VBoxContainer) -> void:
	var kind := str(_ev.get("kind", "info"))
	var head := QuestUI.hbox(10)
	var icon_kind: String = "alert" if _severity >= 1 else {"market": "chart", "quiz": "question", "audit": "shield", "settlement": "coins", "seminar": "bulb", "checkup": "shield_check", "dilemma": "question", "review": "people"}.get(kind, "info")
	head.add_child(QuestUI.icon(icon_kind, 30.0, QuestUI.RED if _severity >= 2 else QuestUI.GOLD))
	var kind_name: String = {"life": "突發人生事件", "market": "市場快訊", "quiz": "合規訓練", "audit": "合規稽核", "settlement": "季度結算", "seminar": "顧問研討會", "info": "站點事件", "checkup": "保單健檢", "dilemma": "情境抉擇", "review": "客戶回訪"}.get(kind, "站點事件")
	head.add_child(QuestUI.title(kind_name, 24 if not phone() else 18))
	head.add_child(QuestUI.spacer())
	if _severity >= 2:
		head.add_child(QuestUI.chip("影響重大", QuestUI.RED))
	elif _severity == 1:
		head.add_child(QuestUI.chip("需要留意", QuestUI.GOLD))
	body.add_child(head)
	var title_text := str(_ev.get("title", ""))
	var dl: Variant = _ev.get("dilemma")
	if title_text == "" and dl is Dictionary:
		title_text = str(dl.get("title", ""))
	var t := QuestUI.title(title_text, 22 if not phone() else 17)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(t)
	var desc := str(_ev.get("body", ""))
	if desc != "":
		body.add_child(QuestUI.label(desc, 16, QuestUI.TEXT, true))
	var claim: Variant = _ev.get("claim")
	if claim is Dictionary:
		body.add_child(_claim_row(claim))
	# 立即影響
	var lines: Array = _ev.get("lines", [])
	if not lines.is_empty():
		var lh := QuestUI.hbox(8)
		lh.add_child(QuestUI.label("立即影響", 15, QuestUI.GOLD, false, true))
		lh.add_child(QuestUI.divider(0.2))
		body.add_child(lh)
		var grid := GridContainer.new()
		grid.columns = 1 if (narrow() or lines.size() < 2) else mini(3, lines.size())
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for l in lines:
			grid.add_child(_impact(l as Dictionary))
		body.add_child(grid)
	if _is_twist():
		var r := QuestUI.hbox(12)
		r.add_child(_impact({"text": "會談時間：回應方式會花掉不同的時間", "tone": "info"}))
		r.add_child(_impact({"text": "需求：客戶的需要可能因此改變", "tone": "ok"}))
		body.add_child(r)
	# What to do
	_choices = QuestUI.vbox(10)
	body.add_child(_choices)
	_render_choices()
	_outcome = QuestUI.vbox(8)
	body.add_child(_outcome)
	_render_outcome()
	var foot := QuestUI.hbox(10)
	foot.add_child(QuestUI.spacer())
	_continue = QuestUI.button("繼續", _on_continue, "primary", "next")
	_continue.name = "EventContinue"
	_continue.custom_minimum_size.x = 200
	foot.add_child(_continue)
	_reason = QuestUI.label("", 13, QuestUI.GOLD, true)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue.set("reason_label", _reason)
	UI.clear(card_footer)
	card_footer.add_child(foot)
	card_footer.add_child(_reason)
	_sync()


func _claim_row(claim: Dictionary) -> Control:
	var h := QuestUI.hbox(14)
	var res := str(claim.get("result", ""))
	var label_text: String = {"held": "保障承接", "partial": "部分承接", "broken": "保障缺口"}.get(res, res)
	h.add_child(QuestUI.chip(label_text, QuestUI.GREEN if res == "held" else (QuestUI.GOLD if res == "partial" else QuestUI.RED), 0.16, 15))
	for pair in [["損失", claim.get("loss", 0)], ["理賠", claim.get("covered", 0)], ["自付", claim.get("outOfPocket", 0)]]:
		var v := QuestUI.vbox(0)
		v.add_child(QuestUI.label(str(pair[0]), 12, QuestUI.MUTED))
		v.add_child(QuestUI.label("NT$ %s 萬" % _wan(float(pair[1])), 16, QuestUI.TEXT, false, true))
		h.add_child(v)
	return h


func _wan(ntd: float) -> String:
	var w := ntd / 10000.0
	return str(int(round(w))) if absf(w - round(w)) < 0.05 else "%.1f" % w


func _impact(l: Dictionary) -> Control:
	var tone := str(l.get("tone", "info"))
	var col := QuestUI.GREEN if tone == "good" else (QuestUI.RED if tone == "bad" else (QuestUI.GOLD if tone == "ok" else QuestUI.MUTED))
	var c := PanelContainer.new()
	c.add_theme_stylebox_override("panel", QuestUI.card_box(0.6, Color(col, 0.45), 12, 12))
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := QuestUI.hbox(10)
	c.add_child(h)
	h.add_child(QuestUI.icon("shield_check" if tone == "good" else ("alert" if tone in ["bad", "ok"] else "info"), 22.0, col))
	h.add_child(QuestUI.label(str(l.get("text", "")), 14, QuestUI.TEXT, true))
	(h.get_child(1) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


func _render_choices() -> void:
	if _choices == null:
		return
	UI.clear(_choices)
	var kind := str(_ev.get("kind", ""))
	var quiz: Variant = _ev.get("quiz")
	var dl: Variant = _ev.get("dilemma")
	var rv: Variant = _ev.get("review")
	if quiz is Dictionary:
		_choices.add_child(QuestUI.label("你會怎麼做？", 15, QuestUI.GOLD, false, true))
		var picked: Variant = quiz.get("picked")
		var opts: Array = quiz.get("options", [])
		for i in range(opts.size()):
			var idx := i
			var b := _choice_button("%s. %s" % [char(65 + i), opts[i]])
			b.name = "Quiz_%d" % i
			b.disabled = picked != null or _sending
			b.pressed.connect(func(): _send_choice({"type": "answer_quiz", "index": idx}))
			_choices.add_child(b)
	elif dl is Dictionary:
		if str(dl.get("prompt", "")) != "" and str(dl.prompt) != str(_ev.get("body", "")):
			_choices.add_child(QuestUI.label(str(dl.prompt), 15, QuestUI.TEXT, true))
		_choices.add_child(QuestUI.label("你希望如何回應？", 15, QuestUI.GOLD, false, true))
		var dpicked: Variant = dl.get("picked")
		for c in dl.get("choices", []):
			var cid := str((c as Dictionary).get("id", ""))
			var b2 := _choice_button(str(c.get("text", "")))
			b2.name = "Dilemma_" + cid.substr(0, 1)
			b2.disabled = dpicked != null or _sending
			b2.pressed.connect(func(): _send_choice({"type": "choose_dilemma", "choice": cid}))
			_choices.add_child(b2)
	elif rv is Dictionary:
		var change: Dictionary = rv.get("change", {})
		_choices.add_child(QuestUI.label("%s 的近況：%s" % [rv.get("clientName", "客戶"), change.get("title", "")], 15, QuestUI.GOLD, true, true))
		var rpicked: Variant = rv.get("picked")
		var cur: Array = (rv.get("current", {}) as Dictionary).get("cards", [])
		var grid := GridContainer.new()
		grid.columns = 2 if not narrow() else 1
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for cd in Net.static_data.get("cards", []):
			var cid2 := str((cd as Dictionary).get("id", ""))
			var has := cur.has(cid2)
			var b3 := _choice_button(("%s（已有）" if has else "建議加入：%s") % str(cd.get("title", "")))
			b3.name = "Review_" + cid2
			b3.disabled = has or rpicked != null or _sending
			b3.pressed.connect(func(): _send_choice({"type": "review", "card": cid2}))
			grid.add_child(b3)
		_choices.add_child(grid)
		var keep := _choice_button("聯絡客戶，確認現有規劃已足夠")
		keep.name = "Review_none"
		keep.disabled = rpicked != null or _sending
		keep.pressed.connect(func(): _send_choice({"type": "review", "card": "none"}))
		_choices.add_child(keep)
		var later := _choice_button("先不聯絡，暫緩拜訪")
		later.name = "Review_skip"
		later.disabled = rpicked != null or _sending
		later.pressed.connect(func(): _send_choice({"type": "review", "card": "skip"}))
		_choices.add_child(later)
	elif _is_twist():
		_choices.add_child(QuestUI.label("你希望如何回應？", 15, QuestUI.GOLD, false, true))
		var row: BoxContainer = QuestUI.hbox(10) if not narrow() else QuestUI.vbox(8)
		for o in QuestUI.shuffled(TWIST_OPTIONS):
			row.add_child(_twist_button(o))
		_choices.add_child(row)
	elif kind == "market" or kind == "life":
		pass


func _choice_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", QuestUI.fs(15))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(1)
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		s.bg_color = Color(QuestUI.CARD.lightened(0.05), 0.96)
		s.border_color = Color(1, 1, 1, 0.16)
		match st:
			"hover":
				s.border_color = QuestUI.GOLD
			"pressed":
				s.bg_color = Color(QuestUI.CARD.darkened(0.1), 0.96)
			"focus":
				s.bg_color = Color(0, 0, 0, 0)
				s.border_color = Color(QuestUI.GOLD, 0.8)
			"disabled":
				s.bg_color = Color(QuestUI.CARD, 0.45)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", QuestUI.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(QuestUI.TEXT, 0.5))
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	b.pressed.connect(func(): AudioManager.play("ui_click"))
	return b


func _twist_button(o: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Twist_" + str(o.id)
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 104)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.button_pressed = _twist_choice == str(o.id)
	var v := QuestUI.vbox(4)
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 14
	v.offset_right = -14
	v.offset_top = 10
	v.offset_bottom = -8
	b.add_child(v)
	v.add_child(QuestUI.label(str(o.title), 16, QuestUI.TEXT, true, true))
	v.add_child(QuestUI.label("花費 %s" % (QuestUI.mmss(float(o.cost)) if float(o.cost) > 0 else "無"), 13, QuestUI.GOLD))
	v.add_child(QuestUI.label(str(o.desc), 12, QuestUI.MUTED, true))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(1)
		s.bg_color = Color(QuestUI.CARD.lightened(0.05), 0.96)
		s.border_color = Color(1, 1, 1, 0.16)
		match st:
			"hover":
				s.border_color = QuestUI.GOLD
			"pressed", "hover_pressed":
				s.bg_color = Color(QuestUI.GREEN, 0.2)
				s.border_color = QuestUI.GREEN
				s.set_border_width_all(2)
			"focus":
				s.bg_color = Color(0, 0, 0, 0)
				s.border_color = Color(QuestUI.GOLD, 0.8)
			"disabled":
				s.bg_color = Color(QuestUI.CARD, 0.45)
		b.add_theme_stylebox_override(st, s)
	b.disabled = _twist_choice != ""
	b.pressed.connect(func(): _pick_twist(o))
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	return b


func _pick_twist(o: Dictionary) -> void:
	if _twist_choice != "":
		return
	_twist_choice = str(o.id)
	AudioManager.play("ui_click")
	var tw_title := str(_ev.get("body", ""))
	match str(o.id):
		"clarify":
			GameState.set_flag("twist_clarify", true)
		"plan":
			GameState.set_flag("twist_plan", true)
		"note":
			GameState.set_flag("twist_note", tw_title)
	if float(o.cost) > 0:
		GameState.spend_time(float(o.cost), "人生事件：" + str(o.title))
	GameState.add_decision("人生事件", "%s：%s" % [tw_title, o.title], str(o.desc) + ("（會談時間 −%s）" % QuestUI.mmss(float(o.cost)) if float(o.cost) > 0 else ""), "good" if str(o.id) != "note" else "ok", {"time": -float(o.cost)})
	GameState.set_value("events", (GameState.record.get("events", []) as Array) + [{"event": tw_title, "choice": str(o.title)}])
	_render_choices()
	UI.clear(_outcome)
	_outcome.add_child(QuestUI.label("已記錄：" + str(o.desc), 14, QuestUI.GREEN, true))
	_sync()
	relayout()


func _send_choice(action: Dictionary) -> void:
	if _sending:
		return
	_sending = true
	_render_choices()
	send(action)


func _render_outcome() -> void:
	if _outcome == null:
		return
	if _is_twist():
		return
	UI.clear(_outcome)
	var out: Variant = null
	var quiz: Variant = _ev.get("quiz")
	if quiz is Dictionary and quiz.get("picked") != null:
		var right := int(quiz.get("answer", -1)) == int(quiz.picked)
		AudioManager.play("trust_up" if right else "trust_down")
		out = {"title": "答對了" if right else "這題選錯了", "body": str(quiz.get("explain", "")), "tone": "good" if right else "bad"}
		if not right:
			var opts: Array = quiz.get("options", [])
			var ai := int(quiz.get("answer", -1))
			if ai >= 0 and ai < opts.size():
				out.body = "較好的選擇是「%s」。%s" % [opts[ai], out.body]
		_record_once("quiz", "合規測驗：" + str(quiz.get("q", _ev.get("body", ""))), str(out.body), "good" if right else "bad")
	var dl: Variant = _ev.get("dilemma")
	if dl is Dictionary and dl.get("outcome") is Dictionary:
		out = dl.outcome
		_record_once("dilemma", "情境抉擇：" + str(dl.get("title", "")), "%s %s" % [out.get("title", ""), out.get("body", "")], str(out.get("tone", "ok")))
	var rv: Variant = _ev.get("review")
	if rv is Dictionary and rv.get("outcome") is Dictionary:
		out = rv.outcome
		_record_once("review", "客戶回訪：" + str(rv.get("clientName", "")), "%s %s" % [out.get("title", ""), out.get("body", "")], str(out.get("tone", "ok")))
	if out is Dictionary:
		var tone := str((out as Dictionary).get("tone", "info"))
		var col := QuestUI.GREEN if tone == "good" else (QuestUI.RED if tone == "bad" else QuestUI.GOLD)
		var c := QuestUI.card(null, 0.7, Color(col, 0.6))
		var v := QuestUI.vbox(6)
		c.add_child(v)
		v.add_child(QuestUI.label(str(out.get("title", "結果")), 16, col, true, true))
		if str(out.get("body", "")) != "":
			v.add_child(QuestUI.label(str(out.body), 14, QuestUI.TEXT, true))
		if str(out.get("effects", "")) != "":
			v.add_child(QuestUI.label("影響：" + str(out.effects), 13, QuestUI.GOLD, true))
		_outcome.add_child(c)
		QuestUI.fade_in(c, 0.0, 0.3, 0.0)


func _record_once(kind: String, title_text: String, detail: String, quality: String) -> void:
	var seen: Dictionary = GameState.flag("event_logged", {}) if GameState.flag("event_logged", {}) is Dictionary else {}
	var key := kind + ":" + _key
	if seen.has(key):
		return
	seen[key] = true
	GameState.set_flag("event_logged", seen)
	GameState.add_decision("站點事件", title_text, detail, quality)


func _required_done() -> String:
	var quiz: Variant = _ev.get("quiz")
	if quiz is Dictionary and quiz.get("picked") == null:
		return "請先選擇一個答案"
	var dl: Variant = _ev.get("dilemma")
	if dl is Dictionary and dl.get("picked") == null:
		return "請先選擇你的回應"
	var rv: Variant = _ev.get("review")
	if rv is Dictionary and rv.get("picked") == null:
		return "請先決定如何回訪"
	if _is_twist() and _twist_choice == "":
		return "請先選擇如何回應這個事件"
	return ""


func _sync() -> void:
	if _continue == null:
		return
	if not _sending:
		_continue.call("set_reason", _required_done())


func _on_continue() -> void:
	if _sending or _required_done() != "":
		return
	_sending = true
	_continue.call("set_loading", true, "前往下一站")
	TensionManager.set_flag("event_severity", 0)
	send({"type": "continue"})
