@tool
extends Control
## Training records: learning portfolio (growth overview, trend chart, client codex, historical interview replay) and trainer learner management.

var main: Node
var target_user_id: String = ""
var target_user_name: String = ""

# UI references
var _outer_v: VBoxContainer
var _tabs_bar: Container
var _tab_buttons: Array = []
var _body_area: Control
var _current_tab: int = 0  # Current tab position in _tab_ids
## Tab IDs (in display order): overview (growth overview), codex (client codex), history (historical records), ai (AI usage), trainer (all learners)
var _tab_ids: Array = []

# Historical records UI references
var _history_list: VBoxContainer
var _history_detail: VBoxContainer
var _history_filter: LineEdit

# All learners UI references
var _trainer_list: VBoxContainer
var _trainer_filter: LineEdit

# Data cache
var _profile: Dictionary = {}
var _records: Array = []
var _all_records: Array = []
var _selected_record: Dictionary = {}
## Chinese labels of weakness tags provided by server (tag -> label)
var _tag_labels: Dictionary = {}


## Score growth trend line chart component (custom-drawn Control)
class TrendChart extends Control:
	var trend_data: Array = []

	func _init() -> void:
		# Allow scroll wheel events to pass through chart to outer ScrollContainer
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_data(data: Array) -> void:
		trend_data = data
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0 or size.y <= 0:
			return
		var font: Font = get_theme_default_font()
		var pad_left: float = 38.0
		var pad_right: float = 24.0
		var pad_top: float = 24.0
		var pad_bottom: float = 28.0
		var plot_w: float = size.x - pad_left - pad_right
		var plot_h: float = size.y - pad_top - pad_bottom

		# Background and border
		draw_rect(Rect2(0, 0, size.x, size.y), Color("#0d2432"), true)
		draw_rect(Rect2(0, 0, size.x, size.y), Color("#1b4052"), false, 1.0)

		# Horizontal scale lines (0, 50, 100 points)
		for val: int in [0, 50, 100]:
			var y: float = pad_top + plot_h * (1.0 - float(val) / 100.0)
			draw_line(Vector2(pad_left, y), Vector2(size.x - pad_right, y), Color("#1b4052", 0.6), 1.0)
			draw_string(font, Vector2(4, y + 4), str(val), HORIZONTAL_ALIGNMENT_RIGHT, int(pad_left - 8), UI.fs(10), UI.MUTED)

		if trend_data.is_empty():
			draw_string(font, Vector2(0, size.y * 0.5 + 4), "尚未有足夠場次繪製趨勢圖", HORIZONTAL_ALIGNMENT_CENTER, int(size.x), UI.fs(13), UI.MUTED)
			return

		var count: int = trend_data.size()
		var points: PackedVector2Array = PackedVector2Array()

		for i: int in count:
			var item: Dictionary = trend_data[i]
			var score: float = clampf(float(item.get("score", 0)), 0.0, 100.0)
			var x: float = pad_left if count == 1 else (pad_left + plot_w * (float(i) / float(count - 1)))
			var y: float = pad_top + plot_h * (1.0 - score / 100.0)
			points.append(Vector2(x, y))

		# Draw polyline
		if points.size() > 1:
			draw_polyline(points, UI.ACCENT_2, 2.5, true)
		elif points.size() == 1:
			draw_circle(points[0], 5.0, UI.ACCENT_2)

		# Draw nodes, grade labels, and match indices
		for i: int in points.size():
			var pt: Vector2 = points[i]
			var item: Dictionary = trend_data[i]
			var grade: String = str(item.get("grade", ""))

			draw_circle(pt, 4.0, UI.GOLD)
			draw_circle(pt, 2.0, UI.BG)

			var grade_color: Color = UI.GOLD if grade == "S" else (UI.GOOD if grade == "A" else (UI.OK if grade == "B" else UI.MUTED))
			draw_string(font, Vector2(pt.x - 16, pt.y - 8), grade, HORIZONTAL_ALIGNMENT_CENTER, 32, UI.fs(11), grade_color)
			draw_string(font, Vector2(pt.x - 16, size.y - 8), "#%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 32, UI.fs(10), UI.MUTED)


func _ready() -> void:
	_build_ui()


func on_layout_changed(_is_portrait: bool) -> void:
	_build_ui()


func _build_ui() -> void:
	UI.clear(self)
	var portrait: bool = UI.is_portrait()

	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad: int = 12 if UI.is_phone_portrait() else (16 if portrait else 28)
	for s: String in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, pad)
	add_child(m)

	_outer_v = UI.vbox(10)
	m.add_child(_outer_v)

	# Top bar
	var head := UI.hbox(8 if UI.is_phone_portrait() else 10)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_text: String = "培訓紀錄"
	if target_user_name != "":
		title_text = "學員成長檔案：%s" % target_user_name
	var title_fs: int = 18 if UI.is_phone_portrait() else (24 if portrait else 28)
	head.add_child(UI.label(title_text, title_fs, UI.ACCENT_2))

	if target_user_id != "" and target_user_id != Net.get_user().get("id", ""):
		head.add_child(UI.button("← 返回" if UI.is_phone_portrait() else "← 返回學員清單", func():
			target_user_id = ""
			target_user_name = ""
			_current_tab = maxi(0, _tab_ids.find("trainer"))
			_build_ui()
		, 13 if UI.is_phone_portrait() else 14, UI.PANEL_2))

	head.add_child(UI.spacer())
	head.add_child(UI.button("回主選單", func(): main.show_menu(), 13 if UI.is_phone_portrait() else 15))
	_outer_v.add_child(head)

	# Not logged in and no specified learner: display login guide card
	if not Net.is_logged_in() and target_user_id == "":
		_build_unauth_view()
		return

	# Tab bar (flow layout in phone portrait to prevent overflow)
	if UI.is_phone_portrait():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		_tabs_bar = flow
	else:
		_tabs_bar = UI.hbox(8)
	_tab_buttons.clear()
	var tabs: Array = ["成長總覽", "客戶圖鑑", "歷次紀錄"]
	_tab_ids = ["overview", "codex", "history"]
	# AI usage records are only viewed for oneself (hidden when trainer views a learner)
	if target_user_id == "" or target_user_id == str(Net.get_user().get("id", "")):
		tabs.append("AI 使用")
		_tab_ids.append("ai")
	if Net.is_trainer() and target_user_id == "":
		tabs.append("全部學員（講師）")
		_tab_ids.append("trainer")
		tabs.append("弱點熱力圖")
		_tab_ids.append("insights")
	_current_tab = clampi(_current_tab, 0, _tab_ids.size() - 1)

	for i: int in tabs.size():
		var idx: int = i
		var t_name: String = tabs[idx]
		var b: Button = UI.button(t_name, func(): _switch_tab(idx), 13 if UI.is_phone_portrait() else 14, UI.ACCENT if _current_tab == idx else UI.PANEL_2)
		b.custom_minimum_size = Vector2(0, 36 if UI.is_phone_portrait() else 40)
		if not UI.is_phone_portrait():
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tab_buttons.append(b)
		_tabs_bar.add_child(b)
	_outer_v.add_child(_tabs_bar)

	# Must be Container for children (ScrollContainer) to fill; regular Control leaves content size at 0
	_body_area = MarginContainer.new()
	_body_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer_v.add_child(_body_area)

	_switch_tab(_current_tab)


