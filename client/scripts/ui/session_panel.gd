extends PanelContainer
## 客戶面談面板：線索觀察 → 需求訪談（含 AI 自由提問）→ 方案配置 → 異議處理（含 AI 評分）→ 結果與壓力預演。
## 支援直向堆疊適配、保障卡自適應排版（防截斷）、AI 教練提示與壓力預演視覺化。

var main: Node
var _sess: Dictionary = {}
var _actor: bool = false
var _body: VBoxContainer
var _scroll: ScrollContainer
var _header_box: Control
var _metrics: VBoxContainer
var _steps: HBoxContainer
var _content: VBoxContainer
var _waiting_ai: bool = false
var _waiting_hint: bool = false
var _last_result_sound_key: String = ""

# 方案配置的本地暫存
var _plan_key: String = ""
var _sess_prev_id: String = ""
var _alloc: Dictionary = {"cash": 0, "protect": 0, "growth": 0}
var _cards: Array = []
var _plan_ui: Dictionary = {}


func _ready() -> void:
	var pad: int = 10 if UI.is_phone_portrait() else (14 if UI.is_portrait() else 16)
	add_theme_stylebox_override("panel", UI.box(Color("#102a37"), 18, Color("#2d5a6e"), pad))
	_body = UI.vbox(10 if UI.is_phone_portrait() else 12)
	_scroll = UI.scroll(_body)
	add_child(_scroll)
	_build_header_container()
	_steps = UI.hbox(4 if UI.is_phone_portrait() else 6)
	_body.add_child(_steps)
	_content = UI.vbox(10 if UI.is_phone_portrait() else 12)
	_body.add_child(_content)


func _build_header_container() -> void:
	if _header_box != null:
		_header_box.queue_free()
	if UI.is_portrait():
		_header_box = UI.vbox(8 if UI.is_phone_portrait() else 10)
	else:
		_header_box = UI.hbox(16)
	_body.add_child(_header_box)
	_body.move_child(_header_box, 0)


func refresh(sess: Dictionary, actor_name: String) -> void:
	var prev_key: String = "%s/%s/%d/%d/%s" % [_sess.get("client", {}).get("id", ""), _sess.get("step", ""), (_sess.get("asked", []) as Array).size(), (_sess.get("clues", []) as Array).filter(func(c: Dictionary): return bool(c.get("observed", false))).size(), str(_sess.get("result") != null)]
	_sess = sess
	_actor = str(sess.get("playerId", "")) == Net.player_id
	var key: String = "%s/%s/%d/%d/%s" % [sess.get("client", {}).get("id", ""), sess.get("step", ""), (sess.get("asked", []) as Array).size(), (sess.get("clues", []) as Array).filter(func(c: Dictionary): return bool(c.get("observed", false))).size(), str(sess.get("result") != null)]
	if key != prev_key:
		_waiting_ai = false
	# 換了一場面談（不同客戶或不同顧問）就回到頂端，避免停在上一場的捲動位置
	if str(sess.get("client", {}).get("id", "")) + str(sess.get("playerId", "")) != str(_sess_prev_id):
		_sess_prev_id = str(sess.get("client", {}).get("id", "")) + str(sess.get("playerId", ""))
		if _scroll != null:
			_scroll.set_deferred("scroll_vertical", 0)
	if sess.get("hint") != null:
		_waiting_hint = false

	_build_header(actor_name)
	_build_steps()
	UI.clear(_content)

	# 顯示 AI 教練提示按鈕或提示條
	_render_coach_hint()

	# 旁觀者競猜條（非當事人觀摩時顯示）
	if not _actor and str(sess.get("step", "")) in ["discover", "plan", "objection"]:
		_render_spectator_prediction()

	match str(sess.get("step", "")):
		"discover": _build_discover()
		"plan": _build_plan()
		"objection": _build_objection()
		"result": _build_result()

	UI.fade_in(_content, 0.2)
	UI.pass_wheel(_body)


