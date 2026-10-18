extends "res://scripts/quest/pages/page_base.gd"
## ObjectionBuilderView (page 6) — 客戶異議處理.
## Three steps, each with options in a new random order: ① 先理解 ② 再釐清 ③ 提出下一步.
## Steps 1–2 are listening / empathy lines judged here; step 3 is this client's own reply set,
## judged by the server. Nothing marks a better option before sending. After 送出回應 (a critical
## decision) the whole answer shows first, a 0.55 s pause, then the client's real reaction and an
## evaluation of 傾聽 / 同理 / 需求掌握 / 清楚程度 / 合規風險 with the reason for each.

const SEG1 := [
	{"text": "我能理解您會這樣想，很多人一開始也有同樣的顧慮。", "q": "good", "l": 1, "e": 2, "c": 0, "why": "先接住客戶的感受，對話才有空間往下談。"},
	{"text": "謝謝您直接說出來，這個想法很常見，我們一起看看。", "q": "good", "l": 1, "e": 1, "c": 1, "why": "肯定客戶願意說出想法，並邀請一起看，氣氛不對立。"},
	{"text": "其實這個問題不用太擔心，我們的方案幾乎都能處理。", "q": "bad", "l": -1, "e": -2, "c": 0, "why": "直接帶過客戶的擔心，沒有先確認他的感受。"},
	{"text": "您現在還年輕，應該不會那麼快遇到這些問題吧？", "q": "bad", "l": -2, "e": -1, "c": 0, "why": "替客戶下結論，等於否定了他提出的顧慮。"},
	{"text": "這個我懂，不過我們還是先把方案看完再說。", "q": "ok", "l": -1, "e": 0, "c": 1, "why": "有回應，但急著回到方案，客戶會覺得沒被聽完。"},
]
const SEG2 := [
	{"text": "可以和我多說一點嗎？您最在意的是哪一部分？", "q": "good", "l": 2, "e": 1, "c": 1, "why": "開放式提問，讓客戶自己說出真正的顧慮。"},
	{"text": "這個顧慮是最近才有的，還是一直都這樣想？", "q": "good", "l": 2, "e": 0, "c": 1, "why": "先弄清楚顧慮從哪裡來，才知道要回應的是什麼。"},
	{"text": "您希望保障額度大概多少？我先幫您算一下。", "q": "ok", "l": 0, "e": 0, "c": 1, "why": "直接跳到數字，還沒弄清楚客戶真正擔心什麼。"},
	{"text": "您的主要需求應該是醫療保障，對嗎？我建議先規劃這部分。", "q": "bad", "l": -2, "e": 0, "c": 0, "why": "用引導式問題替客戶決定需求。"},
	{"text": "您是擔心保費太貴，還是擔心用不到？", "q": "ok", "l": 1, "e": 0, "c": 1, "why": "有在釐清，但只給兩個選項，可能漏掉真正的原因。"},
]
const STEPS := [["先理解", "表達同理，建立信任。"], ["再釐清", "透過提問，深入了解客戶的情況。"], ["提出下一步", "回應疑慮，給出具體、可執行的下一步。"]]

var _cols: Array = []
var _choice: Array = [-1, -1, -1]
var _opts: Array = [[], [], []]
var _preview: Label
var _client_line: Label
var _done_label: Label
var _send: Button
var _reason: Label
var _eval: VBoxContainer
var _status: Control
var _after: Control
var _reaction: VBoxContainer
var _sending := false
var _revealed := false
var _before: Dictionary = {}
## 用自己的話回應: the AI grades a free reply (server objection_free) instead of the three steps
var _free_mode := false
var _free_text := ""
var _free_input: LineEdit
var _free_send: Button


func guide_lines() -> Array:
	return ["客戶提出疑慮了。分三段組成你的回應：先理解、再釐清、最後提出下一步。", "每段選一句，順序每次不同；送出後會先看到完整的回答，再看到客戶的反應與評估。"]