func _build_unauth_view() -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var p := UI.panel(UI.PANEL, 16, 24)
	p.custom_minimum_size = Vector2(400 if UI.is_phone_portrait() else 480, 0)
	var v := UI.vbox(14)
	p.add_child(v)

	v.add_child(UI.label("登入後可查看培訓紀錄", 20, UI.ACCENT_2))
	v.add_child(UI.label("登入個人帳號即可享有：\n・歷次面談決策與五力成長趨勢折線圖\n・專屬客戶圖鑑解鎖與最佳評級進度\n・常見決策盲點與改進建議\n・8 項專業顧問成就徽章", 14, UI.TEXT, true))

	var btns := UI.vbox(10)
	if bool(Net.auth_config.get("google", true)):
		btns.add_child(UI.button("使用 Google 帳號登入", func():
			var login_url: String = Net.base_url + "/api/auth/google/start?return=/"
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.location.href='%s'" % login_url)
			else:
				OS.shell_open(login_url)
		, 16, UI.ACCENT))

	if bool(Net.auth_config.get("dev", false)):
		btns.add_child(UI.button("測試登入（本機開發）", func():
			var name_encoded: String = Net.player_name.uri_encode()
			if name_encoded == "":
				name_encoded = "測試顧問".uri_encode()
			var dev_url: String = Net.base_url + "/api/auth/dev-login?name=%s&return=/" % name_encoded
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.location.href='%s'" % dev_url)
			else:
				OS.shell_open(dev_url)
		, 15, UI.PANEL_2))

	v.add_child(btns)
	v.add_child(UI.label("訪客模式下遊玩可體驗遊戲，但紀錄不會被保存。", 12, UI.MUTED, true))
	center.add_child(p)
	_outer_v.add_child(center)


func _switch_tab(tab_idx: int) -> void:
	_current_tab = tab_idx
	for i: int in _tab_buttons.size():
		var b: Button = _tab_buttons[i]
		if i == _current_tab:
			b.add_theme_stylebox_override("normal", UI.box(UI.ACCENT, 10, Color(0, 0, 0, 0), 12))
		else:
			b.add_theme_stylebox_override("normal", UI.box(UI.PANEL_2, 10, Color(0, 0, 0, 0), 12))

	UI.clear(_body_area)

	match str(_tab_ids[_current_tab]) if _current_tab < _tab_ids.size() else "overview":
		"overview":
			_render_overview_tab()
		"codex":
			_render_codex_tab()
		"history":
			_render_history_tab()
		"ai":
			_render_ai_tab()
		"trainer":
			_render_trainer_tab()
		"insights":
			_render_insights_tab()


# ──────────────────────────────────────────────────────────────────
# Tab 0: Growth overview
# ──────────────────────────────────────────────────────────────────

