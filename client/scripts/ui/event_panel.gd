@tool
extends PanelContainer
## Event panel: life events, market alerts, compliance quiz, compliance dilemmas, client check-ins, audits, quarterly settlement, seminars.

const CARD_INFO: Dictionary = {
	"medical": {"title": "醫療費用分擔", "tag": "醫療支出"},
	"income": {"title": "工作能力防線", "tag": "收入中斷"},
	"accident": {"title": "意外支出防線", "tag": "意外風險"},
	"tools": {"title": "器材與營運防線", "tag": "營業中斷"},
	"legacy": {"title": "家庭責任防線", "tag": "家庭責任"},
	"care": {"title": "長期照顧準備", "tag": "長期照顧"},
}

var _v: VBoxContainer
var _scroll: ScrollContainer
var _last_ev_title: String = ""
var _last_manual_scroll_time: float = -999.0
var _scroll_tween: Tween = null
var _target_focus_node: Control = null
var _body_label: Label = null
var _cur_kind: String = ""
var _cur_player_id: String = ""
var _streamed_market: bool = false
var _streamed_seminar: bool = false
var _stream_text_market: String = ""
var _stream_text_seminar: String = ""


func _ready() -> void:
	var pad: int = 10 if UI.is_phone_portrait() else (14 if UI.is_portrait() else 22)
	add_theme_stylebox_override("panel", UI.box(UI.PANEL, 18, UI.ACCENT, pad))
	_v = UI.vbox(12)
	_scroll = UI.scroll(_v)
	add_child(_scroll)
	if not Engine.is_editor_hint():
		_scroll.gui_input.connect(_on_scroll_input)
		var v_bar := _scroll.get_v_scroll_bar()
		if v_bar != null:
			v_bar.gui_input.connect(_on_scroll_input)
		if not Net.stream_chunk.is_connected(_on_stream_chunk):
			Net.stream_chunk.connect(_on_stream_chunk)


func _on_stream_chunk(key: String, text: String, _done: bool) -> void:
	if key == "market":
		_streamed_market = true
		_stream_text_market = text
		if _cur_kind == "market" and _body_label != null and is_instance_valid(_body_label):
			_body_label.text = text
			_body_label.visible_ratio = 1.0
	elif key == "seminar:" + Net.player_id or (_cur_player_id != "" and key == "seminar:" + _cur_player_id):
		_streamed_seminar = true
		_stream_text_seminar = text
		if _cur_kind == "seminar" and _body_label != null and is_instance_valid(_body_label):
			_body_label.text = text
			_body_label.visible_ratio = 1.0


func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] or mb.pressed:
			_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
			if _scroll_tween != null and _scroll_tween.is_valid():
				_scroll_tween.kill()
				_scroll_tween = null
	elif event is InputEventPanGesture or event is InputEventScreenDrag:
		_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
		if _scroll_tween != null and _scroll_tween.is_valid():
			_scroll_tween.kill()
			_scroll_tween = null
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_last_manual_scroll_time = Time.get_ticks_msec() / 1000.0
			if _scroll_tween != null and _scroll_tween.is_valid():
				_scroll_tween.kill()
				_scroll_tween = null


func _auto_follow_deferred(target: Control) -> void:
	if target == null or Engine.is_editor_hint():
		return
	await get_tree().process_frame
	if not is_instance_valid(target) or not target.is_inside_tree() or _scroll == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_manual_scroll_time < 4.0:
		return
	_smooth_scroll_to(target, 0.3)


