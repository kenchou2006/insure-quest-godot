extends "res://scripts/quest/pages/page_base.gd"
## ProposalBuilderView (page 5) — 保障與預算配置.
## The client's monthly budget is the server's 10 allocation units (緊急預備 / 風險保障 / 目標成長),
## plus 2–3 coverage cards. Every need found in the meeting gets someone to carry it (a card or a
## budget line, chosen by the advisor); the coverage ring stays broken while a need is uncovered and
## closes, with a soft confirm, when needs and budget balance. Over budget: the total turns red,
## a short warning plays once, the budget card shakes once, and 提交 says why it is closed.
## Briefcase tools act here (保障缺口表 / 風險屬性問卷 reveal the server's hints when used).
## 提交顧問方案 → critical decision → 0.55 s → the plan goes to the server for scoring.

const RES := [["cash", "緊急預備", "應對突發支出與收入中斷的現金"], ["protect", "風險保障", "醫療、意外、收入中斷等保障的保費"], ["growth", "目標成長", "為人生目標累積的長期資金"]]
const TOTAL := 10

var _alloc := {"cash": 0, "protect": 0, "growth": 0}
var _cards: Array = []
var _cover: Dictionary = {}
var _needs: Array = []
var _res_rows: Dictionary = {}
var _card_btns: Dictionary = {}
var _need_rows: VBoxContainer
var _total_label: Label
var _budget_card: PanelContainer
var _ring: QuestUI.Ring
var _ring_note: Label
var _eval: VBoxContainer
var _submit: Button
var _reason: Label
var _tools_box: VBoxContainer
var _status: Control
var _was_over := false
var _was_closed := false
var _sending := false


func guide_lines() -> Array:
	return ["這是方案配置。客戶每月能運用的預算是 10 個單位，要剛好用完，不能超出。", "替每一項需求選一個承接方式；需求都有人承接、預算剛好時，右邊的圓環才會閉合。"]


func help_lines() -> Array:
	return ["先守住緊急預備，再用保障卡承接最關鍵的風險；成長部位留給人生目標。", "超出預算或還有需求沒承接時，提交按鈕旁會寫出原因。"]


func idle_lines() -> Array:
	return ["從最讓客戶擔心的需求開始，替它選一張保障卡或一筆預備金。"]


func key_rects() -> Array:
	return [rect_of(_submit)]


func highlight_rects() -> Array:
	return [rect_of(_budget_card), rect_of(_ring)]


