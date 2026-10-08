extends PanelContainer
## 事件面板：人生事件、市場快訊、合規測驗、合規抉擇、客戶回訪、稽核、季度結算、研討會。

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


func _ready() -> void:
	var pad: int = 10 if UI.is_phone_portrait() else (14 if UI.is_portrait() else 22)
	add_theme_stylebox_override("panel", UI.box(Color("#102a37"), 18, Color("#2d5a6e"), pad))
	_v = UI.vbox(12)
	_scroll = UI.scroll(_v)
	add_child(_scroll)


func refresh(ev: Dictionary, actor_name: String) -> void:
	UI.clear(_v)
	var actor: bool = str(ev.get("playerId", "")) == Net.player_id
	var kind: String = str(ev.get("kind", "info"))
	var title: String = str(ev.get("title", ""))

	var dilemma = ev.get("dilemma")
	var review = ev.get("review")

	if title == "" and dilemma is Dictionary:
		title = str(dilemma.get("title", "情境合規抉擇"))
	elif title == "" and review is Dictionary:
		title = "客戶回訪：%s" % str(review.get("clientName", "已簽約客戶"))

	if title != "" and title != _last_ev_title:
		_last_ev_title = title
		Sound.play("ding", self)

	var icons: Dictionary = {
		"life": "✚ 人生事件",
		"market": "市 市場快訊",
		"quiz": "訓 合規訓練",
		"audit": "稽 合規稽核",
		"settlement": "★ 季度結算",
		"seminar": "研 顧問研討會",
		"dilemma": "訓 合規情境抉擇",
		"review": "◎ 客戶回訪",
		"info": "※ 提示"
	}
	var colors: Dictionary = {
		"life": UI.TILE_COLORS["life"],
		"market": UI.TILE_COLORS["market"],
		"quiz": UI.TILE_COLORS["training"],
		"audit": UI.TILE_COLORS["audit"],
		"settlement": UI.TILE_COLORS["start"],
		"seminar": UI.TILE_COLORS["seminar"],
		"dilemma": UI.GOLD,
		"review": UI.ACCENT_2,
	}
	var head := UI.hbox(10)
	head.add_child(UI.label(icons.get(kind, "事件"), 16, colors.get(kind, UI.INFO)))
	head.add_child(UI.spacer())
	head.add_child(UI.label(("你的回合" if actor else "觀看中：%s 的回合" % actor_name), 14, UI.GOLD if actor else UI.MUTED))
	_v.add_child(head)

	if not actor:
		var obs := UI.panel(Color("#143547"), 8, 8)
		obs.add_theme_stylebox_override("panel", UI.box(Color("#143547"), 8, UI.GOLD, 8, false))
		var obsv := UI.vbox(2)
		obsv.add_child(UI.label("★ 觀摩學習中 ｜ %s 正在處理此事件" % actor_name, 13 if UI.is_phone_portrait() else 14, UI.GOLD, true))
		var tip_msg := "觀察其決策與作答，思考若換成自己會如何處理。"
		if kind == "dilemma":
			tip_msg = "觀察其面對利益與合規衝突時的價值抉擇。"
		elif kind == "review":
			tip_msg = "觀察其對既有客戶人生變化的保障健檢建議。"
		obsv.add_child(UI.label(tip_msg, 11 if UI.is_phone_portrait() else 12, UI.TEXT, true))
		obs.add_child(obsv)
		_v.add_child(obs)

	_v.add_child(UI.label(title, 22 if UI.is_portrait() else 26, UI.TEXT, true))
	var body_txt: String = str(ev.get("body", ""))
	if body_txt != "":
		_v.add_child(UI.label(body_txt, 15 if UI.is_portrait() else 17, UI.MUTED, true))

	# ───────── 1. 合規情境抉擇（dilemma）─────────
	if dilemma is Dictionary:
		_build_dilemma_ui(dilemma, actor)

	# ───────── 2. 客戶生命週期回訪（review）─────────
	elif review is Dictionary:
		_build_review_ui(review, actor)

	# ───────── 3. 合規測驗（quiz）─────────
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
			i += 1

	# ───────── 4. 一般事件動態回饋行 ─────────
	var lines: Array = ev.get("lines", [])
	for line: Dictionary in lines:
		var p := UI.panel(UI.PANEL, 10, 10)
		p.add_child(UI.label(str(line.get("text", "")), 15 if UI.is_portrait() else 16, UI.tone_color(str(line.get("tone", "info"))), true))
		_v.add_child(p)

	# ───────── 5. 繼續按鈕與觀看提示 ─────────
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

	UI.fade_in(_v, 0.2)
	UI.pass_wheel(_v)


