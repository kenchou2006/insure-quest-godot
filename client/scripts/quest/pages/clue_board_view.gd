extends "res://scripts/quest/pages/page_base.gd"
## ClueBoardView (page 4) — 需求探索線索板.
## Clue cards (the meeting's real clues and one decoy, unknown which) go into 必要需求 / 潛在風險 /
## 暫時無關 by drag or by tap-then-tap. Putting a card into a need box investigates it (server
## observe, at most 3): the card flips with a scan sound. A real need correctly placed gets one gold
## scan line; a misjudged card shows a short reason and costs meeting time. No line or colour
## hints at the answer before the player commits. 確認需求判斷 opens only when every card is placed
## and the interview has its 3 questions — the reason sits next to the button.

const WRONG_COST := 20.0
const BINS := [["need", "必要需求", "確定要處理的需求"], ["risk", "潛在風險", "可能發生、需要預防"], ["none", "暫時無關", "和這次規劃無關"]]

var _cards_box: Container
var _bins: Dictionary = {}
var _cards: Dictionary = {}
var _detail: VBoxContainer
var _count: Label
var _confirm: Button
var _clear: Button
var _reason: Label
var _status: Control
var _selected := -1
var _observing: Dictionary = {}
var _prev_observed: Dictionary = {}
var _submitted := false
var _need_more_questions := false


func guide_lines() -> Array:
	return ["這是線索板。把每張線索放進「必要需求」、「潛在風險」或「暫時無關」。", "放進需求區會調查並翻開線索，最多 3 張；判斷錯了會花掉會談時間。全部分類後再確認需求判斷；若訪談還不到 3 題，按鈕會帶你回會談補問。"]


func help_lines() -> Array:
	return ["和財務無關的線索放「暫時無關」；確定要處理的需求放「必要需求」，可能發生的放「潛在風險」。", "可以拖曳，也可以先點線索、再點分類區。"]


func idle_lines() -> Array:
	return ["先挑一張最像「錢與生活」的線索翻開，看它說了什麼。"]


func key_rects() -> Array:
	return [rect_of(_confirm)]


func highlight_rects() -> Array:
	var out: Array = []
	for k in _bins:
		out.append(rect_of(_bins[k]))
	return out


