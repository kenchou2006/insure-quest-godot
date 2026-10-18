extends "res://scripts/quest/pages/page_base.gd"
## ComplianceScanView (page 7) — 合規掃描.
## The meeting's record: the client's objection, the advisor's own composed reply (a risk when the
## server judged it so), one of the client's answers, and advisor lines from a bank of common
## practice — in a new order every time. A fine scan line passes every line at the same pace (no
## line is singled out). The player marks lines; only a marked risk shows its red underline and
## low tone. Wrong marks and missed risks both cost; the result explains each risk and a better line.
## 合規檢核表 in the briefcase forgives one wrong mark.

const RISKS := [
	{"type": "不當承諾", "text": "這檔商品過去幾年都沒有虧損，可以保證讓您穩賺不賠，完全不用擔心。", "fix": "「過去績效不代表未來，這類商品可能有虧損，我們一起看清楚風險。」", "why": "保證獲利或不會虧損屬於不當承諾。"},
	{"type": "不當承諾", "text": "照這樣規劃，您的目標一定沒問題，我可以保證。", "fix": "「這樣規劃能降低風險對目標的影響，但沒有人能保證人生結果。」", "why": "顧問不能承諾人生目標一定達成。"},
	{"type": "施壓成交", "text": "現在正好有內部名額，這個機會只有一週，錯過就不會再有了，建議您今天就簽。", "fix": "「您可以帶回去和家人討論，不用今天決定。」", "why": "以時間壓力或名額限制促使客戶成交。"},
	{"type": "施壓成交", "text": "身邊的人都已經買了，您再猶豫就來不及了。", "fix": "「每個家庭的狀況不同，我們依您的需求來看就好。」", "why": "用從眾與後悔感施壓，不是需求教育。"},
	{"type": "資訊不足", "text": "費用、收取方式和相關風險我之後再用文件補給您，您先不用看那麼多，先把名額保留比較重要。", "fix": "「簽約前，費用、收取方式與風險我們先逐項看過。」", "why": "沒有在客戶決定前說明費用與風險。"},
	{"type": "資訊不足", "text": "除外條款都是小細節，不太影響理賠，不用特別看。", "fix": "「除外條款會影響理賠範圍，我們一起逐條確認。」", "why": "淡化除外條款，客戶無法完整理解保障範圍。"},
]
const SAFE := [
	"這份方案的保障範圍和除外條款，我們一起逐條看過。",
	"您可以帶回家和家人討論，不用今天決定。",
	"投資部位的報酬會有波動，過去績效不代表未來。",
	"簽約後有 10 天的契約撤銷期，您可以再好好想想。",
	"預算有限的話，我們先處理影響最大的風險，其他再慢慢補。",
]
const WRONG_COST := 15
const MISS_COST := 25

var _rows: Array = []
var _lines: Array = []
var _marked: Dictionary = {}
var _wrong_marks: Dictionary = {}
var _forgiven := false
var _done := false
var _list: VBoxContainer
var _scan_line: ColorRect
var _ring: QuestUI.Ring
var _ring_note: Label
var _count: Label
var _finish: Button
var _reason: Label
var _clear: Button
var _next: Button
var _tip: PanelContainer
var _risk_total := 2


func guide_lines() -> Array:
	return ["這是合規檢核。讀一遍本次會談的紀錄，點選可能違反合規的句子。", "標錯或漏選都會影響合規分數；你自己剛才說的話也在紀錄裡。"]


func help_lines() -> Array:
	return ["常見風險有三種：不當承諾（保證獲利、保證結果）、施壓成交（名額、期限、從眾）、資訊不足（費用與風險沒說清楚）。"]


func idle_lines() -> Array:
	return ["找找看有沒有「保證」、「今天就簽」或「之後再補資料」這類說法。"]


func key_rects() -> Array:
	return [rect_of(_finish), rect_of(_next)]


func highlight_rects() -> Array:
	return [rect_of(_list)]