func _render_overview_tab() -> void:
	var scroll: ScrollContainer = UI.scroll(UI.vbox(14))
	_body_area.add_child(scroll)
	var content: VBoxContainer = scroll.get_child(0) as VBoxContainer

	content.add_child(UI.label("載入個人學習檔案中……", 15, UI.MUTED))

	var res: Array = await Net.fetch_profile(target_user_id)
	UI.clear(content)

	if not bool(res[0]):
		content.add_child(UI.label("無法載入學習檔案：%s" % str(res[1]), 15, UI.BAD, true))
		return

	_profile = res[1] if res[1] is Dictionary else {}

	# 1. Key metrics KPI row
	var kpi_flow: BoxContainer
	if UI.is_phone_portrait():
		kpi_flow = UI.vbox(8)
	else:
		kpi_flow = UI.hbox(10)

	var games_cnt: int = int(_profile.get("games", 0))
	var avg_score: float = float(_profile.get("avgScore", 0))
	var best_grade: String = str(_profile.get("bestGrade", "無"))
	if best_grade == "":
		best_grade = "無"

	var quiz: Dictionary = _profile.get("quiz", {})
	var q_corr: int = int(quiz.get("correct", 0))
	var q_tot: int = int(quiz.get("total", 0))
	var quiz_str: String = "尚未測驗" if q_tot == 0 else ("%d / %d（%.0f%%）" % [q_corr, q_tot, (float(q_corr) * 100.0 / float(q_tot))])

	kpi_flow.add_child(_make_kpi_card("培訓場次", "%d 場" % games_cnt, UI.ACCENT_2))
	kpi_flow.add_child(_make_kpi_card("平均分數", "%.1f 分" % avg_score, UI.TEXT))
	kpi_flow.add_child(_make_kpi_card("最佳評級", best_grade, UI.GOLD if best_grade == "S" else UI.GOOD))
	kpi_flow.add_child(_make_kpi_card("合規測驗答對率", quiz_str, UI.INFO))
	content.add_child(kpi_flow)

	# 2. Score trend line chart card
	var trend_card := UI.panel(UI.PANEL, 14, 14)
	var trend_v := UI.vbox(8)
	trend_card.add_child(trend_v)

	var trend_arr: Array = _profile.get("trend", [])
	trend_v.add_child(UI.label("分數成長趨勢（最近 %d 場）" % trend_arr.size(), 16, UI.ACCENT_2))

	var chart := TrendChart.new()
	chart.custom_minimum_size = Vector2(0, 160 if UI.is_phone_portrait() else 190)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.set_data(trend_arr)
	trend_v.add_child(chart)
	content.add_child(trend_card)

	# 3. Latest five-dimensional competency metric card
	var skill_card := UI.panel(UI.PANEL, 14, 14)
	var skill_v := UI.vbox(8)
	skill_card.add_child(skill_v)
	skill_v.add_child(UI.label("最新五力維度指標", 16, UI.ACCENT_2))

	var latest_skill: Dictionary = {}
	if not trend_arr.is_empty():
		var last_item: Dictionary = trend_arr[trend_arr.size() - 1]
		if last_item.get("skill") is Dictionary:
			latest_skill = last_item["skill"]

	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		skill_v.add_child(UI.metric_row(k, float(latest_skill.get(k, 0))))
	content.add_child(skill_card)

	# 4. Common blind spots and improvement suggestions
	var mistakes_card := UI.panel(UI.PANEL, 14, 14)
	var mistakes_v := UI.vbox(10)
	mistakes_card.add_child(mistakes_v)
	mistakes_v.add_child(UI.label("常見決策盲點與改進建議", 16, UI.ACCENT_2))

	var mistakes: Array = _profile.get("mistakes", [])
	if mistakes.is_empty():
		mistakes_v.add_child(UI.label("✓ 目前無明顯失誤或合規盲點，表現優異！", 14, UI.GOOD, true))
	else:
		for m_item: Dictionary in mistakes:
			var m_box := UI.panel(UI.PANEL_2, 10, 10)
			var m_v := UI.vbox(4)
			m_box.add_child(m_v)
			m_v.add_child(UI.label("▲ %s（累計 %d 次）" % [str(m_item.get("label", "")), int(m_item.get("count", 0))], 14, UI.BAD))
			m_v.add_child(UI.label(str(m_item.get("advice", "")), 13, UI.TEXT, true))
			mistakes_v.add_child(m_box)
	content.add_child(mistakes_card)

	# 5. Advisor achievement badge wall
	var badges_card := UI.panel(UI.PANEL, 14, 14)
	var badges_v := UI.vbox(10)
	badges_card.add_child(badges_v)
	badges_v.add_child(UI.label("顧問專業成就徽章", 16, UI.ACCENT_2))

	var badges_grid := GridContainer.new()
	badges_grid.columns = 2 if UI.is_phone_portrait() else (3 if UI.is_portrait() else 4)
	badges_grid.add_theme_constant_override("h_separation", 10)
	badges_grid.add_theme_constant_override("v_separation", 10)

	var badges_list: Array = _profile.get("badges", [])
	for b_item: Dictionary in badges_list:
		var earned: bool = bool(b_item.get("earned", false))
		var bg_col: Color = UI.PANEL_2 if earned else Color("#0e2430")
		var b_box := UI.panel(bg_col, 10, 10)
		b_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var b_inner := UI.vbox(4)
		b_box.add_child(b_inner)

		var title_col: Color = UI.GOLD if earned else UI.MUTED
		var icon_str: String = "★ " if earned else "○ "
		var status_str: String = "" if earned else "（未解鎖）"
		b_inner.add_child(UI.label(icon_str + str(b_item.get("title", "")) + status_str, 13, title_col, true))
		b_inner.add_child(UI.label(str(b_item.get("desc", "")), 11, UI.TEXT if earned else UI.MUTED, true))

		badges_grid.add_child(b_box)
	badges_v.add_child(badges_grid)
	content.add_child(badges_card)