func _build_dilemma_ui(dilemma: Dictionary, actor: bool) -> void:
	var prompt_txt: String = str(dilemma.get("prompt", ""))
	if prompt_txt != "":
		var prompt_box := UI.panel(Color("#163242"), 10, 10)
		prompt_box.add_child(UI.label(prompt_txt, 15 if UI.is_portrait() else 16, UI.TEXT, true))
		_v.add_child(prompt_box)

	var picked = dilemma.get("picked")
	var choices: Array = dilemma.get("choices", [])
	for c: Dictionary in choices:
		var cid: String = str(c.get("id", ""))
		var ctext: String = str(c.get("text", ""))
		var is_picked: bool = picked != null and str(picked) == cid
		var btn_col: Color = UI.ACCENT.darkened(0.3) if is_picked else UI.PANEL_2
		var btn := UI.option_button("【%s】 %s" % [cid, ctext], func():
			Net.act({"type": "choose_dilemma", "choice": cid})
		, btn_col)
		btn.disabled = not actor or picked != null
		_v.add_child(btn)

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


func _build_review_ui(review: Dictionary, actor: bool) -> void:
	var cname: String = str(review.get("clientName", "客戶"))
	var change: Dictionary = review.get("change", {})
	var change_title: String = str(change.get("title", "生活新變化"))
	var change_body: String = str(change.get("body", ""))

	# 客戶生活變化說明卡
	var chg_panel := UI.panel(Color("#133647"), 10, 10)
	var chg_v := UI.vbox(4)
	chg_v.add_child(UI.label("【%s 的人生轉折】%s" % [cname, change_title], 16, UI.GOLD, true))
	if change_body != "":
		chg_v.add_child(UI.label(change_body, 14, UI.TEXT, true))
	chg_panel.add_child(chg_v)
	_v.add_child(chg_panel)

	# 目前配置狀況
	var cur_data: Dictionary = review.get("current", {})
	var cur_alloc: Dictionary = cur_data.get("alloc", {})
	var cur_cards: Array = cur_data.get("cards", [])
	var cur_panel := UI.panel(Color("#0d2432"), 8, 8)
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

	# 6 張保障卡按鈕網格
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
			btn_col = Color("#172e3a")
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

	_v.add_child(grid)

	# 額外 2 個決策選項：現有規劃已足夠、先不聯絡
	var none_picked: bool = picked != null and str(picked) == "none"
	var none_btn := UI.option_button("✓ 聯絡客戶，確認現有規劃已充足（維持現狀）", func():
		Net.act({"type": "review", "card": "none"})
	, UI.GOOD.darkened(0.5) if none_picked else UI.PANEL_2)
	none_btn.disabled = not actor or picked != null
	_v.add_child(none_btn)

	var skip_picked: bool = picked != null and str(picked) == "skip"
	var skip_btn := UI.option_button("× 先不聯絡客戶（暫緩拜訪）", func():
		Net.act({"type": "review", "card": "skip"})
	, UI.BAD.darkened(0.5) if skip_picked else Color("#172832"))
	skip_btn.disabled = not actor or picked != null
	_v.add_child(skip_btn)

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

	UI.pass_wheel(_v)