func build() -> void:
	add_background()
	var v := add_frame()
	_prepare_lines()
	# Left: secretary-style tip
	var left := QuestUI.vbox(12)
	_tip = QuestUI.card(null, 0.95, Color(QuestUI.GOLD, 0.45))
	var tv := QuestUI.vbox(10)
	_tip.add_child(tv)
	tv.add_child(QuestUI.label("請閱讀本次會談的紀錄，找出 %d 個可能違反合規的風險點並點選標記。" % _risk_total, 16, QuestUI.TEXT, true))
	tv.add_child(QuestUI.divider())
	tv.add_child(QuestUI.label("小提示：常見風險包括不當承諾、施壓成交，或關鍵資訊未說明清楚。", 14, QuestUI.MUTED, true))
	var got: Button = QuestUI.button("我知道了", func(): _tip.visible = false, "primary", "next")
	got.name = "TipOk"
	tv.add_child(got)
	left.add_child(_tip)
	left.add_child(secretary_button())
	left.add_child(review_button("回顧異議回應", ["異議處理"]))
	# Centre: the record
	var center := QuestUI.card(null, 0.95)
	var cv := QuestUI.vbox(10)
	center.add_child(cv)
	var head := QuestUI.hbox(10)
	head.add_child(QuestUI.icon("scan", 30.0, QuestUI.GOLD))
	head.add_child(QuestUI.title("合規檢核", 26 if not phone() else 19))
	head.add_child(QuestUI.label("｜找出 %d 個風險點" % _risk_total, 18, QuestUI.TEXT, false, true))
	cv.add_child(head)
	cv.add_child(QuestUI.label("點選你認為可能違反合規的內容（可複選）。", 13, QuestUI.MUTED, true))
	var list_wrap := Control.new()
	list_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_wrap.custom_minimum_size = Vector2(0, 200)
	list_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list = QuestUI.vbox(8)
	var sc := QuestUI.scroll(_list)
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	list_wrap.add_child(sc)
	_scan_line = ColorRect.new()
	_scan_line.color = Color(QuestUI.GOLD, 0.7)
	_scan_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan_line.visible = false
	list_wrap.add_child(_scan_line)
	cv.add_child(list_wrap)
	for i in range(_lines.size()):
		var r := _row(i, _lines[i])
		_list.add_child(r)
		_rows.append(r)
	# Right: score, risk types; controls pinned
	var sc_card := QuestUI.card(null, 0.95)
	var sv := QuestUI.vbox(10)
	sc_card.add_child(sv)
	sv.add_child(QuestUI.header("shield", "合規得分"))
	var rh := QuestUI.hbox(12)
	_ring = QuestUI.Ring.new()
	_ring.custom_minimum_size = Vector2(120, 120) if not compact() else Vector2(84, 84)
	_ring.center_text = "--"
	_ring.sub_text = "/ 100"
	_ring.ratio = 0.0
	rh.add_child(_ring)
	_ring_note = QuestUI.label("完成檢核後，依你的判斷計算合規得分。找出所有風險點、沒有誤判可得 100 分。", 13, QuestUI.MUTED, true)
	_ring_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(_ring_note)
	sv.add_child(rh)
	sv.add_child(QuestUI.label("此為訓練模擬情境，僅供內部教育使用。", 12, QuestUI.MUTED, true))
	var types := QuestUI.card(null, 0.92)
	var tyv := QuestUI.vbox(8)
	types.add_child(tyv)
	tyv.add_child(QuestUI.header("info", "風險類型說明"))
	for t in [["question", "資訊不足", "未充分說明費用、風險、限制等重要內容"], ["alert", "不當承諾", "承諾保證獲利、無風險或保證結果"], ["people", "施壓成交", "以時間壓力、名額限制等方式促使成交"]]:
		var h := QuestUI.hbox(8)
		h.add_child(QuestUI.icon(t[0], 22.0, QuestUI.GOLD))
		var dv := QuestUI.vbox(0)
		dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(QuestUI.label(t[1], 14, QuestUI.TEXT, false, true))
		dv.add_child(QuestUI.label(t[2], 12, QuestUI.MUTED, true))
		h.add_child(dv)
		tyv.add_child(h)
	_count = QuestUI.label("已標記 0 / %d" % _risk_total, 18, QuestUI.GOLD, false, true)
	var btns := QuestUI.hbox(10)
	_clear = QuestUI.button("取消標記", _clear_marks, "secondary", "refresh")
	_clear.name = "ClearMarks"
	_clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(_clear)
	_finish = QuestUI.button("完成檢核", _on_finish, "primary", "check")
	_finish.name = "FinishScan"
	_finish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(_finish)
	_reason = QuestUI.label("", 13, QuestUI.GOLD, true)
	_finish.set("reason_label", _reason)
	_next = QuestUI.button("查看任務結果", func(): go.emit("scan_done", {}), "primary", "next")
	_next.name = "ToResult"
	_next.visible = false
	var right := side([sc_card, types], [_count, btns, _reason, _next])
	v.add_child(columns([QuestUI.scroll(left) if not narrow() else left, center, right], [0.9, 2.0, 1.1]))
	_sync()


