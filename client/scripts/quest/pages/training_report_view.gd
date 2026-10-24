extends Control
## TrainingReportView (page 10) — AI 個人化培訓報告 (the end-of-game screen).
## Scores come from the server's rule engine (FinalRow: score, grade, skills) plus this client's
## own training record (time management, composed replies, compliance scan); the AI only writes the
## coach text. Every section quotes this game's decisions (server decisions + GameState history):
## questions asked, needs missed, the plan, objection handling, budget / compliance slips, events.
## A 10-year financial trajectory card visualizes the client's net worth with vs without the plan.
## While the coach text is still being written a progress bar runs; sections then open in order.

const ReportScreen := preload("res://scripts/ui/report.gd")
const GameHeader := preload("res://scripts/quest/widgets/game_header.gd")
const BACKGROUND := preload("res://assets/unified/background.webp")
const SettingsModal := preload("res://scripts/quest/widgets/settings_modal.gd")
const TimelineChartClass := preload("res://scripts/ui/timeline_chart.gd")
const AutomationBridge := preload("res://scripts/automation.gd")
const JudgeGuide := preload("res://scripts/quest/widgets/judge_guide.gd")

var main: Node
var _built := false
var _sections: Array = []
var _coach_label: Label
var _progress: PanelContainer
var _progress_bar: QuestUI.Bar
var _progress_t := 0.0
var _body: VBoxContainer
var _mine: Dictionary = {}
var _state: Dictionary = {}
var _settings: Control
var _legacy: Control
var _judge_guide: Control = null
var _revealed := false
var _finance_timeline_idx := -1
var _finance_slot: VBoxContainer
var _finance_card: Control
var _finance_card_container: VBoxContainer
var _finance_data_hash: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = BACKGROUND
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var veil := ColorRect.new()
	veil.color = Color(QuestUI.BG, 0.8)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 8 if UI.is_phone() else 16)
	add_child(m)
	var outer := QuestUI.vbox(10)
	m.add_child(outer)
	var header := GameHeader.new(UI.is_phone())
	header.connect("settings_requested", func(): _settings.call("open"))
	outer.add_child(header)
	_body = QuestUI.vbox(14)
	outer.add_child(QuestUI.scroll(_body))
	_settings = SettingsModal.new()
	_settings.set("home_label", "返回主畫面")
	_settings.connect("leave_requested", func(): main.leave_to_menu())
	add_child(_settings)
	Net.stream_chunk.connect(_on_stream)
	AudioManager.set_music_state("report")
	TensionManager.set_active(false)
	GameState.timed_page = false

	if AutomationBridge.is_judge():
		_judge_guide = JudgeGuide.new()
		_judge_guide.z_index = 50
		add_child(_judge_guide)
		_judge_guide.set_current_step(6)


func _exit_tree() -> void:
	if Net.stream_chunk.is_connected(_on_stream):
		Net.stream_chunk.disconnect(_on_stream)


func on_layout_changed(_portrait: bool) -> void:
	_built = false
	_revealed = true
	if not _state.is_empty():
		refresh(_state)


func refresh(s: Dictionary) -> void:
	_state = s
	_mine = {}
	for r in s.get("final", []) if s.get("final") is Array else []:
		if str((r as Dictionary).get("playerId", "")) == Net.player_id:
			_mine = r
	var pending := bool(s.get("aiPending", false)) or bool(_mine.get("coachPending", false))
	if not _built:
		_built = true
		_build(pending)
	else:
		if _coach_label and is_instance_valid(_coach_label):
			var coach := str(_mine.get("coach", ""))
			if coach != "" and not pending:
				_coach_label.text = coach
		_sync_finance_timeline_card(pending)
	if _progress and is_instance_valid(_progress):
		_progress.visible = pending
	if not pending and not _revealed:
		_revealed = true
		_reveal()


func _process(delta: float) -> void:
	if _progress and is_instance_valid(_progress) and _progress.visible:
		_progress_t += delta
		_progress_bar.value = 100.0 * (1.0 - exp(-_progress_t / 6.0))


func _on_stream(key: String, text: String, _done: bool) -> void:
	if key == "coach:" + Net.player_id and _coach_label and is_instance_valid(_coach_label):
		_coach_label.text = text


# --- Layout -----------------------------------------------------------------------------------

func _wide() -> bool:
	return not UI.is_portrait() and size.x >= 900.0


