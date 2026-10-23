extends "res://scripts/quest/pages/modal_base.gd"
## MissionResultModal（任務結算）— 任務結果與下一站解鎖。
## For a meeting that pauses between visits (stage result) and for the finished case (final result).
## Items appear one by one, 0.4 s apart: 需求洞察 → 預算適配 → 溝通品質 → 合規表現 → 客戶信任變化 →
## 經驗值 → 解鎖. Never only a score: the key decisions, the client's reaction, why it went well,
## what to improve, and what a different choice would have changed. A strong result gets a few
## quiet gold sparks; a slip gets one red scan line — nothing loops.
## 前往下一站：關閉結算卡，回到地圖播放解鎖動畫並推進路線（最後一站改為生成培訓報告）；
## 查看決策回顧：本局每個選擇與原因；返回主頁：先跳出確認視窗。
## 分數由規則引擎計算；回饋文字只讀後端給的內容，這裡不改分數。

const DecisionReview := preload("res://scripts/quest/widgets/decision_review.gd")

const STEP_GAP := 0.4

var _final := false
var _ev: Dictionary = {}
var _items: Container
var _cta: Button
var _sending := false
var _xp := 0
var _good := true
var _rows: Array = []


func guide_lines() -> Array:
	return ["這是這一站的結果：每一項都有原因。看完做得好與需要改善的地方，再回到地圖。"]


func key_rects() -> Array:
	return [rect_of(_cta)]


func build() -> void:
	timed = false
	max_card_width = 980.0
	var sess := GameState.my_session()
	_final = not sess.is_empty() and str(sess.get("step", "")) == "result"
	_ev = GameState.my_event()
	var body := add_card(Color(QuestUI.GOLD, 0.6))
	var result: Dictionary = sess.get("result", {}) if sess.get("result") is Dictionary else {}
	_good = _is_good(result)
	# Heading
	var head := QuestUI.hbox(14)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(QuestUI.icon("trophy" if _good else "flag", 46.0 if not phone() else 32.0, QuestUI.GOLD))
	var hv := QuestUI.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow() else Control.SIZE_SHRINK_CENTER
	var ttl := ""
	if _final:
		ttl = "任務完成" if bool(result.get("signed", false)) else "需要加強"
	else:
		ttl = str(_ev.get("title", "會談告一段落")).split("｜")[0]
	var heading := QuestUI.title(ttl, 40 if not phone() else 26, QuestUI.GOLD)
	heading.name = "ResultHeading"
	hv.add_child(heading)
	var verdict := QuestUI.chip("任務完成" if _good else "需要加強", QuestUI.GREEN if _good else QuestUI.GOLD)
	verdict.name = "ResultVerdict"
	verdict.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hv.add_child(verdict)
	var sub := str(result.get("summary", "")) if _final else str(_ev.get("body", ""))
	if sub == "":
		sub = "你已完成本次客戶會談。"
	hv.add_child(QuestUI.label(sub, 14, QuestUI.MUTED, true))
	head.add_child(hv)
	if PlayerProfile.player_profile_created:
		var me := QuestUI.hbox(8)
		me.add_child(UI.RoundTex.new(PlayerProfile.portrait(), Vector2(40, 40), -1.0, PlayerProfile.token_color(), 2.0))
		var mv := QuestUI.vbox(0)
		mv.add_child(QuestUI.label("顧問　" + PlayerProfile.player_name, 14, QuestUI.TEXT, false, true))
		mv.add_child(QuestUI.label(PlayerProfile.level_text(), 12, QuestUI.GOLD))
		me.add_child(mv)
		me.name = "AdvisorChip"
		head.add_child(me)
	body.add_child(head)
	var split: BoxContainer = QuestUI.hbox(16) if not narrow() else QuestUI.vbox(12)
	body.add_child(split)
	# Client card
	var cc := QuestUI.card(null, 0.6)
	var ccv := QuestUI.vbox(8)
	cc.add_child(ccv)
	var pic := QuestUI.portrait(GameState.client_portrait_id(), Vector2(150, 180) if not phone() else Vector2(96, 116))
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ccv.add_child(pic)
	ccv.add_child(QuestUI.title(GameState.client_name(), 18))
	ccv.add_child(QuestUI.metric_bar("信任", GameState.trust()))
	if _final and str(result.get("grade", "")) != "":
		var gr := QuestUI.hbox(8)
		gr.add_child(QuestUI.label("評級", 14, QuestUI.MUTED))
		gr.add_child(QuestUI.title(str(result.grade), 30, QuestUI.GOLD))
		gr.add_child(QuestUI.label("%d 分" % int(result.get("score", 0)), 14, QuestUI.TEXT))
		ccv.add_child(gr)
	split.add_child(cc)
	# Items revealed in order
	# 寬畫面兩欄排列，九項一眼看完（精簡結算卡）
	if narrow():
		_items = QuestUI.vbox(8)
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_items = grid
	_items.name = "ResultItems"
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.size_flags_stretch_ratio = 1.6
	split.add_child(_items)
	_build_rows(sess, result)
	# Why / improve / alternative
	var why := QuestUI.card(null, 0.6)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wv := QuestUI.vbox(8)
	why.add_child(wv)
	_build_reasons(wv, sess, result)
	split.add_child(why)
	var foot := QuestUI.hbox(12)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	var last := GameState.current_stage() >= GameState.total_stages() and _final
	_cta = QuestUI.button("生成培訓報告" if last else "前往下一站", _on_continue, "primary", "report" if last else "next")
	_cta.name = "ResultContinue"
	_cta.custom_minimum_size.x = 240
	foot.add_child(_cta)
	var review: Button = QuestUI.button("查看決策回顧", _open_decisions, "secondary", "doc")
	review.name = "ReviewDecisions"
	foot.add_child(review)
	var home: Button = QuestUI.button("返回主頁", _go_home, "quiet", "house")
	home.name = "ResultHome"
	foot.add_child(home)
	card_footer.add_child(foot)
	_award_xp(sess, result)


