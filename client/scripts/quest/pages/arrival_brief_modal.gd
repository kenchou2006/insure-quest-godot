extends "res://scripts/quest/pages/modal_base.gd"
## ArrivalBriefModal（任務簡報）— 抵達站點後的任務卡。地圖在背後變暗約 45%，仍看得出抵達的
## 站點。卡片上的資料全部來自後端這次抽出的客戶：站點、任務類型、客戶姓名與頭像、身分職業、
## 本次目標、可用會談時間、可負擔預算、初步風險線索、難度與可得經驗。
## 開始任務 → 客戶訪談；返回地圖 → 收起卡片看地圖（客戶不變，「回到任務簡報」再叫回）；
## 查看客戶線索 → 就地展開精簡線索。不提示答案：目標以中性圓點呈現。

const GOALS := {
	"discover": ["了解客戶背景", "找出真正的需求", "全程維持合規"],
	"plan": ["依需求配置預算", "選出核心保障", "守住每月預算"],
	"objection": ["理解客戶的疑慮", "釐清真正的擔心", "提出合規的下一步"],
}
const TITLES := {"discover": "需求探索", "plan": "方案設計", "objection": "疑慮回應"}
## 本次目標（一句話，放在目標橫條）
const OBJECTIVES := {
	"discover": "找出客戶真正的需求與合規風險",
	"plan": "依需求與預算設計合適的方案",
	"objection": "回應疑慮並提出合規的下一步",
}

var _clues_box: VBoxContainer
var _start: Button
var _known: Button
var _peek_pill: Button
var _portrait: Control
var _goal_rows: Array = []


func guide_lines() -> Array:
	return ["這是任務簡報：先看清楚站點、客戶和這次要完成的目標。", "準備好就按「開始任務」，會談計時從那一刻開始。"]


func key_rects() -> Array:
	return [rect_of(_start)]


func highlight_rects() -> Array:
	return [rect_of(_start)]