func _build(pending: bool) -> void:
	UI.clear(_body)
	_sections.clear()
	var dims := _dimensions()
	# Title row with the client
	var top: BoxContainer = QuestUI.hbox(16) if _wide() else QuestUI.vbox(10)
	var tv := QuestUI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var th := QuestUI.hbox(10)
	th.add_child(QuestUI.icon("report", 34.0, QuestUI.GOLD))
	th.add_child(QuestUI.title("本局顧問培訓報告", 32 if not UI.is_phone() else 22))
	tv.add_child(th)
	tv.add_child(QuestUI.label("完成本次客戶諮詢，以下為你的表現分析與個人化建議。", 15, QuestUI.MUTED, true))
	top.add_child(tv)
	top.add_child(_advisor_card())
	top.add_child(_client_card())
	_body.add_child(top)
	_progress = QuestUI.card(null, 0.95, Color(QuestUI.GOLD, 0.5))
	var pv := QuestUI.vbox(8)
	_progress.add_child(pv)
	pv.add_child(QuestUI.label("AI 正在根據你這局的決策紀錄撰寫回饋……分數已由規則引擎算好。", 15, QuestUI.TEXT, true))
	_progress_bar = QuestUI.Bar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 10)
	_progress_bar.color = QuestUI.GOLD
	pv.add_child(_progress_bar)
	_progress.visible = pending
	_body.add_child(_progress)
	# Row 1: grade, radar, decisions, growth
	var row1: Container = _row()
	row1.add_child(_section(_grade_card(dims)))
	row1.add_child(_section(_radar_card(dims)))
	row1.add_child(_section(_decisions_card()))
	row1.add_child(_section(_growth_card()))
	_body.add_child(row1)
	_finance_slot = QuestUI.vbox(0)
	_finance_slot.name = "FinanceTimelineSlot"
	_finance_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_finance_slot)
	_finance_card = null
	_finance_card_container = null
	_finance_data_hash = 0
	_sync_finance_timeline_card(pending)
	# Row 2: done well, next practice, AI feedback, certificate
	var row2: Container = _row()
	row2.add_child(_section(_list_card("thumb", "做得好的地方", _best(3, "good"), "這局還沒有明顯的亮點，下一局從需求探索開始累積。")))
	row2.add_child(_section(_list_card("target", "最需要改善的地方", _best(3, "bad"), "沒有明顯的失誤，維持這個節奏。")))
	row2.add_child(_section(_ai_card()))
	row2.add_child(_section(_cert_card()))
	_body.add_child(row2)
	var row3: Container = _row()
	row3.add_child(_section(_practice_card()))
	row3.add_child(_section(_next_client_card()))
	_body.add_child(row3)
	_body.add_child(_actions())
	if not pending:
		_revealed = true
		_reveal()
	else:
		for s in _sections:
			if is_instance_valid(s):
				(s as Control).modulate.a = 0.25


func _row() -> Container:
	if _wide():
		var h := QuestUI.hbox(14)
		return h
	return QuestUI.vbox(12)


