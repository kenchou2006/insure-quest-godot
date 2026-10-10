@tool
extends Control
## Settlement report: ranking, individual five competencies, AI coach feedback, key decision review. Supports portrait vertical split.

var main: Node
var _v: VBoxContainer
var _scroll: ScrollContainer
var _letter_idx: int = 0
var _downloading_cert: bool = false
var _coach_label: Label = null
var _cert_coach_label: Label = null
var _cur_letter_card: Control = null
var _coach_streamed: bool = false
var _streamed_coach_text: String = ""
var _letters_streamed: Dictionary = {}
var _streamed_letter_texts: Dictionary = {}


func _ready() -> void:
	Tutorial.record_game()
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad: int = 12 if UI.is_phone_portrait() else (16 if UI.is_portrait() else 32)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, pad)
	add_child(m)
	_v = UI.vbox(14)
	_scroll = UI.scroll(_v)
	m.add_child(_scroll)
	UI.pop_in(self)
	if not Engine.is_editor_hint() and not Net.stream_chunk.is_connected(_on_stream_chunk):
		Net.stream_chunk.connect(_on_stream_chunk)
	if not Net.state.is_empty():
		refresh(Net.state)


func _on_stream_chunk(key: String, text: String, _done: bool) -> void:
	if key == "coach:" + Net.player_id:
		_coach_streamed = true
		_streamed_coach_text = text
		if _coach_label != null and is_instance_valid(_coach_label):
			_coach_label.modulate.a = 1.0
			_coach_label.add_theme_color_override("font_color", UI.TEXT)
			_coach_label.text = text
			_coach_label.visible_ratio = 1.0
		if _cert_coach_label != null and is_instance_valid(_cert_coach_label):
			_cert_coach_label.modulate.a = 1.0
			var coach_line: String = text.split("。")[0] if text.contains("。") else text
			if coach_line.length() > 60:
				coach_line = coach_line.substr(0, 58) + "…"
			_cert_coach_label.text = "教練評語：「%s」" % coach_line
			_cert_coach_label.visible_ratio = 1.0
	elif key.begins_with("letter:" + Net.player_id + ":"):
		var parts: PackedStringArray = key.split(":")
		if parts.size() >= 3:
			var cid: String = parts[2]
			_letters_streamed[cid] = true
			_streamed_letter_texts[cid] = text
			if _cur_letter_card != null and is_instance_valid(_cur_letter_card):
				var cur_cid: String = str(_cur_letter_card.get_meta("client_id", ""))
				if cur_cid == cid or cur_cid == "":
					var body_lbl: Label = _cur_letter_card.find_child("LetterBodyLabel", true, false)
					if body_lbl != null:
						body_lbl.modulate.a = 1.0
						body_lbl.add_theme_color_override("font_color", Color("#2c241d"))
						body_lbl.text = text
						body_lbl.visible_ratio = 1.0


func on_layout_changed(_is_portrait: bool) -> void:
	if not Net.state.is_empty():
		refresh(Net.state)