func help_lines() -> Array:
	return ["好的回應先接住感受，再用開放式問題問清楚，最後給客戶一個不施壓的下一步。", "任何保證結果或催促成交的說法，都會傷害信任與合規。"]


func idle_lines() -> Array:
	return ["想像你是客戶：哪一句會讓你覺得被聽見？從第一段開始。"]


func key_rects() -> Array:
	return [rect_of(_send)]


func highlight_rects() -> Array:
	var out: Array = []
	for c in _cols:
		out.append(rect_of(c))
	return out


func build() -> void:
	add_background()
	var v := add_frame()
	var sess := GameState.my_session()
	var obj: Dictionary = sess.get("objection", {}) if sess.get("objection") is Dictionary else {}
	_restore_options(obj)
	# Left: the composer
	var left := QuestUI.card(null, 0.94)
	var lv := QuestUI.vbox(12)
	left.add_child(lv)
	var top := QuestUI.hbox(10)
	top.add_child(QuestUI.icon("chat", 30.0, QuestUI.GOLD))
	var tv := QuestUI.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(QuestUI.title("異議回應組合", 26 if not phone() else 19))
	tv.add_child(QuestUI.label("面對客戶的疑慮，選出最合適的回應，組成完整且專業的對話。", 13, QuestUI.MUTED, true))
	top.add_child(tv)
	var reset: Button = QuestUI.button("重設選擇", _reset, "secondary", "refresh")
	reset.name = "ResetButton"
	top.add_child(reset)
	_done_label = QuestUI.label("已完成 0/3", 17, QuestUI.GOLD, false, true)
	top.add_child(_done_label)
	lv.add_child(top)
	var plan: Variant = sess.get("plan")
	if plan is Dictionary:
		var q := str(plan.get("quality", ""))
		var note := "方案評估：%s" % {"good": "配置與需求相符", "ok": "配置大致合理", "bad": "配置與需求落差大"}.get(q, "已提交")
		lv.add_child(QuestUI.label(note, 13, QuestUI.MUTED, true))
	var cols: BoxContainer = QuestUI.hbox(12) if not narrow() else QuestUI.vbox(12)
	for i in range(3):
		var col := _build_col(i)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(col)
		_cols.append(col)
	lv.add_child(cols)
	# Dialogue preview
	var pv := QuestUI.card(null, 0.6)
	var pvv := QuestUI.vbox(8)
	pv.add_child(pvv)
	pvv.add_child(QuestUI.header("chat", "對話預覽", "（會顯示你選的三句）", QuestUI.MUTED))
	var ph: BoxContainer = QuestUI.hbox(12) if not narrow() else QuestUI.vbox(8)
	pvv.add_child(ph)
	_client_line = _bubble(str(obj.get("text", "")), true)
	ph.add_child(_client_line.get_parent().get_parent())
	_preview = _bubble("請從上方各段選擇一句話，組成你的回應……", false)
	ph.add_child(_preview.get_parent().get_parent())
	lv.add_child(pv)
	# Or in the advisor's own words, graded by the AI (the original free reply stays available)
	var free_row := QuestUI.hbox(8)
	_free_input = LineEdit.new()
	_free_input.placeholder_text = "或用自己的話回應客戶（AI 評分）"
	_free_input.max_length = 200
	_free_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_input.custom_minimum_size = Vector2(0, 44)
	_free_input.add_theme_font_size_override("font_size", QuestUI.fs(15))
	free_row.add_child(_free_input)
	_free_send = QuestUI.button("送出自己的回應", _on_free_send, "secondary", "send")
	_free_send.name = "SendFreeReply"
	free_row.add_child(_free_send)
	lv.add_child(free_row)
	_reaction = QuestUI.vbox(8)
	_reaction.visible = false
	lv.add_child(_reaction)
	# Right: context, evaluation (after sending); 送出 pinned
	_status = ClientStatusPanel.new(true)
	var ctx_card := QuestUI.card(null, 0.92)
	var cv := QuestUI.vbox(6)
	ctx_card.add_child(cv)
	cv.add_child(QuestUI.header("doc", "情境說明"))
	var who := GameState.client_name()
	cv.add_child(QuestUI.label("%s 對方案提出疑慮。請選擇合適的回應，展現同理心、專業提問與具體的下一步，建立信任並推進對話。" % (who if who != "" else "客戶"), 14, QuestUI.TEXT, true))
	var ev_card := QuestUI.card(null, 0.92)
	_eval = QuestUI.vbox(8)
	ev_card.add_child(_eval)
	_eval_placeholder()
	_send = QuestUI.button("送出回應", _on_send, "primary", "send")
	_send.name = "SendReply"
	_reason = QuestUI.label("", 13, QuestUI.GOLD, true)
	_send.set("reason_label", _reason)
	_after = QuestUI.button("下一步：合規檢核", _to_scan, "primary", "next")
	_after.name = "ToCompliance"
	_after.visible = false
	var right := side([_status, ctx_card, ev_card], [secretary_button(), review_button("回顧方案配置", ["方案配置", "公事包"]), _send, _reason, _after])
	v.add_child(columns([QuestUI.scroll(left) if not narrow() else left, right], [2.6, 1.0]))
	_sync()