func _section(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.append(c)
	return c


func _reveal() -> void:
	for i in range(_sections.size()):
		var s: Control = _sections[i]
		if not is_instance_valid(s):
			continue
		if QuestUI.motion_off():
			s.modulate.a = 1.0
			continue
		s.modulate.a = 0.0
		var tw := s.create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(s, "modulate:a", 1.0, 0.3)
	AudioManager.play("mission_success")


## The player's own advisor: portrait, name, level after this game
func _advisor_card() -> Control:
	var c := QuestUI.card(null, 0.92, Color(QuestUI.GOLD, 0.45))
	c.name = "AdvisorCard"
	var h := QuestUI.hbox(12)
	c.add_child(h)
	if PlayerProfile.portrait() != null:
		h.add_child(UI.RoundTex.new(PlayerProfile.portrait(), Vector2(72, 72), -1.0, PlayerProfile.token_color(), 3.0))
	var v := QuestUI.vbox(2)
	v.add_child(QuestUI.label("受訓顧問", 12, QuestUI.MUTED))
	var nm := PlayerProfile.player_name if PlayerProfile.player_name != "" else str(_mine.get("name", "顧問"))
	v.add_child(QuestUI.title(nm, 20))
	v.add_child(QuestUI.label(PlayerProfile.level_text(), 13, QuestUI.GOLD))
	h.add_child(v)
	return c


func _client_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	var h := QuestUI.hbox(12)
	c.add_child(h)
	var cid := GameState.client_id
	h.add_child(QuestUI.portrait(cid, Vector2(84, 96)))
	var v := QuestUI.vbox(2)
	v.add_child(QuestUI.label("本次客戶", 12, QuestUI.MUTED))
	var name_text := GameState.client_name()
	if name_text == "":
		for b in Net.me().get("book", []):
			name_text = str((b as Dictionary).get("name", ""))
	v.add_child(QuestUI.title(name_text if name_text != "" else "—", 20))
	var cl := GameState.current_client()
	var bits: Array = []
	if int(cl.get("age", 0)) > 0:
		bits.append("%d 歲" % int(cl.age))
	if str(cl.get("job", "")) != "":
		bits.append(str(cl.job))
	v.add_child(QuestUI.label("・".join(bits), 13, QuestUI.MUTED, true))
	h.add_child(v)
	var topics := QuestUI.vbox(4)
	topics.add_child(QuestUI.label("本次諮詢主題", 12, QuestUI.MUTED))
	var needs: Array = []
	for n in GameState.record.get("needs", []):
		needs.append(str((n as Dictionary).get("text", "")))
	for n in needs.slice(0, 4):
		topics.add_child(QuestUI.label("・" + str(n), 13, QuestUI.TEXT, true))
	if needs.is_empty():
		topics.add_child(QuestUI.label("・需求探索與保障規劃", 13, QuestUI.TEXT))
	h.add_child(topics)
	return c


# --- Scores (rule engine + training record) ----------------------------------------------------

func _dimensions() -> Dictionary:
	var sk: Dictionary = _mine.get("skill", {}) if _mine.get("skill") is Dictionary else {}
	var scan: Dictionary = {}
	var comm_total := 0.0
	var comm_n := 0
	var time_total := 0.0
	var time_n := 0
	var recs := GameState.all_records()
	for id in recs:
		var r: Dictionary = recs[id]
		if (r.get("scan", {}) as Dictionary).has("score"):
			scan = r.scan
		var c: Dictionary = r.get("comm", {})
		if int(c.get("count", 0)) > 0:
			comm_total += 50.0 + (float(c.get("listen", 0)) + float(c.get("empathy", 0)) + float(c.get("clarity", 0))) / int(c.count) * 8.0
			comm_n += 1
		var total := float(r.get("total", 600.0))
		time_total += clampf(60.0 + float(r.get("remaining", total)) / maxf(1.0, total) * 40.0 - float(r.get("overtime", 0.0)) / 5.0, 0, 100)
		time_n += 1
	var objection := 60.0
	for d in Net.me().get("decisions", []):
		if str((d as Dictionary).get("stage", "")) == "異議處理":
			objection = {"good": 90.0, "ok": 68.0, "bad": 38.0}.get(str(d.get("quality", "")), 60.0)
	var comm := clampf(comm_total / comm_n, 0, 100) if comm_n > 0 else 60.0
	var comp := float(sk.get("compliance", 100))
	if scan.has("score"):
		comp = (comp + float(scan.score)) * 0.5
	return {
		"需求探索": float(sk.get("insight", 50)),
		"溝通傾聽": comm,
		"預算適配": float(sk.get("fit", 50)),
		"異議處理": (objection + comm) * 0.5,
		"合規表現": comp,
		"時間管理": time_total / time_n if time_n > 0 else 70.0,
	}


func _grade_card(_dims: Dictionary) -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("trophy", "綜合評分"))
	var grade := str(_mine.get("grade", "—"))
	var score := int(_mine.get("score", 0))
	var ring := QuestUI.Ring.new()
	ring.custom_minimum_size = Vector2(170, 170) if not UI.is_phone() else Vector2(120, 120)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ring.ratio = score / 100.0
	ring.color = QuestUI.GOLD
	ring.center_text = grade
	ring.sub_text = {"S": "頂尖顧問", "A": "優秀顧問", "B": "穩健顧問", "C": "持續練習"}.get(grade, "")
	v.add_child(ring)
	var sl := QuestUI.title("%d / 100" % score, 26, QuestUI.TEXT)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	var caps: Array = _mine.get("caps", []) if _mine.get("caps") is Array else []
	var note := "分數由規則引擎依信任、需求、適配、風險與合規計算。" + ("" if caps.is_empty() else "評級上限：" + "；".join(caps))
	v.add_child(QuestUI.label(note, 12, QuestUI.MUTED, true))
	return c


func _radar_card(dims: Dictionary) -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("chart", "能力表現"))
	var r := Radar.new()
	r.values = dims
	r.custom_minimum_size = Vector2(240, 220) if not UI.is_phone() else Vector2(200, 190)
	v.add_child(r)
	return c


func _decisions_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	c.name = "DecisionsCard"
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("pin", "關鍵決策歷程"))
	var items := _key_decisions(5)
	if items.is_empty():
		v.add_child(QuestUI.label("這局沒有留下決策紀錄。", 13, QuestUI.MUTED))
	for i in range(items.size()):
		var d: Dictionary = items[i]
		var h := QuestUI.hbox(8)
		var num := QuestUI.chip(str(i + 1), QuestUI.GOLD)
		num.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(num)
		var dv := QuestUI.vbox(2)
		dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(QuestUI.label("%s｜%s" % [d.get("stage", ""), d.get("title", "")], 14, QuestUI.TEXT, true, true))
		if str(d.get("detail", "")) != "":
			dv.add_child(QuestUI.label(str(d.detail), 12, QuestUI.MUTED, true))
		h.add_child(dv)
		v.add_child(h)
	return c


func _get_all_timelines() -> Array:
	var list: Array = []
	var raw_timelines: Variant = _mine.get("timelines")
	if raw_timelines is Array:
		for item in (raw_timelines as Array):
			if item is Dictionary and not (item as Dictionary).is_empty():
				list.append(item as Dictionary)
	if list.is_empty():
		var raw_timeline: Variant = _mine.get("timeline")
		if raw_timeline is Dictionary and not (raw_timeline as Dictionary).is_empty():
			list.append(raw_timeline as Dictionary)
	return list