func on_open() -> void:
	AudioManager.set_music_state("result_success" if _good else "result_reflect")
	AudioManager.play("mission_success" if _good else "mission_fail")
	await enter()
	for r in _rows:
		(r as Control).modulate.a = 0.0
	for i in range(_rows.size()):
		await get_tree().create_timer(STEP_GAP if not QuestUI.motion_off() else 0.01).timeout
		if not is_instance_valid(self):
			return
		var r: Control = _rows[i]
		r.modulate.a = 1.0
		QuestUI.fade_in(r, 0.0, 0.25, 0.0)
		if r.has_meta("sound"):
			AudioManager.play(str(r.get_meta("sound")))
	if _good:
		_sparks()
	else:
		_red_scan()


func refresh(_s: Dictionary) -> void:
	pass


func server_error(_msg: String) -> void:
	_sending = false
	_cta.call("set_loading", false)


func _is_good(result: Dictionary) -> bool:
	if _final:
		return str(result.get("grade", "C")) in ["S", "A"] and bool(result.get("signed", false))
	for l in _ev.get("lines", []):
		if str((l as Dictionary).get("tone", "")) == "bad":
			return false
	return true


func _row(icon_kind: String, cap: String, value: String, note: String, col := QuestUI.TEXT, sound := "") -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", QuestUI.card_box(0.6, Color(1, 1, 1, 0.1), 12, 10))
	var h := QuestUI.hbox(10)
	p.add_child(h)
	h.add_child(QuestUI.icon(icon_kind, 22.0, QuestUI.GOLD))
	var v := QuestUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := QuestUI.hbox(8)
	top.add_child(QuestUI.label(cap, 16, QuestUI.TEXT, false, true))
	top.add_child(QuestUI.spacer())
	top.add_child(QuestUI.label(value, 18, col, false, true))
	v.add_child(top)
	if note != "":
		v.add_child(QuestUI.label(note, 12, QuestUI.MUTED, true))
	h.add_child(v)
	if sound != "":
		p.set_meta("sound", sound)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_child(p)
	_rows.append(p)
	return p


func _signed(v: float) -> String:
	return ("+%d" if v >= 0 else "%d") % int(round(v))