func build() -> void:
	add_background()
	var v := add_frame()
	var sess := GameState.my_session()
	# Left: clue cards
	var left := QuestUI.card(null, 0.92)
	var lv := QuestUI.vbox(10)
	left.add_child(lv)
	lv.add_child(QuestUI.header("search", "可用線索"))
	lv.add_child(QuestUI.label("拖曳或點選線索，放進右邊的分類區。", 13, QuestUI.MUTED, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_cards_box = grid
	lv.add_child(grid)
	var tools: Array = Net.me().get("briefcase", [])
	if tools.has("family_map") and GameState.client_family() != "":
		var fam := QuestUI.card(null, 0.5, Color(QuestUI.GOLD, 0.4))
		var fv := QuestUI.vbox(4)
		fam.add_child(fv)
		fv.add_child(QuestUI.label("公事包・家庭關係圖", 13, QuestUI.GOLD, false, true))
		fv.add_child(QuestUI.label(GameState.client_family(), 14, QuestUI.TEXT, true))
		lv.add_child(fam)
	# Centre: the three boxes and the confirm bar
	var center := QuestUI.vbox(12)
	var ttl := QuestUI.title("把線索分類，建立需求輪廓", 26 if not phone() else 19)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(ttl)
	var sub := QuestUI.label("必要需求與潛在風險都會成為方案要承接的事；放錯會花時間，也會影響方案。", 14, QuestUI.MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)
	var bins_row: BoxContainer = QuestUI.hbox(12) if not UI.is_phone_portrait() else QuestUI.vbox(10)
	bins_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for spec in BINS:
		var b := Bin.new(spec[0], spec[1], spec[2], self)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bins_row.add_child(b)
		_bins[spec[0]] = b
	var bins_scroll: Control = QuestUI.scroll(bins_row) if not narrow() else bins_row
	center.add_child(bins_scroll)
	var bar := QuestUI.card(null, 0.95)
	var bh := QuestUI.hbox(12 if not narrow() else 6)
	bar.add_child(bh)
	bh.add_child(QuestUI.icon("circle_check", 26.0, QuestUI.GOLD))
	_count = QuestUI.label("已分類 0 / 0", 18, QuestUI.TEXT, false, true)
	bh.add_child(_count)
	bh.add_child(QuestUI.spacer())
	_clear = QuestUI.button("清除", _clear_unjudged, "secondary", "trash")
	_clear.name = "ClearButton"
	bh.add_child(_clear)
	_confirm = QuestUI.button("確認需求判斷", _on_confirm, "primary", "check")
	_confirm.name = "ConfirmClues"
	bh.add_child(_confirm)
	_reason = QuestUI.label("", 13, QuestUI.GOLD, true)
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_confirm.set("reason_label", _reason)
	if narrow():
		# Phones: the confirm bar is pinned at the bottom with the other key buttons
		_footer_items.append(bar)
		_footer_items.append(_reason)
	else:
		center.add_child(bar)
		center.add_child(_reason)
	# Right: status + reading of the selected clue; 返回 pinned
	_status = ClientStatusPanel.new(true)
	var read := QuestUI.card(null, 0.92)
	_detail = QuestUI.vbox(8)
	read.add_child(_detail)
	var back: Button = QuestUI.button("返回會談", func(): go.emit("dialogue", {}), "quiet", "back")
	back.name = "BackButton"
	var right := side([_status, read], [secretary_button(), back])
	v.add_child(columns([QuestUI.scroll(left) if not narrow() else left, center, right], [1.1, 1.7, 1.0]))
	_build_cards(sess)
	_show_detail(-1)


func refresh(_s: Dictionary) -> void:
	var sess := GameState.my_session()
	if sess.is_empty():
		return
	var clues: Array = sess.get("clues", [])
	for i in range(clues.size()):
		var cl: Dictionary = clues[i]
		var card: ClueCard = _cards.get(i)
		if card == null:
			continue
		var was := bool(_prev_observed.get(i, false))
		var now := bool(cl.get("observed", false))
		card.data = cl
		if now and not was:
			card.flip(true)
			if _observing.has(i):
				_observing.erase(i)
				_judge(i)
			if i == _selected:
				_show_detail(i)
		_prev_observed[i] = now
	if is_instance_valid(_status):
		_status.call("refresh")
	_sync()


func server_error(_msg: String) -> void:
	# An observe that failed puts the card back on the shelf
	for i in _observing.keys():
		_unplace(i)
	_observing.clear()
	_confirm.call("set_loading", false)
	_submitted = false
	if is_instance_valid(_clear):
		_clear.disabled = false
	_sync()


func _build_cards(sess: Dictionary) -> void:
	var clues: Array = sess.get("clues", [])
	var placed: Dictionary = GameState.selected_clues()
	for i in range(clues.size()):
		var cl: Dictionary = clues[i]
		var card := ClueCard.new(i, cl, self)
		_cards[i] = card
		_prev_observed[i] = bool(cl.get("observed", false))
		var bin := str(placed.get(str(i), ""))
		if bin != "" and _bins.has(bin):
			_bins[bin].call("put", card)
		else:
			_cards_box.add_child(card)
	_sync()


# --- Placing ----------------------------------------------------------------------------------

func select(i: int) -> void:
	_selected = i
	AudioManager.play("clue_scan")
	for k in _cards:
		(_cards[k] as ClueCard).set_selected(k == i)
	# Out of investigations: a face-down card can only go to 暫時無關, so only that box takes it
	var locked := i >= 0 and _cards.has(i) and _no_scans_left(i)
	for k in _bins:
		_bins[k].call("set_armed", i >= 0 and (k == "none" or not locked))
		_bins[k].call("set_recommended", locked and k == "none")
	_show_detail(i)


func place(i: int, bin: String) -> void:
	if _submitted or not _cards.has(i):
		return
	var card: ClueCard = _cards[i]
	var cl: Dictionary = card.data
	var observed := bool(cl.get("observed", false))
	var placed: Dictionary = GameState.selected_clues()
	var old := str(placed.get(str(i), ""))
	if old == bin:
		return
	if bin in ["need", "risk"] and not observed:
		if _observed_count() + _observing.size() >= 3:
			layer.call("show_toast", "調查次數已用完（3/3）：這張線索只能放進「暫時無關」", "warning")
			QuestUI.shake(_bins[bin])
			_bins["none"].call("flash")
			return
		if bool(GameState.my_session().get("aiBusy", false)):
			layer.call("show_toast", "客戶還在回應，稍等一下再調查", "warning")
			return
	placed[str(i)] = bin
	GameState.set_value("clues", placed)
	_bins[bin].call("put", card)
	_bins[bin].call("flash")
	select(-1)
	if bin in ["need", "risk"] and not observed:
		_observing[i] = true
		card.set_busy(true)
		send({"type": "observe", "index": i})
	elif observed:
		_judge(i)
	_sync()


func _unplace(i: int) -> void:
	var placed: Dictionary = GameState.selected_clues()
	placed.erase(str(i))
	GameState.set_value("clues", placed)
	var card: ClueCard = _cards[i]
	card.set_busy(false)
	if card.get_parent():
		card.get_parent().remove_child(card)
	_cards_box.add_child(card)


func _clear_unjudged() -> void:
	if _submitted:
		return
	# Judged cards keep their verdict; only cards not yet judged go back
	var res: Dictionary = GameState.record.get("clue_results", {})
	for i in _cards:
		if not res.has(str(i)) and GameState.selected_clues().has(str(i)) and not _observing.has(i):
			_unplace(i)
	select(-1)
	_sync()


## Verdict once a placed card is face up
func _judge(i: int) -> void:
	var card: ClueCard = _cards[i]
	var cl: Dictionary = card.data
	var bin := str(GameState.selected_clues().get(str(i), ""))
	var real := bool(cl.get("real", false))
	var res: Dictionary = GameState.record.get("clue_results", {})
	var key := str(i)
	var correct := (real and bin in ["need", "risk"]) or (not real and bin == "none")
	var prev := str(res.get(key, ""))
	if prev == "wrong" and correct:
		res[key] = "fixed"
		card.set_verdict("fixed")
		GameState.add_decision("線索分類", "改判「%s」" % str(cl.get("title", "")), "修正了判斷，但先前誤判花掉的時間不會回來。", "ok")
	elif correct:
		res[key] = "correct"
		card.set_verdict("correct")
		if real:
			card.gold_scan()
			AudioManager.play("gold_scan")
		GameState.add_decision("線索分類", "「%s」→ %s" % [str(cl.get("title", "")), _bin_name(bin)], str(cl.get("fact", cl.get("detail", ""))), "good")
	else:
		res[key] = "wrong"
		card.set_verdict("wrong")
		QuestUI.shake(card)
		AudioManager.play("trust_down")
		var why := ("這不是需求線索：%s" % str(cl.get("detail", ""))) if not real else ("這是需求線索：%s，不該放在暫時無關。" % str(cl.get("fact", "")))
		GameState.spend_time(WRONG_COST, "線索誤判")
		GameState.add_decision("線索分類", "誤判「%s」" % str(cl.get("title", "")), why + "（會談時間 -0:20）", "bad")
		layer.call("show_toast", why, "warning")
	GameState.set_value("clue_results", res)
	if i == _selected or _selected < 0:
		_show_detail(i)


func _observed_count() -> int:
	var n := 0
	for k in _cards:
		if bool((_cards[k] as ClueCard).data.get("observed", false)):
			n += 1
	return n


## True when card i is still face down and all 3 investigations are spent
func _no_scans_left(i: int) -> bool:
	return not bool((_cards[i] as ClueCard).data.get("observed", false)) and _observed_count() + _observing.size() >= 3


## Titles of the cards still on the shelf, when every one of them can only go to 暫時無關
func _stuck_titles() -> Array:
	var placed := GameState.selected_clues()
	var out: Array = []
	for k in _cards:
		if placed.has(str(k)):
			continue
		if not _no_scans_left(k):
			return []
		out.append("「%s」" % str((_cards[k] as ClueCard).data.get("title", "")))
	return out


func _bin_name(b: String) -> String:
	for spec in BINS:
		if spec[0] == b:
			return spec[1]
	return b


func _sync() -> void:
	var total := _cards.size()
	var placed := GameState.selected_clues().size()
	_count.text = "已分類 %d / %d" % [placed, total]
	var sess := GameState.my_session()
	var covered: Array = sess.get("covered", [])
	var n_covered := mini(covered.size(), 3)
	var need_return := false
	var reason := ""
	if not _observing.is_empty():
		reason = "線索調查中，請稍候"
	elif placed < total:
		var stuck := _stuck_titles()
		if stuck.is_empty():
			reason = "還有 %d 張線索沒有分類" % (total - placed)
		else:
			reason = "調查次數已用完（3/3）：把%s放進「暫時無關」就能確認" % "、".join(stuck)
	elif bool(sess.get("aiBusy", false)):
		reason = "客戶還在回應中"
	elif not bool(sess.get("ready", false)):
		need_return = true
	if not _submitted:
		if need_return:
			_need_more_questions = true
			_confirm.call("set_label", "回到會談補問（%d/3）" % n_covered)
			_confirm.call("set_icon", "back")
			_confirm.call("set_reason", "")
			_confirm.disabled = false
			var missing := 3 - n_covered
			var tip := "需求判斷要根據至少 3 個不同主題的訪談。還差 %d 題，回會談再問一題吧。" % missing
			_reason.text = tip
			_reason.visible = true
			_confirm.tooltip_text = tip
		else:
			_need_more_questions = false
			_confirm.call("set_label", "確認需求判斷")
			_confirm.call("set_icon", "check")
			_confirm.call("set_reason", reason)
	elif is_instance_valid(_clear):
		_clear.disabled = true


func _show_detail(i: int) -> void:
	UI.clear(_detail)
	_detail.add_child(QuestUI.header("doc", "線索解讀"))
	if i < 0 or not _cards.has(i):
		var ph := QuestUI.vbox(8)
		ph.alignment = BoxContainer.ALIGNMENT_CENTER
		ph.add_child(QuestUI.icon("search", 44.0, Color(QuestUI.MUTED, 0.6)))
		var l := QuestUI.label("先從左側選一張線索，這裡會顯示它的重點與可能影響。", 15, QuestUI.MUTED, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.add_child(l)
		_detail.add_child(ph)
		return
	var cl: Dictionary = (_cards[i] as ClueCard).data
	_detail.add_child(QuestUI.title(str(cl.get("title", "")), 19))
	if not bool(cl.get("observed", false)):
		if _observed_count() + _observing.size() >= 3:
			_detail.add_child(QuestUI.label("調查次數已用完（3/3），翻開過的線索不會退回次數。這張線索請放進「暫時無關」，再按「確認需求判斷」。", 14, QuestUI.GOLD, true))
		else:
			_detail.add_child(QuestUI.label("尚未調查。放進「必要需求」或「潛在風險」就會調查並翻開（最多 3 張）；確定和財務無關就放「暫時無關」。", 14, QuestUI.MUTED, true))
		return
	if str(cl.get("detail", "")) != "":
		_detail.add_child(QuestUI.label(str(cl.detail), 15, QuestUI.TEXT, true))
	if str(cl.get("fact", "")) != "":
		var r := QuestUI.hbox(6)
		r.add_child(QuestUI.icon("bulb", 16.0, QuestUI.GOLD))
		r.add_child(QuestUI.label("重點：" + str(cl.fact), 15, QuestUI.GOLD, true))
		_detail.add_child(r)
	var verdict := str((GameState.record.get("clue_results", {}) as Dictionary).get(str(i), ""))
	if verdict == "wrong":
		_detail.add_child(QuestUI.label("這張判斷錯了，可以移到正確的分類區修正。", 14, QuestUI.RED.lightened(0.2), true))


# --- Confirm ----------------------------------------------------------------------------------

func _on_confirm() -> void:
	if _need_more_questions:
		go.emit("dialogue", {})
		return
	if _submitted:
		return
	_submitted = true
	if is_instance_valid(_clear):
		_clear.disabled = true
	_confirm.call("set_loading", true, "整理需求")
	var sess := GameState.my_session()
	var clues: Array = sess.get("clues", [])
	var placed: Dictionary = GameState.selected_clues()
	var res: Dictionary = GameState.record.get("clue_results", {})
	# Cards left face down in 暫時無關: exactly one clue of the meeting is a decoy
	var decoy_seen := false
	var hidden_none: Array = []
	for i in range(clues.size()):
		var cl: Dictionary = clues[i]
		if bool(cl.get("observed", false)) and not bool(cl.get("real", false)):
			decoy_seen = true
		if not bool(cl.get("observed", false)) and str(placed.get(str(i), "")) == "none":
			hidden_none.append(i)
	var missed := hidden_none.size() if decoy_seen else maxi(0, hidden_none.size() - 1)
	if missed > 0:
		GameState.spend_time(WRONG_COST * missed, "漏判需求線索")
		GameState.add_decision("線索分類", "漏判 %d 張需求線索" % missed, "放進「暫時無關」的線索裡有真正的需求；方案可能因此少承接一項風險。（會談時間 -0:%02d）" % int(WRONG_COST * missed), "bad")
		layer.call("show_toast", "有 %d 張被放進「暫時無關」的線索其實是需求" % missed, "warning")
	elif hidden_none.size() == 1 and not decoy_seen:
		res[str(hidden_none[0])] = "correct"
		GameState.add_decision("線索分類", "排除干擾線索", "沒有花調查次數在和需求無關的線索上。", "good")
	var good := 0
	var bad := 0
	for k in res:
		if str(res[k]) == "correct":
			good += 1
		elif str(res[k]) == "wrong":
			bad += 1
	GameState.set_value("clue_results", res)
	# Needs carried into the plan: everything placed in 必要需求 / 潛在風險
	var needs: Array = []
	for i in range(clues.size()):
		var bin := str(placed.get(str(i), ""))
		if bin in ["need", "risk"] and str(clues[i].get("fact", "")) != "":
			needs.append({"text": str(clues[i].fact), "bin": bin})
	GameState.set_value("needs", needs)
	GameState.add_decision("線索分類", "需求判斷完成", "正確 %d 張、誤判 %d 張、漏判 %d 張。" % [good, bad, missed], "good" if bad == 0 and missed == 0 else ("ok" if bad + missed <= 1 else "bad"))
	AudioManager.play("confirm_soft")
	await get_tree().create_timer(0.4).timeout
	send({"type": "to_plan"})


# --- Card and box ------------------------------------------------------------------------------

class ClueButton extends Button:
	var card: Control = null

	func _get_drag_data(at: Vector2) -> Variant:
		if card and card.has_method("_get_drag_data"):
			return card.call("_get_drag_data", at)
		return null


class ClueCard extends PanelContainer:
	signal pressed

	var index := 0
	var data: Dictionary = {}
	var view: Control
	var btn: Button
	var _content: VBoxContainer
	var _title: Label
	var _body: Label
	var _badge: Label
	var _scan: ColorRect
	var _face_up := false
	var _verdict := ""
	var _selected := false
	var _hover := false

	var disabled: bool:
		set(val):
			disabled = val
			if btn and is_instance_valid(btn):
				btn.disabled = val
			modulate.a = 0.45 if val else 1.0
		get:
			if btn and is_instance_valid(btn):
				return btn.disabled
			return disabled

	func _init(i: int, cl: Dictionary, owner_view: Control) -> void:
		index = i
		data = cl
		view = owner_view
		name = "Clue_%dCard" % i
		var base_h: float = 96.0 if not UI.is_phone() else 80.0
		custom_minimum_size = Vector2(150.0, base_h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

		_content = QuestUI.vbox(4)
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_content)

		_badge = QuestUI.label("", 11, QuestUI.GOLD)
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_badge)

		_title = QuestUI.label(str(cl.get("title", "")), 16, QuestUI.TEXT, true, true)
		_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_title)

		_body = QuestUI.label("", 12, QuestUI.MUTED, true)
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(_body)

		btn = ClueButton.new()
		btn.card = self
		btn.name = "Clue_%d" % i
		btn.flat = true
		btn.text = ""
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		add_child(btn)

		_scan = ColorRect.new()
		_scan.color = Color(QuestUI.GOLD, 0.85)
		_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scan.visible = false
		btn.add_child(_scan)

		btn.pressed.connect(func():
			view.call("select", index)
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

		_face_up = bool(cl.get("observed", false))
		_style()
		_fill()

	func _style(verdict := "") -> void:
		var v := verdict if verdict != "" else _verdict
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(12)
		s.set_border_width_all(2 if _selected else 1)
		s.bg_color = Color(QuestUI.CARD.lightened(0.05), 0.96) if _face_up else Color(QuestUI.INK, 0.95)
		s.border_color = Color(1, 1, 1, 0.14)
		if v == "wrong":
			s.border_color = Color(QuestUI.RED, 0.8)
		elif v in ["correct", "fixed"]:
			s.border_color = Color(QuestUI.GOLD, 0.7)
		elif _selected:
			s.border_color = QuestUI.GOLD
		elif _hover:
			s.border_color = QuestUI.GOLD
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 10
		s.content_margin_bottom = 8
		add_theme_stylebox_override("panel", s)

	func _fill() -> void:
		_title.text = str(data.get("title", ""))
		if _face_up:
			_body.text = str(data.get("detail", ""))
			_badge.text = "已翻開"
		else:
			_body.text = "尚未調查"
			_badge.text = "？ 線索"
		if _verdict != "":
			_badge.text = {"correct": "判斷正確", "fixed": "已修正", "wrong": "判斷有誤"}.get(_verdict, _badge.text)

	func flip(up: bool) -> void:
		AudioManager.play("card_flip")
		if QuestUI.motion_off():
			_face_up = up
			_style()
			_fill()
			return
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_property(self, "scale:x", 0.0, 0.12)
		tw.tween_callback(func():
			_face_up = up
			_style()
			_fill()
		)
		tw.tween_property(self, "scale:x", 1.0, 0.14)

	func set_busy(on: bool) -> void:
		if on:
			_badge.text = "調查中…"
		else:
			_fill()

	func set_selected(on: bool) -> void:
		_selected = on
		_style()

	func set_verdict(v: String) -> void:
		_verdict = v
		_style(v)
		_badge.text = {"correct": "判斷正確", "fixed": "已修正", "wrong": "判斷有誤"}.get(v, _badge.text)
		_badge.add_theme_color_override("font_color", QuestUI.RED.lightened(0.2) if v == "wrong" else QuestUI.GOLD)

	## One gold scan line sweeping down the card (correct key clue), never repeated
	func gold_scan() -> void:
		if QuestUI.motion_off():
			return
		_scan.visible = true
		_scan.size = Vector2(btn.size.x if btn.size.x > 0 else size.x, 2)
		_scan.position = Vector2(0, 0)
		var tw := create_tween()
		tw.tween_property(_scan, "position:y", (btn.size.y if btn.size.y > 0 else size.y) - 2, 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func(): _scan.visible = false)

	func _get_drag_data(_at: Vector2) -> Variant:
		var p := PanelContainer.new()
		var s := StyleBoxFlat.new()
		s.bg_color = Color(QuestUI.CARD, 0.95)
		s.set_corner_radius_all(10)
		s.set_border_width_all(1)
		s.border_color = QuestUI.GOLD
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 8
		s.content_margin_bottom = 8
		p.add_theme_stylebox_override("panel", s)
		p.add_child(QuestUI.label(str(data.get("title", "")), 15, QuestUI.TEXT, false, true))
		set_drag_preview(p)
		view.call("select", index)
		return {"clue": index}


class Bin extends PanelContainer:
	var key := ""
	var view: Control
	var _items: VBoxContainer
	var _hint: Control
	var _hover := false
	var _armed := false
	var _recommended := false
	var _pick: Button

	func _init(k: String, title_text: String, sub: String, owner_view: Control) -> void:
		key = k
		view = owner_view
		name = "Bin_" + k
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(150, 200 if not UI.is_phone() else 120)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(QuestUI.CARD, 0.88)
		s.set_corner_radius_all(14)
		s.set_border_width_all(1)
		s.border_color = Color(1, 1, 1, 0.12)
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 12
		s.content_margin_bottom = 12
		add_theme_stylebox_override("panel", s)
		var v := QuestUI.vbox(8)
		add_child(v)
		var icon_kind: String = {"need": "target", "risk": "shield", "none": "close"}.get(k, "doc")
		var head := QuestUI.hbox(8)
		head.alignment = BoxContainer.ALIGNMENT_CENTER
		head.add_child(QuestUI.icon(icon_kind, 22.0, QuestUI.GOLD))
		head.add_child(QuestUI.title(title_text, 18))
		v.add_child(head)
		var sl := QuestUI.label(sub, 12, QuestUI.MUTED, true)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
		_items = QuestUI.vbox(6)
		_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(_items)
		_hint = QuestUI.vbox(4)
		_hint.alignment = BoxContainer.ALIGNMENT_CENTER
		_hint.add_child(QuestUI.icon("plus", 26.0, Color(QuestUI.TEXT, 0.5)))
		var hl := QuestUI.label("拖曳線索至此", 12, QuestUI.MUTED)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.add_child(hl)
		_items.add_child(_hint)
		_pick = QuestUI.button("放到這裡", func(): view.call("place", int(view.get("_selected")), key), "quiet")
		_pick.name = "PlaceHere_" + k
		_pick.visible = false
		v.add_child(_pick)

	func put(card: Control) -> void:
		if card.get_parent():
			card.get_parent().remove_child(card)
		_items.add_child(card)
		_hint.visible = false

	func set_armed(on: bool) -> void:
		_armed = on
		_pick.visible = on
		queue_redraw()

	## The only box the selected card can go to: bright frame, a pulse and a clearer button
	func set_recommended(on: bool) -> void:
		if on == _recommended:
			return
		_recommended = on
		_pick.text = "放到這裡（調查已用完）" if on else "放到這裡"
		if on:
			flash()
		queue_redraw()

	func flash() -> void:
		QuestUI.pulse_once(self, 1.02)

	func _process(_d: float) -> void:
		_hint.visible = _items.get_child_count() <= 1

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok := data is Dictionary and (data as Dictionary).has("clue")
		if ok != _hover:
			_hover = ok
			queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_hover = false
		queue_redraw()
		view.call("place", int((data as Dictionary).clue), key)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			if _hover:
				_hover = false
				queue_redraw()

	func _draw() -> void:
		# Dashed inner frame; gold and brighter while a card hovers over this box
		var r := Rect2(Vector2(8, 8), size - Vector2(16, 16))
		var col := Color(QuestUI.GOLD, 0.95) if _hover or _recommended else (Color(QuestUI.GOLD, 0.5) if _armed else Color(1, 1, 1, 0.22))
		if _hover or _recommended:
			draw_rect(r, Color(QuestUI.GOLD, 0.08))
		var dash := 8.0
		var gap := 6.0
		for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end], [r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			var a: Vector2 = edge[0]
			var b: Vector2 = edge[1]
			var length := a.distance_to(b)
			var d := 0.0
			while d < length:
				draw_line(a.lerp(b, d / length), a.lerp(b, minf(d + dash, length) / length), col, 1.5)
				d += dash + gap