func _selected_timeline() -> Dictionary:
	var list := _get_all_timelines()
	if list.is_empty():
		return {}
	if _finance_timeline_idx < 0 or _finance_timeline_idx >= list.size():
		_finance_timeline_idx = list.size() - 1
	return list[_finance_timeline_idx] if list[_finance_timeline_idx] is Dictionary else {}


static func _fmt_money(amount: int) -> String:
	var neg: bool = amount < 0
	var s: String = str(absi(amount))
	var res: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count % 3 == 0 and i > 0:
			res = "," + res
	if neg:
		res = "-" + res
	return res + " 元"


func _find_letter_for(client_name: String) -> Dictionary:
	var raw_letters: Variant = _mine.get("letters")
	var letters: Array = raw_letters as Array if raw_letters is Array else []
	var trimmed_target := client_name.strip_edges()
	for item in letters:
		if item is Dictionary:
			var d: Dictionary = item as Dictionary
			if trimmed_target != "" and str(d.get("clientName", "")).strip_edges() == trimmed_target:
				return d
	return {}


func _outcome_name(outcome: String) -> String:
	match outcome:
		"thanks":
			return "感謝"
		"regret":
			return "後悔"
		"mixed":
			return "五味雜陳"
		"complaint":
			return "客訴副本"
		_:
			return outcome


func _outcome_color(outcome: String) -> Color:
	match outcome:
		"thanks":
			return QuestUI.GREEN
		"regret", "complaint":
			return QuestUI.RED
		"mixed":
			return QuestUI.GOLD
		_:
			return QuestUI.MUTED


func _calc_finance_hash() -> int:
	var raw_timelines: Variant = _mine.get("timelines")
	var raw_timeline: Variant = _mine.get("timeline")
	var raw_letters: Variant = _mine.get("letters")
	return hash([raw_timelines, raw_timeline, raw_letters])


func _sync_finance_timeline_card(pending: bool = false) -> void:
	if _finance_slot == null or not is_instance_valid(_finance_slot):
		return
	var list := _get_all_timelines()
	if list.is_empty():
		if _finance_card != null and is_instance_valid(_finance_card):
			_sections.erase(_finance_card)
			_finance_card.queue_free()
			_finance_card = null
			_finance_card_container = null
		_finance_data_hash = 0
		return

	var h := _calc_finance_hash()
	if _finance_card == null or not is_instance_valid(_finance_card):
		var c := QuestUI.card(null, 0.92)
		c.name = "FinanceTimelineCard"
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := QuestUI.vbox(10)
		c.add_child(v)
		_finance_card = c
		_finance_card_container = v
		_finance_slot.add_child(c)
		if not _sections.has(c):
			_sections.append(c)
		if pending and not _revealed:
			c.modulate.a = 0.25
		else:
			c.modulate.a = 1.0
		_finance_data_hash = h
		_render_finance_timeline_card_content()
	elif h != _finance_data_hash:
		_finance_data_hash = h
		_render_finance_timeline_card_content()