func _build_rows(sess: Dictionary, result: Dictionary) -> void:
	var m := GameState.metrics()
	var clue_res: Dictionary = GameState.record.get("clue_results", {})
	var good_clues := 0
	var bad_clues := 0
	for k in clue_res:
		if str(clue_res[k]) == "correct":
			good_clues += 1
		elif str(clue_res[k]) == "wrong":
			bad_clues += 1
	var insight := float(m.get("insight", 20))
	var found := GameState.client_needs().size()
	if found == 0:
		found = (GameState.record.get("needs", []) as Array).size()
	_row("search", "需求洞察", str(int(insight)), "線索判斷正確 %d 張、誤判 %d 張；確認的需求 %d 項。" % [good_clues, bad_clues, found], QuestUI.metric_color(insight))
	var plan: Variant = sess.get("plan")
	var fit := float(m.get("fit", 50))
	var plan_note := "方案尚未設計（下次會談處理）。"
	if plan is Dictionary:
		plan_note = {"good": "配置與需求相符。", "ok": "配置大致合理。", "bad": "配置與需求落差大。"}.get(str(plan.get("quality", "")), "")
	elif not _final and str(_ev.get("title", "")).begins_with("方案已提交"):
		plan_note = str((_ev.get("lines", [{}]) as Array)[0].get("text", "方案已提交。")) if not (_ev.get("lines", []) as Array).is_empty() else "方案已提交。"
	_row("coins", "預算適配", str(int(fit)), plan_note, QuestUI.metric_color(fit))
	var comm := GameState.comm_score()
	_row("chat", "溝通品質", str(int(comm)), "依你在異議回應中的傾聽、同理與清楚程度計算。" if int((GameState.record.get("comm", {}) as Dictionary).get("count", 0)) > 0 else "異議回應尚未進行。", QuestUI.metric_color(comm))
	var comp := float(m.get("compliance", 100))
	var scan: Dictionary = GameState.record.get("scan", {})
	var comp_note := "會談中沒有出現違規說法。" if comp >= 90 else "會談中出現不當說法，合規表達被扣分。"
	if scan.has("score"):
		comp_note += " 合規檢核得分 %d（漏選 %d、誤判 %d）。" % [int(scan.score), int(scan.get("missed", 0)), int(scan.get("wrong", 0))]
	_row("shield", "合規表現", str(int(comp)), comp_note, QuestUI.metric_color(comp), "compliance_risk" if comp < 70 else "")
	var over := GameState.overtime()
	var left := GameState.remaining_time()
	var time_note := "在會談時間內完成，節奏掌握得宜。" if over <= 0.0 else "超出會談時間，下次可以把問題聚焦在關鍵需求。"
	_row("clock", "時間管理", ("超時 " + QuestUI.mmss(over)) if over > 0.0 else ("剩 " + QuestUI.mmss(left)), time_note, QuestUI.GREEN if over <= 0.0 else QuestUI.RED)
	var trust := float(m.get("trust", 50))
	_row("handshake", "客戶信任變化", _signed(trust - 50.0), "從初次見面的 50 到現在的 %d。" % int(trust), QuestUI.GREEN if trust >= 50 else QuestUI.RED, "trust_up" if trust >= 50 else "trust_down")
	var gain := _xp_amount(sess, result)
	# 這一站的經驗發放過後 advisor_xp() 已含它；等級進度條以加總後的經驗計算
	var total := GameState.advisor_xp() + (0 if _awarded() else gain)
	var lv := PlayerProfile.level_for(total)
	var xp_row := _row("gift", "獲得經驗值", "+%d" % gain, "累積經驗 %d・Lv.%d %s，距離下一級 %d" % [total, lv, PlayerProfile.level_title(lv), GameState.XP_PER_LEVEL - total % GameState.XP_PER_LEVEL], QuestUI.GOLD, "xp_gain")
	var bar := ProgressBar.new()
	bar.name = "LevelProgress"
	bar.min_value = 0
	bar.max_value = GameState.XP_PER_LEVEL
	bar.value = total % GameState.XP_PER_LEVEL
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.1)
	back.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = QuestUI.GOLD
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	((xp_row.get_child(0) as Control).get_child(1) as Control).add_child(bar)
	var contacts_now: Array = Net.me().get("contacts", [])
	var known: Array = GameState.flag("contacts_seen", []) if GameState.flag("contacts_seen", []) is Array else []
	var fresh: Array = contacts_now.filter(func(n): return not known.has(n))
	GameState.set_flag("contacts_seen", contacts_now.duplicate())
	_row("people", "新增人脈", "+%d" % fresh.size(), ("、".join(fresh) + " 願意介紹或再聯絡。") if not fresh.is_empty() else "這一站沒有新增人脈；完成案件、讓客戶滿意會帶來轉介紹。", QuestUI.GREEN if not fresh.is_empty() else QuestUI.MUTED)
	var unlock := ""
	var contacts: Array = Net.me().get("contacts", [])
	if _final and bool(GameState.main_case().get("done", false)):
		unlock = "主要案件完成，新的客戶案件解鎖" + ("：" + "、".join(contacts) if not contacts.is_empty() else "")
	elif _final:
		unlock = "完成這位客戶，地圖上的下一段路線開放。"
	else:
		unlock = "下一次抵達客戶節點時，會繼續和 %s 往下談。" % GameState.client_name()
	_row("unlock", "解鎖", "已解鎖" if _final else "下一站", unlock, QuestUI.GREEN, "node_unlock")


