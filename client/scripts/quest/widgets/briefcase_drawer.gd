extends Control
## BriefcaseDrawer：顧問公事包道具抽屜（由右側滑出）。列出會前準備帶的道具：插圖、名稱、一句
## 用途、可使用次數、適用時機與實際效果。
## 道具效果由後端規則引擎在會談開始時套用（對話 +1 輪、開場線索、自由提問 +1、合規扣分減半）；
## 需要主動使用的道具按「使用」後才顯示後端這次給的資料（核心保障建議、合理配置區間）或開啟
## 多出來的自由提問。每次使用都寫進本局道具紀錄與決策紀錄，培訓報告會用到。
## 抽屜開著時只有它能操作；關閉時整個節點移除，不留下攔截滑鼠的元件。

signal closed
signal free_question_requested

const BriefcaseData := preload("res://scripts/briefcase_data.gd")

const RES := [["cash", "緊急預備"], ["protect", "風險保障"], ["growth", "目標成長"]]
const WHEN := {
	"needs_form": "需求訪談時",
	"cashflow": "會談開場",
	"family_map": "想多問一題時",
	"gap_sheet": "決定核心保障前",
	"risk_survey": "分配預算前",
	"compliance_check": "說明方案、回應疑慮時",
}
## 對信任、需求判斷、時間或合規的影響
const IMPACT := {
	"needs_form": "需求判斷：多 1 輪對話可多問一次目標與優先順序",
	"cashflow": "需求判斷：開場就掌握 1 條真實需求線索",
	"family_map": "需求判斷：多 1 次自由提問，可追問扶養與家庭責任",
	"gap_sheet": "需求判斷：顯示這位客戶最該優先處理的保障",
	"risk_survey": "預算：顯示合理的配置區間，避免超出負擔",
	"compliance_check": "合規：對話中的合規扣分減半，合規檢核可免一次誤判",
}

var _panel: PanelContainer
var _list: VBoxContainer
var _dim: ColorRect
var _closing := false


func _init() -> void:
	name = "BriefcaseDrawer"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40


func _ready() -> void:
	GameState.hold("briefcase", true)
	tree_exited.connect(func(): GameState.hold("briefcase", false))
	_dim = ColorRect.new()
	_dim.color = Color(QuestUI.INK, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.name = "DrawerPanel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0D4038", 0.98)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(QuestUI.GOLD, 0.45)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 16
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := QuestUI.vbox(12)
	_panel.add_child(v)
	var head := QuestUI.hbox(8)
	head.add_child(QuestUI.icon("briefcase", 24.0, QuestUI.GOLD))
	var t := QuestUI.title("顧問公事包", 22)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x: Button = QuestUI.button("", close, "quiet", "close")
	x.name = "CloseDrawer"
	x.tooltip_text = "關閉公事包"
	x.custom_minimum_size = Vector2(44, 44)
	head.add_child(x)
	v.add_child(head)
	v.add_child(QuestUI.label("會前準備帶來的工具。效果由規則引擎在會談中實際執行。", 13, QuestUI.MUTED, true))
	_list = QuestUI.vbox(10)
	_list.name = "ToolList"
	var sc := QuestUI.scroll(_list)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	resized.connect(_place)
	_build()
	_place()
	# 抽屜由右側滑入
	if QuestUI.motion_off():
		_dim.color.a = 0.45
		return
	var final_x := _panel.position.x
	_panel.position.x = size.x
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "color:a", 0.45, 0.25)
	tw.tween_property(_panel, "position:x", final_x, 0.3)


func _place() -> void:
	if _panel == null:
		return
	var w := minf(460.0, size.x - 24.0)
	_panel.size = Vector2(w, size.y - 24.0)
	_panel.position = Vector2(size.x - w - 12.0, 12.0)


func close() -> void:
	if _closing:
		return
	_closing = true
	GameState.hold("briefcase", false)
	AudioManager.play("ui_back")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if QuestUI.motion_off():
		closed.emit()
		queue_free()
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_dim, "color:a", 0.0, 0.2)
	tw.tween_property(_panel, "position:x", size.x, 0.22)
	tw.chain().tween_callback(func():
		closed.emit()
		queue_free()
	)


## 帶了哪些道具（後端 p.briefcase）
static func packed() -> Array:
	return Net.me().get("briefcase", [])


static func tool_def(id: String) -> Dictionary:
	for d in BriefcaseData.tool_defs():
		if str((d as Dictionary).get("id", "")) == id:
			return d
	return {"id": id, "name": id, "effect": ""}


func _build() -> void:
	UI.clear(_list)
	var tools := packed()
	if tools.is_empty():
		_list.add_child(QuestUI.label("這次沒有攜帶工具。會前準備的「選工具」步驟可以帶 3 樣。", 14, QuestUI.MUTED, true))
		return
	for t in tools:
		_list.add_child(_tool_card(str(t)))