func refresh(_s: Dictionary) -> void:
	if is_instance_valid(_status):
		_status.call("refresh")
	var sess := GameState.my_session()
	if _sending and not _revealed and sess.get("objectionReply") is Dictionary:
		_revealed = true
		_reveal(sess)


func server_error(_msg: String) -> void:
	_sending = false
	_free_mode = false
	GameState.set_flag("hold_objection", false)
	_send.call("set_loading", false)
	_free_send.call("set_loading", false)
	for col in _cols:
		for b in (col as Control).find_children("Seg*", "Button", true, false):
			(b as Button).disabled = false
	_sync()


func _restore_options(obj: Dictionary) -> void:
	var saved: Dictionary = GameState.selected_dialogue()
	if saved.has("opts"):
		_opts = saved.opts
		_choice = saved.get("choice", [-1, -1, -1])
		return
	# Steps 1–2: three of five, always at least one considerate line; step 3: the client's set
	for k in range(2):
		var bank: Array = (SEG1 if k == 0 else SEG2).duplicate()
		var goods: Array = bank.filter(func(o): return o.q == "good")
		var rest: Array = bank.filter(func(o): return o.q != "good")
		var pick: Array = [QuestUI.shuffled(goods)[0]]
		pick.append_array(QuestUI.shuffled(rest).slice(0, 1))
		var others: Array = bank.filter(func(o): return not pick.has(o))
		pick.append(QuestUI.shuffled(others)[0])
		_opts[k] = QuestUI.shuffled(pick)
	var server_opts: Array = []
	var texts: Array = obj.get("options", [])
	for i in range(texts.size()):
		server_opts.append({"text": str(texts[i]), "index": i})
	_opts[2] = QuestUI.shuffled(server_opts)
	_save()


func _save() -> void:
	GameState.set_value("dialogue", {"opts": _opts, "choice": _choice})


func _build_col(i: int) -> Control:
	var col := QuestUI.card(null, 0.55)
	var v := QuestUI.vbox(8)
	col.add_child(v)
	var h := QuestUI.hbox(8)
	var num := _num_badge(i + 1)
	h.add_child(num)
	var tv := QuestUI.vbox(0)
	tv.add_child(QuestUI.title(STEPS[i][0], 19))
	tv.add_child(QuestUI.label(STEPS[i][1], 12, QuestUI.MUTED, true))
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(tv)
	v.add_child(h)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var opts: Array = _opts[i]
	for k in range(opts.size()):
		var b := _option(str(opts[k].text), group)
		b.name = "Seg%d_%d" % [i + 1, k]
		b.button_pressed = _choice[i] == k
		var seg := i
		var idx := k
		b.toggled.connect(func(on: bool):
			if on:
				_pick(seg, idx)
		)
		v.add_child(b)
	return col


