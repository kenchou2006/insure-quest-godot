extends Control
## DecisionReview：查看決策回顧。本局每一個選擇（需求訪談、線索分類、方案、異議回應、合規檢核、
## 公事包使用、事件回應……）依時間排列：做了什麼、結果好壞、原因與數值影響。
## 資料來自本局決策紀錄（GameState），也是最後 AI 培訓報告的依據；這裡只讀不改。
## 關閉時整個節點移除，不留下攔截滑鼠的元件。

signal closed

const STAGE_ICONS := {"需求訪談": "chat", "線索分類": "search", "方案設計": "chart", "異議回應": "handshake", "合規檢核": "shield", "公事包": "briefcase", "經驗值": "star"}


func _init() -> void:
	name = "DecisionReview"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 60


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(QuestUI.INK, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := QuestUI.card(null, 1.0, Color(QuestUI.GOLD, 0.5))
	card.name = "ReviewCard"
	var vs := get_viewport_rect().size
	card.custom_minimum_size = Vector2(minf(720.0, vs.x - 32.0), minf(560.0, vs.y - 48.0))
	center.add_child(card)
	var v := QuestUI.vbox(10)
	card.add_child(v)
	var head := QuestUI.hbox(8)
	var t := QuestUI.header("doc", "決策回顧")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var x: Button = QuestUI.button("", close, "quiet", "close")
	x.name = "CloseReview"
	x.tooltip_text = "關閉決策回顧"
	x.custom_minimum_size = Vector2(44, 44)
	head.add_child(x)
	v.add_child(head)
	v.add_child(QuestUI.label("本局每一個選擇與原因。培訓報告會依這些紀錄寫個人化回饋；分數由規則引擎計算。", 13, QuestUI.MUTED, true))
	var list := QuestUI.vbox(8)
	list.name = "DecisionList"
	var sc := QuestUI.scroll(list)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var ds: Array = GameState.decision_history()
	if ds.is_empty():
		list.add_child(QuestUI.label("這一局還沒有留下決策紀錄。", 14, QuestUI.MUTED))
	for d in ds:
		var dd := d as Dictionary
		if str(dd.get("stage", "")) == "經驗值":
			continue
		list.add_child(_row(dd))
	var ok: Button = QuestUI.button("返回結算", close, "primary", "back")
	ok.name = "ReviewDone"
	v.add_child(ok)
	if not QuestUI.motion_off():
		QuestUI.fade_in(card, 0.0, 0.25, 0.0)


func close() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	AudioManager.play("ui_back")
	closed.emit()
	queue_free()


func _row(d: Dictionary) -> Control:
	var q := str(d.get("quality", ""))
	var col: Color = QuestUI.GREEN if q == "good" else (QuestUI.RED if q == "bad" else QuestUI.GOLD)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", QuestUI.card_box(0.5, Color(col, 0.35), 12, 10))
	var h := QuestUI.hbox(10)
	p.add_child(h)
	var ic := QuestUI.icon(str(STAGE_ICONS.get(str(d.get("stage", "")), "circle")), 20.0, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := QuestUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := QuestUI.hbox(8)
	top.add_child(QuestUI.label(str(d.get("stage", "")), 12, QuestUI.GOLD))
	if int(d.get("round", 0)) > 0:
		top.add_child(QuestUI.label("第 %d 站" % int(d.round), 12, QuestUI.MUTED))
	top.add_child(QuestUI.spacer())
	top.add_child(QuestUI.label({"good": "做得好", "bad": "需要加強"}.get(q, "一般"), 12, col))
	v.add_child(top)
	v.add_child(QuestUI.label(str(d.get("title", "")), 14, QuestUI.TEXT, true, true))
	if str(d.get("detail", "")) != "":
		v.add_child(QuestUI.label(str(d.detail), 13, QuestUI.MUTED, true))
	var fx: Variant = d.get("effects")
	if fx is Dictionary and not (fx as Dictionary).is_empty():
		var parts: Array = []
		for k in ["trust", "insight", "compliance"]:
			if (fx as Dictionary).has(k) and int(fx[k]) != 0:
				parts.append("%s %s%d" % [{"trust": "信任", "insight": "需求", "compliance": "合規"}[k], "+" if int(fx[k]) > 0 else "", int(fx[k])])
		if not parts.is_empty():
			v.add_child(QuestUI.label("　".join(parts), 12, QuestUI.TEXT))
	return p