func _build_header(actor_name: String) -> void:
	UI.clear(_header_box)
	var portrait: bool = UI.is_portrait()
	var is_phone: bool = UI.is_phone_portrait()
	var c: Dictionary = _sess.get("client", {})
	var referral: bool = bool(_sess.get("referral", false))
	var generated: bool = bool(c.get("generated", false))

	# 客戶檔案卡外框
	var card_panel := UI.panel(Color("#0d2432"), 14, 12 if is_phone else 14)
	card_panel.add_theme_stylebox_override("panel", UI.box(Color("#0d2432"), 14, UI.GOLD if referral else Color("#1e475b"), 10))
	card_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var main_box: BoxContainer = UI.vbox(10) if portrait else UI.hbox(16)
	card_panel.add_child(main_box)

	# 左側：大型頭像／插畫檔案框
	var p_size: int = 76 if is_phone else (90 if portrait else 105)
	var avatar_box := UI.portrait(c, p_size)
	main_box.add_child(avatar_box)

	# 右側：檔案詳細資料
	var info_v := UI.vbox(4 if is_phone else 5)
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 第 1 行：姓名、年齡、性別、職業
	var name_row := UI.hbox(8)
	var c_name: String = str(c.get("name", "客戶"))
	var c_age: int = int(c.get("age", 30))
	var c_gender: String = str(c.get("gender", ""))
	var c_job: String = str(c.get("job", ""))
	name_row.add_child(UI.label(c_name, 18 if is_phone else 21, UI.GOLD if referral else UI.TEXT, true))
	name_row.add_child(UI.label("｜ %d 歲・%s・%s" % [c_age, c_gender, c_job], 13 if is_phone else 15, UI.MUTED, true))
	info_v.add_child(name_row)

	# 第 2 行：Chips 標籤列（族群標籤、難度星等、轉介紹、AI 生成）
	var chips_row := UI.hbox(6)
	# 族群標籤 Chip
	var tag_str: String = str(c.get("tag", "生活理財"))
	if tag_str != "":
		var tag_p := UI.panel(Color("#133647"), 8, 4)
		tag_p.add_child(UI.label("［%s］" % tag_str, 11 if is_phone else 12, UI.ACCENT_2))
		chips_row.add_child(tag_p)

	# 難度星等 Chip
	var diff: String = str(c.get("difficulty", "normal"))
	var diff_stars: String = "★☆☆ 基礎" if diff == "easy" else ("★★☆ 進階" if diff == "normal" else "★★★ 挑戰")
	var diff_p := UI.panel(Color("#262214"), 8, 4)
	diff_p.add_child(UI.label(diff_stars, 11 if is_phone else 12, UI.GOLD))
	chips_row.add_child(diff_p)

	# 特殊身份 Chip
	if referral:
		var ref_p := UI.panel(Color("#183d2a"), 8, 4)
		ref_p.add_child(UI.label("♥ 轉介紹客戶", 11 if is_phone else 12, UI.GOOD))
		chips_row.add_child(ref_p)
	if generated:
		var ai_p := UI.panel(Color("#1a2b38"), 8, 4)
		ai_p.add_child(UI.label("AI 即時新客戶", 11 if is_phone else 12, UI.INFO))
		chips_row.add_child(ai_p)
	info_v.add_child(chips_row)

	# 第 3 行：財務目標
	var goal_str: String = str(c.get("goal", ""))
	var amount_str: String = str(c.get("amount", ""))
	if goal_str != "":
		info_v.add_child(UI.label("◎ 核心目標：%s（需求預算：%s）" % [goal_str, amount_str], 12 if is_phone else 13, UI.TEXT, true))

	# 第 4 行：家庭與收支
	var fam_str: String = str(c.get("family", ""))
	var inc_str: String = str(c.get("incomeInfo", ""))
	if fam_str != "" or inc_str != "":
		info_v.add_child(UI.label("家庭：%s ｜ 月收：%s" % [fam_str, inc_str], 11 if is_phone else 12, UI.MUTED, true))

	# 第 5 行：客戶獨白金句
	var quote_str: String = str(c.get("quote", ""))
	if quote_str != "":
		info_v.add_child(UI.label("「%s」" % quote_str, 12 if is_phone else 13, Color("#c7e4f2"), true))

	if not _actor:
		var obs_p := UI.panel(Color("#143547"), 8, 6)
		obs_p.add_theme_stylebox_override("panel", UI.box(Color("#143547"), 8, UI.GOLD, 6, false))
		var obs_v := UI.vbox(2)
		obs_v.add_child(UI.label("★ 觀摩學習中 ｜ %s 正在進行面談" % actor_name, 12 if is_phone else 13, UI.GOLD, true))
		obs_v.add_child(UI.label("觀察其提問順序與異議回應，亦可在下方參與評級競猜！", 11, UI.TEXT, true))
		obs_p.add_child(obs_v)
		info_v.add_child(obs_p)

	main_box.add_child(info_v)
	_header_box.add_child(card_panel)

	# 右側／下方：專業五力即時雷達指標
	_metrics = UI.vbox(3 if is_phone else 4)
	if not portrait:
		_metrics.custom_minimum_size = Vector2(230, 0)
	var m_dict: Dictionary = _sess.get("metrics", {})
	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		_metrics.add_child(UI.metric_row(k, float(m_dict.get(k, 50.0))))
	_header_box.add_child(_metrics)


func _build_steps() -> void:
	UI.clear(_steps)
	var cur_step: String = str(_sess.get("step", ""))
	var is_phone: bool = UI.is_phone_portrait()
	var step_keys := ["discover", "plan", "objection", "result"]
	var step_names := ["訪談線索", "方案配置", "異議處理", "結果預演"] if is_phone else ["① 訪談線索", "② 方案配置", "③ 異議處理", "④ 結果預演"]
	var cur_idx: int = step_keys.find(cur_step)
	if cur_idx < 0:
		cur_idx = 0

	for i: int in range(4):
		var is_past: bool = i < cur_idx
		var is_curr: bool = i == cur_idx
		var bg_col: Color = UI.ACCENT.darkened(0.2) if is_curr else (Color("#133647") if is_past else Color("#0d202b"))
		var border_col: Color = UI.GOLD if is_curr else (UI.GOOD.darkened(0.4) if is_past else Color("#173748"))

		var s_box := UI.panel(bg_col, 6 if is_phone else 8, 4 if is_phone else 6)
		s_box.add_theme_stylebox_override("panel", UI.box(bg_col, 6 if is_phone else 8, border_col, 4 if is_phone else 6, false))
		s_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var sh := UI.hbox(4 if is_phone else 6)
		sh.alignment = BoxContainer.ALIGNMENT_CENTER

		var icon_txt: String = "✓" if is_past else ("●" if is_curr else "%d" % (i + 1))
		var icon_col: Color = UI.GOOD if is_past else (UI.GOLD if is_curr else UI.MUTED)
		sh.add_child(UI.label(icon_txt, 11 if is_phone else 13, icon_col))

		var name_col: Color = Color.WHITE if is_curr else (UI.TEXT if is_past else UI.MUTED)
		sh.add_child(UI.label(step_names[i], 11 if is_phone else 13, name_col))

		s_box.add_child(sh)
		_steps.add_child(s_box)

		if i < 3:
			var arrow := UI.label("→", 11 if is_phone else 13, UI.GOOD if is_past else UI.MUTED)
			_steps.add_child(arrow)