func _smooth_scroll_to(target: Control, duration: float = 0.3) -> void:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree() or _scroll == null:
		return
	var s_rect := _scroll.get_global_rect()
	var t_rect := target.get_global_rect()
	if s_rect.size.y <= 0:
		return
	var diff_top: float = t_rect.position.y - s_rect.position.y
	var diff_bottom: float = (t_rect.position.y + t_rect.size.y) - (s_rect.position.y + s_rect.size.y)
	var current_scroll: int = _scroll.scroll_vertical
	var target_scroll: int = current_scroll

	if t_rect.size.y >= s_rect.size.y:
		if absf(diff_top) > 4.0:
			target_scroll = int(current_scroll + diff_top - 12.0)
		else:
			return
	elif diff_top < 0:
		target_scroll = int(current_scroll + diff_top - 12.0)
	elif diff_bottom > 0:
		target_scroll = int(current_scroll + diff_bottom + 20.0)
	else:
		return

	target_scroll = maxi(0, target_scroll)
	var v_bar := _scroll.get_v_scroll_bar()
	if v_bar != null:
		var max_v: int = maxi(0, int(v_bar.max_value - v_bar.page))
		target_scroll = mini(target_scroll, max_v)

	if target_scroll == current_scroll:
		return

	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", target_scroll, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func refresh(ev: Dictionary, actor_name: String) -> void:
	UI.clear(_v)
	_target_focus_node = null
	var actor: bool = str(ev.get("playerId", "")) == Net.player_id
	var kind: String = str(ev.get("kind", "info"))
	var title: String = str(ev.get("title", ""))

	var dilemma = ev.get("dilemma")
	var review = ev.get("review")
	var claim = ev.get("claim")
	var checkup = ev.get("checkup")

	if title == "" and dilemma is Dictionary:
		title = str(dilemma.get("title", "情境合規抉擇"))
	elif title == "" and review is Dictionary:
		title = "客戶回訪：%s" % str(review.get("clientName", "已簽約客戶"))
	elif title == "" and claim is Dictionary:
		title = "理賠服務 ｜ %s" % str(claim.get("clientName", "已簽約客戶"))
	elif title == "" and (kind == "checkup" or checkup is Dictionary):
		var chk_name: String = str(checkup.get("clientName", "已簽約客戶")) if checkup is Dictionary else "已簽約客戶"
		title = "保單健檢 ｜ %s" % chk_name

	# Only play sound and fade in on event change; updates within same event redraw directly to prevent flickering
	var is_new_event: bool = title != _last_ev_title
	_cur_kind = kind
	_cur_player_id = str(ev.get("playerId", ""))
	if is_new_event:
		_streamed_market = false
		_streamed_seminar = false
		_stream_text_market = ""
		_stream_text_seminar = ""
	if title != "" and is_new_event:
		_last_ev_title = title
		UI.pop_in(self, 0.22)
		if claim is Dictionary and str(claim.get("result", "")) == "held":
			Sound.play("claim", self)
		else:
			Sound.play("ding", self)

	var icons: Dictionary = {
		"life": "✚ 人生事件" if claim == null else "✚ 理賠服務",
		"market": "↗ 市場快訊",
		"quiz": "✓ 合規訓練",
		"audit": "⚠ 合規稽核",
		"settlement": "★ 季度結算",
		"seminar": "◇ 顧問研討會",
		"dilemma": "✓ 合規情境抉擇",
		"review": "◎ 客戶回訪",
		"checkup": "♥ 保單健檢",
		"info": "※ 提示"
	}
	var colors: Dictionary = {
		"life": UI.GOLD if claim != null else UI.TILE_COLORS["life"],
		"market": UI.TILE_COLORS["market"],
		"quiz": UI.TILE_COLORS["training"],
		"audit": UI.TILE_COLORS["audit"],
		"settlement": UI.TILE_COLORS["start"],
		"seminar": UI.TILE_COLORS["seminar"],
		"dilemma": UI.GOLD,
		"review": UI.ACCENT_2,
		"checkup": UI.GOLD,
	}
	var head := UI.hbox(10)
	head.add_child(UI.label(icons.get(kind, "事件"), 16, colors.get(kind, UI.INFO)))
	head.add_child(UI.spacer())
	head.add_child(UI.label(("你的回合" if actor else "觀看中：%s 的回合" % actor_name), 14, UI.GOLD if actor else UI.MUTED))
	_v.add_child(head)

	if not actor:
		var obs := UI.panel(UI.PANEL_2, 8, 8)
		obs.add_theme_stylebox_override("panel", UI.box(UI.PANEL_2, 8, UI.GOLD, 8, false))
		var obsv := UI.vbox(2)
		obsv.add_child(UI.label("★ 觀摩學習中 ｜ %s 正在處理此事件" % actor_name, 13 if UI.is_phone_portrait() else 14, UI.GOLD, true))
		var tip_msg := "觀察其決策與作答，思考若換成自己會如何處理。"
		if kind == "dilemma":
			tip_msg = "觀察其面對利益與合規衝突時的價值抉擇。"
		elif kind == "review":
			tip_msg = "觀察其對既有客戶人生變化的保障健檢建議。"
		elif claim is Dictionary:
			tip_msg = "觀察其客戶面對人生風險時的保單理賠承接成效。"
		elif kind == "checkup":
			tip_msg = "觀察其定期關懷既有客戶之保單健檢與互動。"
		obsv.add_child(UI.label(tip_msg, 11 if UI.is_phone_portrait() else 12, UI.TEXT, true))
		obs.add_child(obsv)
		_v.add_child(obs)

	_v.add_child(UI.label(title, 22 if UI.is_portrait() else 26, UI.TEXT, true))
	var body_txt: String = str(ev.get("body", ""))
	if kind == "market":
		var display_market := body_txt if body_txt != "" else _stream_text_market
		if display_market != "":
			_body_label = UI.label(display_market, 15 if UI.is_portrait() else 17, UI.MUTED, true)
			if body_txt != "":
				UI.typewriter(_body_label, body_txt, _streamed_market)
			_v.add_child(_body_label)
	elif kind == "seminar":
		var display_seminar := body_txt if body_txt != "" else _stream_text_seminar
		if display_seminar != "":
			_body_label = UI.label(display_seminar, 15 if UI.is_portrait() else 17, UI.MUTED, true)
			if body_txt != "":
				UI.typewriter(_body_label, body_txt, _streamed_seminar)
			_v.add_child(_body_label)
	else:
		if body_txt != "" and not (dilemma is Dictionary and str(dilemma.get("prompt", "")) != ""):
			_body_label = UI.label(body_txt, 15 if UI.is_portrait() else 17, UI.MUTED, true)
			_v.add_child(_body_label)

	# ───────── 1. Compliance dilemma (dilemma) ─────────
	if dilemma is Dictionary:
		_build_dilemma_ui(dilemma, actor)

	# ───────── 2. Client lifecycle check-in (review) ─────────
	elif review is Dictionary:
		_build_review_ui(review, actor)

	# ───────── 3. Claim service moment (claim) ─────────
	elif claim is Dictionary:
		_build_claim_ui(claim, ev, actor)

	# ───────── 4. Policy checkup (checkup) ─────────
	elif kind == "checkup" or checkup is Dictionary:
		_build_checkup_ui(checkup if checkup is Dictionary else {}, ev, actor)

	# ───────── 3. Compliance quiz (quiz) ─────────
	var quiz = ev.get("quiz")
	if quiz is Dictionary:
		var picked = quiz.get("picked")
		var i: int = 0
		var options: Array = quiz.get("options", [])
		for opt in options:
			var idx: int = i
			var col: Color = UI.PANEL_2
			if picked != null:
				if idx == int(quiz.get("answer", -1)):
					col = UI.GOOD.darkened(0.5)
				elif idx == int(picked):
					col = UI.BAD.darkened(0.5)
			var b := UI.option_button("%s. %s" % [char(65 + idx), opt], func(): Net.act({"type": "answer_quiz", "index": idx}), col)
			b.disabled = not actor or picked != null
			_v.add_child(b)
			if picked != null and idx == int(picked):
				_target_focus_node = b
			i += 1

	# ───────── 4. Standard event feedback lines ─────────
	var lines: Array = ev.get("lines", [])
	for line: Dictionary in lines:
		var p := UI.panel(UI.PANEL, 10, 10)
		p.add_child(UI.label(str(line.get("text", "")), 15 if UI.is_portrait() else 16, UI.tone_color(str(line.get("tone", "info"))), true))
		_v.add_child(p)
		_target_focus_node = p

	# ───────── 5. Continue button and spectating prompt ─────────
	var can_continue: bool = true
	if quiz is Dictionary:
		can_continue = quiz.get("picked") != null
	elif dilemma is Dictionary:
		can_continue = dilemma.get("picked") != null
	elif review is Dictionary:
		can_continue = review.get("picked") != null

	if actor:
		var b := UI.button("繼續 →", func(): Net.act({"type": "continue"}), 18)
		b.disabled = not can_continue
		_v.add_child(b)
	else:
		var wait_text: String = "等待 %s 繼續……" % actor_name
		if not can_continue:
			if kind == "dilemma":
				wait_text = "等待 %s 做出情境抉擇……" % actor_name
			elif kind == "review":
				wait_text = "等待 %s 提出回訪建議……" % actor_name
			elif quiz is Dictionary:
				wait_text = "等待 %s 作答……" % actor_name
		_v.add_child(UI.label(wait_text, 14, UI.MUTED))

	if is_new_event:
		UI.fade_in(_v, 0.2)
	UI.pass_wheel(_v)

	if not actor and _target_focus_node != null:
		_auto_follow_deferred(_target_focus_node)