func _num_badge(n: int) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = QuestUI.GOLD
	s.set_corner_radius_all(999)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.add_child(QuestUI.title(str(n), 18, QuestUI.INK))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


func _option(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 64)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", QuestUI.fs(15))
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(1)
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 10
		s.content_margin_bottom = 10
		s.bg_color = Color(QuestUI.CARD.lightened(0.03), 0.95)
		s.border_color = Color(1, 1, 1, 0.14)
		match st:
			"hover":
				s.border_color = QuestUI.GOLD
			"pressed", "hover_pressed":
				# Chosen: the same ivory card for any option (never a right / wrong colour)
				s.bg_color = Color("#F1EBDD")
				s.border_color = QuestUI.GOLD
				s.set_border_width_all(2)
			"focus":
				s.bg_color = Color(0, 0, 0, 0)
				s.border_color = Color(QuestUI.GOLD, 0.8)
			"disabled":
				s.bg_color = Color(QuestUI.CARD, 0.5)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_color_override("font_color", QuestUI.TEXT)
	b.add_theme_color_override("font_hover_color", QuestUI.TEXT)
	b.add_theme_color_override("font_pressed_color", QuestUI.INK)
	b.add_theme_color_override("font_hover_pressed_color", QuestUI.INK)
	b.add_theme_color_override("font_disabled_color", Color(QuestUI.TEXT, 0.45))
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	b.pressed.connect(func(): AudioManager.play("ui_click"))
	return b


func _bubble(text: String, client: bool) -> Label:
	var wrap := QuestUI.vbox(4)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(QuestUI.label("客戶" if client else "你的回應", 12, QuestUI.MUTED))
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.bg_color = Color("#E9E4D6") if client else Color(QuestUI.GREEN, 0.2)
	if not client:
		s.set_border_width_all(1)
		s.border_color = Color(QuestUI.GREEN, 0.5)
	p.add_theme_stylebox_override("panel", s)
	var l := QuestUI.label(text, 15, QuestUI.INK if client else QuestUI.TEXT, true)
	p.add_child(l)
	wrap.add_child(p)
	return l


func _pick(seg: int, idx: int) -> void:
	if _sending:
		return
	_choice[seg] = idx
	_save()
	_sync()


func _reset() -> void:
	if _sending:
		return
	_choice = [-1, -1, -1]
	_save()
	for col in _cols:
		for b in (col as Control).find_children("Seg*", "Button", true, false):
			(b as Button).set_pressed_no_signal(false)
	_sync()


func _composed() -> String:
	if _free_mode:
		return _free_text
	var parts: Array = []
	for i in range(3):
		if _choice[i] >= 0:
			parts.append(str(_opts[i][_choice[i]].text))
	return "".join(parts)


func _sync() -> void:
	var n := 0
	for c in _choice:
		if c >= 0:
			n += 1
	_done_label.text = "已完成 %d/3" % n
	var t := _composed()
	_preview.text = t if t != "" else "請從上方各段選擇一句話，組成你的回應……"
	if not _sending:
		_send.call("set_reason", "" if n == 3 else "請完成三段回應（已完成 %d/3）" % n)


func _eval_placeholder() -> void:
	UI.clear(_eval)
	var h := QuestUI.hbox(8)
	h.add_child(QuestUI.icon("chart", 22.0, QuestUI.GOLD))
	h.add_child(QuestUI.title("回應評估", 19))
	h.add_child(QuestUI.label("（送出後顯示）", 12, QuestUI.MUTED))
	h.add_child(QuestUI.spacer())
	h.add_child(QuestUI.icon("lock", 18.0, QuestUI.MUTED))
	_eval.add_child(h)
	_eval.add_child(QuestUI.label("送出回應後，會顯示客戶信任的變化，以及傾聽、同理、需求掌握、清楚程度與合規風險的評估。", 13, QuestUI.MUTED, true))
	var row := QuestUI.hbox(10)
	for cap in ["客戶信任度", "合規檢核"]:
		var c := QuestUI.card(null, 0.5)
		var cv := QuestUI.vbox(4)
		c.add_child(cv)
		cv.add_child(QuestUI.label(cap, 13, QuestUI.TEXT))
		cv.add_child(QuestUI.title("— —", 22, QuestUI.MUTED))
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(c)
	_eval.add_child(row)