func _render_coach_hint() -> void:
	var hint_str: String = str(_sess.get("hint", "")) if _sess.get("hint") != null else ""
	var hint_used: bool = bool(_sess.get("hintUsed", false))
	var step_str: String = str(_sess.get("step", ""))

	if hint_str != "":
		var hb := UI.panel(UI.INFO.darkened(0.65), 10, 10)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hv := UI.vbox(4)
		hv.add_child(UI.label("★ AI 教練提示：", 15, UI.INFO))
		hv.add_child(UI.label(hint_str, 14, UI.TEXT, true))
		hb.add_child(hv)
		_content.add_child(hb)
	elif _actor and not hint_used and step_str in ["discover", "plan", "objection"]:
		var hint_bar: BoxContainer = UI.vbox(4) if UI.is_phone_portrait() else UI.hbox(8)
		hint_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _waiting_hint:
			hint_bar.add_child(UI.label("教練思考中……", 14, UI.GOLD, true))
		else:
			var hint_btn := UI.button("求助教練（扣聲望 2）", func():
				_waiting_hint = true
				Net.act({"type": "hint"})
				refresh(_sess, "")
			, 14, UI.PANEL_2)
			hint_bar.add_child(hint_btn)
			var rem_quota: int = Net.get_ai_remaining()
			var hint_desc := UI.label("（每場面談限一次・AI 剩 %d 次）" % rem_quota, 12 if UI.is_phone_portrait() else 13, UI.MUTED, true)
			hint_bar.add_child(hint_desc)
		_content.add_child(hint_bar)


func _render_spectator_prediction() -> void:
	var preds: Dictionary = _sess.get("predictions", {}) if _sess.get("predictions") is Dictionary else {}
	var mine_pred: Variant = preds.get("mine")
	var p_card := UI.panel(UI.PANEL_2, 10, 8)
	var p_box: BoxContainer = UI.vbox(6) if UI.is_phone_portrait() else UI.hbox(8)
	p_card.add_child(p_box)

	if mine_pred != null and str(mine_pred) != "":
		p_box.add_child(UI.label("★ 旁觀競猜：你已預測該顧問評級為 ［%s］（共 %d 人參與預測）" % [str(mine_pred), int(preds.get("count", 1))], 14, UI.GOLD, true))
	else:
		p_box.add_child(UI.label("旁觀競猜（預測其評級，猜中聲望 +2）：", 13, UI.GOLD, true))
		var btn_row := UI.hbox(6)
		for g: String in ["S", "A", "B", "C"]:
			var grade_val: String = g
			var btn := UI.button(grade_val, func():
				Net.send({"t": "predict", "grade": grade_val})
			, 13, UI.PANEL)
			btn.custom_minimum_size = Vector2(36, 30)
			btn_row.add_child(btn)
		p_box.add_child(btn_row)
	_content.add_child(p_card)


func _section(title: String) -> VBoxContainer:
	var p := UI.panel(UI.PANEL, 12, 10 if UI.is_phone_portrait() else (12 if UI.is_portrait() else 14))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(6 if UI.is_phone_portrait() else 8)
	p.add_child(v)
	v.add_child(UI.label(title, 15 if UI.is_phone_portrait() else (16 if UI.is_portrait() else 17), UI.ACCENT_2, true))
	_content.add_child(p)
	return v


# ───────── ① 線索與訪談 ─────────