func build() -> void:
	timed = false
	dim_alpha = 0.45
	var sess := GameState.my_session()
	var c: Dictionary = sess.get("client", {})
	var step := str(sess.get("step", "discover"))
	var body := add_card()
	# 標題：抵達站點｜站名　　第 N / M 站
	var head := QuestUI.hbox(10)
	head.add_child(QuestUI.icon("target", 26.0 if not phone() else 20.0, QuestUI.GOLD))
	var where := _station_name(sess)
	var ttl := QuestUI.title("抵達站點｜%s" % where, 28 if not phone() else 20, QuestUI.TEXT)
	ttl.name = "BriefTitle"
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ttl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	head.add_child(ttl)
	var counter := QuestUI.label("%02d / %02d" % [GameState.current_stage(), GameState.total_stages()], 16, QuestUI.MUTED)
	counter.name = "StageCounter"
	counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(counter)
	body.add_child(head)
	# 任務類型與拜訪次數
	var visit := int(GameState.main_case().get("visits", 1))
	var kind := "轉介紹客戶" if bool(sess.get("referral", false)) else ("客戶初訪" if step == "discover" else ("第 %d 次會談" % maxi(visit, 2)))
	var chips := QuestUI.hbox(8)
	var type_chip := QuestUI.chip("任務類型：" + str(TITLES.get(step, "會談")), QuestUI.GREEN)
	type_chip.name = "MissionType"
	chips.add_child(type_chip)
	chips.add_child(QuestUI.chip(kind, QuestUI.GOLD))
	body.add_child(chips)
	var situation := str(c.get("intro", c.get("goal", "")))
	if situation != "":
		body.add_child(_boxed(QuestUI.label(situation, 15, QuestUI.TEXT, true)))
	# 客戶：頭像、姓名、身分職業、一句話
	var who := QuestUI.hbox(16)
	_portrait = QuestUI.portrait(GameState.client_portrait_id(), Vector2(110, 130) if not phone() else Vector2(68, 86))
	who.add_child(_portrait)
	var info := QuestUI.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(info)
	var name_row := QuestUI.hbox(10)
	var cname := QuestUI.title(str(c.get("name", "客戶")), 24 if not phone() else 18)
	cname.name = "ClientName"
	name_row.add_child(cname)
	if str(c.get("job", "")) != "":
		var job := QuestUI.label(str(c.job), 15, QuestUI.MUTED)
		job.name = "ClientJob"
		job.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(job)
	info.add_child(name_row)
	var quote := str(c.get("quote", ""))
	if quote != "":
		var q := QuestUI.hbox(8)
		q.add_child(QuestUI.label("「", 22, QuestUI.GOLD))
		var ql := QuestUI.label(quote.trim_prefix("「").trim_suffix("」"), 15, QuestUI.TEXT, true)
		ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		q.add_child(ql)
		info.add_child(q)
	var tw: Variant = sess.get("twist")
	if tw is Dictionary and str(tw.get("title", "")) != "":
		var row := QuestUI.hbox(6)
		row.add_child(QuestUI.icon("info", 16.0, QuestUI.GOLD))
		row.add_child(QuestUI.label("近況：" + str(tw.title), 14, QuestUI.GOLD, true))
		info.add_child(row)
	var note: Variant = GameState.flag("twist_note")
	if note is String and note != "":
		info.add_child(QuestUI.label("你的紀錄：" + str(note), 13, QuestUI.MUTED, true))
	body.add_child(who)
	# 本次目標
	var goal_bar := HBoxContainer.new()
	goal_bar.add_theme_constant_override("separation", 10)
	goal_bar.add_child(QuestUI.icon("target", 20.0, QuestUI.GOLD))
	var goal := QuestUI.label("本次目標：" + str(OBJECTIVES.get(step, OBJECTIVES.discover)), 17 if not phone() else 15, QuestUI.TEXT, true)
	goal.name = "MissionGoal"
	goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_bar.add_child(goal)
	body.add_child(_boxed(goal_bar))
	# 時間、難度、經驗
	var stats := QuestUI.hbox(18 if not phone() else 10)
	stats.add_child(_stat("clock", "可用會談時間", QuestUI.mmss(GameState.remaining_time()), "StatTime"))
	var diff := str(c.get("difficulty", ""))
	stats.add_child(_stat("chart", "任務難度", diff if diff != "" else "標準", "StatDifficulty"))
	stats.add_child(_stat("star", "可獲得經驗", "最高 +%d" % (80 if step == "discover" else 60), "StatXp"))
	body.add_child(stats)
	# 三格資訊：客戶背景／可用預算／風險線索
	var facts: BoxContainer = QuestUI.hbox(12) if not narrow() else QuestUI.vbox(8)
	facts.add_child(_fact("people", "客戶背景", _background(c), QuestUI.TEXT, "FactBackground"))
	facts.add_child(_fact("wallet", "可用預算", _budget(c), QuestUI.TEXT, "FactBudget"))
	facts.add_child(_fact("alert", "風險線索", _risk(c, sess), QuestUI.RED.lightened(0.15), "FactRisk"))
	body.add_child(facts)
	# 本站訓練目標（中性圓點，一個個出現）
	var grow: BoxContainer = QuestUI.hbox(18) if not narrow() else QuestUI.vbox(6)
	for g in GOALS.get(step, GOALS.discover):
		var r := QuestUI.hbox(8)
		r.add_child(QuestUI.icon("circle", 16.0, QuestUI.MUTED))
		r.add_child(QuestUI.label(str(g), 15))
		grow.add_child(r)
		_goal_rows.append(r)
	body.add_child(grow)
	# 精簡線索（就地展開）
	_clues_box = QuestUI.vbox(6)
	_clues_box.name = "ClientClues"
	_clues_box.visible = false
	body.add_child(_clues_box)
	# 按鈕
	var actions := QuestUI.hbox(12)
	_start = QuestUI.button("開始任務", _on_start, "primary", "next")
	_start.name = "StartMeeting"
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.size_flags_stretch_ratio = 1.4
	var map_btn: Button = QuestUI.button("返回地圖", _peek, "secondary", "map")
	map_btn.name = "PeekMap"
	map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_start)
	actions.add_child(map_btn)
	card_footer.add_child(actions)
	_known = QuestUI.button("查看客戶線索", _toggle_clues, "quiet", "search")
	_known.name = "KnownClues"
	_known.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_footer.add_child(_known)
	_peek_pill = QuestUI.button("回到任務簡報", _unpeek, "primary", "back")
	_peek_pill.name = "BackToBrief"
	_peek_pill.visible = false
	add_child(_peek_pill)