func _on_send() -> void:
	if _sending:
		return
	var ok: bool = await layer.call("critical", _send, "送出回應", "客戶會聽到你組成的完整回答：\n「%s」" % _composed(), "確認送出")
	if not ok or not is_instance_valid(self):
		return
	_sending = true
	_send.call("set_loading", true, "客戶聆聽中")
	for col in _cols:
		for b in (col as Control).find_children("Seg*", "Button", true, false):
			(b as Button).disabled = true
	# The full answer is on screen first; the page stays for the reaction (layer holds it here)
	QuestUI.pulse_once(_preview.get_parent(), 1.02)
	GameState.set_flag("hold_objection", true)
	_before = GameState.metrics().duplicate()
	await get_tree().create_timer(0.5).timeout
	var seg3: Dictionary = _opts[2][_choice[2]]
	send({"type": "objection", "index": int(seg3.get("index", 0))})


func _on_free_send() -> void:
	if _sending:
		return
	var t := _free_input.text.strip_edges()
	if t.length() < 4:
		layer.call("show_toast", "請先寫下至少一句完整的回應", "warning")
		return
	var ok: bool = await layer.call("critical", _free_send, "送出自己的回應", "AI 會依同理、需求、清楚與合規評估這段回應：\n「%s」" % t, "確認送出")
	if not ok or not is_instance_valid(self):
		return
	_free_mode = true
	_free_text = t
	_sending = true
	_free_send.call("set_loading", true, "AI 評估中")
	_send.call("set_reason", "已送出自己的回應")
	_preview.text = t
	for col in _cols:
		for b in (col as Control).find_children("Seg*", "Button", true, false):
			(b as Button).disabled = true
	GameState.set_flag("hold_objection", true)
	_before = GameState.metrics().duplicate()
	await get_tree().create_timer(0.5).timeout
	send({"type": "objection_free", "text": t})


