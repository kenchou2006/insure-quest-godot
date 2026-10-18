extends "res://scripts/quest/pages/modal_base.gd"
## ArrivalBriefModal (page 2) — 抵達新站點. One look tells: where, who, what now.
## Station, client portrait and name, current situation, this meeting's training goals, time left
## and the metrics that can move. 開始會談 starts the meeting, 查看已有線索 opens what is already
## known, 查看地圖 folds the brief so the map can be checked (a pill brings it back).
## Nothing here hints at an answer: goals are neutral circles, no colours or links per option.

const GOALS := {
	"discover": ["了解客戶背景", "找出真正的需求", "全程維持合規"],
	"plan": ["依需求配置預算", "選出核心保障", "守住每月預算"],
	"objection": ["理解客戶的疑慮", "釐清真正的擔心", "提出合規的下一步"],
}
const TITLES := {"discover": "需求探索", "plan": "方案設計", "objection": "疑慮回應"}

var _clues_box: VBoxContainer
var _start: Button
var _peek_pill: Button
var _portrait: Control
var _goal_rows: Array = []


func guide_lines() -> Array:
	return ["這是到站簡報：先看清楚地點、客戶和這次會談要完成的事。", "準備好就按「開始會談」，會談計時從那一刻開始。"]


func key_rects() -> Array:
	return [rect_of(_start)]


func highlight_rects() -> Array:
	return [rect_of(_start)]


func build() -> void:
	timed = false
	var sess := GameState.my_session()
	var c: Dictionary = sess.get("client", {})
	var step := str(sess.get("step", "discover"))
	var body := add_card()
	# Title with the gold ornaments
	var head := QuestUI.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(_ornament())
	var t := QuestUI.title("抵達新站點", 30 if not phone() else 22, QuestUI.TEXT)
	head.add_child(t)
	head.add_child(_ornament())
	body.add_child(head)
	# Visit type chip
	var visit := int(GameState.main_case().get("visits", 1))
	var kind := "轉介紹客戶" if bool(sess.get("referral", false)) else ("客戶初訪" if step == "discover" else ("第 %d 次會談" % maxi(visit, 2)))
	var chip_row := QuestUI.hbox(8)
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chip_row.add_child(QuestUI.chip(kind, QuestUI.GOLD))
	body.add_child(chip_row)
	var where := _station_name(sess)
	var ttl := QuestUI.title("%s｜%s" % [where, TITLES.get(step, "會談")], 26 if not phone() else 19, QuestUI.TEXT)
	ttl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ttl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(ttl)
	# Client: portrait + who + situation
	var who := QuestUI.hbox(16)
	_portrait = QuestUI.portrait(GameState.client_portrait_id(), Vector2(96, 120) if not phone() else Vector2(68, 86))
	who.add_child(_portrait)
	var info := QuestUI.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.add_child(info)
	info.add_child(QuestUI.title(str(c.get("name", "客戶")), 22 if not phone() else 18))
	var bits: Array = []
	if int(c.get("age", 0)) > 0:
		bits.append("%d 歲" % int(c.age))
	for k in ["job", "family"]:
		if str(c.get(k, "")) != "":
			bits.append(str(c[k]))
	info.add_child(QuestUI.label("・".join(bits), 14, QuestUI.MUTED, true))
	var situation := str(c.get("intro", c.get("goal", "")))
	if situation != "":
		info.add_child(QuestUI.label("當前情境：" + situation, 15, QuestUI.TEXT, true))
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
	# This meeting's goals (neutral circles, appear one by one) — in a row on wide screens
	var goals_card := QuestUI.card(null, 0.6)
	var gv := QuestUI.vbox(8)
	goals_card.add_child(gv)
	gv.add_child(QuestUI.header("target", "本站訓練目標"))
	var grow: BoxContainer = QuestUI.hbox(18) if not narrow() else QuestUI.vbox(6)
	gv.add_child(grow)
	for g in GOALS.get(step, GOALS.discover):
		var r := QuestUI.hbox(8)
		r.add_child(QuestUI.icon("circle", 18.0, QuestUI.MUTED))
		r.add_child(QuestUI.label(str(g), 16))
		grow.add_child(r)
		_goal_rows.append(r)
	body.add_child(goals_card)
	# Clock and the metrics that can move
	var stats := QuestUI.hbox(18 if not phone() else 10)
	stats.add_child(_stat("clock", "剩餘時間", QuestUI.mmss(GameState.remaining_time())))
	stats.add_child(_stat("star", "可得經驗", "最高 +%d" % (80 if step == "discover" else 60)))
	stats.add_child(_stat("chart", "可能影響", "信任・需求・合規"))
	body.add_child(stats)
	# Known so far (folded)
	_clues_box = QuestUI.vbox(6)
	_clues_box.visible = false
	body.add_child(_clues_box)
	# Actions
	var actions := QuestUI.hbox(12)
	_start = QuestUI.button("開始會談", _on_start, "primary", "next")
	_start.name = "StartMeeting"
	_start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start.size_flags_stretch_ratio = 1.4
	var known: Button = QuestUI.button("查看已有線索", _toggle_clues, "secondary", "search")
	known.name = "KnownClues"
	known.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_start)
	actions.add_child(known)
	card_footer.add_child(actions)
	var map_btn: Button = QuestUI.button("查看地圖", _peek, "quiet", "map")
	map_btn.name = "PeekMap"
	map_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_footer.add_child(map_btn)
	_peek_pill = QuestUI.button("回到任務簡報", _unpeek, "primary", "back")
	_peek_pill.name = "BackToBrief"
	_peek_pill.visible = false
	add_child(_peek_pill)


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


func _stat(icon_kind: String, cap: String, val: String) -> Control:
	var h := QuestUI.hbox(8)
	h.add_child(QuestUI.icon(icon_kind, 20.0, QuestUI.GOLD))
	var v := QuestUI.vbox(0)
	v.add_child(QuestUI.label(cap, 12, QuestUI.MUTED))
	v.add_child(QuestUI.label(val, 16, QuestUI.TEXT, false, true))
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


func _peek() -> void:
	card.visible = false
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_peek_pill.visible = true
	_peek_pill.reset_size()
	_peek_pill.position = Vector2((size.x - _peek_pill.size.x) * 0.5, size.y - _peek_pill.size.y - 24)


func _unpeek() -> void:
	_peek_pill.visible = false
	card.visible = true
	dim.visible = true
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_filter = Control.MOUSE_FILTER_STOP


func _on_start() -> void:
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