func _render_finance_timeline_card_content() -> void:
	if _finance_card_container == null or not is_instance_valid(_finance_card_container):
		return
	UI.clear(_finance_card_container)
	var list := _get_all_timelines()
	if list.is_empty():
		return
	if _finance_timeline_idx < 0 or _finance_timeline_idx >= list.size():
		_finance_timeline_idx = list.size() - 1
	var cur_timeline: Dictionary = list[_finance_timeline_idx] if list[_finance_timeline_idx] is Dictionary else {}

	_finance_card_container.add_child(QuestUI.header("chart", "十年財務人生軌跡"))

	if list.size() > 1:
		var switch_row := QuestUI.hbox(8)
		switch_row.name = "TimelineSwitcher"
		var on_switch := func(idx: int) -> void:
			_finance_timeline_idx = idx
			_render_finance_timeline_card_content()
		for i in range(list.size()):
			var tm_item: Dictionary = list[i] if list[i] is Dictionary else {}
			var name_btn := str(tm_item.get("clientName", "客戶 %d" % (i + 1)))
			var is_active := (i == _finance_timeline_idx)
			var b: Button = QuestUI.button(name_btn, on_switch.bind(i), "primary" if is_active else "secondary")
			b.name = "ClientTimelineBtn_%d" % i
			b.custom_minimum_size = Vector2(0, 32)
			b.add_theme_font_size_override("font_size", 13)
			switch_row.add_child(b)
		_finance_card_container.add_child(switch_row)

	_finance_card_container.add_child(QuestUI.label("有你的規劃 vs 沒有規劃：同一個家庭十年後的淨資產", 13, QuestUI.MUTED, true))

	var tc: Control = TimelineChartClass.new()
	tc.name = "TimelineChart"
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_finance_card_container.add_child(tc)
	var is_compact: bool = UI.is_phone_portrait()
	tc.set_data(cur_timeline, is_compact)

	var adopted: bool = bool(cur_timeline.get("adopted", true))
	var worst_with: int = int(cur_timeline.get("worstWith", 0))
	var worst_no: int = int(cur_timeline.get("worstNo", 0))
	var premium_total: int = int(cur_timeline.get("premiumTotal", 0))

	var stat_box: BoxContainer = QuestUI.hbox(14) if _wide() else QuestUI.vbox(4)
	stat_box.name = "TimelineStats"
	var worst_txt := ""
	if adopted:
		worst_txt = "最糟一年：有規劃 %s vs 沒規劃 %s" % [_fmt_money(worst_with), _fmt_money(worst_no)]
	else:
		worst_txt = "最糟一年：客戶沒有採用這份規劃 vs 沒規劃 %s" % _fmt_money(worst_no)
	if worst_with < 0 or worst_no < 0:
		worst_txt += "（負數代表負債）"

	var worst_lbl := QuestUI.label(worst_txt, 14, QuestUI.TEXT, true)
	worst_lbl.name = "WorstYearLabel"
	if _wide():
		worst_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_box.add_child(worst_lbl)

	if adopted:
		var prem_lbl := QuestUI.label("十年保費合計：%s" % _fmt_money(premium_total), 14, QuestUI.GOLD, not _wide())
		prem_lbl.name = "PremiumTotalLabel"
		if _wide():
			prem_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
		stat_box.add_child(prem_lbl)

	_finance_card_container.add_child(stat_box)

	var c_name := str(cur_timeline.get("clientName", ""))
	if c_name == "":
		c_name = GameState.client_name()
	var letter := _find_letter_for(c_name)
	if not letter.is_empty():
		var outcome := str(letter.get("outcome", ""))
		var raw_content := str(letter.get("content", "")).strip_edges()
		var excerpt := raw_content.substr(0, 60) + ("…" if raw_content.length() > 60 else "")
		var tag_name := _outcome_name(outcome)
		var tag_col := _outcome_color(outcome)

		var letter_box := PanelContainer.new()
		letter_box.name = "LetterExcerptBox"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(QuestUI.CARD, 0.6)
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 1, 1, 0.08)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		letter_box.add_theme_stylebox_override("panel", sb)

		var lh := QuestUI.vbox(4)
		var l_top := QuestUI.hbox(8)
		l_top.add_child(QuestUI.icon("doc", 16.0, QuestUI.MUTED))
		l_top.add_child(QuestUI.label("十年後的信", 13, QuestUI.MUTED, false, true))
		l_top.add_child(QuestUI.chip(tag_name, tag_col))
		lh.add_child(l_top)

		var l_text := QuestUI.label("「%s」" % excerpt, 13, QuestUI.TEXT, true)
		l_text.name = "LetterExcerptLabel"
		lh.add_child(l_text)

		letter_box.add_child(lh)
		_finance_card_container.add_child(letter_box)


func _growth_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("bars", "培訓成長進度"))
	var lv := GameState.advisor_level()
	var xp := GameState.advisor_xp()
	var h := QuestUI.hbox(10)
	h.add_child(QuestUI.title("Lv. %d" % lv, 34, QuestUI.GOLD))
	h.add_child(QuestUI.spacer())
	h.add_child(QuestUI.label("+%d XP" % GameState.game_xp(), 18, QuestUI.GOLD, false, true))
	v.add_child(h)
	var bar := QuestUI.Bar.new()
	bar.custom_minimum_size = Vector2(0, 10)
	bar.color = QuestUI.GOLD
	bar.value = float(xp % GameState.XP_PER_LEVEL) / GameState.XP_PER_LEVEL * 100.0
	v.add_child(bar)
	v.add_child(QuestUI.label("%d / %d" % [xp % GameState.XP_PER_LEVEL, GameState.XP_PER_LEVEL], 12, QuestUI.MUTED))
	v.add_child(QuestUI.label("距離下一等級", 14, QuestUI.TEXT, false, true))
	var served := (Net.me().get("book", []) as Array).size()
	var score := int(_mine.get("score", 0))
	var comp_ok := not _any_bad("合規")
	for item in [["完成客戶諮詢", served >= 1, "%d / 1" % served], ["綜合評分達 85 分以上", score >= 85, "%d / 85" % score], ["通過合規情境挑戰", comp_ok, "1 / 1" if comp_ok else "0 / 1"]]:
		var r := QuestUI.hbox(8)
		r.add_child(QuestUI.icon("circle_check" if item[1] else "circle", 18.0, QuestUI.GREEN if item[1] else QuestUI.MUTED))
		r.add_child(QuestUI.label(str(item[0]), 13, QuestUI.TEXT))
		r.add_child(QuestUI.spacer())
		r.add_child(QuestUI.label(str(item[2]), 13, QuestUI.GOLD))
		v.add_child(r)
	return c