func _build_dilemma_ui(dilemma: Dictionary, actor: bool) -> void:
	var prompt_txt: String = str(dilemma.get("prompt", ""))
	if prompt_txt != "":
		var prompt_box := UI.panel(UI.PANEL_2, 10, 10)
		prompt_box.add_child(UI.label(prompt_txt, 15 if UI.is_portrait() else 16, UI.TEXT, true))
		_v.add_child(prompt_box)

	var picked = dilemma.get("picked")
	var choices: Array = dilemma.get("choices", [])
	var choice_idx: int = 0
	for c: Dictionary in choices:
		var cid: String = str(c.get("id", ""))
		var ctext: String = str(c.get("text", ""))
		var is_picked: bool = picked != null and str(picked) == cid
		var btn_col: Color = UI.ACCENT.darkened(0.3) if is_picked else UI.PANEL_2
		var letter: String = char(65 + choice_idx)
		var btn := UI.option_button("%s. %s" % [letter, ctext], func():
			Net.act({"type": "choose_dilemma", "choice": cid})
		, btn_col)
		btn.disabled = not actor or picked != null
		_v.add_child(btn)
		if is_picked:
			_target_focus_node = btn
		choice_idx += 1

	var outcome = dilemma.get("outcome")
	if outcome is Dictionary:
		var op := UI.panel(UI.PANEL_2, 10, 10)
		var ov := UI.vbox(4)
		var o_title: String = str(outcome.get("title", "抉擇結果"))
		var o_tone: String = str(outcome.get("tone", "info"))
		ov.add_child(UI.label(o_title, 16, UI.tone_color(o_tone), true))
		var o_body: String = str(outcome.get("body", ""))
		if o_body != "":
			ov.add_child(UI.label(o_body, 14, UI.TEXT, true))
		var o_effects: String = str(outcome.get("effects", ""))
		if o_effects != "":
			ov.add_child(UI.label("影響：%s" % o_effects, 13, UI.GOLD, true))
		op.add_child(ov)
		_v.add_child(op)
		_target_focus_node = op