func _build_discover() -> void:
	var clues: Array = _sess.get("clues", [])
	var observed: int = 0
	for cl: Dictionary in clues:
		if cl.get("observed", false): observed += 1

	var c_dict: Dictionary = _sess.get("client", {})
	var scene_name: String = str(c_dict.get("scene", "")) if c_dict.get("scene") != null else ""
	if scene_name == "" or scene_name == "null":
		scene_name = str(c_dict.get("id", ""))
	var scene_path := ""
	if scene_name != "" and scene_name != "null":
		for ext in ["webp", "png", "jpg"]:
			var p := "res://assets/clients/%s.%s" % [scene_name, ext]
			if ResourceLoader.exists(p):
				scene_path = p
				break

	if scene_path != "":
		_build_scene_hotspots(scene_path, clues, observed)
	else:
		_build_clues_grid(clues, observed)

	var asked: Array = _sess.get("asked", [])
	# 伺服器的 covered 已包含自由提問命中的標準題，與「需 3 題才能進入配置」的判定一致
	var std: int = (_sess.get("covered", []) as Array).size() if _sess.get("covered") != null else asked.filter(func(a: Dictionary): return str(a.get("qid", "")) != "free").size()
	var qv := _section("◎ 需求訪談（%d/3）— 5 題選 3，順序與時機影響客戶信任" % std)
	var asked_ids: Array = asked.map(func(a: Dictionary): return str(a.get("qid", "")))
	var covered_ids: Array = _sess.get("covered", []) if _sess.get("covered") != null else []
	for q: Dictionary in Net.static_data.get("questions", []):
		var qid: String = str(q.get("id", ""))
		if qid in asked_ids or qid in covered_ids:
			continue
		var b := UI.option_button(str(q.get("text", "")), func(): Net.act({"type": "ask", "qid": qid}))
		b.disabled = not _actor or bool(_sess.get("ready", false))
		qv.add_child(b)
	for a: Dictionary in asked:
		var bubble := UI.panel(UI.PANEL_2, 10, 10)
		var bv := UI.vbox(4)
		var who: String = "AI 你（自由提問）" if str(a.get("qid", "")) == "free" else "你"
		bv.add_child(UI.label("%s：%s" % [who, a.get("question", "")], 14, UI.MUTED, true))
		bv.add_child(UI.label("%s：%s" % [_sess.get("client", {}).get("short", ""), a.get("answer", "")], 15, UI.TEXT, true))
		if a.get("key") != null and str(a.get("key", "")) != "":
			bv.add_child(UI.label("※ 掌握到：" + str(a.get("key", "")), 13, UI.GOLD, true))
		if a.get("note") != null and str(a.get("note", "")) != "":
			bv.add_child(UI.label("教練：" + str(a.get("note", "")), 13, UI.INFO, true))
		bubble.add_child(bv)
		qv.add_child(bubble)

	if int(_sess.get("freeLeft", 0)) > 0:
		var rem_quota: int = Net.get_ai_remaining()
		var fv := _section("AI 自由提問（自由提問剩 %d 次・AI 額度剩 %d 次）" % [int(_sess.get("freeLeft", 0)), rem_quota])
		if rem_quota <= 0:
			fv.add_child(UI.label("※ 今日 AI 額度已用完，送出後將改由規則版回答", 12, UI.GOLD, true))
		if _actor:
			if _waiting_ai:
				fv.add_child(UI.label("客戶思考中……", 15, UI.GOLD))
			else:
				fv.add_child(UI.text_input("例如：如果明天開始三個月不能工作，你最擔心什麼？", func(t: String):
					_waiting_ai = true
					Net.act({"type": "ask_free", "text": t})
					refresh(_sess, "")
				))
		else:
			fv.add_child(UI.label("（只有面談中的顧問可以提問）", 14, UI.MUTED))

	var go := UI.button("進入方案配置 →", func(): Net.act({"type": "to_plan"}), 18)
	go.disabled = not _actor or not bool(_sess.get("ready", false))
	_content.add_child(go)


func _build_clues_grid(clues: Array, observed: int) -> void:
	var cv := _section("◎ 觀察線索（%d/3）— 場景中有 3 個需求線索與 1 個干擾物" % observed)
	var grid := GridContainer.new()
	grid.columns = 1 if UI.is_phone_portrait() else 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var i: int = 0
	for cl: Dictionary in clues:
		var idx: int = i
		if cl.get("observed", false):
			var real: bool = bool(cl.get("real", false))
			var p := UI.panel(UI.GOOD.darkened(0.65) if real else Color("#2b3a42"), 10, 10)
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var v := UI.vbox(2)
			v.add_child(UI.label(("✓ " if real else "× ") + str(cl.get("title", "")), 15, UI.GOOD if real else UI.MUTED, true))
			v.add_child(UI.label(str(cl.get("detail", "")), 13, UI.TEXT, true))
			if real:
				v.add_child(UI.label("→ " + str(cl.get("fact", "")), 13, UI.GOLD, true))
			p.add_child(v)
			grid.add_child(p)
		else:
			var b := UI.option_button("？ " + str(cl.get("title", "")), func(): Net.act({"type": "observe", "index": idx}))
			b.disabled = not _actor or observed >= 3
			grid.add_child(b)
		i += 1
	cv.add_child(grid)