func on_open() -> void:
	_scan_pass()


func refresh(_s: Dictionary) -> void:
	pass


# --- Record -----------------------------------------------------------------------------------

func _prepare_lines() -> void:
	var saved: Dictionary = GameState.record.get("scan", {})
	if saved.has("lines"):
		_lines = saved.lines
		_risk_total = int(saved.get("risks", 2))
		return
	var sess := GameState.my_session()
	var obj: Dictionary = sess.get("objection", {}) if sess.get("objection") is Dictionary else {}
	var reply: Dictionary = sess.get("objectionReply", {}) if sess.get("objectionReply") is Dictionary else {}
	var client_lines: Array = []
	if str(obj.get("text", "")) != "":
		client_lines.append(str(obj.text).replace("「", "").replace("」", ""))
	for a in sess.get("asked", []):
		var ans := str((a as Dictionary).get("answer", "")).replace("「", "").replace("」", "")
		if ans != "" and client_lines.size() < 2:
			client_lines.append(ans)
	var advisor: Array = []
	var own_text := _own_reply()
	var own_risk := str(reply.get("quality", "")) == "bad"
	var own_type := ""
	if own_text != "":
		if own_risk:
			own_type = "施壓成交" if (own_text.contains("後悔") or own_text.contains("來不及") or own_text.contains("今天")) else "不當承諾"
			advisor.append({"who": "顧問", "text": own_text, "risk": true, "type": own_type, "why": "這是你剛才的回應：" + str(reply.get("body", "")), "fix": "「我理解您的顧慮，我們一起看這項安排怎麼保住您在乎的目標，您可以慢慢決定。」", "own": true})
		else:
			advisor.append({"who": "顧問", "text": own_text, "risk": false, "own": true})
	var need_bank := 2 - (1 if own_risk else 0)
	var bank := QuestUI.shuffled(RISKS)
	var types_used: Array = [own_type]
	for r in bank:
		if need_bank <= 0:
			break
		if types_used.has(r.type):
			continue
		types_used.append(r.type)
		advisor.append({"who": "顧問", "text": str(r.text), "risk": true, "type": str(r.type), "why": str(r.why), "fix": str(r.fix)})
		need_bank -= 1
	var safe := QuestUI.shuffled(SAFE)
	advisor.append({"who": "顧問", "text": str(safe[0]), "risk": false})
	if advisor.size() < 4:
		advisor.append({"who": "顧問", "text": str(safe[1]), "risk": false})
	advisor = QuestUI.shuffled(advisor)
	# Interleave: client, advisor, client, advisor, advisor …
	var out: Array = []
	var minute := 3
	var ci := 0
	var ai := 0
	var pattern := ["c", "a", "c", "a", "a", "a"]
	for p in pattern:
		if p == "c" and ci < client_lines.size():
			out.append({"who": "客戶", "text": str(client_lines[ci]), "risk": false})
			ci += 1
		elif ai < advisor.size():
			out.append(advisor[ai])
			ai += 1
	while ai < advisor.size():
		out.append(advisor[ai])
		ai += 1
	for o in out:
		o["time"] = "10:%02d" % minute
		minute += 2 + randi() % 2
	_lines = out
	_risk_total = 0
	for o in out:
		if bool(o.get("risk", false)):
			_risk_total += 1
	GameState.set_value("scan", {"lines": _lines, "risks": _risk_total})


func _own_reply() -> String:
	var d: Dictionary = GameState.selected_dialogue()
	var opts: Array = d.get("opts", [])
	var choice: Array = d.get("choice", [])
	var parts: Array = []
	for i in range(mini(opts.size(), choice.size())):
		var c := int(choice[i])
		if c >= 0 and c < (opts[i] as Array).size():
			parts.append(str(opts[i][c].text))
	if not parts.is_empty():
		return "".join(parts)
	var reply: Variant = GameState.my_session().get("objectionReply")
	return str((reply as Dictionary).get("text", "")) if reply is Dictionary else ""