func _build_review_ui(review: Dictionary, actor: bool) -> void:
	var cname: String = str(review.get("clientName", "客戶"))
	var change: Dictionary = review.get("change", {})
	var change_title: String = str(change.get("title", "生活新變化"))
	var change_body: String = str(change.get("body", ""))

	# Client life changes description card
	var chg_panel := UI.panel(UI.PANEL_2, 10, 10)
	var chg_v := UI.vbox(4)
	chg_v.add_child(UI.label("【%s 的人生轉折】%s" % [cname, change_title], 16, UI.GOLD, true))
	if change_body != "":
		chg_v.add_child(UI.label(change_body, 14, UI.TEXT, true))
	chg_panel.add_child(chg_v)
	_v.add_child(chg_panel)

	# Current allocation status
	var cur_data: Dictionary = review.get("current", {})
	var cur_alloc: Dictionary = cur_data.get("alloc", {})
	var cur_cards: Array = cur_data.get("cards", [])
	var cur_panel := UI.panel(UI.PANEL, 8, 8)
	var cur_v := UI.vbox(3)
	cur_v.add_child(UI.label("目前配置：預備金 %d ｜ 保障 %d ｜ 成長 %d" % [int(cur_alloc.get("cash", 0)), int(cur_alloc.get("protect", 0)), int(cur_alloc.get("growth", 0))], 13, UI.ACCENT_2))
	var card_names: Array = []
	for cid in cur_cards:
		var c_str: String = str(cid)
		var c_name: String = CARD_INFO.get(c_str, {}).get("title", c_str)
		card_names.append(c_name)
	var cards_str: String = "、".join(card_names) if not card_names.is_empty() else "無"
	cur_v.add_child(UI.label("既有防線：%s" % cards_str, 13, UI.MUTED))
	cur_panel.add_child(cur_v)
	_v.add_child(cur_panel)

	_v.add_child(UI.label("請評估客戶新需求，選擇後續規劃建議：", 14, UI.GOLD))

	var picked = review.get("picked")

	# 6 coverage card button grid
	var grid := GridContainer.new()
	grid.columns = 1 if UI.is_phone_portrait() else 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)

	for cid: String in ["medical", "income", "accident", "tools", "legacy", "care"]:
		var info: Dictionary = CARD_INFO.get(cid, {})
		var c_title: String = info.get("title", cid)
		var c_tag: String = info.get("tag", "")
		var already_has: bool = cur_cards.has(cid)
		var is_picked: bool = picked != null and str(picked) == cid

		var btn_text: String = ""
		var btn_col: Color = UI.PANEL_2
		if already_has:
			btn_text = "%s：%s（已有）" % [c_tag, c_title]
			btn_col = UI.PANEL.darkened(0.2)
		else:
			btn_text = "+ 建議加入：%s（%s）" % [c_title, c_tag]
			if is_picked:
				btn_col = UI.ACCENT.darkened(0.2)

		var btn := UI.option_button(btn_text, func():
			Net.act({"type": "review", "card": cid})
		, btn_col)
		btn.custom_minimum_size = Vector2(0, 42)
		btn.disabled = not actor or picked != null or already_has
		grid.add_child(btn)
		if is_picked:
			_target_focus_node = btn

	_v.add_child(grid)

	# 2 additional decision options: current plan sufficient, hold off contacting
	var none_picked: bool = picked != null and str(picked) == "none"
	var none_btn := UI.option_button("✓ 聯絡客戶，確認現有規劃已充足（維持現狀）", func():
		Net.act({"type": "review", "card": "none"})
	, UI.GOOD.darkened(0.5) if none_picked else UI.PANEL_2)
	none_btn.disabled = not actor or picked != null
	_v.add_child(none_btn)
	if none_picked:
		_target_focus_node = none_btn

	var skip_picked: bool = picked != null and str(picked) == "skip"
	var skip_btn := UI.option_button("× 先不聯絡客戶（暫緩拜訪）", func():
		Net.act({"type": "review", "card": "skip"})
	, UI.BAD.darkened(0.5) if skip_picked else UI.PANEL)
	skip_btn.disabled = not actor or picked != null
	_v.add_child(skip_btn)
	if skip_picked:
		_target_focus_node = skip_btn

	var outcome = review.get("outcome")
	if outcome is Dictionary:
		var op := UI.panel(UI.PANEL_2, 10, 10)
		var ov := UI.vbox(4)
		var o_title: String = str(outcome.get("title", "回訪結果"))
		var o_tone: String = str(outcome.get("tone", "info"))
		ov.add_child(UI.label(o_title, 16, UI.tone_color(o_tone), true))
		var o_body: String = str(outcome.get("body", ""))
		if o_body != "":
			ov.add_child(UI.label(o_body, 14, UI.TEXT, true))
		op.add_child(ov)
		_v.add_child(op)
		_target_focus_node = op

	UI.pass_wheel(_v)