func _list_card(icon_kind: String, title_text: String, items: Array, empty: String) -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header(icon_kind if icon_kind != "thumb" else "star", title_text))
	if items.is_empty():
		v.add_child(QuestUI.label(empty, 13, QuestUI.MUTED, true))
	for d in items:
		var h := QuestUI.hbox(8)
		h.add_child(QuestUI.icon("circle_check" if icon_kind == "thumb" else "alert", 18.0, QuestUI.GREEN if icon_kind == "thumb" else QuestUI.GOLD))
		var dv := QuestUI.vbox(2)
		dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(QuestUI.label(str(d.get("title", "")), 14, QuestUI.TEXT, true, true))
		dv.add_child(QuestUI.label(str(d.get("detail", "")), 12, QuestUI.MUTED, true))
		h.add_child(dv)
		v.add_child(h)
	return c


func _ai_card() -> Control:
	var c := QuestUI.card(null, 0.92, Color(QuestUI.GOLD, 0.4))
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("spark", "AI 個人化回饋"))
	var coach := str(_mine.get("coach", ""))
	_coach_label = QuestUI.label(coach if coach != "" else "AI 回饋整理中……", 15, QuestUI.INK, true)
	var bubble := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#F3F0E7")
	s.set_corner_radius_all(14)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	bubble.add_theme_stylebox_override("panel", s)
	bubble.add_child(_coach_label)
	v.add_child(bubble)
	v.add_child(QuestUI.label("來自本次決策的具體證據", 14, QuestUI.GOLD, false, true))
	for q in _evidence(3):
		v.add_child(QuestUI.label("・" + str(q), 13, QuestUI.TEXT, true))
	return c


func _cert_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("doc", "培訓證書條件"))
	var modules := [
		["基礎保障規劃", _has_stage("方案配置")],
		["家庭責任與風險", _has_need_like(["家", "孩", "房貸", "扶養", "父母"])],
		["退休與資產規劃", _has_need_like(["退休", "資產", "投資"])],
		["稅務與財富傳承", false],
		["高資產客戶策略", false],
		["合規與職業操守", not _any_bad("合規") and _has_stage("合規檢核")],
	]
	var done := 0
	for mdl in modules:
		if mdl[1]:
			done += 1
	var h := QuestUI.hbox(12)
	var ring := QuestUI.Ring.new()
	ring.custom_minimum_size = Vector2(90, 90)
	ring.ratio = float(done) / modules.size()
	ring.color = QuestUI.GREEN
	ring.center_text = "%d%%" % int(round(100.0 * done / modules.size()))
	h.add_child(ring)
	var hv := QuestUI.vbox(2)
	hv.add_child(QuestUI.label("初級顧問認證", 15, QuestUI.TEXT, false, true))
	hv.add_child(QuestUI.label("%d / %d 模組" % [done, modules.size()], 14, QuestUI.GOLD))
	h.add_child(hv)
	v.add_child(h)
	for mdl in modules:
		var r := QuestUI.hbox(8)
		r.add_child(QuestUI.icon("circle_check" if mdl[1] else "circle", 16.0, QuestUI.GREEN if mdl[1] else QuestUI.MUTED))
		r.add_child(QuestUI.label(str(mdl[0]), 13, QuestUI.TEXT if mdl[1] else QuestUI.MUTED))
		v.add_child(r)
	return c


func _practice_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("target", "下一次建議練習"))
	var tips: Array = []
	if _any_bad("需求訪談") or _any_bad("線索分類"):
		tips.append(["深化需求挖掘", "先問生活與最不能犧牲的目標，再談預算；把和財務無關的線索排除在外。"])
	if _any_bad("方案配置") or _any_bad_title("預算"):
		tips.append(["預算內的取捨", "先守住緊急預備，再用 2–3 張保障卡承接最關鍵的風險。"])
	if _any_bad("異議處理"):
		tips.append(["異議處理技巧", "先接住感受、再開放式提問，最後把方案連回客戶自己的目標。"])
	if _any_bad("合規檢核") or _any_bad("合規"):
		tips.append(["辨識合規風險", "留意保證獲利、名額期限與「之後再補資料」這類說法。"])
	if GameState.overtime() > 0:
		tips.append(["時間管理", "會談時間有限：先完成關鍵決定，細節留到下次會談。"])
	if tips.is_empty():
		tips.append(["挑戰更難的客戶", "這局表現穩定，試試進階或挑戰難度的客戶。"])
	for t in tips.slice(0, 3):
		var dv := QuestUI.vbox(2)
		dv.add_child(QuestUI.label(str(t[0]), 14, QuestUI.TEXT, false, true))
		dv.add_child(QuestUI.label(str(t[1]), 12, QuestUI.MUTED, true))
		v.add_child(dv)
	return c