func _build_reasons(wv: VBoxContainer, sess: Dictionary, result: Dictionary) -> void:
	var ds: Array = GameState.decision_history()
	var goods: Array = []
	var bads: Array = []
	for d in ds:
		var dd := d as Dictionary
		if str(dd.get("stage", "")) in ["經驗值"]:
			continue
		if str(dd.get("quality", "")) == "good" and goods.size() < 3:
			goods.append(dd)
		elif str(dd.get("quality", "")) == "bad" and bads.size() < 3:
			bads.append(dd)
	# The client's reaction
	var reaction := ""
	if _final:
		var epi: Variant = result.get("epilogue")
		if epi is Dictionary:
			reaction = str(epi.get("headline", ""))
		var letter: Variant = result.get("letter")
		if reaction == "" and letter is Dictionary:
			reaction = str(letter.get("content", "")).substr(0, 80)
	else:
		for l in _ev.get("lines", []):
			if str((l as Dictionary).get("tone", "")) == "info":
				reaction = str(l.get("text", ""))
				break
	if reaction != "":
		wv.add_child(QuestUI.label("客戶反應", 14, QuestUI.GOLD, false, true))
		wv.add_child(QuestUI.label(reaction, 14, QuestUI.TEXT, true))
	wv.add_child(QuestUI.header("bulb", "為什麼"))
	if goods.is_empty():
		wv.add_child(QuestUI.label("這一站還沒有特別突出的判斷。", 13, QuestUI.MUTED, true))
	for d in goods:
		wv.add_child(_reason_row("circle_check", QuestUI.GREEN, str(d.get("title", "")), str(d.get("detail", ""))))
	wv.add_child(QuestUI.header("target", "可再加強"))
	if bads.is_empty():
		wv.add_child(QuestUI.label("沒有明顯的失誤，保持這個節奏。", 13, QuestUI.MUTED, true))
	for d in bads:
		wv.add_child(_reason_row("alert", QuestUI.GOLD, str(d.get("title", "")), str(d.get("detail", ""))))
	# What a different choice would have changed
	var alt := _alternative(sess)
	if alt != "":
		wv.add_child(QuestUI.label("若重新選擇", 14, QuestUI.GOLD, false, true))
		wv.add_child(QuestUI.label(alt, 13, QuestUI.TEXT, true))
	# Server's own decisions for this client (rule engine)
	var caps: Array = result.get("caps", []) if result.get("caps") is Array else []
	for c in caps:
		wv.add_child(_reason_row("flag", QuestUI.RED, "評級上限", str(c)))
	# 個人化回饋：後端依這次會談產生的評語（AI 開啟時由 AI 撰寫，分數不受影響）
	var fb := _feedback(result)
	if fb != "":
		var fbl := QuestUI.label("「%s」" % fb, 14, QuestUI.TEXT, true)
		fbl.name = "PersonalFeedback"
		wv.add_child(QuestUI.header("spark", "個人化回饋"))
		wv.add_child(fbl)