func _row(i: int, line: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.name = "Line_%d" % i
	var s := StyleBoxFlat.new()
	s.bg_color = Color("#F3F0E7", 0.95)
	s.set_corner_radius_all(12)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	var h := QuestUI.hbox(12)
	p.add_child(h)
	var num := QuestUI.label(str(i + 1), 16, QuestUI.TEXT, false, true)
	var nb := PanelContainer.new()
	var ns := StyleBoxFlat.new()
	ns.bg_color = QuestUI.BG
	ns.set_corner_radius_all(999)
	ns.content_margin_left = 10
	ns.content_margin_right = 10
	ns.content_margin_top = 2
	ns.content_margin_bottom = 2
	nb.add_theme_stylebox_override("panel", ns)
	nb.add_child(num)
	nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nb)
	var is_client := str(line.get("who", "")) == "客戶"
	if is_client:
		var pt := QuestUI.portrait(GameState.client_portrait_id(), Vector2(48, 48))
		pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pt)
	else:
		var ic := QuestUI.icon("user", 40.0, QuestUI.BG)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	var who := QuestUI.vbox(0)
	who.custom_minimum_size.x = 44
	who.add_child(QuestUI.label(str(line.get("who", "")), 14, QuestUI.INK, false, true))
	who.add_child(QuestUI.label(str(line.get("time", "")), 12, Color(QuestUI.INK, 0.6)))
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(who)
	var tv := QuestUI.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := QuestUI.label(str(line.get("text", "")), 15, QuestUI.INK, true)
	tv.add_child(t)
	var under := ColorRect.new()
	under.name = "Underline"
	under.color = QuestUI.RED
	under.custom_minimum_size = Vector2(0, 2)
	under.visible = false
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(under)
	var note := QuestUI.label("", 13, QuestUI.INK, true)
	note.name = "Note"
	note.visible = false
	tv.add_child(note)
	h.add_child(tv)
	h.add_child(_mark_button(i))
	return p


## Large mark toggle (44 px): ring when free, gold check when marked; readable on the light rows
func _mark_button(i: int) -> Button:
	var b := Button.new()
	b.name = "Mark"
	b.toggle_mode = true
	b.tooltip_text = "標記為合規風險"
	b.custom_minimum_size = Vector2(44, 44)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(10)
		s.set_border_width_all(2)
		s.bg_color = Color(QuestUI.BG, 0.06)
		s.border_color = Color(QuestUI.BG, 0.45)
		match st:
			"hover":
				s.border_color = QuestUI.GOLD
			"pressed", "hover_pressed":
				s.bg_color = Color(QuestUI.GOLD, 0.2)
				s.border_color = QuestUI.GOLD
			"focus":
				s.bg_color = Color(0, 0, 0, 0)
				s.border_color = Color(QuestUI.GOLD, 0.8)
			"disabled":
				s.border_color = Color(QuestUI.BG, 0.2)
		b.add_theme_stylebox_override(st, s)
	var ic := QuestUI.icon("check", 24.0, QuestUI.BG)
	ic.position = Vector2(10, 10)
	ic.visible = false
	b.add_child(ic)
	b.toggled.connect(func(on: bool):
		ic.visible = on
		_mark(i, on)
	)
	b.mouse_entered.connect(func(): AudioManager.play("ui_hover"))
	return b


func _scan_pass() -> void:
	if QuestUI.motion_off() or _rows.is_empty():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_scan_line.visible = true
	_scan_line.size = Vector2(_list.size.x, 2)
	_scan_line.position = Vector2(0, 0)
	AudioManager.play("clue_scan")
	var tw := create_tween()
	# The same short stop on every line: the scan never singles a sentence out
	for r in _rows:
		var y: float = (r as Control).position.y + (r as Control).size.y * 0.5
		tw.tween_property(_scan_line, "position:y", y, 0.16).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.1)
	tw.tween_property(_scan_line, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		_scan_line.visible = false
		_scan_line.modulate.a = 1.0
	)