func _next_client_card() -> Control:
	var c := QuestUI.card(null, 0.92)
	var v := QuestUI.vbox(8)
	c.add_child(v)
	v.add_child(QuestUI.header("user", "適合解鎖的下一位客戶"))
	var served: Array = []
	for b in Net.me().get("book", []):
		served.append(str((b as Dictionary).get("clientId", "")))
	served.append(GameState.client_id)
	var order := ["入門", "進階", "挑戰"]
	var cur := order.find(str(GameState.current_client().get("difficulty", "入門")))
	var target: String = order[mini(order.size() - 1, maxi(0, cur) + (1 if int(_mine.get("score", 0)) >= 75 else 0))]
	var pick: Dictionary = {}
	for o in _state.get("caseOptions", []):
		var od := o as Dictionary
		if served.has(str(od.get("id", ""))):
			continue
		if pick.is_empty() or str(od.get("difficulty", "")) == target:
			pick = od
	var contacts: Array = Net.me().get("contacts", [])
	if not pick.is_empty():
		var h := QuestUI.hbox(10)
		h.add_child(QuestUI.portrait(str(pick.get("id", "")), Vector2(64, 76)))
		var pv := QuestUI.vbox(2)
		pv.add_child(QuestUI.label("%s（%s）" % [pick.get("name", ""), pick.get("difficulty", "")], 15, QuestUI.TEXT, false, true))
		pv.add_child(QuestUI.label(str(pick.get("tag", pick.get("job", ""))), 12, QuestUI.MUTED, true))
		pv.add_child(QuestUI.label("建議理由：%s" % ("你這局表現穩定，可以挑戰更複雜的需求。" if target != order[maxi(0, cur)] else "再練一位同難度的客戶，鞏固這局的弱項。"), 12, QuestUI.TEXT, true))
		h.add_child(pv)
		v.add_child(h)
	if not contacts.is_empty():
		v.add_child(QuestUI.label("人脈中認識的客戶：" + "、".join(contacts), 12, QuestUI.MUTED, true))
	return c