func _reason_row(icon_kind: String, col: Color, title_text: String, detail: String) -> Control:
	var h := QuestUI.hbox(8)
	var ic := QuestUI.icon(icon_kind, 18.0, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := QuestUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(QuestUI.label(title_text, 14, QuestUI.TEXT, true, true))
	if detail != "":
		v.add_child(QuestUI.label(detail, 12, QuestUI.MUTED, true))
	h.add_child(v)
	return h


func _alternative(sess: Dictionary) -> String:
	var plan: Variant = sess.get("plan")
	if plan is Dictionary and not (plan.get("notes", []) as Array).is_empty():
		return "方案若照這些方向調整，適配度與抗壓力會更高：" + "".join(plan.notes)
	var reply: Variant = sess.get("objectionReply")
	if reply is Dictionary and str(reply.get("quality", "")) != "good":
		return "回應客戶疑慮時，先接住感受、再用開放式問題確認，最後把方案連回客戶自己的目標，信任通常會上升。"
	for d in GameState.decision_history():
		if str((d as Dictionary).get("stage", "")) == "線索分類" and str(d.get("quality", "")) == "bad":
			return "若一開始就把和財務無關的線索放進「暫時無關」，可以省下時間，把調查次數留給真正的需求。"
	for l in _ev.get("lines", []):
		if str((l as Dictionary).get("tone", "")) in ["bad", "ok"]:
			return "下次會談前先想好：客戶最不能犧牲的是什麼？先問那一題，關鍵需求比較不會漏掉。"
	return ""


func _xp_amount(sess: Dictionary, result: Dictionary) -> int:
	if _final:
		var g := str(result.get("grade", "C"))
		var scan: Dictionary = GameState.record.get("scan", {})
		return 60 + int({"S": 60, "A": 40, "B": 20}.get(g, 0)) + int(scan.get("score", 0)) / 5
	var good_lines := 0
	for l in _ev.get("lines", []):
		if str((l as Dictionary).get("tone", "")) == "good":
			good_lines += 1
	return 30 + good_lines * 15


func _xp_key() -> String:
	return ("final:" if _final else "stage:") + str(_ev.get("title", "")) + ":" + str(GameState.current_stage())


func _awarded() -> bool:
	var awarded: Variant = GameState.flag("xp_awarded", {})
	return awarded is Dictionary and (awarded as Dictionary).has(_xp_key())


func _award_xp(sess: Dictionary, result: Dictionary) -> void:
	var key := _xp_key()
	var awarded: Dictionary = GameState.flag("xp_awarded", {}) if GameState.flag("xp_awarded", {}) is Dictionary else {}
	if awarded.has(key):
		return
	awarded[key] = true
	GameState.set_flag("xp_awarded", awarded)
	_xp = _xp_amount(sess, result)
	GameState.add_xp(_xp, "完成「%s」" % ("客戶案件" if _final else str(_ev.get("title", "會談"))))


func _on_continue() -> void:
	if _sending or not QuestFlow.claim():
		return
	_sending = true
	_cta.call("set_loading", true, "整理中")
	# 回到地圖時先播放下一站解鎖（最後一站直接進培訓報告）
	QuestFlow.unlock_pending = _cta.text != "生成培訓報告"
	send({"type": "continue"})
	# 連線中斷時後端不會回應：8 秒後按鈕復原並提示，不讓結算卡停在送出中
	get_tree().create_timer(8.0).timeout.connect(func():
		if is_instance_valid(self) and _sending:
			_sending = false
			QuestFlow.unlock_pending = false
			_cta.call("set_loading", false)
			push_warning("任務結算：前往下一站 8 秒沒有收到後端回應")
			if layer:
				layer.call("show_toast", "沒有收到回應，請確認連線後再按一次", "error")
	)


func _open_decisions() -> void:
	if find_child("DecisionReview", false, false) != null:
		return
	add_child(DecisionReview.new())


## 返回主頁：先確認（繼續培訓／儲存並返回主畫面／放棄本次培訓），避免誤觸
func _go_home() -> void:
	if layer:
		layer.call("_leave")


func _feedback(result: Dictionary) -> String:
	if _final:
		var letter: Variant = result.get("letter")
		if letter is Dictionary and str(letter.get("content", "")) != "":
			return str(letter.content).strip_edges().substr(0, 90)
		return str(result.get("summary", ""))
	for l in _ev.get("lines", []):
		if str((l as Dictionary).get("tone", "")) in ["good", "info"]:
			return str(l.get("text", ""))
	return str(_ev.get("body", ""))


## A few quiet gold sparks rising behind the heading (about 1 s, once)
func _sparks() -> void:
	if QuestUI.motion_off() or card == null:
		return
	for i in range(14):
		var s := ColorRect.new()
		s.color = Color(QuestUI.GOLD, 0.0)
		s.size = Vector2(3, 3)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		var start := card.position + Vector2(randf_range(0.2, 0.8) * card.size.x, randf_range(40.0, 120.0))
		s.position = start
		var tw := s.create_tween()
		tw.tween_interval(randf() * 0.4)
		tw.tween_property(s, "color:a", 0.8, 0.15)
		tw.parallel().tween_property(s, "position", start + Vector2(randf_range(-20, 20), -randf_range(30, 70)), 1.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(s, "color:a", 0.0, 0.3)
		tw.tween_callback(s.queue_free)


## One red scan line across the card (a slip happened); never repeats
func _red_scan() -> void:
	if QuestUI.motion_off() or card == null:
		return
	var line := ColorRect.new()
	line.color = Color(QuestUI.RED, 0.75)
	line.size = Vector2(card.size.x - 24, 2)
	line.position = card.position + Vector2(12, 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "position:y", card.position.y + card.size.y - 14, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(line, "color:a", 0.0, 0.25)
	tw.tween_callback(line.queue_free)