func _make_kpi_card(title: String, val: String, val_color: Color) -> PanelContainer:
	var p := UI.panel(UI.PANEL, 12, 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(2)
	p.add_child(v)
	v.add_child(UI.label(title, 12, UI.MUTED))
	v.add_child(UI.label(val, 18, val_color))
	return p


# ──────────────────────────────────────────────────────────────────
# AI usage records: today quota, provider call counts, last 7 days
# ──────────────────────────────────────────────────────────────────

const PROVIDER_NAMES := {
	"nvidia-nim": "NVIDIA NIM（不計額度）",
	"nvidia-nim-backup": "NVIDIA NIM 備援 DeepSeek（不計額度）",
	"workers-ai": "Cloudflare Workers AI（計入額度）",
	"claude": "Claude（計入額度）",
	"mock": "本機模擬",
}


func _render_ai_tab() -> void:
	var scroll: ScrollContainer = UI.scroll(UI.vbox(14))
	_body_area.add_child(scroll)
	var content: VBoxContainer = scroll.get_child(0) as VBoxContainer
	content.add_child(UI.label("載入 AI 使用紀錄中……", 15, UI.MUTED))

	var res: Array = await Net.http_json(HTTPClient.METHOD_GET, "/api/ai-usage")
	if not is_instance_valid(content):
		return
	UI.clear(content)
	if not bool(res[0]) or not (res[1] is Dictionary):
		content.add_child(UI.label("無法載入 AI 使用紀錄：%s" % str(res[1]), 14, UI.BAD, true))
		return
	var d: Dictionary = res[1]
	var limit: int = int(d.get("limit", 50))
	var used: int = int(d.get("used", 0))
	var remaining: int = int(d.get("remaining", maxi(0, limit - used)))
	var history: Array = d.get("history", [])
	var today: Dictionary = history.back() if not history.is_empty() and history.back() is Dictionary else {}
	var today_calls: Dictionary = today.get("calls", {}) if today.get("calls") is Dictionary else {}
	var total_today: int = 0
	for k in today_calls:
		total_today += int(today_calls[k])

	# Today quota
	var qp := UI.panel(UI.PANEL, 14, 14)
	var qv := UI.vbox(8)
	qp.add_child(qv)
	qv.add_child(UI.label("今日 AI 額度（Workers AI 計次）", 17, UI.ACCENT_2))
	var row := UI.hbox(8 if UI.is_phone_portrait() else 10)
	row.add_child(UI.label("已用 %d / %d 次" % [used, limit], 17 if UI.is_phone_portrait() else 22, UI.TEXT))
	row.add_child(UI.spacer())
	row.add_child(UI.label("剩餘 %d 次" % remaining, 17 if UI.is_phone_portrait() else 22, UI.GOOD if remaining > 10 else (UI.OK if remaining > 0 else UI.BAD)))
	qv.add_child(row)
	var bar := UI.bar(100.0 * float(used) / float(maxi(1, limit)), UI.GOOD if remaining > 10 else (UI.OK if remaining > 0 else UI.BAD), 120 if UI.is_phone_portrait() else 400)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 10)
	qv.add_child(bar)
	var secs: int = maxi(0, int((float(d.get("resetAt", 0)) - float(d.get("now", 0))) / 1000.0))
	qv.add_child(UI.label("%d 小時 %d 分後重置（台北時間午夜）" % [secs / 3600, (secs % 3600) / 60], 13, UI.MUTED))
	if remaining <= 0:
		qv.add_child(UI.label("※ 今日額度已用完：AI 功能改用規則版，遊戲照常進行。", 13, UI.GOLD, true))
	content.add_child(qp)

	# Today provider call counts
	var cp := UI.panel(UI.PANEL, 14, 14)
	var cv := UI.vbox(6)
	cp.add_child(cv)
	cv.add_child(UI.label("今日 AI 呼叫 %d 次" % total_today, 17, UI.ACCENT_2))
	if today_calls.is_empty():
		cv.add_child(UI.label("今天還沒有使用 AI。登入後在面談中自由提問、異議回應、教練提示都會用到 AI。", 13, UI.MUTED, true))
	for k in today_calls:
		var call_cnt: int = int(today_calls[k])
		if UI.is_phone_portrait():
			var r := UI.vbox(2)
			r.add_child(UI.label(str(PROVIDER_NAMES.get(str(k), str(k))), 13, UI.TEXT, true))
			var sub_h := UI.hbox(6)
			sub_h.add_child(UI.spacer())
			sub_h.add_child(UI.label("%d 次" % call_cnt, 13, UI.GOLD))
			r.add_child(sub_h)
			cv.add_child(r)
		else:
			var r := UI.hbox(8)
			r.add_child(UI.label(str(PROVIDER_NAMES.get(str(k), str(k))), 14, UI.TEXT))
			r.add_child(UI.spacer())
			r.add_child(UI.label("%d 次" % call_cnt, 14, UI.TEXT))
			cv.add_child(r)
	if bool(d.get("nimUnmetered", false)):
		cv.add_child(UI.label("說明：優先使用 NVIDIA NIM，失敗時改用 NIM 備援模型（DeepSeek，較慢），兩者都不扣每日額度；都失敗時才改用 Workers AI，並扣 1 次額度（失敗會退還）。", 12, UI.MUTED, true))
	content.add_child(cp)

	# Last 7 days
	var hp := UI.panel(UI.PANEL, 14, 14)
	var hv := UI.vbox(6)
	hp.add_child(hv)
	hv.add_child(UI.label("近 7 天", 17, UI.ACCENT_2))
	var head := UI.hbox(8)
	head.add_child(UI.label("日期", 12 if UI.is_phone_portrait() else 13, UI.MUTED))
	head.add_child(UI.spacer())
	head.add_child(UI.label("呼叫 / 額度" if UI.is_phone_portrait() else "AI 呼叫　｜　計入額度", 12 if UI.is_phone_portrait() else 13, UI.MUTED))
	hv.add_child(head)
	var max_calls: int = 1
	for h: Dictionary in history:
		var tot: int = 0
		for k in (h.get("calls", {}) as Dictionary):
			tot += int(h["calls"][k])
		max_calls = maxi(max_calls, tot)
	for i in range(history.size() - 1, -1, -1):
		var h: Dictionary = history[i]
		var tot: int = 0
		for k in (h.get("calls", {}) as Dictionary):
			tot += int(h["calls"][k])
		var r := UI.hbox(6 if UI.is_phone_portrait() else 8)
		var day: String = str(h.get("day", ""))
		var day_txt: String = (day.substr(5).replace("-", "/") + ("（今）" if i == history.size() - 1 else "")) if UI.is_phone_portrait() else (day.substr(5).replace("-", "/") + ("（今天）" if i == history.size() - 1 else ""))
		r.add_child(UI.label(day_txt, 12 if UI.is_phone_portrait() else 14, UI.TEXT))
		var b := UI.bar(100.0 * float(tot) / float(max_calls), UI.ACCENT_2, 50 if UI.is_phone_portrait() else 160)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(b)
		var cnt_txt: String = ("%d / %d 次" % [tot, int(h.get("quota", 0))]) if UI.is_phone_portrait() else ("%d 次　｜　%d 次" % [tot, int(h.get("quota", 0))])
		r.add_child(UI.label(cnt_txt, 12 if UI.is_phone_portrait() else 14, UI.TEXT))
		hv.add_child(r)
	content.add_child(hp)

	content.add_child(UI.button("重新整理", func(): _switch_tab(_current_tab), 14, UI.PANEL_2))


# ──────────────────────────────────────────────────────────────────
# Tab 1: Client codex (18 slots)
# ──────────────────────────────────────────────────────────────────