func refresh(s: Dictionary) -> void:
	UI.clear(_v)
	var portrait: bool = UI.is_portrait()

	if UI.is_phone_portrait():
		var top_row := UI.hbox(8)
		top_row.add_child(UI.label("顧問結算報告", 20, UI.ACCENT_2))
		top_row.add_child(UI.spacer())
		if Net.is_logged_in():
			top_row.add_child(UI.button("查看我的成長", func(): Net.leave(); main.show_records(), 14, UI.ACCENT))
		else:
			top_row.add_child(UI.button("培訓紀錄", func(): Net.leave(); main.show_records(), 14, UI.PANEL_2))
		top_row.add_child(UI.button("回主選單", func(): main.leave_to_menu(), 14))
		_v.add_child(top_row)

		var hint_row := UI.hbox(4)
		hint_row.add_child(UI.spacer())
		if Net.is_logged_in():
			hint_row.add_child(UI.label("✓ 紀錄已保存", 12, UI.GOOD))
		else:
			hint_row.add_child(UI.label("登入後可保存紀錄", 12, UI.MUTED))
		_v.add_child(hint_row)
	else:
		var head := UI.hbox(10)
		head.add_child(UI.label("顧問結算報告", 24 if portrait else 32, UI.ACCENT_2))
		head.add_child(UI.spacer())
		if Net.is_logged_in():
			head.add_child(UI.label("✓ 紀錄已保存", 13, UI.GOOD))
			head.add_child(UI.button("查看我的成長", func(): Net.leave(); main.show_records(), 15, UI.ACCENT))
		else:
			head.add_child(UI.label("登入後可保存紀錄", 13, UI.MUTED))
			head.add_child(UI.button("培訓紀錄", func(): Net.leave(); main.show_records(), 15, UI.PANEL_2))
		head.add_child(UI.button("回主選單", func(): main.leave_to_menu(), 15))
		_v.add_child(head)
	_v.add_child(UI.label("評分＝能力 50%＋服務 15%＋守護 10%＋聲望 15%＋業績 10%。不適合的銷售會在稽核中被扣分。", 13 if portrait else 14, UI.MUTED, true))

	var final: Array = s.get("final", []) if s.get("final") != null else []
	var mine: Dictionary = {}
	for r: Dictionary in final:
		if str(r.get("playerId", "")) == Net.player_id:
			mine = r
			break

	# Training certificate card for local human player at top of report
	if not mine.is_empty() and not mine.get("isBot", false):
		_v.add_child(_build_certificate_card(mine, s))

	var rank: int = 1
	for r: Dictionary in final:
		var row := UI.panel(UI.PANEL_2 if str(r.get("playerId", "")) == Net.player_id else UI.PANEL, 12, 12)
		var h := UI.hbox(12 if portrait else 16)
		h.add_child(UI.label("#%d" % rank, 20 if portrait else 24, UI.GOLD if rank == 1 else UI.MUTED))
		var g_str: String = str(r.get("grade", "C"))
		var g_col: Color = {"S": UI.GOLD, "A": UI.GOOD, "B": UI.INFO}.get(g_str, UI.BAD)
		var g := UI.label(g_str, 28 if portrait else 34, g_col)
		g.custom_minimum_size = Vector2(36 if portrait else 48, 0)
		h.add_child(g)
		var nv := UI.vbox(2)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(UI.label("%s%s　%d 分" % [r.get("name", ""), "（電腦）" if r.get("isBot", false) else "", int(r.get("score", 0))], 16 if UI.is_phone_portrait() else (18 if portrait else 20), UI.TEXT, true))

		# Score breakdown row under grade: 能力 / 服務 / 守護 / 聲望 / 業績 with weights (50/15/10/15/10)
		var sk_dict: Dictionary = r.get("skill", {}) if r.get("skill") is Dictionary else {}
		var sk_val: int = 0
		if not sk_dict.is_empty():
			var sum_sk: float = 0.0
			for k in ["trust", "insight", "fit", "risk", "compliance"]:
				sum_sk += float(sk_dict.get(k, 0.0))
			sk_val = int(round(sum_sk / 5.0))
		var s_val: int = int(r.get("service", 0))
		var p_val: int = int(r.get("protection", 0))
		var rep_val: int = int(r.get("reputation", 0))
		var com_val: int = int(r.get("commission", 0))

		var breakdown_txt := "能力(50%%) %d ｜ 服務(15%%) %d ｜ 守護(10%%) %d ｜ 聲望(15%%) %d ｜ 業績(10%%) %d" % [sk_val, s_val, p_val, rep_val, com_val]
		nv.add_child(UI.label(breakdown_txt, 11 if UI.is_phone_portrait() else 12, UI.ACCENT_2, true))

		nv.add_child(UI.label("客戶 %d 位・滿意度 %d・守護分 %d・聲望 %d・業績 %d" % [int(r.get("clients", 0)), s_val, p_val, rep_val, com_val], 11 if UI.is_phone_portrait() else 12, UI.MUTED, true))
		for cap in (r.get("caps", []) as Array):
			nv.add_child(UI.label("評級上限：" + str(cap), 12 if UI.is_phone_portrait() else 13, UI.OK, true))
		h.add_child(nv)
		row.add_child(h)
		_v.add_child(row)
		rank += 1

	# Honor medal wall (endgame special awards)
	var awards: Array = s.get("awards", []) if s.get("awards") != null else []
	if not awards.is_empty():
		var aw_panel := UI.panel(UI.PANEL, 14, 12)
		aw_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, 14, UI.GOLD, 8, false))
		var aw_v := UI.vbox(8)
		var aw_head := UI.hbox(8)
		aw_head.add_child(UI.label("★ 本局榮譽勳章", 18 if portrait else 20, UI.GOLD))
		aw_head.add_child(UI.spacer())
		aw_head.add_child(UI.label("表彰本局卓越顧問表現", 12 if portrait else 13, UI.MUTED))
		aw_v.add_child(aw_head)

		var aw_grid := GridContainer.new()
		aw_grid.columns = 1 if UI.is_phone_portrait() else (2 if portrait else 3)
		aw_grid.add_theme_constant_override("h_separation", 8)
		aw_grid.add_theme_constant_override("v_separation", 8)
		aw_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		for a: Dictionary in awards:
			var wid: String = str(a.get("winnerId", ""))
			var is_my_award: bool = wid != "" and wid == Net.player_id
			var card_bg: Color = UI.PANEL_2 if is_my_award else UI.PANEL
			var card_border: Color = UI.GOLD if is_my_award else Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.3)
			var ac := UI.panel(card_bg, 10, 10)
			ac.add_theme_stylebox_override("panel", UI.box(card_bg, 10, card_border, 8, false))
			# Autowrapped Label has min width 0; cells must expand or text gets squeezed into one character per line
			ac.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var av := UI.vbox(3)
			var h_row := UI.hbox(6)
			h_row.add_child(UI.label("◆", 16, UI.GOLD if is_my_award else UI.ACCENT_2))
			var atitle: String = str(a.get("title", "榮譽獎項"))
			var title_lbl := UI.label(atitle, 15 if UI.is_phone_portrait() else 16, UI.GOLD, true)
			title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h_row.add_child(title_lbl)
			av.add_child(h_row)

			var wname: String = str(a.get("winnerName", "顧問"))
			var win_lbl := "得主：%s" % wname + ("（你）★" if is_my_award else "")
			av.add_child(UI.label(win_lbl, 13 if UI.is_phone_portrait() else 14, UI.TEXT if is_my_award else UI.MUTED, true))

			var reason: String = str(a.get("reason", ""))
			if reason != "":
				av.add_child(UI.label(reason, 11 if UI.is_phone_portrait() else 12, UI.MUTED, true))

			ac.add_child(av)
			aw_grid.add_child(ac)

		aw_v.add_child(aw_grid)
		aw_panel.add_child(aw_v)
		_v.add_child(aw_panel)

	if mine.is_empty():
		return

	# Stack five competencies and coach feedback vertically in portrait
	var body: BoxContainer = UI.vbox(12) if portrait else UI.hbox(16)
	var sk := UI.panel()
	if not portrait:
		sk.custom_minimum_size = Vector2(360, 0)
	var skv := UI.vbox(8)
	skv.add_child(UI.label("你的專業五力（面談平均）", 17 if portrait else 18, UI.ACCENT_2))
	var skill_dict: Dictionary = mine.get("skill", {})
	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		skv.add_child(UI.metric_row(k, float(skill_dict.get(k, 50.0))))
	sk.add_child(skv)
	body.add_child(sk)

	var coach := UI.panel()
	coach.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := UI.hbox(12)
	var img := TextureRect.new()
	img.texture = load("res://assets/coach.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img.custom_minimum_size = Vector2(80 if portrait else 110, 100 if portrait else 130)
	cv.add_child(img)
	var ct := UI.vbox(6)
	ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ct.add_child(UI.label("AI 教練回饋" if Net.ai_enabled else "教練回饋", 17 if portrait else 18, UI.ACCENT_2))
	# Show prompt while AI is still drafting (only logged-in players with AI will wait for AI version)
	var coach_str: String = str(mine.get("coach", ""))
	var coach_pending: bool = bool(mine.get("coachPending", false)) or (bool(s.get("aiPending", false)) and Net.ai_enabled and coach_str == "")
	var ai_pending: bool = coach_pending
	if coach_str != "":
		_coach_label = UI.label(coach_str, 15 if portrait else 16, UI.TEXT, true)
		if not _coach_streamed:
			UI.typewriter(_coach_label, coach_str, false)
		ct.add_child(_coach_label)
	elif _streamed_coach_text != "":
		_coach_label = UI.label(_streamed_coach_text, 15 if portrait else 16, UI.TEXT, true)
		ct.add_child(_coach_label)
	elif coach_pending:
		_coach_label = UI.label("AI 教練評語產生中……", 15 if portrait else 16, UI.GOLD, true)
		if not Engine.is_editor_hint() and not UI.is_animation_disabled():
			var tw := _coach_label.create_tween().set_loops()
			tw.tween_property(_coach_label, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_coach_label, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
		ct.add_child(_coach_label)
	else:
		_coach_label = UI.label(coach_str, 15 if portrait else 16, UI.TEXT, true)
		ct.add_child(_coach_label)
	cv.add_child(ct)
	coach.add_child(cv)
	body.add_child(coach)
	_v.add_child(body)

	# Letter from ten years later (up to 3 letters, navigable left/right)
	var is_ai_player: bool = Net.ai_enabled and not bool(mine.get("isBot", false)) and Net.is_logged_in()
	var letters_pending: bool = is_ai_player and (bool(mine.get("lettersPending", false)) or bool(s.get("aiPending", false)))
	var letters: Array = mine.get("letters", []) as Array if mine.get("letters") != null else []
	if not letters.is_empty():
		var l_section := UI.vbox(8)
		l_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var l_head := UI.hbox(8)
		l_head.add_child(UI.label("十年後的信", 17 if portrait else 18, UI.ACCENT_2))
		l_head.add_child(UI.spacer())

		if letters.size() > 1:
			var prev_btn := UI.button("◀ 上一封", func():
				_letter_idx = (_letter_idx - 1 + letters.size()) % letters.size()
				refresh(s)
			, 12 if UI.is_phone_portrait() else 13, UI.PANEL_2)
			l_head.add_child(prev_btn)

			l_head.add_child(UI.label("%d / %d" % [_letter_idx + 1, letters.size()], 13, UI.MUTED))

			var next_btn := UI.button("下一封 ▶", func():
				_letter_idx = (_letter_idx + 1) % letters.size()
				refresh(s)
			, 12 if UI.is_phone_portrait() else 13, UI.PANEL_2)
			l_head.add_child(next_btn)

		l_section.add_child(l_head)

		if _letter_idx >= letters.size() or _letter_idx < 0:
			_letter_idx = 0
		var cur_letter: Dictionary = letters[_letter_idx] if letters[_letter_idx] is Dictionary else {}
		var c_name: String = str(cur_letter.get("clientName", "客戶"))
		var cid: String = str(cur_letter.get("clientId", cur_letter.get("id", "")))
		var has_streamed_letter: bool = _streamed_letter_texts.has(cid) and str(_streamed_letter_texts[cid]) != ""
		var card := UI.letter_card(cur_letter, c_name, letters_pending and not has_streamed_letter)
		card.set_meta("client_id", cid)
		_cur_letter_card = card
		l_section.add_child(card)

		var body_lbl: Label = card.find_child("LetterBodyLabel", true, false)
		if body_lbl != null:
			if letters_pending and has_streamed_letter:
				body_lbl.text = str(_streamed_letter_texts[cid])
				body_lbl.add_theme_color_override("font_color", Color("#2c241d"))
				body_lbl.visible_ratio = 1.0
			elif not letters_pending:
				var c_content: String = str(cur_letter.get("content", ""))
				if c_content != "":
					var was_streamed: bool = bool(_letters_streamed.get(cid, false))
					if not was_streamed:
						UI.typewriter(body_lbl, c_content, false)
					else:
						body_lbl.text = c_content
						body_lbl.visible_ratio = 1.0

		# Small TimelineChart in compact mode (height ~90)
		var timelines_arr: Array = mine.get("timelines", []) as Array if mine.get("timelines") != null else []
		var match_timeline: Dictionary = {}
		for tm in timelines_arr:
			if tm is Dictionary and str(tm.get("clientName", "")) == c_name:
				match_timeline = tm
				break
		if match_timeline.is_empty():
			if _letter_idx == 0 and mine.get("timeline") is Dictionary:
				match_timeline = mine.get("timeline")
			elif _letter_idx < timelines_arr.size() and timelines_arr[_letter_idx] is Dictionary:
				match_timeline = timelines_arr[_letter_idx]

		if not match_timeline.is_empty():
			var chart_card := UI.panel(UI.PANEL, 8, 8)
			var chart_v := UI.vbox(3)
			chart_v.add_child(UI.label("十年財務人生軌跡（有規劃 vs 沒有規劃）：", 12, UI.MUTED))
			var tc := TimelineChart.new()
			tc.set_data(match_timeline, true)
			chart_v.add_child(tc)
			chart_card.add_child(chart_v)
			l_section.add_child(chart_card)

		_v.add_child(l_section)

	var me: Dictionary = Net.me()
	var ds: Array = me.get("decisions", [])
	if not ds.is_empty():
		var dp := UI.panel(UI.PANEL, 14, 14)
		var dv := UI.vbox(10)

		# Phone portrait: title and quality counts stack, side by side they exceed the screen width
		var dh: BoxContainer = UI.vbox(4) if UI.is_phone_portrait() else UI.hbox(8)
		dh.add_child(UI.label("關鍵決策回顧（最近 %d 項）" % ds.size(), 17 if portrait else 18, UI.ACCENT_2))
		if not UI.is_phone_portrait():
			dh.add_child(UI.spacer())
		var good_cnt: int = 0
		var ok_cnt: int = 0
		var bad_cnt: int = 0
		for d: Dictionary in ds:
			var q: String = str(d.get("quality", ""))
			if q == "good": good_cnt += 1
			elif q == "ok": ok_cnt += 1
			elif q == "bad": bad_cnt += 1
		dh.add_child(UI.label("✓ 優質 %d　△ 尚可 %d　× 盲點 %d" % [good_cnt, ok_cnt, bad_cnt], 12 if portrait else 13, UI.MUTED))
		dv.add_child(dh)

		var d_grid := GridContainer.new()
		d_grid.columns = 1 if UI.is_phone_portrait() else (1 if portrait else 2)
		d_grid.add_theme_constant_override("h_separation", 10)
		d_grid.add_theme_constant_override("v_separation", 10)
		d_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		for d: Dictionary in ds:
			var q: String = str(d.get("quality", "ok"))
			var q_col: Color = UI.tone_color(q)
			var q_bg: Color = Color(q_col.r, q_col.g, q_col.b, 0.08)
			var q_border: Color = Color(q_col.r, q_col.g, q_col.b, 0.35)
			var q_label: String = {"good": "✓ 優質", "ok": "△ 尚可", "bad": "× 盲點"}.get(q, "・紀錄")

			var card := UI.panel(q_bg, 8, 10)
			card.add_theme_stylebox_override("panel", UI.box(q_bg, 8, q_border, 6, false))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var cv_item := UI.vbox(4)
			var top_row := UI.hbox(6)

			# Quality tag chip
			var badge := UI.chip(Color(q_col.r, q_col.g, q_col.b, 0.2), Color(0, 0, 0, 0), 4, 8, 3)
			badge.add_child(UI.label(q_label, 11, q_col))
			top_row.add_child(badge)

			# Round and client
			var rnd_txt := "第 %d 回合・%s" % [int(d.get("round", 1)), str(d.get("clientName", "客戶"))]
			top_row.add_child(UI.label(rnd_txt, 12, UI.TEXT))

			# Stage tag
			var stg_txt := "［%s］" % str(d.get("stage", ""))
			top_row.add_child(UI.label(stg_txt, 11, UI.MUTED))

			cv_item.add_child(top_row)

			# Decision title
			var tit_lbl := UI.label(str(d.get("title", "")), 14 if portrait else 15, UI.GOLD if q == "good" else UI.TEXT, true)
			cv_item.add_child(tit_lbl)

			# Decision description
			var body_txt: String = str(d.get("body", ""))
			if body_txt != "":
				var body_lbl := UI.label(body_txt, 12 if portrait else 13, UI.MUTED, true)
				cv_item.add_child(body_lbl)

			card.add_child(cv_item)
			d_grid.add_child(card)

		dv.add_child(d_grid)
		dp.add_child(dv)
		_v.add_child(dp)

	UI.pass_wheel(_v)


func _build_certificate_card(mine: Dictionary, s: Dictionary, for_export: bool = false) -> Control:
	if for_export:
		return _build_export_certificate_card(mine, s)

	var portrait: bool = UI.is_portrait()
	var is_phone: bool = UI.is_phone_portrait()

	# Warm palette: Ivory text on deep green background with gold borders
	var cert_bg := Color("#0d2821")
	var cert_ivory := Color("#fdfcf7")
	var cert_muted := Color("#c8ded4")

	var card_panel := UI.panel(cert_bg, 16, 14 if is_phone else 18)
	card_panel.add_theme_stylebox_override("panel", UI.box(cert_bg, 16, UI.GOLD, 8 if is_phone else 12, false))
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if not portrait and not UI.is_phone():
		card_panel.custom_minimum_size = Vector2(640, 360)

	var v := UI.vbox(10 if is_phone else 12)
	card_panel.add_child(v)

	# 1. Header row
	var head := UI.hbox(8)
	var title_lbl := UI.label("公平待客面談完訓卡", 20 if is_phone else 24, UI.GOLD)
	head.add_child(title_lbl)
	var sub_lbl := UI.label("｜ 專業顧問合格證明", 12 if is_phone else 14, cert_muted)
	head.add_child(sub_lbl)
	head.add_child(UI.spacer())

	var coach_pending: bool = bool(mine.get("coachPending", false)) or (bool(s.get("aiPending", false)) and Net.ai_enabled and str(mine.get("coach", "")) == "")

	# Download image button (web only, omitted in export instance)
	if not Engine.is_editor_hint() and OS.has_feature("web"):
		var dl_btn := UI.button("儲存圖片", func(): _download_certificate(mine, s), 12 if is_phone else 13, UI.ACCENT)
		dl_btn.disabled = coach_pending
		head.add_child(dl_btn)
		if coach_pending:
			head.add_child(UI.label("等待 AI 評語…", 11 if is_phone else 12, UI.GOLD))
	v.add_child(head)

	# 2. Main content row: Left info + competencies, Right seal & comment
	var body: BoxContainer = UI.vbox(10) if is_phone else UI.hbox(16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Left column: Name, Date, Clients served, Red light stamp, Mini 5-power bars
	var left_v := UI.vbox(6)
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info_h := UI.hbox(8)
	info_h.add_child(UI.label("顧問：%s" % str(mine.get("name", "顧問")), 16 if is_phone else 18, cert_ivory))
	var date_str: String = Time.get_date_string_from_system()
	info_h.add_child(UI.label("（%s 完訓）" % date_str, 12 if is_phone else 13, cert_muted))
	left_v.add_child(info_h)

	var stats_h := UI.hbox(8)
	var clients_count: int = int(mine.get("clients", 0))
	stats_h.add_child(UI.label("服務客戶：%d 位" % clients_count, 13 if is_phone else 14, cert_ivory))

	# Red-light count & stamp
	var red_lights: int = 0
	for b in Net.me().get("book", []):
		if bool(b.get("violation", false)):
			red_lights += 1
	if red_lights == 0 and mine.has("violations"):
		red_lights = int(mine.get("violations", 0))

	if red_lights == 0:
		var gold_stamp := UI.stamp("★ 零違規", UI.GOLD, 13 if is_phone else 14)
		stats_h.add_child(gold_stamp)
	else:
		var red_badge := UI.stamp("⚠ 違規 %d 次" % red_lights, UI.BAD, 13 if is_phone else 14)
		stats_h.add_child(red_badge)
	left_v.add_child(stats_h)

	# Five competencies mini bars
	var skill_dict: Dictionary = mine.get("skill", {})
	var skills_box := UI.vbox(2)
	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		var val: float = float(skill_dict.get(k, 50.0))
		var m_row := UI.metric_row(k, val)
		skills_box.add_child(m_row)
	left_v.add_child(skills_box)
	body.add_child(left_v)

	# Right column: Seal badge + one-line coach comment
	var right_v := UI.vbox(8)
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.alignment = BoxContainer.ALIGNMENT_CENTER

	var seal_box := UI.hbox(10)
	seal_box.alignment = BoxContainer.ALIGNMENT_CENTER

	# Seal-like badge in gold
	var grade_str: String = str(mine.get("grade", "C"))
	var grade_col: Color = {"S": UI.GOLD, "A": UI.GOOD, "B": UI.INFO}.get(grade_str, UI.BAD)
	var seal := UI.panel(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.18), 48 if is_phone else 64, 8)
	seal.add_theme_stylebox_override("panel", UI.box(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.22), 48 if is_phone else 64, UI.GOLD, 4, false))
	seal.custom_minimum_size = Vector2(80 if is_phone else 100, 80 if is_phone else 100)
	var seal_v := UI.vbox(0)
	seal_v.alignment = BoxContainer.ALIGNMENT_CENTER
	var s_lbl := UI.label(grade_str, 40 if is_phone else 52, UI.GOLD if grade_str == "S" else grade_col)
	s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_v.add_child(s_lbl)
	var s_sub := UI.label("GRADE", 10, UI.GOLD)
	s_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_v.add_child(s_sub)
	seal.add_child(seal_v)
	seal_box.add_child(seal)
	right_v.add_child(seal_box)

	# One-line coach comment or waiting state
	var coach_full: String = str(mine.get("coach", ""))
	if coach_full != "":
		var coach_line: String = coach_full.split("。")[0] if coach_full.contains("。") else coach_full
		if coach_line.length() > 60:
			coach_line = coach_line.substr(0, 58) + "…"
		else:
			coach_line += "。"
		_cert_coach_label = UI.label("教練評語：「%s」" % coach_line, 12 if is_phone else 13, cert_muted, true)
		_cert_coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not is_phone else HORIZONTAL_ALIGNMENT_LEFT
		if not _coach_streamed:
			UI.typewriter(_cert_coach_label, "教練評語：「%s」" % coach_line, false)
		right_v.add_child(_cert_coach_label)
	elif _streamed_coach_text != "":
		var coach_line: String = _streamed_coach_text.split("。")[0] if _streamed_coach_text.contains("。") else _streamed_coach_text
		if coach_line.length() > 60:
			coach_line = coach_line.substr(0, 58) + "…"
		_cert_coach_label = UI.label("教練評語：「%s」" % coach_line, 12 if is_phone else 13, cert_muted, true)
		_cert_coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not is_phone else HORIZONTAL_ALIGNMENT_LEFT
		right_v.add_child(_cert_coach_label)
	elif coach_pending:
		_cert_coach_label = UI.label("AI 教練評語產生中……", 12 if is_phone else 13, UI.GOLD, true)
		_cert_coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not is_phone else HORIZONTAL_ALIGNMENT_LEFT
		if not Engine.is_editor_hint() and not UI.is_animation_disabled():
			var tw := _cert_coach_label.create_tween().set_loops()
			tw.tween_property(_cert_coach_label, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
			tw.tween_property(_cert_coach_label, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
		right_v.add_child(_cert_coach_label)
	else:
		var coach_line := "持續精進需求訪談與專業配置。"
		_cert_coach_label = UI.label("教練評語：「%s」" % coach_line, 12 if is_phone else 13, cert_muted, true)
		_cert_coach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not is_phone else HORIZONTAL_ALIGNMENT_LEFT
		right_v.add_child(_cert_coach_label)

	body.add_child(right_v)
	v.add_child(body)

	return card_panel


func _build_export_certificate_card(mine: Dictionary, s: Dictionary) -> Control:
	var cert_bg := Color("#0d2821")
	var cert_ivory := Color("#fdfcf7")
	var cert_muted := Color("#c8ded4")

	var root := Control.new()
	root.custom_minimum_size = Vector2(1200, 675)
	root.size = Vector2(1200, 675)
	root.theme = UI.make_theme()

	var card_panel := UI.panel(cert_bg, 16, 24)
	var card_sb := UI.box(cert_bg, 16, UI.GOLD, 24, false)
	card_sb.set_border_width_all(3)
	card_sb.content_margin_left = 32
	card_sb.content_margin_right = 32
	card_sb.content_margin_top = 22
	card_sb.content_margin_bottom = 20
	card_panel.add_theme_stylebox_override("panel", card_sb)
	card_panel.position = Vector2(40, 30)
	card_panel.size = Vector2(1120, 615)
	card_panel.custom_minimum_size = Vector2(1120, 615)
	card_panel.clip_contents = true
	root.add_child(card_panel)

	var v := UI.vbox(12)
	card_panel.add_child(v)

	# 1. Header band across full width: 「公平待客面談完訓卡」 large (gold) with 「專業顧問合格證明」 subtitle; small game name on right
	var head := UI.hbox(10)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_lbl := UI.label("公平待客面談完訓卡", 28, UI.GOLD)
	head.add_child(title_lbl)
	var sub_lbl := UI.label("｜ 專業顧問合格證明", 16, cert_muted)
	head.add_child(sub_lbl)
	head.add_child(UI.spacer())
	var game_lbl := UI.label("INSURE QUEST 人生顧問局", 14, Color("#f3d282"))
	head.add_child(game_lbl)
	v.add_child(head)

	# 2. Body in two columns filling height: left ~55%, right ~45%
	var body := UI.hbox(28)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Left column: advisor name, date, clients served, stamp, 5-power bars
	var left_v := UI.vbox(10)
	left_v.custom_minimum_size = Vector2(580, 0)
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var info_h := UI.hbox(10)
	var adv_name: String = str(mine.get("name", "顧問"))
	info_h.add_child(UI.label("顧問：%s" % adv_name, 22, cert_ivory))
	var date_str: String = Time.get_date_string_from_system()
	info_h.add_child(UI.label("（%s 完訓）" % date_str, 15, cert_muted))
	left_v.add_child(info_h)

	var stats_h := UI.hbox(12)
	var clients_count: int = int(mine.get("clients", 0))
	stats_h.add_child(UI.label("服務客戶：%d 位" % clients_count, 16, cert_ivory))

	var red_lights: int = 0
	for b in Net.me().get("book", []):
		if bool(b.get("violation", false)):
			red_lights += 1
	if red_lights == 0 and mine.has("violations"):
		red_lights = int(mine.get("violations", 0))

	if red_lights == 0:
		var gold_stamp := UI.stamp("★ 零違規", UI.GOLD, 15)
		gold_stamp.scale = Vector2.ONE
		stats_h.add_child(gold_stamp)
	else:
		var red_badge := UI.stamp("⚠ 違規 %d 次" % red_lights, UI.BAD, 15)
		red_badge.scale = Vector2.ONE
		stats_h.add_child(red_badge)
	left_v.add_child(stats_h)

	# Five competency bars (~46 px per row)
	var skill_dict: Dictionary = mine.get("skill", {})
	var skills_box := UI.vbox(4)
	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		var val: float = float(skill_dict.get(k, 50.0))
		var m_row := UI.hbox(10)
		m_row.custom_minimum_size = Vector2(0, 46)
		m_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var l := UI.label(UI.METRIC_NAMES.get(k, k), 16, cert_ivory)
		l.custom_minimum_size = Vector2(85, 0)
		m_row.add_child(l)

		var val_col: Color = UI.GOOD if val >= 75 else (UI.OK if val >= 50 else UI.BAD)
		var pbar: ProgressBar = UI.bar(val, val_col, 240)
		pbar.custom_minimum_size = Vector2(240, 12)
		pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		m_row.add_child(pbar)

		var v_lbl := UI.label(str(int(val)), 16, val_col)
		v_lbl.custom_minimum_size = Vector2(36, 0)
		v_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		m_row.add_child(v_lbl)

		skills_box.add_child(m_row)
	left_v.add_child(skills_box)
	body.add_child(left_v)

	# Right column: seal, total score, quote box coach comment
	var right_v := UI.vbox(8)
	right_v.custom_minimum_size = Vector2(440, 0)
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.alignment = BoxContainer.ALIGNMENT_CENTER

	var seal_box := UI.hbox(0)
	seal_box.alignment = BoxContainer.ALIGNMENT_CENTER

	var grade_str: String = str(mine.get("grade", "C"))
	var grade_col: Color = {"S": UI.GOLD, "A": UI.GOOD, "B": UI.INFO}.get(grade_str, UI.BAD)

	var seal := UI.panel(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.18), 95, 10)
	var seal_sb := UI.box(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.22), 95, UI.GOLD, 5, false)
	seal_sb.set_border_width_all(4)
	seal.add_theme_stylebox_override("panel", seal_sb)
	seal.custom_minimum_size = Vector2(190, 190)

	var seal_v := UI.vbox(0)
	seal_v.alignment = BoxContainer.ALIGNMENT_CENTER
	var s_lbl := UI.label(grade_str, 76, UI.GOLD if grade_str == "S" else grade_col)
	s_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_v.add_child(s_lbl)
	var s_sub := UI.label("GRADE", 13, UI.GOLD)
	s_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_v.add_child(s_sub)
	seal.add_child(seal_v)
	seal_box.add_child(seal)
	right_v.add_child(seal_box)

	var score_val: int = int(mine.get("score", 0))
	var score_lbl := UI.label("綜合得分 %d 分" % score_val, 19, UI.GOLD)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_v.add_child(score_lbl)

	var quote_panel := UI.panel(Color("#091d17"), 10, 12)
	var q_sb := UI.box(Color("#091d17"), 10, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35), 12, false)
	q_sb.content_margin_left = 16
	q_sb.content_margin_right = 16
	q_sb.content_margin_top = 10
	q_sb.content_margin_bottom = 10
	quote_panel.add_theme_stylebox_override("panel", q_sb)
	quote_panel.custom_minimum_size = Vector2(430, 0)
	quote_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var qv := UI.vbox(4)
	qv.add_child(UI.label("★ 教練評語", 13, UI.GOLD))

	var coach_full: String = str(mine.get("coach", "持續精進需求訪談與專業配置。"))
	var coach_lbl := UI.label("「%s」" % coach_full, 18, cert_ivory, true)
	coach_lbl.custom_minimum_size = Vector2(400, 0)
	qv.add_child(coach_lbl)
	quote_panel.add_child(qv)
	right_v.add_child(quote_panel)

	body.add_child(right_v)
	v.add_child(body)

	# Footer strip: thin gold rule + small text
	var rule := Panel.new()
	var rule_sb := StyleBoxFlat.new()
	rule_sb.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.35)
	rule.add_theme_stylebox_override("panel", rule_sb)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	var footer_h := UI.hbox(8)
	var footer_lbl := UI.label("完訓日期 %s · 本證明由 INSURE QUEST 訓練紀錄自動產生" % date_str, 13, cert_muted)
	footer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_h.add_child(footer_lbl)
	v.add_child(footer_h)

	return root


func _download_certificate(mine: Dictionary, s: Dictionary) -> void:
	if Engine.is_editor_hint() or not OS.has_feature("web"):
		return
	var coach_pending: bool = bool(mine.get("coachPending", false)) or (bool(s.get("aiPending", false)) and Net.ai_enabled and str(mine.get("coach", "")) == "")
	if coach_pending:
		return
	if _downloading_cert:
		return
	_downloading_cert = true

	var prev_profile: String = UI.layout_profile
	UI.layout_profile = "desktop"
	var export_card: Control = _build_certificate_card(mine, s, true)
	UI.layout_profile = prev_profile

	var vp := SubViewport.new()
	vp.size = Vector2i(1200, 675)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	vp.add_child(export_card)
	add_child(vp)

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var tex := vp.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	if img == null or img.is_empty():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		tex = vp.get_texture()
		img = tex.get_image() if tex != null else null

	if img != null and not img.is_empty():
		var buf: PackedByteArray = img.save_png_to_buffer()
		if not buf.is_empty():
			JavaScriptBridge.download_buffer(buf, "fair-treatment-certificate.png", "image/png")

	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.queue_free()
	_downloading_cert = false