func _boxed(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(QuestUI.INK, 0.35)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(child)
	return p


func _fact(icon_kind: String, cap: String, text: String, head_color: Color, node_name: String) -> Control:
	var v := QuestUI.vbox(6)
	var h := QuestUI.hbox(6)
	h.add_child(QuestUI.icon(icon_kind, 18.0, head_color if head_color != QuestUI.TEXT else QuestUI.GOLD))
	h.add_child(QuestUI.label(cap, 15, head_color))
	v.add_child(h)
	var l := QuestUI.label(text, 14, QuestUI.MUTED, true)
	l.name = node_name
	v.add_child(l)
	var box := _boxed(v)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


func _background(c: Dictionary) -> String:
	var lines: Array = []
	var bits: Array = []
	if int(c.get("age", 0)) > 0:
		bits.append("%d 歲" % int(c.age))
	if str(c.get("family", "")) != "":
		bits.append(str(c.family))
	if not bits.is_empty():
		lines.append("・".join(bits))
	if str(c.get("job", "")) != "":
		lines.append(str(c.job))
	if str(c.get("goal", "")) != "":
		lines.append("目標：" + str(c.goal))
	return "\n".join(lines) if not lines.is_empty() else "會談中再了解"


## 可負擔預算：有收支資料時算每月可支配，否則用收入說明與目標金額
func _budget(c: Dictionary) -> String:
	var lines: Array = []
	var f: Variant = c.get("finance")
	if f is Dictionary and int(f.get("income", 0)) > 0:
		var spare := int(f.get("income", 0)) - int(f.get("expense", 0))
		lines.append("每月可支配約 %s" % _money(spare))
		if int(f.get("savings", 0)) > 0:
			lines.append("存款約 %s" % _money(int(f.savings)))
	elif str(c.get("incomeInfo", "")) != "":
		lines.append(str(c.incomeInfo))
	if str(c.get("amount", "")) != "":
		lines.append("目標金額 " + str(c.amount))
	return "\n".join(lines) if not lines.is_empty() else "會談中再確認"


## 初步風險線索：這次的近況變化，否則客戶類型；細節要在會談中確認
func _risk(c: Dictionary, sess: Dictionary) -> String:
	var lines: Array = []
	var tw: Variant = sess.get("twist")
	if tw is Dictionary and str(tw.get("title", "")) != "":
		lines.append(str(tw.title))
	if str(c.get("tag", "")) != "":
		lines.append("客戶類型：" + str(c.tag))
	lines.append("細節需在會談中確認")
	return "\n".join(lines)


static func _money(v: int) -> String:
	if absi(v) >= 10000:
		var wan := v / 10000.0
		return ("%d 萬" % int(wan)) if is_equal_approx(wan, roundf(wan)) else ("%.1f 萬" % wan)
	return "%d 元" % v


func on_open() -> void:
	await enter()
	if QuestUI.motion_off():
		return
	# Portrait rises, goals appear one by one
	if is_instance_valid(_portrait):
		_portrait.modulate.a = 0.0
		var tw := _portrait.create_tween()
		tw.tween_interval(0.15)
		tw.tween_property(_portrait, "modulate:a", 1.0, 0.3)
	for i in range(_goal_rows.size()):
		var r: Control = _goal_rows[i]
		r.modulate.a = 0.0
		var tw2 := r.create_tween()
		tw2.tween_interval(0.3 + i * 0.12)
		tw2.tween_property(r, "modulate:a", 1.0, 0.22)
	_start.grab_focus.call_deferred()


func _ornament() -> Control:
	var c := Ornament.new()
	c.custom_minimum_size = Vector2(70 if not phone() else 34, 16)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _stat(icon_kind: String, cap: String, val: String, node_name := "") -> Control:
	var h := QuestUI.hbox(8)
	h.add_child(QuestUI.icon(icon_kind, 20.0, QuestUI.GOLD))
	var v := QuestUI.vbox(0)
	v.add_child(QuestUI.label(cap, 12, QuestUI.MUTED))
	var l := QuestUI.label(val, 16, QuestUI.TEXT, false, true)
	if node_name != "":
		l.name = node_name
	v.add_child(l)
	h.add_child(v)
	return h


func _station_name(sess: Dictionary) -> String:
	var b := GameState.board()
	var i := int(sess.get("tileIndex", GameState.current_node()))
	if i >= 0 and i < b.size():
		return str((b[i] as Dictionary).get("name", "客戶據點"))
	return "客戶據點"


func _toggle_clues() -> void:
	_clues_box.visible = not _clues_box.visible
	_known.text = "收起客戶線索" if _clues_box.visible else "查看客戶線索"
	if _clues_box.visible:
		UI.clear(_clues_box)
		var sess := GameState.my_session()
		var c: Dictionary = sess.get("client", {})
		_clues_box.add_child(QuestUI.header("doc", "已知資料"))
		for pair in [["人生目標", c.get("goal", "")], ["家庭", c.get("family", "")], ["收入", c.get("incomeInfo", "")], ["目標金額", c.get("amount", "")]]:
			if str(pair[1]) != "":
				_clues_box.add_child(QuestUI.label("%s：%s" % [pair[0], pair[1]], 14, QuestUI.TEXT, true))
		var found := GameState.client_needs()
		if found.is_empty():
			_clues_box.add_child(QuestUI.label("會談中的線索還沒有取得——觀察與提問後才會出現在這裡。", 14, QuestUI.MUTED, true))
		else:
			_clues_box.add_child(QuestUI.label("已取得的線索：", 14, QuestUI.GOLD))
			for f in found:
				_clues_box.add_child(QuestUI.label("・" + str(f), 14, QuestUI.TEXT, true))
	relayout()


## 返回地圖：卡片收起、地圖恢復亮度，這次抽出的客戶與會談保留，「回到任務簡報」再叫回
func _peek() -> void:
	QuestFlow.go(QuestFlow.MAP_IDLE, "返回地圖（客戶保留）")
	card.visible = false
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_peek_pill.visible = true
	_peek_pill.reset_size()
	_peek_pill.position = Vector2((size.x - _peek_pill.size.x) * 0.5, size.y - _peek_pill.size.y - 24)


func _unpeek() -> void:
	QuestFlow.go(QuestFlow.MISSION_BRIEFING, "回到任務簡報")
	_peek_pill.visible = false
	card.visible = true
	dim.visible = true
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_start() -> void:
	if not QuestFlow.claim():
		return
	_start.call("set_loading", true, "準備會談")
	AudioManager.play("confirm_soft")
	go.emit("start_meeting", {})


class Ornament extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := size.y * 0.5
		draw_line(Vector2(0, y), Vector2(size.x - 10, y), Color(QuestUI.GOLD, 0.8), 1.0, true)
		var c := Vector2(size.x - 5, y)
		var pts := PackedVector2Array([c + Vector2(0, -5), c + Vector2(3, 0), c + Vector2(0, 5), c + Vector2(-3, 0)])
		draw_colored_polygon(pts, QuestUI.GOLD)