func _build_scene_hotspots(scene_path: String, clues: Array, observed: int) -> void:
	var cv := _section("◎ 生活場景探索（%d/3）— 點擊畫面熱點尋找需求線索（共 3 個需求與 1 個干擾）" % observed)
	var scene_box := Control.new()
	scene_box.clip_contents = true
	# 預設 STOP 會吃掉滾輪，讓外層 ScrollContainer 無法捲動
	scene_box.mouse_filter = Control.MOUSE_FILTER_PASS
	var aspect_h: float = 260.0 if UI.is_phone_portrait() else (320.0 if UI.is_portrait() else 360.0)
	scene_box.custom_minimum_size = Vector2(0, aspect_h)
	scene_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tex := TextureRect.new()
	tex.texture = load(scene_path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_box.add_child(tex)

	var i: int = 0
	for cl: Dictionary in clues:
		var idx: int = i
		var is_obs: bool = bool(cl.get("observed", false))
		var spot: Dictionary = cl.get("spot", {}) if cl.get("spot") is Dictionary else {}
		var sx: float = float(spot.get("x", 10.0 + i * 22.0)) / 100.0
		var sy: float = float(spot.get("y", 20.0 + (i % 2) * 30.0)) / 100.0
		var sw: float = float(spot.get("w", 18.0)) / 100.0
		var sh: float = float(spot.get("h", 20.0)) / 100.0

		var btn := Button.new()
		btn.anchor_left = sx
		btn.anchor_top = sy
		btn.anchor_right = sx + sw
		btn.anchor_bottom = sy + sh
		btn.offset_left = 0
		btn.offset_top = 0
		btn.offset_right = 0
		btn.offset_bottom = 0

		# 不可設 flat：flat 按鈕不繪製 stylebox，外框會整個消失
		btn.text = ""
		btn.mouse_filter = Control.MOUSE_FILTER_PASS

		if is_obs:
			var real: bool = bool(cl.get("real", false))
			var border_col: Color = UI.GOOD if real else UI.BAD
			var fill_col: Color = Color(border_col.r, border_col.g, border_col.b, 0.14)

			var obs_sb := UI.box(fill_col, 6, border_col, 2)
			btn.add_theme_stylebox_override("normal", obs_sb)
			btn.add_theme_stylebox_override("hover", obs_sb)
			btn.add_theme_stylebox_override("pressed", obs_sb)
			btn.add_theme_stylebox_override("disabled", obs_sb)
			btn.add_theme_stylebox_override("focus", obs_sb)
			btn.disabled = true

			# 標籤放在框的上緣小標，不要蓋住插圖中的物件
			var tag_p := PanelContainer.new()
			var tag_sb := UI.box(border_col.darkened(0.2), 4, Color(0, 0, 0, 0), 2)
			tag_p.add_theme_stylebox_override("panel", tag_sb)
			tag_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag_p.position = Vector2(2, 2)
			var tag_lbl := UI.label("✓ 線索" if real else "× 干擾", 10, Color.WHITE)
			tag_p.add_child(tag_lbl)
			btn.add_child(tag_p)
		else:
			# 未揭露：淡色金黃外框＋極淡填色 (alpha <= 0.12)，滑過時加亮
			var unobs_fill := Color(0.95, 0.75, 0.3, 0.08)
			var unobs_border := Color(0.95, 0.75, 0.3, 0.55)
			var unobs_normal := UI.box(unobs_fill, 6, unobs_border, 2)
			var unobs_hover := UI.box(Color(0.95, 0.75, 0.3, 0.18), 6, UI.GOLD, 2)
			var unobs_disabled := UI.box(Color(0.95, 0.75, 0.3, 0.05), 6, Color(0.95, 0.75, 0.3, 0.35), 2)

			btn.add_theme_stylebox_override("normal", unobs_normal)
			btn.add_theme_stylebox_override("hover", unobs_hover)
			btn.add_theme_stylebox_override("pressed", unobs_hover)
			btn.add_theme_stylebox_override("disabled", unobs_disabled)
			btn.add_theme_stylebox_override("focus", unobs_normal)

			# 框上緣小標
			var hint_p := PanelContainer.new()
			var hint_sb := UI.box(Color(0.08, 0.20, 0.28, 0.75), 4, Color(0.95, 0.75, 0.3, 0.35), 2)
			hint_p.add_theme_stylebox_override("panel", hint_sb)
			hint_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hint_p.position = Vector2(2, 2)
			var hint_lbl := UI.label("？", 10, UI.GOLD)
			hint_p.add_child(hint_lbl)
			btn.add_child(hint_p)

			btn.disabled = not _actor or observed >= 3
			btn.pressed.connect(func():
				Net.act({"type": "observe", "index": idx})
			)
		scene_box.add_child(btn)
		i += 1

	cv.add_child(scene_box)

	var obs_list := UI.vbox(4)
	var any_obs: bool = false
	for cl: Dictionary in clues:
		if cl.get("observed", false):
			any_obs = true
			var real: bool = bool(cl.get("real", false))
			var p := UI.panel(UI.GOOD.darkened(0.65) if real else Color("#2b3a42"), 8, 8)
			var bv := UI.vbox(2)
			bv.add_child(UI.label(("✓ " if real else "× ") + str(cl.get("title", "")), 14, UI.GOOD if real else UI.MUTED, true))
			bv.add_child(UI.label(str(cl.get("detail", "")), 13, UI.TEXT, true))
			if real and cl.get("fact") != null and str(cl.get("fact", "")) != "":
				bv.add_child(UI.label("→ " + str(cl.get("fact", "")), 13, UI.GOLD, true))
			p.add_child(bv)
			obs_list.add_child(p)
	if any_obs:
		cv.add_child(obs_list)
	elif _actor:
		cv.add_child(UI.label("提示：請在上方畫面上點選發光的黃框區域探索線索！", 13, UI.MUTED, true))


# ───────── ② 方案配置 ─────────

func _build_plan() -> void:
	var key: String = str(_sess.get("client", {}).get("id", ""))
	if key != _plan_key:
		_plan_key = key
		_alloc = {"cash": 4, "protect": 3, "growth": 3}
		_cards = []
	_plan_ui = {"rows": {}, "cards": {}}
	var av := _section("")
	_plan_ui["alloc_title"] = av.get_child(0)
	var hints := {"cash": "可支撐必要支出、避免低點賣出", "protect": "承接傷病、意外與收入中斷", "growth": "長期目標的資產累積"}
	var is_narrow: bool = UI.is_phone_portrait()
	for r: String in ["cash", "protect", "growth"]:
		var res: String = r
		var h := UI.hbox(6 if is_narrow else 8)
		var nm := UI.vbox(0)
		nm.custom_minimum_size = Vector2(110 if is_narrow else (160 if UI.is_portrait() else 220), 0)
		nm.add_child(UI.label(UI.RES_NAMES[r], 15 if is_narrow else 16, UI.TEXT, true))
		nm.add_child(UI.label(hints[r], 11 if is_narrow else 12, UI.MUTED, true))
		h.add_child(nm)
		var minus := UI.button("－", func(): _bump(res, -1), 16, UI.PANEL_2)
		h.add_child(minus)
		var value := UI.label("", 19 if is_narrow else 20, UI.GOLD)
		value.custom_minimum_size = Vector2(24 if is_narrow else 26, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(value)
		var plus := UI.button("＋", func(): _bump(res, 1), 16, UI.PANEL_2)
		h.add_child(plus)
		var coins := UI.label("", 15 if is_narrow else 16, UI.ACCENT_2)
		h.add_child(coins)
		av.add_child(h)
		_plan_ui["rows"][r] = {"minus": minus, "plus": plus, "value": value, "coins": coins}

	var cv := _section("")
	_plan_ui["cards_title"] = cv.get_child(0)
	var grid := GridContainer.new()
	# 手機直向 480 寬用 1 欄，平板直向 2 欄，橫向 3 欄
	grid.columns = 1 if UI.is_phone_portrait() else (2 if UI.is_portrait() else 3)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for card: Dictionary in Net.static_data.get("cards", []):
		var cid: String = str(card.get("id", ""))
		var b := UI.option_button("", func(): _toggle(cid))
		# 1 欄時高度 80 即充足，2 欄時需 110
		var min_h: int = 80 if UI.is_phone_portrait() else (110 if UI.is_portrait() else 96)
		b.custom_minimum_size = Vector2(0, min_h)
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = not _actor
		b.set_meta("card", card)
		grid.add_child(b)
		_plan_ui["cards"][cid] = b
	cv.add_child(grid)

	if not _actor:
		_content.add_child(UI.label("（等待顧問提交方案……）", 15, UI.MUTED))
	else:
		var submit := UI.button("提交方案 →", func(): Net.act({"type": "plan", "alloc": _alloc, "cards": _cards}), 18)
		_content.add_child(submit)
		_plan_ui["submit"] = submit
	_sync_plan()


## 只更新文字與按鈕狀態，不重建節點（維持原本避免連點漏點的做法）
func _sync_plan() -> void:
	var left: int = 10 - int(_alloc["cash"]) - int(_alloc["protect"]) - int(_alloc["growth"])
	(_plan_ui["alloc_title"] as Label).text = "◎ 分配 10 枚資源幣（剩 %d 枚）" % left
	var is_narrow: bool = UI.is_phone_portrait()
	for r: String in _plan_ui["rows"]:
		var row: Dictionary = _plan_ui["rows"][r]
		(row["value"] as Label).text = str(_alloc[r])
		if is_narrow:
			(row["coins"] as Label).text = "●%d" % int(_alloc[r])
		else:
			(row["coins"] as Label).text = "●".repeat(int(_alloc[r])) + "○".repeat(max(0, left))
		(row["minus"] as Button).disabled = not _actor or int(_alloc[r]) <= 0
		(row["plus"] as Button).disabled = not _actor or left <= 0
	(_plan_ui["cards_title"] as Label).text = "◎ 選擇 2–3 張保障卡（已選 %d）— 避免過度配置" % _cards.size()
	for cid: String in _plan_ui["cards"]:
		var b: Button = _plan_ui["cards"][cid]
		var card: Dictionary = b.get_meta("card")
		var on: bool = cid in _cards
		b.text = "%s%s\n［%s］%s" % ["✓ " if on else "", card.get("title", ""), card.get("tag", ""), card.get("detail", "")]
		var col: Color = UI.ACCENT.darkened(0.35) if on else UI.PANEL_2
		b.add_theme_stylebox_override("normal", UI.box(col, 10, Color("#2d5a6e"), 10))
		b.add_theme_stylebox_override("hover", UI.box(col.lightened(0.1), 10, UI.ACCENT_2, 10))
	if _plan_ui.has("submit"):
		(_plan_ui["submit"] as Button).disabled = left != 0 or _cards.size() < 2 or _cards.size() > 3


func _bump(r: String, d: int) -> void:
	_alloc[r] = clampi(int(_alloc[r]) + d, 0, 10)
	_sync_plan()


func _toggle(cid: String) -> void:
	if cid in _cards:
		_cards.erase(cid)
	elif _cards.size() < 3:
		_cards.append(cid)
	else:
		main.toast("最多選 3 張保障卡", UI.OK)
	_sync_plan()


# ───────── ③ 異議處理 ─────────

func _build_objection() -> void:
	var o: Dictionary = _sess.get("objection", {})
	var plan: Dictionary = _sess.get("plan", {})
	if not plan.is_empty():
		var pv := _section("你的方案：預備 %d／保障 %d／成長 %d　保障卡：%s" % [plan.get("alloc", {}).get("cash", 0), plan.get("alloc", {}).get("protect", 0), plan.get("alloc", {}).get("growth", 0), _card_names(plan.get("cards", []))])
		for n in plan.get("notes", []):
			pv.add_child(UI.label("・" + str(n), 14, UI.OK, true))
	var v := _section("◎ 客戶提出異議")
	v.add_child(UI.label(str(o.get("text", "")), 18 if UI.is_portrait() else 20, UI.GOLD, true))
	var i: int = 0
	for t in o.get("options", []):
		var idx: int = i
		var b := UI.option_button(str(t), func(): Net.act({"type": "objection", "index": idx}))
		b.disabled = not _actor or _waiting_ai
		v.add_child(b)
		i += 1
	var rem_quota: int = Net.get_ai_remaining()
	var fv := _section("AI 或用你自己的話回應（AI 額度剩 %d 次；恐嚇與保證重扣合規）" % rem_quota)
	if rem_quota <= 0:
		fv.add_child(UI.label("※ 今日 AI 額度已用完，送出後將改由規則版講師評分", 12, UI.GOLD, true))
	if _actor:
		if _waiting_ai:
			fv.add_child(UI.label("AI 講師評分中……", 15, UI.GOLD))
		else:
			fv.add_child(UI.text_input("輸入你的回應……", func(t: String):
				_waiting_ai = true
				Net.act({"type": "objection_free", "text": t})
				refresh(_sess, "")
			, 200))
	else:
		fv.add_child(UI.label("（等待顧問回應……）", 14, UI.MUTED))


func _card_names(ids: Array) -> String:
	var names: Array = []
	for card: Dictionary in Net.static_data.get("cards", []):
		if card.get("id") in ids:
			names.append(card.get("title", ""))
	return "、".join(names)


# ───────── ④ 結果與壓力預演 ─────────

func _build_result() -> void:
	var r: Dictionary = _sess.get("result", {})
	var result_key: String = "%s_%s_%s" % [str(_sess.get("client", {}).get("id", "")), str(r.get("score", "")), str(r.get("signed", ""))]
	if result_key != _last_result_sound_key:
		_last_result_sound_key = result_key
		var is_signed: bool = bool(r.get("signed", false))
		var is_s_grade: bool = str(r.get("grade", "")) == "S"
		if is_signed:
			Sound.play("win", self)
		else:
			Sound.play("fail", self)
		if is_signed or is_s_grade:
			UI.spawn_confetti(self)

	var is_phone: bool = UI.is_phone_portrait()
	var top := UI.hbox(10 if is_phone else 16)
	var grade_color: Color = {"S": UI.GOLD, "A": UI.GOOD, "B": UI.INFO}.get(str(r.get("grade", "C")), UI.BAD)
	var gp := UI.panel(grade_color.darkened(0.35), 36 if is_phone else 60, 8 if is_phone else 14)
	gp.custom_minimum_size = Vector2(70 if is_phone else 110, 70 if is_phone else 110)
	var gl := UI.label(str(r.get("grade", "?")), 38 if is_phone else 60, Color.WHITE)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gp.add_child(gl)
	top.add_child(gp)

	var tv := UI.vbox(3 if is_phone else 4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_stamp: Control = UI.stamp("✓ 簽約成功", UI.GOOD, 14 if is_phone else 16) if bool(r.get("signed", false)) else UI.stamp("未簽約・再考慮", UI.MUTED, 14 if is_phone else 16)
	var final_score: int = int(r.get("score", 0))
	var score_lbl := UI.label("評分 0 分", 18 if is_phone else 22, UI.TEXT)
	var stamp_row := UI.hbox(8)
	stamp_row.add_child(score_lbl)
	stamp_row.add_child(status_stamp)
	tv.add_child(stamp_row)

	# 數字滾動演出 (0.45s)
	var score_tw := create_tween()
	score_tw.tween_method(func(val: int):
		score_lbl.text = "評分 %d 分" % val
	, 0, final_score, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# 印章蓋下彈跳與微震動動畫 (0.24s)
	status_stamp.pivot_offset = Vector2(40, 14)
	status_stamp.scale = Vector2(1.8, 1.8)
	status_stamp.modulate.a = 0.0
	var stamp_tw := create_tween()
	stamp_tw.set_parallel(true)
	stamp_tw.tween_property(status_stamp, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stamp_tw.tween_property(status_stamp, "modulate:a", 1.0, 0.15)
	stamp_tw.chain().tween_callback(func():
		var punch_tw := tv.create_tween()
		punch_tw.tween_property(tv, "position:y", tv.position.y + 3.0, 0.04)
		punch_tw.tween_property(tv, "position:y", tv.position.y, 0.05)
	)
	tv.add_child(UI.label(str(r.get("summary", "")), 14 if is_phone else 15, UI.TEXT, true))
	if r.get("signed", false):
		tv.add_child(UI.label("業績 +%d" % int(r.get("commission", 0)), 15, UI.GOLD))
	for cap in r.get("caps", []):
		tv.add_child(UI.label("評級上限：" + str(cap), 13, UI.OK, true))
	top.add_child(tv)
	_content.add_child(top)

	# 顯示旁觀者競猜命中名單
	var hits: Array = r.get("predictionHits", []) if r.get("predictionHits") is Array else []
	if not hits.is_empty():
		var hit_box := UI.panel(UI.GOOD.darkened(0.65), 10, 8)
		hit_box.add_child(UI.label("★ 評級預測成功（聲望 +2）：%s" % "、".join(hits), 14, UI.GOOD, true))
		_content.add_child(hit_box)

	var rep: Dictionary = _sess.get("objectionReply", {}) if _sess.get("objectionReply") != null else {}
	if not rep.is_empty():
		var v := _section("異議回應回饋")
		v.add_child(UI.label("你說：" + str(rep.get("text", "")), 13, UI.MUTED, true))
		v.add_child(UI.label(str(rep.get("title", "")), 16 if is_phone else 17, UI.tone_color(str(rep.get("quality", "")))))
		v.add_child(UI.label(str(rep.get("body", "")), 14, UI.TEXT, true))

	# 壓力預演視覺化：對撞圖表演出
	var stress: Array = _sess.get("stress", []) if _sess.get("stress") != null else []
	if not stress.is_empty():
		var sv := _section("◎ 90 天壓力預演（事件承接測試）")
		for e: Dictionary in stress:
			var res: String = str(e.get("result", ""))
			var tone: String = "good" if res == "held" else ("ok" if res == "partial" else "bad")
			var tag_text: String = "● 穩健承接" if res == "held" else ("▲ 部分承受" if res == "partial" else "× 風險擊穿")

			var card := UI.panel(UI.PANEL_2, 10, 10)
			var cv := UI.vbox(5 if is_phone else 6)
			card.add_child(cv)

			var h := UI.hbox(6 if is_phone else 8)
			var title_lbl := UI.label("［%s］%s" % [e.get("tag", ""), e.get("title", "")], 14, UI.TEXT, true)
			title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(title_lbl)
			h.add_child(UI.label(tag_text, 13 if is_phone else 14, UI.tone_color(tone)))
			cv.add_child(h)

			# 視覺對撞比較：需求 vs 防禦
			var need_val: float = float(e.get("need", 10.0))
			var def_val: float = float(e.get("defense", 0.0))
			var ratio: float = clampf((def_val / maxf(1.0, need_val)) * 100.0, 0.0, 100.0)

			var meter := UI.hbox(8)
			meter.add_child(UI.label("防禦度", 13, UI.MUTED))
			var pbar: ProgressBar = UI.bar(ratio, UI.tone_color(tone), 140 if UI.is_portrait() else 200)
			pbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var def_s: String = ("%d" % int(def_val)) if is_equal_approx(def_val, roundf(def_val)) else ("%.1f" % def_val)
			var need_s: String = ("%d" % int(need_val)) if is_equal_approx(need_val, roundf(need_val)) else ("%.1f" % need_val)
			meter.add_child(UI.label("%s / %s" % [def_s, need_s], 13, UI.MUTED))
			cv.add_child(meter)

			cv.add_child(UI.label(str(e.get("text", "")), 13, UI.MUTED, true))
			sv.add_child(card)

	# 專屬結局與沒有規劃對比
	var ep: Dictionary = r.get("epilogue", {}) if r.get("epilogue") is Dictionary else {}
	if not ep.is_empty():
		var ep_v := _section("◎ 人生結局對比")
		var headline: String = str(ep.get("headline", "")).replace("<br>", "\n").replace("<br/>", "\n")
		if headline != "":
			ep_v.add_child(UI.label(headline, 16 if is_phone else 18, UI.GOLD, true))
		var ep_title: String = str(ep.get("title", ""))
		if ep_title != "":
			ep_v.add_child(UI.label("方案效果：%s" % ep_title, 14 if is_phone else 15, UI.ACCENT_2, true))

		var comp_box: BoxContainer = UI.vbox(8) if is_phone else UI.hbox(12)
		comp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# 沒有規劃
		var np_card := UI.panel(UI.BAD.darkened(0.7), 10, 10)
		np_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var np_v := UI.vbox(4)
		np_card.add_child(np_v)
		np_v.add_child(UI.label("× 如果沒有規劃", 15, UI.BAD))
		for item in (ep.get("noPlan", []) as Array):
			np_v.add_child(UI.label("・" + str(item), 13, UI.MUTED, true))
		comp_box.add_child(np_card)

		# 你的方案
		var pl_card := UI.panel(UI.GOOD.darkened(0.7), 10, 10)
		pl_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pl_v := UI.vbox(4)
		pl_card.add_child(pl_v)
		pl_v.add_child(UI.label("✓ 你的顧問方案", 15, UI.GOOD))
		for item in (ep.get("list", []) as Array):
			pl_v.add_child(UI.label("・" + str(item), 13, UI.TEXT, true))
		comp_box.add_child(pl_card)

		ep_v.add_child(comp_box)

	var plan: Dictionary = _sess.get("plan", {}) if _sess.get("plan") != null else {}
	if not plan.is_empty() and not (plan.get("notes", []) as Array).is_empty():
		var nv := _section("方案檢討")
		for n in plan.get("notes", []):
			nv.add_child(UI.label("・" + str(n), 14, UI.OK, true))

	if _actor:
		_content.add_child(UI.button("繼續 →", func(): Net.act({"type": "continue"}), 18))