func _tool_card(id: String) -> Control:
	var d := tool_def(id)
	var sess := GameState.my_session()
	var used: Dictionary = GameState.record.get("tools", {})
	var card := PanelContainer.new()
	card.name = "Tool_" + id
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(QuestUI.INK, 0.35)
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	var h := QuestUI.hbox(12)
	card.add_child(h)
	h.add_child(_tool_image(d))
	var v := QuestUI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(QuestUI.label(str(d.get("name", id)), 16, QuestUI.TEXT, false, true))
	v.add_child(QuestUI.label(str(d.get("effect", "")), 13, QuestUI.MUTED, true))
	v.add_child(_kv("可使用次數", _uses(id, sess)))
	v.add_child(_kv("適用時機", str(WHEN.get(id, "會談中"))))
	v.add_child(_kv("實際效果", str(IMPACT.get(id, ""))))
	var status := _status(id, sess, used)
	if status != "":
		var st := QuestUI.label(status, 13, QuestUI.GREEN.lightened(0.2), true)
		st.name = "Status"
		v.add_child(st)
	var action := _action(id, sess, used)
	if action != null:
		v.add_child(action)
	return card


func _tool_image(d: Dictionary) -> Control:
	var path := str(d.get("image", ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(64, 64)
		tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		tr.material = UI.get_rounded_material(0.12)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var ic := QuestUI.icon("briefcase", 40.0, QuestUI.GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return ic


func _kv(k: String, val: String) -> Control:
	var h := QuestUI.hbox(6)
	var kl := QuestUI.label(k, 12, QuestUI.GOLD)
	kl.custom_minimum_size = Vector2(70, 0)
	h.add_child(kl)
	var vl := QuestUI.label(val, 13, QuestUI.TEXT, true)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	return h


func _uses(id: String, sess: Dictionary) -> String:
	match id:
		"needs_form": return "首次會談自動 +1 輪（目前對話剩 %d 輪）" % int(sess.get("talkLeft", 0)) if not sess.is_empty() else "首次會談自動 +1 輪"
		"cashflow": return "會談開場自動 1 次"
		"family_map": return "自由提問剩 %d 次" % int(sess.get("freeLeft", 0)) if not sess.is_empty() else "自由提問 +1 次"
		"gap_sheet", "risk_survey": return "每次會談可查看 1 次"
		"compliance_check": return "整個案件全程生效"
	return "—"


func _status(id: String, sess: Dictionary, used: Dictionary) -> String:
	var hints: Dictionary = sess.get("toolHints", {}) if sess.get("toolHints") is Dictionary else {}
	match id:
		"needs_form", "cashflow", "compliance_check":
			return "已生效"
		"gap_sheet":
			if used.has(id) and hints.has("coreCards"):
				return "核心保障建議：" + _card_names(hints.coreCards)
		"risk_survey":
			if used.has(id) and hints.has("ideal"):
				var parts: Array = []
				var ideal: Dictionary = hints.ideal
				for spec in RES:
					var r: Array = ideal.get(spec[0], [])
					if r.size() == 2:
						parts.append("%s %d–%d" % [spec[1], int(r[0]), int(r[1])])
				return "合理配置區間：" + "、".join(parts)
	return ""


func _action(id: String, sess: Dictionary, used: Dictionary) -> Control:
	var hints: Dictionary = sess.get("toolHints", {}) if sess.get("toolHints") is Dictionary else {}
	var b: Button = null
	match id:
		"family_map":
			var left := int(sess.get("freeLeft", 0))
			b = QuestUI.button("使用：多問一題", func(): _use(id), "secondary", "chat")
			b.call("set_reason", "" if left > 0 and str(sess.get("step", "")) == "discover" else "需求訪談時才能使用")
		"gap_sheet":
			if used.has(id):
				return null
			b = QuestUI.button("使用：查看核心保障建議", func(): _use(id), "secondary", "shield")
			b.call("set_reason", "" if hints.has("coreCards") else "會談開始後才能使用")
		"risk_survey":
			if used.has(id):
				return null
			b = QuestUI.button("使用：查看合理配置區間", func(): _use(id), "secondary", "chart")
			b.call("set_reason", "" if hints.has("ideal") else "會談開始後才能使用")
	if b != null:
		b.name = "UseTool_" + id
	return b


func _use(id: String) -> void:
	if GameState.record.is_empty():
		push_error("公事包：本局紀錄尚未建立，無法使用「%s」" % id)
		return
	var d := tool_def(id)
	var used: Dictionary = GameState.record.get("tools", {})
	used[id] = true
	GameState.record["tools"] = used
	var uses: Dictionary = GameState.record.get("tool_uses", {})
	uses[id] = int(uses.get(id, 0)) + 1
	GameState.record["tool_uses"] = uses
	GameState.add_decision("公事包", "使用：" + str(d.get("name", id)), str(IMPACT.get(id, "")), "ok", {"tool": id})
	AudioManager.play("card_flip")
	if id == "family_map":
		free_question_requested.emit()
		close()
		return
	_build()


func _card_names(ids: Array) -> String:
	var out: Array = []
	for cd in Net.static_data.get("cards", []):
		if ids.has(str((cd as Dictionary).get("id", ""))):
			out.append(str(cd.get("title", "")))
	return "、".join(out)
