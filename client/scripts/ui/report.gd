extends Control
## 結算報告：排名、個人五力、AI 教練回饋、關鍵決策回顧。支援直向上下分欄。

var main: Node
var _v: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad: int = 12 if UI.is_phone_portrait() else (16 if UI.is_portrait() else 32)
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, pad)
	add_child(m)
	_v = UI.vbox(14)
	_scroll = UI.scroll(_v)
	m.add_child(_scroll)
	if not Net.state.is_empty():
		refresh(Net.state)


func on_layout_changed(_is_portrait: bool) -> void:
	if not Net.state.is_empty():
		refresh(Net.state)


func refresh(s: Dictionary) -> void:
	UI.clear(_v)
	var portrait: bool = UI.is_portrait()

	var head := UI.hbox(8 if UI.is_phone_portrait() else 10)
	head.add_child(UI.label("顧問結算報告", 20 if UI.is_phone_portrait() else (24 if portrait else 32), UI.ACCENT_2))
	head.add_child(UI.spacer())
	if Net.is_logged_in():
		head.add_child(UI.label("✓ 紀錄已保存", 13, UI.GOOD))
		head.add_child(UI.button("查看我的成長", func(): Net.leave(); main.show_records(), 14 if UI.is_phone_portrait() else 15, UI.ACCENT))
	else:
		head.add_child(UI.label("登入後可保存紀錄", 13, UI.MUTED))
		head.add_child(UI.button("培訓紀錄", func(): Net.leave(); main.show_records(), 14 if UI.is_phone_portrait() else 15, UI.PANEL_2))
	head.add_child(UI.button("回主選單", func(): main.leave_to_menu(), 14 if UI.is_phone_portrait() else 15))
	_v.add_child(head)
	_v.add_child(UI.label("評分＝專業五力 50%＋滿意度 25%＋聲望 15%＋業績 10%。不適合的銷售會在稽核中被扣分。", 13 if portrait else 14, UI.MUTED, true))

	var final: Array = s.get("final", []) if s.get("final") != null else []
	var rank: int = 1
	var mine: Dictionary = {}
	for r: Dictionary in final:
		if str(r.get("playerId", "")) == Net.player_id:
			mine = r
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
		nv.add_child(UI.label("客戶 %d 位・滿意度 %d・聲望 %d・業績 %d" % [int(r.get("clients", 0)), int(r.get("service", 0)), int(r.get("reputation", 0)), int(r.get("commission", 0))], 12 if UI.is_phone_portrait() else (13 if portrait else 14), UI.MUTED, true))
		for cap in (r.get("caps", []) as Array):
			nv.add_child(UI.label("評級上限：" + str(cap), 12 if UI.is_phone_portrait() else 13, UI.OK, true))
		h.add_child(nv)
		row.add_child(h)
		_v.add_child(row)
		rank += 1

	# 榮譽勳章牆（終局特別獎項）
	var awards: Array = s.get("awards", []) if s.get("awards") != null else []
	if not awards.is_empty():
		var aw_panel := UI.panel(Color("#102b3a"), 14, 12)
		aw_panel.add_theme_stylebox_override("panel", UI.box(Color("#102b3a"), 14, UI.GOLD, 8, false))
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
			var card_bg: Color = Color("#173c52") if is_my_award else Color("#0e222e")
			var card_border: Color = UI.GOLD if is_my_award else Color("#21495e")
			var ac := UI.panel(card_bg, 10, 10)
			ac.add_theme_stylebox_override("panel", UI.box(card_bg, 10, card_border, 8, false))
			# 自動換行的 Label 最小寬度為 0，格子不撐開會被擠成一字一行
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

	# 直向時五力與教練回饋上下堆疊
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
	ct.add_child(UI.label(str(mine.get("coach", "")), 15 if portrait else 16, UI.TEXT, true))
	cv.add_child(ct)
	coach.add_child(cv)
	body.add_child(coach)
	_v.add_child(body)

	var me: Dictionary = Net.me()
	var ds: Array = me.get("decisions", [])
	if not ds.is_empty():
		var dp := UI.panel()
		var dv := UI.vbox(6)
		dv.add_child(UI.label("關鍵決策回顧（最近 12 項）", 17 if portrait else 18, UI.ACCENT_2))
		for d: Dictionary in ds:
			var q: String = str(d.get("quality", ""))
			var mark: String = {"good": "✓", "ok": "△", "bad": "×"}.get(q, "・")
			dv.add_child(UI.label("%s 第%d回合｜%s｜%s：%s" % [mark, int(d.get("round", 1)), d.get("clientName", ""), d.get("stage", ""), d.get("title", "")], 14 if portrait else 15, UI.tone_color(q), true))
			dv.add_child(UI.label("　" + str(d.get("body", "")), 13, UI.MUTED, true))
		dp.add_child(dv)
		_v.add_child(dp)

	UI.pass_wheel(_v)