func _format_wan(ntd: float) -> String:
	var wan := ntd / 10000.0
	if wan < 10.0:
		return "%.1f萬" % wan
	return "%d萬" % int(round(wan))


func _get_portrait_control(client_id: String, client_name: String, size: int = 64) -> Control:
	var tex: Texture2D = Portraits.get_texture(client_id)
	if tex != null:
		return UI.avatar(tex, client_name, size)
	return UI.portrait({"id": client_id, "name": client_name}, size)


func _build_seal(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r, col.g, col.b, 0.15)
	sb.border_color = col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var l := UI.label(text, 13, col, true)
	p.add_child(l)
	return p


func _build_claim_ui(claim: Dictionary, ev: Dictionary, _actor: bool) -> void:
	var cid: String = str(claim.get("clientId", ""))
	var cname: String = str(claim.get("clientName", "客戶"))
	var ev_title: String = str(claim.get("event", ev.get("title", "人生事件")))
	var tag: String = str(claim.get("tag", ""))
	var result: String = str(claim.get("result", "held"))
	var loss: float = float(claim.get("loss", 0.0))
	var covered: float = float(claim.get("covered", 0.0))
	var out_of_pocket: float = float(claim.get("outOfPocket", 0.0))

	var card := UI.panel(UI.PANEL_2, 12, 12)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := UI.vbox(10)
	card.add_child(cv)

	# Header: Portrait (64px) + Info + Seal
	var top_h := UI.hbox(12)
	top_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var port := _get_portrait_control(cid, cname, 64)
	top_h.add_child(port)

	var info_v := UI.vbox(3)
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head_title := "理賠服務 ｜ %s" % cname
	info_v.add_child(UI.label(head_title, 17, UI.GOLD, true))
	var ev_desc := "遭遇事件：%s" % ev_title + ("（%s）" % tag if tag != "" else "")
	info_v.add_child(UI.label(ev_desc, 13, UI.TEXT, true))
	if loss > 0.0:
		info_v.add_child(UI.label("財務衝擊估算：%s" % _format_wan(loss), 12, UI.MUTED, true))
	top_h.add_child(info_v)

	# Seal: held = green seal 「理賠完成」, broken = red 「保障缺口」, partial = ok 「部分理賠」
	var seal_text: String = "理賠完成" if result == "held" else ("保障缺口" if result == "broken" else "部分理賠")
	var seal_col: Color = UI.GOOD if result == "held" else (UI.BAD if result == "broken" else UI.OK)
	var seal_ctrl := _build_seal(seal_text, seal_col)
	seal_ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_h.add_child(seal_ctrl)
	cv.add_child(top_h)

	# Three-segment comparison bar: covered vs out-of-pocket (vs remaining/reserve)
	var total_span: float = maxf(1.0, loss)
	if covered + out_of_pocket > total_span:
		total_span = covered + out_of_pocket
	var cov_ratio: float = clampf(covered / total_span, 0.0, 1.0)
	var oop_ratio: float = clampf(out_of_pocket / total_span, 0.0, 1.0)
	var rem_ratio: float = clampf(1.0 - cov_ratio - oop_ratio, 0.0, 1.0)

	var bar_v := UI.vbox(4)
	var bar_panel := PanelContainer.new()
	bar_panel.custom_minimum_size = Vector2(0, 18)
	bar_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg_sb := StyleBoxFlat.new()
	bar_bg_sb.bg_color = Color(0, 0, 0, 0.3)
	bar_bg_sb.set_corner_radius_all(6)
	bar_panel.add_theme_stylebox_override("panel", bar_bg_sb)

	var bar_h := HBoxContainer.new()
	bar_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_h.add_theme_constant_override("separation", 2)
	bar_panel.add_child(bar_h)

	if cov_ratio > 0.001:
		var cov_seg := Panel.new()
		cov_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cov_seg.size_flags_stretch_ratio = cov_ratio
		var cov_sb := StyleBoxFlat.new()
		cov_sb.bg_color = UI.GOOD
		cov_sb.set_corner_radius_all(4)
		cov_seg.add_theme_stylebox_override("panel", cov_sb)
		bar_h.add_child(cov_seg)

	if oop_ratio > 0.001:
		var oop_seg := Panel.new()
		oop_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oop_seg.size_flags_stretch_ratio = oop_ratio
		var oop_sb := StyleBoxFlat.new()
		oop_sb.bg_color = UI.BAD
		oop_sb.set_corner_radius_all(4)
		oop_seg.add_theme_stylebox_override("panel", oop_sb)
		bar_h.add_child(oop_seg)

	if rem_ratio > 0.01:
		var rem_seg := Panel.new()
		rem_seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rem_seg.size_flags_stretch_ratio = rem_ratio
		var rem_sb := StyleBoxFlat.new()
		rem_sb.bg_color = Color(UI.MUTED.r, UI.MUTED.g, UI.MUTED.b, 0.25)
		rem_sb.set_corner_radius_all(4)
		rem_seg.add_theme_stylebox_override("panel", rem_sb)
		bar_h.add_child(rem_seg)

	bar_v.add_child(bar_panel)

	var num_h := UI.hbox(8)
	num_h.add_child(UI.label("理賠撥付：%s" % _format_wan(covered), 12, UI.GOOD))
	num_h.add_child(UI.spacer())
	num_h.add_child(UI.label("自付負擔：%s" % _format_wan(out_of_pocket), 12, UI.BAD if out_of_pocket > 0 else UI.MUTED))
	bar_v.add_child(num_h)
	cv.add_child(bar_v)

	_v.add_child(card)
	_target_focus_node = card


func _build_checkup_ui(checkup: Dictionary, _ev: Dictionary, _actor: bool) -> void:
	var cid: String = str(checkup.get("clientId", ""))
	var cname: String = str(checkup.get("clientName", "客戶"))
	var referral: bool = bool(checkup.get("referral", false))

	var card := UI.panel(UI.PANEL_2, 14, 12)
	card.add_theme_stylebox_override("panel", UI.box(UI.PANEL_2, 14, UI.GOLD, 10, false))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cv := UI.vbox(8)
	card.add_child(cv)

	var top_h := UI.hbox(12)
	top_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var port := _get_portrait_control(cid, cname, 64)
	top_h.add_child(port)

	var info_v := UI.vbox(3)
	info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_v.add_child(UI.label("保單健檢 ｜ %s" % cname, 18, UI.GOLD, true))
	info_v.add_child(UI.label("停留在自己的版圖格，持續關懷既有客戶，維護長期信任", 12, UI.MUTED, true))
	top_h.add_child(info_v)

	if referral:
		var ref_badge := _build_seal("♥ 觸發轉介紹", UI.GOOD)
		ref_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top_h.add_child(ref_badge)

	cv.add_child(top_h)
	_v.add_child(card)
	_target_focus_node = card