func _render_codex_tab() -> void:
	var scroll: ScrollContainer = UI.scroll(UI.vbox(14))
	_body_area.add_child(scroll)
	var content: VBoxContainer = scroll.get_child(0) as VBoxContainer

	content.add_child(UI.label("載入客戶圖鑑資料中……", 15, UI.MUTED))

	if _profile.is_empty():
		var res: Array = await Net.fetch_profile(target_user_id)
		if bool(res[0]) and res[1] is Dictionary:
			_profile = res[1]

	UI.clear(content)

	var clients: Array = _profile.get("clients", [])
	if clients.is_empty():
		content.add_child(UI.label("尚未有客戶圖鑑資料。", 15, UI.MUTED))
		return

	var served_count: int = 0
	for c: Dictionary in clients:
		if int(c.get("served", 0)) > 0:
			served_count += 1

	content.add_child(UI.label("客戶圖鑑收集進度：%d / %d 位已面談" % [served_count, clients.size()], 16, UI.ACCENT_2))

	var grid := GridContainer.new()
	grid.columns = 2 if UI.is_phone_portrait() else (3 if UI.is_portrait() else 6)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)

	for c_item: Dictionary in clients:
		var served: int = int(c_item.get("served", 0))
		var card := UI.panel(UI.PANEL if served > 0 else Color("#0d212b"), 12, 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var v := UI.vbox(4)
		card.add_child(v)

		if served > 0:
			var avatar: Control = UI.portrait({"portrait": c_item.get("id", ""), "name": c_item.get("name", "")}, 48)
			avatar.custom_minimum_size = Vector2(48, 48)
			v.add_child(avatar)

			v.add_child(UI.label(str(c_item.get("name", "")), 14, UI.ACCENT_2))
			v.add_child(UI.label(str(c_item.get("job", "")), 11, UI.MUTED, true))

			var best_g: String = str(c_item.get("bestGrade", "C"))
			var g_col: Color = UI.GOLD if best_g == "S" else (UI.GOOD if best_g == "A" else (UI.OK if best_g == "B" else UI.MUTED))
			v.add_child(UI.label("最佳：%s 級" % best_g, 12, g_col))
			v.add_child(UI.label("面談：%d 次" % served, 11, UI.TEXT))
		else:
			# Locked client silhouette
			var mystery := CenterContainer.new()
			mystery.custom_minimum_size = Vector2(48, 48)
			var q_bg := UI.panel(Color("#132a36"), 24, 0)
			q_bg.custom_minimum_size = Vector2(48, 48)
			var q_lbl := UI.label("？", 20, UI.MUTED)
			q_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q_bg.add_child(q_lbl)
			mystery.add_child(q_bg)
			v.add_child(mystery)

			v.add_child(UI.label("？？？", 14, UI.MUTED))
			v.add_child(UI.label("尚未面談", 11, UI.MUTED, true))
			v.add_child(UI.label("未解鎖", 11, UI.MUTED))

		grid.add_child(card)


# ──────────────────────────────────────────────────────────────────
# Tab 2: Historical records and interview replay
# ──────────────────────────────────────────────────────────────────

func _render_history_tab() -> void:
	var portrait: bool = UI.is_portrait()

	var history_main := UI.vbox(8 if UI.is_phone_portrait() else 10)
	history_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_area.add_child(history_main)

	var top_filter := UI.hbox(8)
	top_filter.custom_minimum_size = Vector2(0, 44)
	top_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_filter = LineEdit.new()
	_history_filter.placeholder_text = "依姓名篩選" if UI.is_phone_portrait() else "依玩家姓名篩選（空白＝全部）"
	_history_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_filter.custom_minimum_size = Vector2(0, 42)
	_history_filter.text_submitted.connect(func(_t: String): _load_history())
	top_filter.add_child(_history_filter)
	top_filter.add_child(UI.button("查詢", _load_history, 14))
	history_main.add_child(top_filter)

	var split_box: BoxContainer
	if portrait:
		split_box = UI.vbox(8 if UI.is_phone_portrait() else 10)
	else:
		split_box = UI.hbox(12)

	split_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_main.add_child(split_box)

	# Left (or top) list
	var left_p := UI.panel()
	if not portrait:
		left_p.custom_minimum_size = Vector2(380, 0)
	else:
		left_p.custom_minimum_size = Vector2(0, 180)
	_history_list = UI.vbox(6)
	left_p.add_child(UI.scroll(_history_list))
	split_box.add_child(left_p)

	# Right (or bottom) details
	var right_p := UI.panel()
	right_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_detail = UI.vbox(8)
	right_p.add_child(UI.scroll(_history_detail))
	split_box.add_child(right_p)

	_load_history()


func _load_history() -> void:
	UI.clear(_history_list)
	UI.clear(_history_detail)
	_history_list.add_child(UI.label("讀取歷次紀錄中……", 14, UI.MUTED))

	var filter_text: String = _history_filter.text.strip_edges()
	var res: Array = await Net.fetch_records_scope(target_user_id, filter_text)

	UI.clear(_history_list)
	if not bool(res[0]):
		_history_list.add_child(UI.label(str(res[1]), 14, UI.BAD, true))
		return

	_records = res[1].get("records", []) if res[1] is Dictionary else []
	if filter_text != "":
		_records = _records.filter(func(r: Dictionary): return filter_text.to_lower() in str(r.get("name", "")).to_lower())
	if res[1] is Dictionary and res[1].get("tagInfo") is Dictionary:
		_tag_labels = res[1]["tagInfo"]
	if _records.is_empty():
		_history_list.add_child(UI.label("尚未有歷次紀錄。完成一場遊戲後將自動保存。", 14, UI.MUTED, true))
		return

	for rec_item: Dictionary in _records:
		var rr: Dictionary = rec_item
		var local_ts: int = int(rr.get("ts", 0)) / 1000 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var dt: String = Time.get_datetime_string_from_unix_time(local_ts).replace("T", " ").substr(0, 16)
		var players_cnt: int = int(rr.get("players", 1))
		var mode_str: String = "單人" if players_cnt <= 1 else ("%d 人局" % players_cnt)
		var label_str: String = "%s　%d 分　%s　（%s）" % [str(rr.get("grade", "C")), int(rr.get("score", 0)), dt, mode_str]

		var b: Button = UI.option_button(label_str, func(): _show_history_detail(rr))
		_history_list.add_child(b)

	if not _records.is_empty():
		_show_history_detail(_records[0])


func _show_history_detail(rec: Dictionary) -> void:
	UI.clear(_history_detail)
	var d: Dictionary = rec.get("data", {})

	# 1. Top summary
	var head_box := UI.panel(UI.PANEL_2, 12, 10)
	var head_v := UI.vbox(4)
	head_box.add_child(head_v)

	head_v.add_child(UI.label("%s｜評級 %s・總分 %d 分" % [str(rec.get("name", "")), str(rec.get("grade", "")), int(rec.get("score", 0))], 18, UI.ACCENT_2, true))
	head_v.add_child(UI.label("服務客戶 %d 位・滿意度 %d・顧問聲望 %d・累積業績 %d" % [
		int(d.get("clients", 0)), int(d.get("service", 0)), int(d.get("reputation", 0)), int(d.get("commission", 0))
	], 12, UI.MUTED, true))

	var skill: Dictionary = d.get("skill", {})
	for k: String in ["trust", "insight", "fit", "risk", "compliance"]:
		head_v.add_child(UI.metric_row(k, float(skill.get(k, 0))))

	if str(d.get("coach", "")) != "":
		head_v.add_child(UI.label("綜合教練回饋：", 13, UI.GOLD))
		head_v.add_child(UI.label(str(d.get("coach", "")), 13, UI.TEXT, true))
	_history_detail.add_child(head_box)

	# 2. Per-interview replay (sessions)
	var sessions: Array = d.get("sessions", [])
	if not sessions.is_empty():
		_history_detail.add_child(UI.label("各場面談實戰軌跡（共 %d 場）" % sessions.size(), 16, UI.ACCENT_2))

		for s_item: Dictionary in sessions:
			var s_panel := UI.panel(UI.PANEL_2, 12, 12)
			var s_v := UI.vbox(6)
			s_panel.add_child(s_v)

			# Header row
			var r_title := UI.hbox(8)
			r_title.add_child(UI.label("R%d｜%s（%s）" % [int(s_item.get("round", 1)), str(s_item.get("clientName", "")), str(s_item.get("job", ""))], 15, UI.ACCENT_2))

			var s_grade: String = str(s_item.get("grade", ""))
			var g_col: Color = UI.GOLD if s_grade == "S" else (UI.GOOD if s_grade == "A" else (UI.OK if s_grade == "B" else UI.MUTED))
			r_title.add_child(UI.label("評級 %s（%d分）" % [s_grade, int(s_item.get("score", 0))], 14, g_col))

			if bool(s_item.get("signed", false)):
				r_title.add_child(UI.label("✓ 已簽約", 13, UI.GOOD))
			else:
				r_title.add_child(UI.label("× 未簽約", 13, UI.BAD))

			if bool(s_item.get("referral", false)):
				r_title.add_child(UI.label("★ 成功轉介", 13, UI.GOLD))

			var hint_text: String = "（提示）" if bool(s_item.get("hintUsed", false)) else "（自主）"
			r_title.add_child(UI.label(hint_text, 12, UI.MUTED))
			s_v.add_child(r_title)

			# Clue exploration
			var clues_dict: Dictionary = s_item.get("clues", {})
			var clue_txt: String = "・發現線索 %d 項" % int(clues_dict.get("found", 0))
			if bool(clues_dict.get("decoy", false)):
				clue_txt += "（包含誤導資訊）"
			s_v.add_child(UI.label(clue_txt, 13, UI.MUTED))

			# Question history
			var qs: Array = s_item.get("questions", [])
			if not qs.is_empty():
				var q_str: String = "・面談提問："
				var q_items: Array = []
				for q: Dictionary in qs:
					var k_mark: String = "★" if q.get("key") != null else ""
					q_items.append("%s%s" % [k_mark, str(q.get("text", ""))])
				s_v.add_child(UI.label(q_str + "、".join(q_items), 13, UI.TEXT, true))

			var free_q = s_item.get("freeQuestion")
			if free_q != null and free_q is Dictionary:
				s_v.add_child(UI.label("・自由提問：%s → %s" % [str(free_q.get("text", "")), str(free_q.get("note", ""))], 13, UI.INFO, true))

			# Plan allocation
			var plan: Dictionary = s_item.get("plan", {})
			var alloc: Dictionary = plan.get("alloc", {})
			var alloc_txt: String = "・方案配置：現金預備 %d%% / 風險保障 %d%% / 目標成長 %d%%（品質：%s）" % [
				int(alloc.get("cash", 0)), int(alloc.get("protect", 0)), int(alloc.get("growth", 0)), str(plan.get("quality", ""))
			]
			s_v.add_child(UI.label(alloc_txt, 13, UI.ACCENT_2, true))

			var plan_notes: Array = plan.get("notes", [])
			if not plan_notes.is_empty():
				for note_text: String in plan_notes:
					s_v.add_child(UI.label("  → %s" % note_text, 12, UI.MUTED, true))

			# Objection handling
			var obj: Dictionary = s_item.get("objection", {})
			if not obj.is_empty():
				var obj_mode_str: String = "自由回應" if str(obj.get("mode", "")) == "free" else "情境選擇"
				var obj_q: String = str(obj.get("quality", ""))
				s_v.add_child(UI.label("・異議回應（%s｜%s）：%s" % [obj_mode_str, obj_q, str(obj.get("title", ""))], 13, UI.tone_color(obj_q)))
				if str(obj.get("text", "")) != "":
					s_v.add_child(UI.label("  → %s" % str(obj.get("text", "")), 12, UI.TEXT, true))

			# Stress test
			var stress_list: Array = s_item.get("stress", [])
			if not stress_list.is_empty():
				var st_str: String = "・壓力預演："
				var st_parts: Array = []
				for st: Dictionary in stress_list:
					var r_str: String = str(st.get("result", ""))
					var icon: String = "✓" if r_str == "held" else ("△" if r_str == "partial" else "×")
					st_parts.append("%s %s" % [icon, str(st.get("title", ""))])
				s_v.add_child(UI.label(st_str + "　".join(st_parts), 13, UI.TEXT, true))

			# Tags
			var tags: Array = s_item.get("tags", [])
			if not tags.is_empty():
				var labels: Array = tags.map(func(t): return str(_tag_labels.get(str(t), str(t))))
				var tag_str: String = "・決策標籤：" + "、".join(labels)
				s_v.add_child(UI.label(tag_str, 12, UI.GOLD, true))

			_history_detail.add_child(s_panel)
	else:
		# Backward compatibility for legacy decision records
		var ds: Array = d.get("decisions", [])
		if not ds.is_empty():
			_history_detail.add_child(UI.label("決策紀錄", 16, UI.ACCENT_2))
			for x: Dictionary in ds:
				var q: String = str(x.get("quality", ""))
				_history_detail.add_child(UI.label("%s %s｜%s：%s" % [{"good": "✓", "ok": "△", "bad": "×"}.get(q, "・"), str(x.get("clientName", "")), str(x.get("stage", "")), str(x.get("title", ""))], 13, UI.tone_color(q), true))


# ──────────────────────────────────────────────────────────────────
# Tab 3: All learners list (trainer only)
# ──────────────────────────────────────────────────────────────────

func _render_trainer_tab() -> void:
	var scroll: ScrollContainer = UI.scroll(UI.vbox(12))
	_body_area.add_child(scroll)
	var content: VBoxContainer = scroll.get_child(0) as VBoxContainer

	var top_bar := UI.hbox(8)
	top_bar.custom_minimum_size = Vector2(0, 44)
	top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trainer_filter = LineEdit.new()
	_trainer_filter.placeholder_text = "依姓名篩選" if UI.is_phone_portrait() else "依學員姓名篩選（空白＝全部）"
	_trainer_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trainer_filter.custom_minimum_size = Vector2(0, 42)
	_trainer_filter.text_submitted.connect(func(_t: String): _load_trainer_learners(content))
	top_bar.add_child(_trainer_filter)
	top_bar.add_child(UI.button("查詢", func(): _load_trainer_learners(content), 14))
	content.add_child(top_bar)

	_trainer_list = UI.vbox(8)
	content.add_child(_trainer_list)

	_load_trainer_learners(content)


func _load_trainer_learners(_container: VBoxContainer) -> void:
	UI.clear(_trainer_list)
	_trainer_list.add_child(UI.label("載入全體學員名單中……", 14, UI.MUTED))

	# First fetch all records (scope=all)
	var filter_text: String = _trainer_filter.text.strip_edges()
	var res: Array = await Net.fetch_records_scope("all", filter_text)

	UI.clear(_trainer_list)
	if not bool(res[0]):
		_trainer_list.add_child(UI.label(str(res[1]), 14, UI.BAD, true))
		return

	var recs: Array = res[1].get("records", []) if res[1] is Dictionary else []
	if recs.is_empty():
		_trainer_list.add_child(UI.label("目前尚無學員紀錄。", 14, UI.MUTED))
		return

	# Aggregate statistics by learner
	var user_map: Dictionary = {}
	for rec_item: Dictionary in recs:
		var uid: String = str(rec_item.get("userId", ""))
		if uid == "":
			uid = "anon_" + str(rec_item.get("name", ""))
		if not user_map.has(uid):
			user_map[uid] = {
				"id": uid,
				"name": str(rec_item.get("name", "學員")),
				"games": 0,
				"totalScore": 0,
				"bestGrade": "C",
				"lastTs": 0,
			}
		var u: Dictionary = user_map[uid]
		u["games"] = int(u["games"]) + 1
		u["totalScore"] = int(u["totalScore"]) + int(rec_item.get("score", 0))
		var cur_g: String = str(rec_item.get("grade", "C"))
		var order: Array = ["C", "B", "A", "S"]
		if order.find(cur_g) >= order.find(str(u["bestGrade"])):
			u["bestGrade"] = cur_g
		var r_ts: int = int(rec_item.get("ts", 0))
		if r_ts > int(u["lastTs"]):
			u["lastTs"] = r_ts

	var u_list: Array = user_map.values()
	u_list.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("lastTs", 0)) > int(b.get("lastTs", 0)))

	_trainer_list.add_child(UI.label("全體學員清單（共 %d 位）" % u_list.size(), 16, UI.ACCENT_2))

	var is_phone := UI.is_phone_portrait()
	for learner: Dictionary in u_list:
		var l_card := UI.panel(UI.PANEL_2, 12, 8 if is_phone else 10)
		var l_box: BoxContainer = UI.vbox(6) if is_phone else UI.hbox(10)
		l_card.add_child(l_box)

		var l_v := UI.vbox(2)
		l_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_box.add_child(l_v)

		var games_num: int = int(learner.get("games", 1))
		var avg_num: float = float(learner.get("totalScore", 0)) / float(games_num)
		var b_grade: String = str(learner.get("bestGrade", "C"))

		var local_ts: int = int(learner.get("lastTs", 0)) / 1000 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var dt: String = Time.get_datetime_string_from_unix_time(local_ts).replace("T", " ").substr(0, 16)

		l_v.add_child(UI.label(str(learner.get("name", "")), 15 if is_phone else 16, UI.TEXT))
		l_v.add_child(UI.label("培訓 %d 場・平均 %.1f 分・最佳評級 %s・最近於 %s" % [games_num, avg_num, b_grade, dt], 12, UI.MUTED, true))

		var view_btn: Button = UI.button("查看學習檔案", func():
			target_user_id = str(learner.get("id", ""))
			target_user_name = str(learner.get("name", ""))
			_current_tab = 0
			_build_ui()
		, 13 if is_phone else 14, UI.ACCENT)
		if is_phone:
			view_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
		l_box.add_child(view_btn)

		_trainer_list.add_child(l_card)