func build() -> void:
	add_background()
	var v := add_frame()
	_restore()
	var sess := GameState.my_session()
	# Left: needs and briefcase
	var left := QuestUI.vbox(12)
	var needs_card := QuestUI.card(null, 0.92)
	var nv := QuestUI.vbox(8)
	needs_card.add_child(nv)
	nv.add_child(QuestUI.header("target", "客戶重點需求"))
	nv.add_child(QuestUI.label("替每一項需求選擇承接方式（方案裡的保障卡或預算項目）。", 13, QuestUI.MUTED, true))
	_need_rows = QuestUI.vbox(8)
	nv.add_child(_need_rows)
	left.add_child(needs_card)
	var tool_card := QuestUI.card(null, 0.92)
	_tools_box = QuestUI.vbox(8)
	tool_card.add_child(_tools_box)
	left.add_child(tool_card)
	# Centre: budget, allocation, cards
	var center := QuestUI.vbox(12)
	center.add_child(task_line("在每月預算內分配 10 個單位、選 2–3 張保障卡，替每項需求選擇承接方式後提交方案。"))
	_budget_card = QuestUI.card(null, 0.95, Color(QuestUI.GOLD, 0.45))
	var bh := QuestUI.hbox(14)
	_budget_card.add_child(bh)
	bh.add_child(QuestUI.icon("wallet", 40.0, QuestUI.GOLD))
	var bv := QuestUI.vbox(2)
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_child(QuestUI.label("每月可運用預算", 14, QuestUI.MUTED))
	_total_label = QuestUI.title("0 / 10 單位", 30 if not phone() else 22, QuestUI.TEXT)
	bv.add_child(_total_label)
	var b := GameState.client_budget()
	var budget_note := "收入：%s" % str(b.income) if str(b.income) != "" else ""
	if str(b.amount) != "":
		budget_note += ("　" if budget_note != "" else "") + "目標金額 %s" % str(b.amount)
	bv.add_child(QuestUI.label(budget_note, 12, QuestUI.MUTED, true))
	bh.add_child(bv)
	center.add_child(_budget_card)
	var alloc_card := QuestUI.card(null, 0.92)
	var av := QuestUI.vbox(10)
	alloc_card.add_child(av)
	av.add_child(QuestUI.header("coins", "預算分配"))
	for spec in RES:
		av.add_child(_res_row(spec[0], spec[1], spec[2]))
	center.add_child(alloc_card)
	var cards_card := QuestUI.card(null, 0.92)
	var cv := QuestUI.vbox(10)
	cards_card.add_child(cv)
	cv.add_child(QuestUI.header("shield", "可選擇的保障卡", "選 2–3 張", QuestUI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3 if not narrow() else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for cd in Net.static_data.get("cards", []):
		var btn := _card_button(cd as Dictionary)
		grid.add_child(btn)
	cv.add_child(grid)
	center.add_child(cards_card)
	# Right: status, evaluation ring; 提交 pinned
	_status = ClientStatusPanel.new(true)
	var eval_card := QuestUI.card(null, 0.92)
	var ev := QuestUI.vbox(10)
	eval_card.add_child(ev)
	ev.add_child(QuestUI.header("chart", "方案評估"))
	var rh := QuestUI.hbox(12)
	_ring = QuestUI.Ring.new()
	_ring.custom_minimum_size = Vector2(108, 108) if not compact() else Vector2(80, 80)
	rh.add_child(_ring)
	_ring_note = QuestUI.label("", 14, QuestUI.TEXT, true)
	_ring_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(_ring_note)
	ev.add_child(rh)
	_eval = QuestUI.vbox(6)
	ev.add_child(_eval)
	_submit = QuestUI.button("提交顧問方案", _on_submit, "primary", "doc")
	_submit.name = "SubmitPlan"
	_reason = QuestUI.label("", 13, QuestUI.GOLD, true)
	_submit.set("reason_label", _reason)
	var right := side([_status, eval_card], [secretary_button(), review_button("回顧需求線索", ["需求訪談", "線索分類"]), _submit, _reason])
	v.add_child(columns([QuestUI.scroll(left) if not narrow() else left, QuestUI.scroll(center) if not narrow() else center, right], [1.0, 1.6, 1.0]))
	_load_needs(sess)
	_build_tools(sess)
	_sync()


func refresh(_s: Dictionary) -> void:
	if is_instance_valid(_status):
		_status.call("refresh")


func server_error(_msg: String) -> void:
	_sending = false
	_submit.call("set_loading", false)
	_sync()


func _restore() -> void:
	var d: Dictionary = GameState.record.get("plan_draft", {})
	if not d.is_empty():
		_alloc = (d.get("alloc", _alloc) as Dictionary).duplicate()
		_cards = (d.get("cards", []) as Array).duplicate()
		_cover = (d.get("cover", {}) as Dictionary).duplicate()


func _save_draft() -> void:
	GameState.set_value("plan_draft", {"alloc": _alloc.duplicate(), "cards": _cards.duplicate(), "cover": _cover.duplicate()})


# --- Allocation -------------------------------------------------------------------------------

func _res_row(key: String, title_text: String, sub: String) -> Control:
	var h := QuestUI.hbox(10)
	var tv := QuestUI.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(QuestUI.label(title_text, 16, QuestUI.TEXT, false, true))
	# Compact screens: the line's meaning is in its tooltip, the row keeps one line
	if not compact():
		tv.add_child(QuestUI.label(sub, 12, QuestUI.MUTED, true))
	tv.tooltip_text = sub
	h.add_child(tv)
	var step := 40.0 if compact() else 44.0
	var minus: Button = QuestUI.button("", func(): _bump(key, -1), "quiet", "minus")
	minus.name = "Minus_" + key
	minus.custom_minimum_size = Vector2(step, step)
	minus.tooltip_text = "減少 1 單位"
	h.add_child(minus)
	var val := QuestUI.title("0", 22, QuestUI.TEXT)
	val.custom_minimum_size.x = 34
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_child(val)
	var plus: Button = QuestUI.button("", func(): _bump(key, 1), "quiet", "plus")
	plus.name = "Plus_" + key
	plus.custom_minimum_size = Vector2(step, step)
	plus.tooltip_text = "增加 1 單位"
	h.add_child(plus)
	var bar := QuestUI.Bar.new()
	bar.custom_minimum_size = Vector2(90 if not phone() else 50, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = QuestUI.GOLD if key == "cash" else (QuestUI.GREEN if key == "protect" else QuestUI.MUTED)
	bar.visible = not compact()
	h.add_child(bar)
	_res_rows[key] = [val, bar, minus, plus]
	return h


func _bump(key: String, d: int) -> void:
	if _sending:
		return
	var n := int(_alloc[key]) + d
	if n < 0 or n > TOTAL:
		return
	_alloc[key] = n
	# Budget lines that drop to 0 can no longer carry a need
	for nk in _cover.keys():
		if str(_cover[nk]) == "res:" + key and n == 0:
			_cover.erase(nk)
	_save_draft()
	_sync()


## 保障卡按鈕：容器結構，由 PanelContainer 自帶最小尺寸與外框樣式，內建覆蓋按鈕處理切換
class CoverageCardButton extends PanelContainer:
	signal toggled(on: bool)
	signal pressed

	var id := ""
	var btn: Button
	var is_compact := false
	var title_lbl: Label = null
	var detail_lbl: Label = null
	var _hover := false
	var _focused := false

	var button_pressed: bool:
		set(val):
			if btn and is_instance_valid(btn):
				btn.button_pressed = val
			_style()
		get:
			if btn and is_instance_valid(btn):
				return btn.button_pressed
			return false

	var disabled: bool:
		set(val):
			disabled = val
			if btn and is_instance_valid(btn):
				btn.disabled = val
			modulate.a = 0.45 if val else 1.0
			_style()
		get:
			if btn and is_instance_valid(btn):
				return btn.disabled
			return false

	func _init(card_id: String, cd: Dictionary, compact_mode: bool) -> void:
		id = card_id
		is_compact = compact_mode
		name = "Card_" + id + "Card"
		var base_h: float = 84.0 if is_compact else 104.0
		custom_minimum_size = Vector2(0.0, base_h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

		var v := QuestUI.vbox(4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)

		var tag_l := QuestUI.label(str(cd.get("tag", "")), 12, QuestUI.GOLD)
		tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag_l)

		title_lbl = QuestUI.label(str(cd.get("title", "")), 15, QuestUI.TEXT, true, true)
		title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(title_lbl)

		detail_lbl = QuestUI.label(str(cd.get("detail", "")), 11, QuestUI.MUTED, true)
		detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(detail_lbl)

		btn = Button.new()
		btn.name = "Card_" + id
		btn.toggle_mode = true
		btn.flat = true
		btn.text = ""
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.tooltip_text = str(cd.get("detail", ""))
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		add_child(btn)

		btn.toggled.connect(func(on: bool):
			_style()
			toggled.emit(on)
		)
		btn.pressed.connect(func():
			pressed.emit()
		)
		btn.mouse_entered.connect(func():
			_hover = true
			_style()
			AudioManager.play("ui_hover")
		)
		btn.mouse_exited.connect(func():
			_hover = false
			_style()
		)
		btn.focus_entered.connect(func():
			_focused = true
			_style()
		)
		btn.focus_exited.connect(func():
			_focused = false
			_style()
		)
		_style()

	func set_pressed_no_signal(on: bool) -> void:
		if btn and is_instance_valid(btn):
			btn.set_pressed_no_signal(on)
		_style()

	func _style() -> void:
		var is_on := btn.button_pressed if (btn and is_instance_valid(btn)) else false
		var is_dis := btn.disabled if (btn and is_instance_valid(btn)) else false
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(2 if is_on else 1)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 8
		s.content_margin_bottom = 6
		if is_dis:
			s.bg_color = Color(QuestUI.CARD, 0.4)
			s.border_color = Color(1, 1, 1, 0.1)
		elif is_on:
			s.bg_color = Color(QuestUI.GREEN, 0.22)
			s.border_color = QuestUI.GREEN
		else:
			s.bg_color = Color(QuestUI.CARD.lightened(0.04), 0.95)
			s.border_color = QuestUI.GOLD if _hover else Color(1, 1, 1, 0.14)
		if _focused and not is_on and not is_dis:
			s.border_color = Color(QuestUI.GOLD, 0.8)
			s.set_border_width_all(2)
		add_theme_stylebox_override("panel", s)


func _card_button(cd: Dictionary) -> Control:
	var id := str(cd.get("id", ""))
	var card := CoverageCardButton.new(id, cd, compact())
	card.button_pressed = _cards.has(id)
	card.toggled.connect(func(on: bool): _toggle_card(id, on, card))
	_card_btns[id] = card
	return card


func _toggle_card(id: String, on: bool, card: Control) -> void:
	if _sending:
		return
	AudioManager.play("ui_click")
	if on and not _cards.has(id):
		if _cards.size() >= 3:
			card.call("set_pressed_no_signal", false)
			layer.call("show_toast", "最多選 3 張保障卡；先取消一張再選", "warning")
			QuestUI.shake(card)
			return
		_cards.append(id)
	elif not on:
		_cards.erase(id)
		for nk in _cover.keys():
			if str(_cover[nk]) == "card:" + id:
				_cover.erase(nk)
	_save_draft()
	_sync()


# --- Needs ------------------------------------------------------------------------------------

func _load_needs(sess: Dictionary) -> void:
	_needs = []
	for n in GameState.record.get("needs", []):
		var t := str((n as Dictionary).get("text", ""))
		if t != "" and not _needs.has(t):
			_needs.append(t)
	for k in GameState.client_needs():
		if not _needs.has(str(k)):
			_needs.append(str(k))
	var tw: Variant = sess.get("twist")
	if bool(GameState.flag("twist_plan", false)) and tw is Dictionary:
		var t2 := "人生事件：" + str(tw.get("title", ""))
		if not _needs.has(t2):
			_needs.append(t2)
	_needs = _needs.slice(0, 6)


func _cover_options() -> Array:
	var out: Array = [["", "選擇承接方式"]]
	for spec in RES:
		if int(_alloc[spec[0]]) > 0:
			out.append(["res:" + spec[0], spec[1]])
	for cd in Net.static_data.get("cards", []):
		var id := str((cd as Dictionary).get("id", ""))
		if _cards.has(id):
			out.append(["card:" + id, str(cd.get("title", ""))])
	return out


var _rows_key := ""
var _need_widgets: Dictionary = {}


## Rows are rebuilt only when the choices change (a card or budget line added / removed);
## otherwise each row updates in place, so an open dropdown never disappears under the pointer
func _build_need_rows() -> void:
	var opts := _cover_options()
	var key := JSON.stringify(opts) + "|" + JSON.stringify(_needs)
	if key == _rows_key and not _need_widgets.is_empty():
		for n in _need_widgets:
			var w: Array = _need_widgets[n]
			var covered := _cover.has(n) and str(_cover[n]) != ""
			w[0].set("kind", "circle_check" if covered else "circle")
			w[0].call("set_color", QuestUI.GREEN if covered else QuestUI.MUTED)
			var ob_now: OptionButton = w[1]
			for i in range(ob_now.item_count):
				if str(ob_now.get_item_metadata(i)) == str(_cover.get(n, "")):
					ob_now.select(i)
		return
	_rows_key = key
	_need_widgets.clear()
	UI.clear(_need_rows)
	if _needs.is_empty():
		_need_rows.add_child(QuestUI.label("會談中還沒有確認需求。可以直接配置，但方案會少了依據。", 13, QuestUI.MUTED, true))
		return
	for n in _needs:
		var row := QuestUI.vbox(4)
		var covered := _cover.has(n) and str(_cover[n]) != ""
		var head := QuestUI.hbox(6)
		var mark := QuestUI.icon("circle_check" if covered else "circle", 16.0, QuestUI.GREEN if covered else QuestUI.MUTED)
		head.add_child(mark)
		head.add_child(QuestUI.label(str(n), 14, QuestUI.TEXT, true))
		row.add_child(head)
		var ob := OptionButton.new()
		ob.name = "Cover_" + str(_needs.find(n))
		ob.add_theme_font_size_override("font_size", QuestUI.fs(14))
		ob.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var sel := 0
		for i in range(opts.size()):
			ob.add_item(str(opts[i][1]), i)
			ob.set_item_metadata(i, opts[i][0])
			if str(opts[i][0]) == str(_cover.get(n, "")):
				sel = i
		ob.select(sel)
		var need: String = n
		ob.item_selected.connect(func(idx: int):
			if _sending:
				return
			var val := str(ob.get_item_metadata(idx))
			if val == "":
				_cover.erase(need)
			else:
				_cover[need] = val
			AudioManager.play("ui_click")
			_save_draft()
			_sync()
		)
		row.add_child(ob)
		_need_rows.add_child(row)
		_need_widgets[n] = [mark, ob]


# --- Briefcase --------------------------------------------------------------------------------

func _build_tools(sess: Dictionary) -> void:
	UI.clear(_tools_box)
	_tools_box.add_child(QuestUI.header("briefcase", "顧問公事包"))
	var tools: Array = Net.me().get("briefcase", [])
	var hints: Dictionary = sess.get("toolHints", {}) if sess.get("toolHints") is Dictionary else {}
	var used: Dictionary = GameState.record.get("tools", {})
	if tools.is_empty():
		_tools_box.add_child(QuestUI.label("這次沒有攜帶工具。", 13, QuestUI.MUTED))
		return
	for t in tools:
		var info := _tool_info(str(t))
		var row := QuestUI.vbox(4)
		row.add_child(QuestUI.label(info[0], 14, QuestUI.GOLD, false, true))
		var tid := str(t)
		if tid == "gap_sheet" and hints.has("coreCards"):
			if used.has(tid):
				row.add_child(QuestUI.label("核心保障建議：" + _card_names(hints.coreCards), 13, QuestUI.TEXT, true))
			else:
				var ub: Button = QuestUI.button("使用：查看核心保障建議", func(): _use_tool(tid), "quiet")
				ub.name = "UseTool_" + tid
				row.add_child(ub)
		elif tid == "risk_survey" and hints.has("ideal"):
			if used.has(tid):
				var ideal: Dictionary = hints.ideal
				var parts: Array = []
				for spec in RES:
					var r: Array = ideal.get(spec[0], [])
					if r.size() == 2:
						parts.append("%s %d–%d" % [spec[1], int(r[0]), int(r[1])])
				row.add_child(QuestUI.label("建議區間：" + "、".join(parts), 13, QuestUI.TEXT, true))
			else:
				var ub2: Button = QuestUI.button("使用：查看建議配置區間", func(): _use_tool(tid), "quiet")
				ub2.name = "UseTool_" + tid
				row.add_child(ub2)
		else:
			row.add_child(QuestUI.label(info[1], 12, QuestUI.MUTED, true))
		_tools_box.add_child(row)


func _tool_info(id: String) -> Array:
	match id:
		"needs_form": return ["需求確認單", "已生效：會談多一輪對話。"]
		"family_map": return ["家庭關係圖", "已生效：多一次自由提問，線索板顯示家庭關係。"]
		"cashflow": return ["現金流量表", "已生效：會談開始時先揭露一張需求線索。"]
		"gap_sheet": return ["保障缺口表", "可在此查看核心保障建議。"]
		"risk_survey": return ["風險屬性問卷", "可在此查看建議配置區間。"]
		"compliance_check": return ["合規檢核表", "已生效：違規扣分減半；合規檢核可免一次誤判。"]
	return [id, ""]


func _card_names(ids: Array) -> String:
	var out: Array = []
	for cd in Net.static_data.get("cards", []):
		if ids.has(str((cd as Dictionary).get("id", ""))):
			out.append(str(cd.get("title", "")))
	return "、".join(out)


func _use_tool(id: String) -> void:
	if _sending:
		return
	var used: Dictionary = GameState.record.get("tools", {})
	used[id] = true
	GameState.set_value("tools", used)
	AudioManager.play("card_flip")
	GameState.add_decision("公事包", "使用「%s」" % _tool_info(id)[0], "用工具取得建議，省下自己摸索的時間。", "good")
	_build_tools(GameState.my_session())


# --- Live state -------------------------------------------------------------------------------

func _total() -> int:
	return int(_alloc.cash) + int(_alloc.protect) + int(_alloc.growth)


func _sync() -> void:
	var total := _total()
	for k in _res_rows:
		var r: Array = _res_rows[k]
		(r[0] as Label).text = str(int(_alloc[k]))
		r[1].value = float(_alloc[k]) * 10.0
		(r[2] as Button).disabled = int(_alloc[k]) <= 0
		(r[3] as Button).disabled = int(_alloc[k]) >= TOTAL
	var over := total > TOTAL
	_total_label.text = "%d / %d 單位" % [total, TOTAL]
	_total_label.add_theme_color_override("font_color", QuestUI.RED if over else (QuestUI.TEXT if total < TOTAL else QuestUI.GREEN))
	if over and not _was_over:
		AudioManager.play("budget_over")
		QuestUI.shake(_budget_card)
		layer.call("show_toast", "目前方案超出客戶每月預算 %d 單位" % (total - TOTAL), "danger")
	_was_over = over
	TensionManager.set_flag("budget_over", over)
	_build_need_rows()
	var covered := 0
	var missing: Array = []
	for n in _needs:
		if _cover.has(n) and str(_cover[n]) != "":
			covered += 1
		else:
			missing.append(n)
	var ratio := 1.0 if _needs.is_empty() else float(covered) / float(_needs.size())
	var balanced := ratio >= 1.0 and total == TOTAL and _cards.size() >= 2
	_ring.ratio = ratio
	_ring.broken = ratio < 1.0
	_ring.color = QuestUI.GREEN if balanced else QuestUI.GOLD
	_ring.center_text = "%d%%" % int(round(ratio * 100))
	_ring.sub_text = "需求承接"
	_ring.queue_redraw()
	_ring_note.text = "需求與預算平衡" if balanced else ("尚有 %d 項需求未承接" % missing.size() if not missing.is_empty() else "需求都有承接，請確認預算與保障卡")
	if balanced and not _was_closed:
		AudioManager.play("confirm_soft")
		QuestUI.pulse_once(_ring, 1.06)
	_was_closed = balanced
	TensionManager.set_flag("coverage_gap", not missing.is_empty())
	# Evaluation lines (no answer hints: budget, coverage and compliance reminders only)
	UI.clear(_eval)
	_eval.add_child(QuestUI.metric_bar("保障完整度", ratio * 100.0, QuestUI.GREEN if ratio >= 1.0 else QuestUI.GOLD))
	var fit_val := 100.0 if total == TOTAL else maxf(0.0, 100.0 - absf(total - TOTAL) * 25.0)
	_eval.add_child(QuestUI.metric_bar("預算適配", fit_val, QuestUI.RED if over else (QuestUI.GREEN if total == TOTAL else QuestUI.GOLD)))
	_eval.add_child(QuestUI.metric_bar("合規表現", GameState.compliance()))
	if int(_alloc.growth) >= 6:
		_eval.add_child(QuestUI.label("提醒：成長部位較高，說明時要講清楚波動，不能暗示保證報酬。", 12, QuestUI.GOLD, true))
	var reason := ""
	if over:
		reason = "目前方案超出客戶每月預算（多 %d 單位）" % (total - TOTAL)
	elif total < TOTAL:
		reason = "還有 %d 單位預算沒有分配（需剛好 10 單位）" % (TOTAL - total)
	elif _cards.size() < 2:
		reason = "請至少選擇 2 張保障卡（目前 %d 張）" % _cards.size()
	elif not missing.is_empty():
		reason = "尚未涵蓋本案主要需求：%s" % str(missing[0])
	if not _sending:
		_submit.call("set_reason", reason)


func _on_submit() -> void:
	if _sending:
		return
	var uncovered := 0
	for n in _needs:
		if not _cover.has(n):
			uncovered += 1
	var body := "客戶會依這份方案做決定，送出後無法再修改。\n預算 %d 單位：預備 %d、保障 %d、成長 %d；保障卡 %d 張。" % [_total(), int(_alloc.cash), int(_alloc.protect), int(_alloc.growth), _cards.size()]
	var ok: bool = await layer.call("critical", _submit, "提交顧問方案", body, "確認提交")
	if not ok or not is_instance_valid(self):
		return
	_sending = true
	_submit.call("set_loading", true, "客戶檢視方案中")
	var lines: Array = []
	for n in _needs:
		lines.append("%s → %s" % [n, _cover_label(str(_cover.get(n, "")))])
	GameState.set_value("coverage", _cover.duplicate())
	GameState.add_decision("方案配置", "提交方案：預備 %d／保障 %d／成長 %d，保障卡 %s" % [int(_alloc.cash), int(_alloc.protect), int(_alloc.growth), _card_names(_cards)], "需求承接：" + "；".join(lines) if not lines.is_empty() else "沒有已確認的需求可以對照。", "ok")
	send({"type": "plan", "alloc": _alloc.duplicate(), "cards": _cards.duplicate()})


func _cover_label(v: String) -> String:
	if v.begins_with("res:"):
		for spec in RES:
			if "res:" + spec[0] == v:
				return spec[1]
	if v.begins_with("card:"):
		return _card_names([v.substr(5)])
	return "未承接"