func _actions() -> Control:
	var h: BoxContainer = QuestUI.hbox(10) if _wide() else QuestUI.vbox(8)
	var again: Button = QuestUI.button("再挑戰一位客戶", _again, "primary", "refresh")
	again.name = "PlayAgain"
	var home: Button = QuestUI.button("返回主畫面", func(): main.leave_to_menu(), "secondary", "house")
	home.name = "BackHome"
	var codex: Button = QuestUI.button("查看客戶圖鑑", func(): Net.leave(); main.show_records(), "secondary", "people")
	codex.name = "OpenCodex"
	var copy: Button = QuestUI.button("複製報告", _copy, "secondary", "copy")
	copy.name = "CopyReport"
	var export: Button = QuestUI.button("匯出訓練結果", _export, "secondary", "export")
	export.name = "ExportReport"
	for b in [again, home, codex, copy, export]:
		(b as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


# --- Evidence from this game's decisions --------------------------------------------------------

func _all_decisions() -> Array:
	var out: Array = []
	for d in Net.me().get("decisions", []):
		var dd := d as Dictionary
		out.append({"stage": dd.get("stage", ""), "title": dd.get("title", ""), "detail": dd.get("body", ""), "quality": dd.get("quality", "")})
	var recs := GameState.all_records()
	for id in recs:
		for d in (recs[id] as Dictionary).get("decisions", []):
			if str((d as Dictionary).get("stage", "")) != "經驗值":
				out.append(d)
	return out


func _key_decisions(n: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for d in _all_decisions():
		var st := str(d.get("stage", ""))
		if seen.has(st) and out.size() >= 3:
			continue
		seen[st] = true
		out.append(d)
		if out.size() >= n:
			break
	return out


func _best(n: int, q: String) -> Array:
	var out: Array = []
	for d in _all_decisions():
		if str(d.get("quality", "")) == q:
			out.append(d)
			if out.size() >= n:
				break
	return out


func _any_bad(stage: String) -> bool:
	for d in _all_decisions():
		if str(d.get("stage", "")).contains(stage) and str(d.get("quality", "")) == "bad":
			return true
	return false


func _any_bad_title(word: String) -> bool:
	for d in _all_decisions():
		if str(d.get("title", "")).contains(word) and str(d.get("quality", "")) == "bad":
			return true
	return false


func _has_stage(stage: String) -> bool:
	for d in _all_decisions():
		if str(d.get("stage", "")) == stage:
			return true
	return false


func _has_need_like(words: Array) -> bool:
	for n in GameState.record.get("needs", []):
		for w in words:
			if str((n as Dictionary).get("text", "")).contains(str(w)):
				return true
	return false


## Concrete quotes: questions asked, misses, the plan, the reply, slips, events
func _evidence(n: int) -> Array:
	var out: Array = []
	for d in _all_decisions():
		var st := str(d.get("stage", ""))
		var title_text := str(d.get("title", ""))
		var line := ""
		match st:
			"需求訪談":
				line = "你問：「%s」——%s" % [title_text, str(d.get("detail", "")).substr(0, 40)]
			"線索分類":
				line = "%s：%s" % [title_text, str(d.get("detail", "")).substr(0, 40)]
			"方案配置":
				line = title_text
			"異議處理":
				line = "%s——%s" % [title_text.substr(0, 40), str(d.get("detail", "")).substr(0, 30)]
			"合規檢核", "人生事件":
				line = "%s：%s" % [title_text, str(d.get("detail", "")).substr(0, 40)]
		if line != "" and not out.has(line):
			out.append(line)
		if out.size() >= n:
			break
	return out


func report_text() -> String:
	var dims := _dimensions()
	var lines: Array = []
	lines.append("INSURE QUEST｜人生顧問局 — 本局顧問培訓報告")
	lines.append("客戶：%s" % GameState.client_name())
	lines.append("綜合評級：%s（%d / 100）" % [_mine.get("grade", "—"), int(_mine.get("score", 0))])
	for k in dims:
		lines.append("%s：%d" % [k, int(dims[k])])
	var tm := _selected_timeline()
	if not tm.is_empty():
		var adopted: bool = bool(tm.get("adopted", true))
		var worst_no := int(tm.get("worstNo", 0))
		var worst_with := int(tm.get("worstWith", 0))
		var x_val := _fmt_money(worst_with) if adopted else "客戶未採用"
		lines.append("十年最糟一年：有規劃 %s／沒規劃 %s" % [x_val, _fmt_money(worst_no)])
	lines.append("")
	lines.append("關鍵決策：")
	for d in _key_decisions(8):
		lines.append("・%s｜%s：%s" % [d.get("stage", ""), d.get("title", ""), d.get("detail", "")])
	lines.append("")
	lines.append("AI 回饋：%s" % str(_mine.get("coach", "")))
	lines.append("顧問等級：Lv.%d（本局 +%d XP）" % [GameState.advisor_level(), GameState.game_xp()])
	return "\n".join(lines)


func _copy() -> void:
	DisplayServer.clipboard_set(report_text())
	_toast("報告已複製到剪貼簿")


func _export() -> void:
	var text := report_text()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "insure-quest-training-report.txt", "text/plain")
		# The certificate image too (the original report's renderer)
		if _legacy == null:
			_legacy = ReportScreen.new()
			_legacy.set("main", main)
			_legacy.visible = false
			add_child(_legacy)
		if not _mine.is_empty():
			_legacy.call("_download_certificate", _mine, _state)
		_toast("已下載訓練報告與證書")
		return
	var path := "user://training_report_%s.txt" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
		_toast("已匯出：" + ProjectSettings.globalize_path(path))
	else:
		_toast("匯出失敗，請改用「複製報告」")


func _again() -> void:
	var bots: Array = []
	for p in _state.get("players", []):
		if bool((p as Dictionary).get("isBot", false)):
			bots.append(str(p.get("botLevel", "novice")) if p.get("botLevel") != null else "novice")
	Net.leave()
	main.create_and_join(bots, true)


func _toast(t: String) -> void:
	if main and main.has_method("toast"):
		main.toast(t)


## Six-axis ability chart (rule-engine scores + training record)
class Radar extends Control:
	var values: Dictionary = {}

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var keys := values.keys()
		var n := keys.size()
		if n < 3:
			return
		var c := size * 0.5 + Vector2(0, 6)
		var r := minf(size.x, size.y) * 0.34
		var font := get_theme_default_font()
		for ring in [0.33, 0.66, 1.0]:
			var pts := PackedVector2Array()
			for i in range(n + 1):
				var a := -PI * 0.5 + TAU * (i % n) / n
				pts.append(c + Vector2(cos(a), sin(a)) * r * ring)
			draw_polyline(pts, Color(1, 1, 1, 0.14), 1.0, true)
		var poly := PackedVector2Array()
		for i in range(n):
			var a := -PI * 0.5 + TAU * i / n
			var v := clampf(float(values[keys[i]]), 0, 100) / 100.0
			poly.append(c + Vector2(cos(a), sin(a)) * r * maxf(v, 0.04))
			draw_line(c, c + Vector2(cos(a), sin(a)) * r, Color(1, 1, 1, 0.1), 1.0)
			var lp := c + Vector2(cos(a), sin(a)) * (r + 22)
			var txt := "%s %d" % [keys[i], int(values[keys[i]])]
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, lp - Vector2(w * 0.5, -4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#F3F0E7"))
		draw_colored_polygon(poly, Color(QuestUI.GREEN, 0.28))
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, QuestUI.GREEN, 2.0, true)
		for p in poly:
			draw_circle(p, 3.5, QuestUI.GREEN)