func _mark(i: int, on: bool) -> void:
	if _done:
		return
	var line: Dictionary = _lines[i]
	var row: Control = _rows[i]
	var under: Control = row.find_child("Underline", true, false)
	if on:
		_marked[i] = true
		AudioManager.play("ui_click")
		if bool(line.get("risk", false)):
			# Only a marked risk shows its red underline and the low tone
			under.visible = true
			AudioManager.play("compliance_risk")
		elif not _wrong_marks.has(i):
			_wrong_marks[i] = true
	else:
		_marked.erase(i)
		under.visible = false
	_sync()


func _clear_marks() -> void:
	if _done:
		return
	for i in _marked.keys():
		var row: Control = _rows[i]
		var box: Button = row.find_child("Mark", true, false)
		box.set_pressed_no_signal(false)
		for c in box.get_children():
			(c as Control).visible = false
		(row.find_child("Underline", true, false) as Control).visible = false
	_marked.clear()
	_sync()


func _sync() -> void:
	_count.text = "已標記 %d / %d" % [_marked.size(), _risk_total]
	if not _done:
		_finish.call("set_reason", "" if _marked.size() > 0 else "請至少標記 1 句你認為有風險的內容")


func _on_finish() -> void:
	if _done:
		return
	var ok: bool = await layer.call("critical", _finish, "完成合規檢核", "送出後會依你的標記計算合規得分：漏選與誤判都會扣分。", "完成檢核")
	if not ok or not is_instance_valid(self):
		return
	_done = true
	_finish.call("set_reason", "已完成檢核")
	_clear.disabled = true
	var missed := 0
	var found := 0
	for i in range(_lines.size()):
		var line: Dictionary = _lines[i]
		var row: Control = _rows[i]
		(row.find_child("Mark", true, false) as Button).disabled = true
		var note: Label = row.find_child("Note", true, false)
		if bool(line.get("risk", false)):
			if _marked.has(i):
				found += 1
				note.text = "【%s】%s\n較合適的說法：%s" % [line.get("type", ""), line.get("why", ""), line.get("fix", "")]
			else:
				missed += 1
				note.text = "漏選【%s】%s\n較合適的說法：%s" % [line.get("type", ""), line.get("why", ""), line.get("fix", "")]
				_set_row_border(row, QuestUI.GOLD)
			(row.find_child("Underline", true, false) as Control).visible = true
			note.visible = true
		elif _wrong_marks.has(i):
			note.text = "這句沒有合規問題：說明清楚、沒有保證或施壓。"
			note.visible = true
	var wrong := _wrong_marks.size()
	var tools: Array = Net.me().get("briefcase", [])
	if wrong > 0 and tools.has("compliance_check"):
		wrong -= 1
		_forgiven = true
	var score := clampi(100 - MISS_COST * missed - WRONG_COST * wrong, 0, 100)
	GameState.set_value("scan", {"lines": _lines, "risks": _risk_total, "score": score, "missed": missed, "wrong": wrong, "found": found, "forgiven": _forgiven})
	GameState.add_decision("合規檢核", "找出 %d/%d 個風險點，誤判 %d 句" % [found, _risk_total, wrong], ("合規檢核表免除了一次誤判。" if _forgiven else "") + ("漏掉的風險會留在客戶的印象裡。" if missed > 0 else "風險說法都被辨識出來。"), "good" if missed == 0 and wrong == 0 else ("ok" if missed + wrong <= 1 else "bad"))
	if score < 60:
		AudioManager.play("mission_fail")
	else:
		AudioManager.play("confirm_soft")
	# Score ring fills to the result
	var tw := create_tween()
	tw.tween_method(func(x: float):
		_ring.ratio = x / 100.0
		_ring.center_text = str(int(x))
		_ring.color = QuestUI.metric_color(x)
		_ring.queue_redraw()
	, 0.0, float(score), 0.8 if not QuestUI.motion_off() else 0.01)
	_ring_note.text = "找出 %d / %d 個風險點，誤判 %d 句。%s" % [found, _risk_total, wrong, "（合規檢核表免除一次誤判）" if _forgiven else ""]
	_finish.visible = false
	_reason.visible = false
	_next.visible = true
	QuestUI.fade_in(_next, 0.2, 0.25, 0.0)


func _set_row_border(row: Control, col: Color) -> void:
	var s := (row as PanelContainer).get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	s.set_border_width_all(2)
	s.border_color = col
	row.add_theme_stylebox_override("panel", s)