func _reveal(sess: Dictionary) -> void:
	var reply: Dictionary = sess.objectionReply
	var after: Dictionary = sess.get("metrics", {})
	var dt := int(after.get("trust", 0)) - int(_before.get("trust", 0))
	var di := int(after.get("insight", 0)) - int(_before.get("insight", 0))
	var dc := int(after.get("compliance", 100)) - int(_before.get("compliance", 100))
	var q := str(reply.get("quality", "ok"))
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(self):
		return
	# The client's reaction comes first
	var short := str(GameState.current_client().get("short", GameState.client_name()))
	var react: String = {"good": "%s點點頭：「這樣說我比較能理解，也願意再往下談。」", "ok": "%s想了想：「嗯……我再考慮看看。」", "bad": "%s皺起眉頭：「你這樣說，讓我有點不舒服。」"}.get(q, "%s沉默了一下。") % short
	AudioManager.play("trust_up" if dt > 0 else "trust_down")
	_reaction.visible = true
	UI.clear(_reaction)
	var rc := QuestUI.card(null, 0.7, Color(QuestUI.GOLD, 0.5))
	var rv := QuestUI.vbox(6)
	rc.add_child(rv)
	rv.add_child(QuestUI.label("客戶反應", 13, QuestUI.GOLD, false, true))
	var rl := QuestUI.label(react, 16, QuestUI.TEXT, true)
	rv.add_child(rl)
	_reaction.add_child(rc)
	QuestUI.fade_in(rc, 0.0, 0.3, 0.0)
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return
	# Then the evaluation with reasons (a free reply is judged by the AI grade alone)
	var s1: Dictionary = _opts[0][_choice[0]] if not _free_mode and _choice[0] >= 0 else {"l": 1 if q == "good" else 0, "e": 1 if q != "bad" else -1, "c": 0, "q": q, "why": str(reply.get("body", "")), "text": ""}
	var s2: Dictionary = _opts[1][_choice[1]] if not _free_mode and _choice[1] >= 0 else {"l": 1 if q == "good" else (0 if q == "ok" else -1), "e": 0, "c": 0, "q": q, "why": str(reply.get("title", "")), "text": ""}
	var listen := int(s1.l) + int(s2.l)
	var empathy := int(s1.e) + int(s2.e)
	var clarity := int(s1.c) + int(s2.c) + (2 if q == "good" else (1 if q == "ok" else -1))
	GameState.add_comm(listen, empathy, clarity)
	UI.clear(_eval)
	_eval.add_child(QuestUI.header("chart", "回應評估"))
	var row := QuestUI.hbox(10)
	row.add_child(QuestUI.chip("信任 %s%d" % ["+" if dt >= 0 else "", dt], QuestUI.GREEN if dt > 0 else QuestUI.RED))
	row.add_child(QuestUI.chip("合規 %s" % ("無扣分" if dc >= 0 else str(dc)), QuestUI.GREEN if dc >= 0 else QuestUI.RED))
	_eval.add_child(row)
	var dims := [
		["傾聽", listen >= 2, str(s2.why)],
		["同理", empathy >= 1, str(s1.why)],
		["需求掌握", di > 0 or q == "good", str(reply.get("title", "")) if q == "good" else "回應還沒有連回客戶自己的目標。"],
		["清楚程度", clarity >= 2, str(reply.get("body", ""))],
		["合規風險", dc >= 0, "沒有保證或施壓的說法。" if dc >= 0 else "說法過度承諾或施壓，可能產生合規風險：" + str(reply.get("title", ""))],
	]
	for d in dims:
		var h := QuestUI.hbox(8)
		h.add_child(QuestUI.icon("circle_check" if d[1] else "alert", 18.0, QuestUI.GREEN if d[1] else QuestUI.GOLD))
		var dv := QuestUI.vbox(2)
		dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(QuestUI.label(str(d[0]), 14, QuestUI.TEXT, false, true))
		dv.add_child(QuestUI.label(str(d[2]), 13, QuestUI.MUTED, true))
		h.add_child(dv)
		_eval.add_child(h)
		QuestUI.fade_in(h, 0.0, 0.25, 0.0)
		await get_tree().create_timer(0.3).timeout
		if not is_instance_valid(self):
			return
	if dc < 0:
		AudioManager.play("compliance_risk")
		TensionManager.set_flag("violation", true)
	var quality := "good" if q == "good" and listen >= 2 and empathy >= 1 else ("bad" if q == "bad" else "ok")
	GameState.add_decision("異議處理", "回應：「%s」" % _composed(), "%s %s" % [str(reply.get("title", "")), str(reply.get("body", ""))], quality, {"trust": dt, "compliance": dc})
	for k in range(2):
		if _free_mode or _choice[k] < 0:
			break
		var o: Dictionary = _opts[k][_choice[k]]
		if str(o.q) != "good":
			GameState.add_decision("異議處理", "%s：「%s」" % [STEPS[k][0], str(o.text)], str(o.why), "ok" if str(o.q) == "ok" else "bad")
	_send.visible = false
	_reason.visible = false
	_free_send.call("set_loading", false)
	_free_send.disabled = true
	_free_input.editable = false
	_after.visible = true
	QuestUI.fade_in(_after, 0.0, 0.25, 0.0)


func _to_scan() -> void:
	GameState.set_flag("hold_objection", false)
	go.emit("compliance", {})