# ──────────────────────────────────────────────────────────────────
# Tab 4: Trainer Insights & Weakness Heatmap (trainer only)
# ──────────────────────────────────────────────────────────────────

func _render_insights_tab() -> void:
	var scroll: ScrollContainer = UI.scroll(UI.vbox(14))
	_body_area.add_child(scroll)
	var content: VBoxContainer = scroll.get_child(0) as VBoxContainer
	content.add_child(UI.label("載入培訓弱點洞察中……", 15, UI.MUTED))

	var res: Array = await Net.fetch_insights()
	if not is_instance_valid(content):
		return
	UI.clear(content)
	if not bool(res[0]) or not (res[1] is Dictionary):
		content.add_child(UI.label("無法載入培訓弱點洞察：%s" % str(res[1]), 14, UI.BAD, true))
		return

	var d: Dictionary = res[1]
	var learners_cnt: int = int(d.get("learners", 0))
	var sessions_cnt: int = int(d.get("sessions", 0))
	var comp: Dictionary = d.get("compliance", {}) if d.get("compliance") is Dictionary else {}
	var violations_cnt: int = int(comp.get("violations", 0))
	var warnings_cnt: int = int(comp.get("warnings", 0))
	var tags: Array = d.get("tags", [])
	var matrix: Array = d.get("matrix", [])

	# 1. Summary row
	var summary_card := UI.panel(UI.PANEL, 14, 12)
	summary_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var summary_v := UI.vbox(8)
	summary_card.add_child(summary_v)
	summary_v.add_child(UI.label("培訓全景洞察概況（近 30 天）", 17, UI.ACCENT_2))

	var is_phone := UI.is_phone_portrait()
	var kpi_box: BoxContainer = UI.vbox(6) if is_phone else UI.hbox(10)
	kpi_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kpi_box.add_child(_make_kpi_card("培訓學員人數", "%d 位" % learners_cnt, UI.ACCENT_2))
	kpi_box.add_child(_make_kpi_card("累計面談場次", "%d 場" % sessions_cnt, UI.TEXT))
	var red_str := "%d 次" % violations_cnt
	if warnings_cnt > 0:
		red_str += "（警示 %d 次）" % warnings_cnt
	kpi_box.add_child(_make_kpi_card("合規違規紅燈", red_str, UI.BAD if violations_cnt > 0 else UI.GOOD))
	summary_v.add_child(kpi_box)
	content.add_child(summary_card)

	# 2. Bar list of top weakness tags
	var tags_card := UI.panel(UI.PANEL, 14, 12)
	tags_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tags_v := UI.vbox(8)
	tags_card.add_child(tags_v)
	tags_v.add_child(UI.label("全體常見決策弱點分佈", 16, UI.ACCENT_2))

	if tags.is_empty():
		tags_v.add_child(UI.label("近 30 天內無弱點標籤紀錄。", 13, UI.MUTED, true))
	else:
		var max_cnt: int = 1
		for t_item: Dictionary in tags:
			max_cnt = maxi(max_cnt, int(t_item.get("count", 0)))

		var display_tags: Array = tags.slice(0, 8)
		for t_item: Dictionary in display_tags:
			var t_lbl: String = str(t_item.get("label", t_item.get("tag", "")))
			var cnt: int = int(t_item.get("count", 0))
			var l_cnt: int = int(t_item.get("learners", 0))

			var row := UI.hbox(8)
			var name_lbl := UI.label(t_lbl, 13 if is_phone else 14, UI.TEXT)
			name_lbl.custom_minimum_size = Vector2(110 if is_phone else 150, 0)
			name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(name_lbl)

			var pct: float = 100.0 * float(cnt) / float(max_cnt)
			var b := UI.bar(pct, UI.GOLD if cnt >= 3 else UI.ACCENT_2, 60 if is_phone else 200)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(b)

			var count_lbl := UI.label("%d 次（%d 人）" % [cnt, l_cnt], 12 if is_phone else 13, UI.MUTED)
			row.add_child(count_lbl)
			tags_v.add_child(row)
	content.add_child(tags_card)

	# 3. Heatmap grid
	var heat_card := UI.panel(UI.PANEL, 14, 12)
	heat_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heat_v := UI.vbox(8)
	heat_card.add_child(heat_v)
	heat_v.add_child(UI.label("學員弱點熱力矩陣（點擊學員列查看學習檔案）", 16, UI.ACCENT_2))

	if matrix.is_empty():
		heat_v.add_child(UI.label("尚未有學員面談矩陣數據。", 13, UI.MUTED, true))
	else:
		var top_6_tags: Array = tags.slice(0, 6)
		var max_cell: int = 1
		for row_item: Dictionary in matrix:
			var r_tags: Dictionary = row_item.get("tags", {}) if row_item.get("tags") is Dictionary else {}
			for t_info: Dictionary in top_6_tags:
				var tag_id: String = str(t_info.get("tag", ""))
				max_cell = maxi(max_cell, int(r_tags.get(tag_id, 0)))

		# Horizontal scroll container for phone portrait / narrow screens
		var scroll_grid := ScrollContainer.new()
		scroll_grid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll_grid.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_grid.mouse_filter = Control.MOUSE_FILTER_PASS

		var table_v := UI.vbox(4)
		table_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll_grid.add_child(table_v)

		# Table Header Row
		var head_row := UI.hbox(4)
		head_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_hdr := UI.panel(Color("#0d2432"), 6, 6)
		name_hdr.custom_minimum_size = Vector2(150, 36)
		var name_hdr_lbl := UI.label("學員姓名（場次）", 12, UI.MUTED)
		name_hdr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_hdr.add_child(name_hdr_lbl)
		head_row.add_child(name_hdr)

		for t_info: Dictionary in top_6_tags:
			var t_lbl: String = str(t_info.get("label", t_info.get("tag", "")))
			var col_hdr := UI.panel(Color("#0d2432"), 6, 6)
			col_hdr.custom_minimum_size = Vector2(72, 36)
			var hdr_lbl := UI.label(t_lbl, 11, UI.MUTED)
			hdr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hdr_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			col_hdr.add_child(hdr_lbl)
			head_row.add_child(col_hdr)
		table_v.add_child(head_row)

		# Learner Rows
		for row_item: Dictionary in matrix:
			var uid: String = str(row_item.get("userId", ""))
			var uname: String = str(row_item.get("name", "學員"))
			var sess_cnt: int = int(row_item.get("sessions", 0))
			var r_tags: Dictionary = row_item.get("tags", {}) if row_item.get("tags") is Dictionary else {}

			var data_row := UI.hbox(4)
			data_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

			var open_profile := func():
				target_user_id = uid
				target_user_name = uname
				_current_tab = 0
				_build_ui()

			var l_btn := UI.button("%s (%d場)" % [uname, sess_cnt], open_profile, 12, UI.PANEL_2)
			l_btn.custom_minimum_size = Vector2(150, 36)
			l_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			data_row.add_child(l_btn)

			for t_info: Dictionary in top_6_tags:
				var tag_id: String = str(t_info.get("tag", ""))
				var cell_cnt: int = int(r_tags.get(tag_id, 0))

				var cell_bg: Color
				if cell_cnt == 0:
					cell_bg = Color("#0b1e28", 0.7)
				else:
					var ratio: float = clampf(float(cell_cnt) / float(max_cell), 0.25, 1.0)
					cell_bg = Color("#1e1b12").lerp(Color("#d9534f"), ratio)

				var cell_btn: Button = UI.button(str(cell_cnt) if cell_cnt > 0 else "-", open_profile, 12, cell_bg)
				cell_btn.custom_minimum_size = Vector2(72, 36)
				if cell_cnt == 0:
					cell_btn.modulate = Color(1, 1, 1, 0.45)
				data_row.add_child(cell_btn)

			table_v.add_child(data_row)

		heat_v.add_child(scroll_grid)
	content.add_child(heat_card)
